import 'club_api_messages.dart';
import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'club_comments_sheet.dart';
import '../../core/moderation/report_sheet.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../auth/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/club_post.dart';
import '../../core/widgets/cy_net_image.dart';
import 'club_post_mutation_sheets.dart';

enum _ClubPostAction { edit, pin, history, delete, report }

final clubFeedProvider = FutureProvider.autoDispose<ClubFeed>((ref) {
  return ref.watch(clubApiProvider).postFeed();
});

/// 俱乐部帖文流。对齐小程序 `pages/talent/list` 的帖文 tab。
class ClubFeedPage extends ConsumerWidget {
  const ClubFeedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(clubFeedProvider);
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).clubAuxFeedTitle)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: async.when(
            loading: () => const Center(child: CupertinoActivityIndicator()),
            error: (Object e, _) => StatusView(
              message: stringsOf(context).clubAuxFeedError,
              sub: clubApiErrorMessage(context, e),
              large: true,
              onRetry: () => ref.invalidate(clubFeedProvider),
            ),
            data: (ClubFeed feed) {
              // ★ 「还没加入俱乐部」与「加入了但没人发帖」是两回事 ——
              //   前者给去俱乐部的入口,后者只说这里还没动静。
              if (feed.hasNoClub) {
                return StatusView(
                  message: stringsOf(context).clubAuxJoinFirst,
                  sub: stringsOf(context).clubAuxJoinFirstHint,
                  large: true,
                  onRetry: () => context.push('/clubs'),
                  retryLabel: stringsOf(context).clubAuxBrowseClubs,
                );
              }
              if (feed.rows.isEmpty) {
                return StatusView(
                  message: stringsOf(context).clubAuxNoActivity,
                  sub: stringsOf(context).clubAuxNoActivityHint,
                  large: true,
                );
              }
              return RefreshIndicator.adaptive(
                onRefresh: () async => ref.invalidate(clubFeedProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.all(CyTokens.pageX),
                  itemCount: feed.rows.length,
                  itemBuilder: (_, int i) => ClubPostTile(
                    post: feed.rows[i],
                    viewerIsClubAdmin: feed.rows[i].viewerCanManage,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 圈子动态卡。★ 公开(不再是 `_PostTile`)是因为俱乐部详情页要复用同一张卡 ——
/// 两处各写一份必然分叉,而分叉的那一份改了没人发现(本项目「孪生页面」那类问题)。
///
/// `onChanged` 指明「改完刷新谁」:聚合流刷 clubFeedProvider,
/// 俱乐部详情刷该俱乐部的动态列表。写死 invalidate(clubFeedProvider)
/// 会让详情页点完赞看起来没反应。
class ClubPostTile extends ConsumerWidget {
  const ClubPostTile({
    super.key,
    required this.post,
    this.onChanged,
    this.onOpenClub,
    this.clubOwnerMemberId,
    this.viewerIsClubAdmin = false,
  });
  final ClubPost post;
  final VoidCallback? onChanged;
  final VoidCallback? onOpenClub;
  final int? clubOwnerMemberId;
  final bool viewerIsClubAdmin;

  void _refresh(WidgetRef ref) {
    if (onChanged != null) {
      onChanged!();
    } else {
      ref.invalidate(clubFeedProvider);
    }
  }

  /// 点赞 / 取消点赞。
  ///
  /// ★ 后端是**切换式**的(已赞再调一次就是取消),所以这里不传「想变成什么」,
  ///   调完直接 invalidate 让服务端说了算 —— 本地先改再对账会在失败时留下
  ///   一个假的已赞态。
  Future<void> _like(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(clubApiProvider).likePost(post.id);
      _refresh(ref);
    } catch (e) {
      if (!context.mounted) return;
      CyNativeNotice.show(
        context,
        clubApiErrorMessage(context, e),
        isError: true,
      );
    }
  }

  /// 权限感知操作：作者可编辑；俱乐部管理者可编辑/置顶公告；历史公开。
  Future<void> _menu(BuildContext context, WidgetRef ref) async {
    final int? viewerMemberId = ref.read(authControllerProvider).user?.id;
    final bool mine =
        post.authorMemberId != null && post.authorMemberId == viewerMemberId;
    final bool canManage =
        viewerIsClubAdmin ||
        (clubOwnerMemberId != null && clubOwnerMemberId == viewerMemberId);
    final bool canEdit = post.isAnnouncement ? canManage : mine;
    final bool canPin = post.isAnnouncement && canManage;
    final _ClubPostAction? selected =
        await showCupertinoModalPopup<_ClubPostAction>(
          context: context,
          builder: (BuildContext sheetContext) => CupertinoActionSheet(
            title: Text(stringsOf(context).clubAuxPostActions),
            actions: <Widget>[
              if (canEdit)
                CupertinoActionSheetAction(
                  key: const Key('club-post-edit'),
                  onPressed: () =>
                      Navigator.of(sheetContext).pop(_ClubPostAction.edit),
                  child: Text(stringsOf(context).clubAuxEditPost),
                ),
              if (canPin)
                CupertinoActionSheetAction(
                  key: const Key('club-post-pin'),
                  onPressed: () =>
                      Navigator.of(sheetContext).pop(_ClubPostAction.pin),
                  child: Text(post.pinned ? stringsOf(context).clubAuxUnpin : stringsOf(context).clubAuxPinAnnouncement),
                ),
              CupertinoActionSheetAction(
                key: const Key('club-post-history'),
                onPressed: () =>
                    Navigator.of(sheetContext).pop(_ClubPostAction.history),
                child: Text(stringsOf(context).clubAuxEditHistory),
              ),
              CupertinoActionSheetAction(
                isDestructiveAction: mine,
                onPressed: () => Navigator.of(
                  sheetContext,
                ).pop(mine ? _ClubPostAction.delete : _ClubPostAction.report),
                child: Text(mine ? stringsOf(context).clubAuxDeletePost : stringsOf(context).clubAuxReportPost),
              ),
            ],
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: Text(stringsOf(context).cancel),
            ),
          ),
        );
    if (selected == null || !context.mounted) return;
    try {
      switch (selected) {
        case _ClubPostAction.edit:
          final bool? changed = await showClubPostEditSheet(
            context,
            post: post,
          );
          if (changed == true) _refresh(ref);
          break;
        case _ClubPostAction.pin:
          final String msg = await clubApiAction(context, () => ref
              .read(clubApiProvider)
              .setPostPinned(
                postId: post.id,
                pinned: !post.pinned,
                version: post.version,
                requestId:
                    'club-post-${post.pinned ? 'unpin' : 'pin'}-${post.id}-v${post.version}',
              ));
          _refresh(ref);
          if (context.mounted) CyNativeNotice.show(context, msg);
          break;
        case _ClubPostAction.history:
          await showClubPostHistorySheet(context, postId: post.id);
          break;
        case _ClubPostAction.delete:
          final bool ok = await cyConfirm(
            context,
            title: stringsOf(context).clubAuxDeletePostTitle,
            content: stringsOf(context).clubAuxDeletePostConfirm,
            confirmText: stringsOf(context).clubAuxDelete,
            danger: true,
          );
          if (!ok || !context.mounted) return;
          final String msg = await clubApiAction(context, () => ref
              .read(clubApiProvider)
              .deletePost(post.id));
          _refresh(ref);
          if (!context.mounted) return;
          CyNativeNotice.show(context, msg);
          break;
        case _ClubPostAction.report:
          final String? reason = await showReportSheet(
            context,
            targetLabel: stringsOf(context).clubAuxThisPost,
          );
          if (reason == null || !context.mounted) return;
          final String msg = await clubApiAction(context, () => ref
              .read(clubApiProvider)
              .reportPost(post.id));
          if (!context.mounted) return;
          CyNativeNotice.show(context, msg);
          break;
      }
    } catch (e) {
      if (!context.mounted) return;
      CyNativeNotice.show(
        context,
        clubApiErrorMessage(context, e),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    // 帖卡在俱乐部根页会被商家视角(merchantLight 作用域)复用,取色必须
    // 走 CyPalette 随主题变 —— 静态 CyTokens 在商家浅底上就是一张黑卡。
    final palette = CyPalette.of(context);
    final body = post.body;
    final authorName = (post.nickname ?? '').trim().isEmpty
        ? stringsOf(context).clubAuxAnonymousAuthor
        : post.authorName;

    final VoidCallback? action = onOpenClub;
    return Semantics(
      container: action != null,
      explicitChildNodes: action != null,
      button: action != null,
      label: action == null ? null : stringsOf(context).clubAuxOpenPostClub,
      onTap: action,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: action,
        child: Container(
          margin: const EdgeInsets.only(bottom: CyTokens.space3),
          padding: const EdgeInsets.all(CyTokens.space3),
          decoration: BoxDecoration(
            color: palette.bgSurface,
            borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            border: Border.all(color: palette.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  // ★ 拿不到作者 id 就不给点 —— 跳 /user/0 会进一个空主页。
                  Semantics(
                    button: post.authorRoute != null,
                    label: post.authorRoute == null
                        ? authorName
                        : stringsOf(context).clubAuxViewAuthor(authorName),
                    onTap: post.authorRoute == null
                        ? null
                        : () => context.push(post.authorRoute!),
                    excludeSemantics: true,
                    child: SizedBox(
                      height: 44,
                      child: CupertinoButton(
                        minimumSize: const Size(44, 44),
                        padding: EdgeInsets.zero,
                        onPressed: post.authorRoute == null
                            ? null
                            : () => context.push(post.authorRoute!),
                        child: Row(
                          children: <Widget>[
                            CyAvatar(
                              url: post.avatar,
                              fallback: authorName.characters.first,
                              size: 32,
                            ),
                            const SizedBox(width: CyTokens.space2),
                            Text(authorName, style: textTheme.titleSmall),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if ((post.createTime ?? '').isNotEmpty)
                    Text(
                      post.createTime!.split(' ').first,
                      style: textTheme.labelSmall?.copyWith(
                        color: palette.textTertiary,
                      ),
                    ),
                  if (post.pinned)
                    Padding(
                      padding: const EdgeInsets.only(left: CyTokens.space2),
                      child: Text(
                        stringsOf(context).clubAuxPinned,
                        key: const Key('club-post-pinned'),
                        style: textTheme.labelSmall?.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                  // 与「…」按钮的可视圆底留缝,免得圆底压住日期/置顶字尾。
                  const SizedBox(width: CyTokens.space1_5),
                  // 举报 / 删除。Apple 1.2 要求 UGC 有举报入口 —— 圈子帖此前没有。
                  CyNativeIconButton(
                    key: const Key('club-post-more'),
                    label: stringsOf(context).clubAuxMorePostActions,
                    icon: const CyNativeButtonIcon(
                      sfSymbol: 'ellipsis',
                      fallback: CupertinoIcons.ellipsis,
                    ),
                    onPressed: () => _menu(context, ref),
                    iconSize: 18,
                  ),
                ],
              ),
              // ★ 只有图没有字时不渲染正文段,免得把图片顶下去。
              if (body != null) ...<Widget>[
                const SizedBox(height: CyTokens.space2),
                Text(body, style: textTheme.bodyMedium),
              ],
              if (post.edited)
                Padding(
                  padding: const EdgeInsets.only(top: CyTokens.space1),
                  child: Text(
                    stringsOf(context).clubAuxEdited,
                    style: textTheme.labelSmall?.copyWith(
                      color: palette.textTertiary,
                    ),
                  ),
                ),
              // 帖子带的游玩引用:成绩卡(refType=1)/模板卡(refType=2)。
              // 真源 `components/cy/post-card/index.wxml` 里两块都在正文后、
              // 图廊前;成绩卡会**顶掉**普通图廊(`wx:if="{{!post.isCompletionShare …"`)。
              if (post.isCompletionShare || post.hasPlayRefCard) ...<Widget>[
                const SizedBox(height: CyTokens.space2),
                _PostRefCard(post: post),
              ],
              if (post.images.isNotEmpty &&
                  !post.isCompletionShare) ...<Widget>[
                const SizedBox(height: CyTokens.space2),
                Wrap(
                  spacing: CyTokens.space1,
                  runSpacing: CyTokens.space1,
                  children: post.images
                      .take(9)
                      .map(
                        (String url) => ClipRRect(
                          borderRadius: BorderRadius.circular(
                            CyTokens.radiusSm,
                          ),
                          child: CyNetImage(
                            url,
                            width: 96,
                            height: 96,
                            fit: BoxFit.cover,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              // ★ 互动数原来只是**一行只读文字** —— 看得到「3 赞」,却点不了赞。
              //   后端 /api/club/post/like 一直都在,App 侧从没接。
              const SizedBox(height: CyTokens.space2),
              Row(
                children: <Widget>[
                  CupertinoButton(
                    onPressed: () => _like(context, ref),
                    padding: const EdgeInsets.symmetric(
                      horizontal: CyTokens.space2,
                      vertical: CyTokens.space1,
                    ),
                    minimumSize: const Size(44, 44),
                    child: Padding(
                      padding: EdgeInsets.zero,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            post.liked ? Icons.favorite : Icons.favorite_border,
                            size: 16,
                            color: post.liked
                                ? palette.statusDanger
                                : palette.textTertiary,
                          ),
                          const SizedBox(width: CyTokens.space1),
                          Text(
                            '${post.likeCount}',
                            style: textTheme.bodySmall?.copyWith(
                              color: palette.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: CyTokens.space2),
                  // ★ 这个图标原来是**只读**的:看得到「3」,点不开 ——
                  //   跟点赞图标当初一模一样的病。后端四个评论接口一直都在。
                  CupertinoButton(
                    key: const Key('club-post-comment'),
                    onPressed: () => showClubCommentsSheet(
                      context,
                      postId: post.id,
                      onChanged: () => _refresh(ref),
                      clubOwnerMemberId: clubOwnerMemberId,
                      viewerIsClubAdmin: viewerIsClubAdmin,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: CyTokens.space2,
                      vertical: CyTokens.space1,
                    ),
                    minimumSize: const Size(44, 44),
                    child: Padding(
                      padding: EdgeInsets.zero,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.mode_comment_outlined,
                            size: 16,
                            color: palette.textTertiary,
                          ),
                          const SizedBox(width: CyTokens.space1),
                          Text(
                            '${post.commentCount}',
                            style: textTheme.bodySmall?.copyWith(
                              color: palette.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 帖子引用卡(成绩卡 / 模板卡)。真源 `components/cy/post-card/index.wxml:73-83`
/// + `components/cy/feed-play-card/index.wxml`:
/// 点卡 = 「看这条主题」(`onPostReference` → 主题详情);
/// 模板卡多一排按钮:「看看模板」进主题详情、「试玩」进玩法页
/// (`onPostReferencePlay`)。后端投影不出展示字段(被引对象删了)时
/// 判定自然为假,这里根本不渲这张卡 —— 不摆空标题卡,也不摆点不动的死卡。
class _PostRefCard extends StatelessWidget {
  const _PostRefCard({required this.post});

  final ClubPost post;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = CyPalette.of(context);
    final String? topicRoute = post.refTopicRoute;
    final String? playRoute = post.refPlayRoute;
    final bool template = post.hasPlayRefCard;
    final String title = post.sportName ?? '';
    final String? cover = post.sportCover?.trim();

    final Widget head = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (cover != null && cover.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: CyTokens.space2_5),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(CyTokens.radiusSm),
              child: CyNetImage(
                cover,
                width: 72,
                height: 54,
                fit: BoxFit.cover,
              ),
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall,
              ),
              Text(
                template ? stringsOf(context).clubAuxThemeTemplate : stringsOf(context).clubAuxPlayRecord,
                style: textTheme.labelSmall?.copyWith(
                  color: palette.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(CyTokens.space2_5),
      decoration: BoxDecoration(
        color: palette.bgElevated,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            button: topicRoute != null,
            label: stringsOf(context).clubAuxViewTitle(title),
            child: topicRoute == null
                ? head
                : CupertinoButton(
                    key: Key('club-post-ref-card-${post.id}'),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(44, 44),
                    onPressed: () => context.push(topicRoute),
                    child: head,
                  ),
          ),
          if (template && playRoute != null) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                CupertinoButton.tinted(
                  key: Key('club-post-ref-play-${post.id}'),
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space3,
                  ),
                  onPressed: () => context.push(playRoute),
                  child: Text(stringsOf(context).clubAuxTryPlay),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
