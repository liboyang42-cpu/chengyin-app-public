import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/moderation/report_sheet.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/club_comment.dart';
import '../auth/auth_controller.dart';

/// 某条圈子动态的评论。
///
/// ★★ 之前动态卡上那个评论图标是**只读**的:看得到「3」,点不开 ——
///   和点赞图标当初一样(那条已修)。后端 `/api/club/post/comment/*`
///   四个接口一直都在,App 侧从没接。
///
/// ★ 删除 / 举报的分流与动态本身同一条规则:自己的给删除、别人的给举报。
///   ⚠️ 后端放行删除的**不止作者本人**(俱乐部创建者和管理员也能删,
///   见 club_api.deleteComment 的注释),所以这里只决定「显示哪个入口」,
///   真正的归属判定在服务端 —— 前端不复刻那套代管规则。
final commentsProvider = FutureProvider.autoDispose
    .family<List<ClubComment>, int>((Ref ref, int postId) {
      return ref.watch(clubApiProvider).postComments(postId);
    });

Future<void> showClubCommentsSheet(
  BuildContext context, {
  required int postId,
  VoidCallback? onChanged,
  int? clubOwnerMemberId,
  bool viewerIsClubAdmin = false,
}) async {
  await showCupertinoSheet<void>(
    context: context,
    enableDrag: false,
    showDragHandle: true,
    topGap: 0.08,
    scrollableBuilder:
        (BuildContext context, ScrollController scrollController) =>
            _CommentsSheet(
              postId: postId,
              onChanged: onChanged,
              clubOwnerMemberId: clubOwnerMemberId,
              viewerIsClubAdmin: viewerIsClubAdmin,
              scrollController: scrollController,
            ),
  );
}

class _CommentsSheet extends ConsumerStatefulWidget {
  const _CommentsSheet({
    required this.postId,
    required this.scrollController,
    this.onChanged,
    this.clubOwnerMemberId,
    this.viewerIsClubAdmin = false,
  });
  final int postId;
  final VoidCallback? onChanged;
  final int? clubOwnerMemberId;
  final bool viewerIsClubAdmin;
  final ScrollController scrollController;

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  final TextEditingController _input = TextEditingController();
  bool _sending = false;
  String? _notice;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    setState(() => _notice = msg);
  }

  Future<void> _send() async {
    final String text = _input.text.trim();
    // 空评论直接不发 —— 后端会拒,但让用户按一下再被拒没有意义。
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _notice = null;
    });
    try {
      await ref
          .read(clubApiProvider)
          .createComment(postId: widget.postId, content: text);
      _input.clear();
      ref.invalidate(commentsProvider(widget.postId));
      // 评论数长在动态卡上,发完要让外面那层也刷新。
      widget.onChanged?.call();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool _canDelete(ClubComment comment) {
    final int? me = ref.read(authControllerProvider).user?.id;
    return canModerateComment(
      viewerMemberId: me,
      commentAuthorId: comment.memberId,
      clubOwnerMemberId: widget.clubOwnerMemberId,
      viewerIsClubAdmin: widget.viewerIsClubAdmin,
    );
  }

  Future<void> _delete(ClubComment comment) async {
    try {
      final bool ok = await cyConfirm(
        context,
        title: '删除这条评论?',
        content: '删除后其他成员就看不到了。',
        confirmText: '删除',
        danger: true,
      );
      if (!ok) return;
      final String msg = await ref
          .read(clubApiProvider)
          .deleteComment(comment.id);
      ref.invalidate(commentsProvider(widget.postId));
      widget.onChanged?.call();
      _toast(msg);
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _report(ClubComment comment) async {
    try {
      final String? reason = await showReportSheet(
        context,
        targetLabel: '这条评论',
      );
      if (reason == null) return;
      // ⚠️ 举报只入审核队列,**不立即删** —— 提示按后端原话,别说「已删除」。
      _toast(await ref.read(clubApiProvider).reportComment(comment.id));
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final CyPalette palette = CyPalette.of(context);
    final async = ref.watch(commentsProvider(widget.postId));
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      resizeToAvoidBottomInset: true,
      child: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CyTokens.pageX,
                CyTokens.space2,
                CyTokens.pageX,
                0,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '评论',
                      style: textTheme.titleLarge?.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Semantics(
                    label: '关闭评论',
                    button: true,
                    child: CupertinoButton(
                      key: const Key('club-comments-close'),
                      minimumSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                      foregroundColor: palette.textSecondary,
                      onPressed: _sending
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const ExcludeSemantics(
                        child: Icon(CupertinoIcons.xmark_circle_fill),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CupertinoActivityIndicator()),
                error: (Object e, _) => StatusView(
                  icon: CupertinoIcons.exclamationmark_circle,
                  message: '评论加载不出来',
                  sub: e.toString().replaceFirst('Exception: ', ''),
                  onRetry: () =>
                      ref.invalidate(commentsProvider(widget.postId)),
                ),
                data: (List<ClubComment> list) => list.isEmpty
                    ? const StatusView(
                        icon: CupertinoIcons.chat_bubble_2,
                        message: '还没有评论',
                        sub: '还没有评论，来抢沙发',
                      )
                    : ListView.builder(
                        controller: widget.scrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.symmetric(
                          horizontal: CyTokens.pageX,
                        ),
                        itemCount: list.length,
                        itemBuilder: (_, int i) => _CommentRow(
                          comment: list[i],
                          canDelete: _canDelete(list[i]),
                          onDelete: () => _delete(list[i]),
                          onReport: () => _report(list[i]),
                        ),
                      ),
              ),
            ),
            if (_notice != null)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.pageX,
                    vertical: CyTokens.space1,
                  ),
                  child: Text(
                    _notice!,
                    style: textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  CyTokens.pageX,
                  CyTokens.space2,
                  CyTokens.pageX,
                  CyTokens.space3 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: CupertinoTextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        placeholder: '写评论…',
                        clearButtonMode: OverlayVisibilityMode.editing,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        padding: const EdgeInsets.all(CyTokens.space3),
                        decoration: BoxDecoration(
                          color: palette.bgSurface,
                          border: Border.all(color: palette.borderSubtle),
                          borderRadius: BorderRadius.circular(
                            CyTokens.radiusMd,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: CyTokens.space2),
                    Semantics(
                      label: '发送评论',
                      button: true,
                      enabled: !_sending,
                      child: CupertinoButton(
                        key: const Key('club-comment-send'),
                        minimumSize: const Size(44, 44),
                        padding: EdgeInsets.zero,
                        color: palette.actionPrimaryBg,
                        foregroundColor: _sending
                            ? palette.textPlaceholder
                            : palette.actionPrimaryFg,
                        borderRadius: BorderRadius.circular(22),
                        onPressed: _sending ? null : _send,
                        child: _sending
                            ? const CupertinoActivityIndicator()
                            : const Icon(CupertinoIcons.arrow_up, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.comment,
    required this.canDelete,
    required this.onDelete,
    required this.onReport,
  });
  final ClubComment comment;
  final bool canDelete;
  final VoidCallback onDelete;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final CyPalette palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CyAvatar(
            url: comment.avatar,
            // 兜底文案不进头像 —— 否则渲出一个「城」字当姓氏(见模型注释)。
            fallback: comment.avatarName,
            size: 28,
          ),
          const SizedBox(width: CyTokens.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(comment.displayName, style: textTheme.titleSmall),
                    const Spacer(),
                    if ((comment.createTime ?? '').isNotEmpty)
                      Text(
                        comment.createTime!.split(' ').first,
                        style: textTheme.labelSmall?.copyWith(
                          color: palette.textTertiary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: CyTokens.space1),
                Text(comment.content ?? '', style: textTheme.bodyMedium),
                const SizedBox(height: CyTokens.space1),
                Row(
                  children: <Widget>[
                    if (canDelete)
                      CupertinoButton(
                        key: Key('club-comment-delete-${comment.id}'),
                        minimumSize: const Size(44, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        foregroundColor: CupertinoColors.systemRed.resolveFrom(
                          context,
                        ),
                        onPressed: onDelete,
                        child: const Text('删除'),
                      ),
                    CupertinoButton(
                      key: Key('club-comment-report-${comment.id}'),
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: palette.textSecondary,
                      onPressed: onReport,
                      child: const Text('举报'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
