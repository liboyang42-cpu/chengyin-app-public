import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/club.dart';
import '../../data/models/club_post.dart';
import '../auth/auth_controller.dart';
import 'club_controller.dart';
import 'club_feed_page.dart';
import 'club_image_picker.dart';

/// 单个俱乐部的动态列表(`/api/club/post/list`)。
///
/// ★★ 与首页那条聚合流(clubFeedProvider)**不是同一个接口**:
///   聚合流是「我关注的所有俱乐部」,这里是「这一个俱乐部」。
///   小程序 pages/club/detail 一直有这块,App 侧的详情页原来只有简介 ——
///   接口写好了、没有任何页面调它,用户点不到(见 endpoint_reachability_test)。
final clubPostsProvider = FutureProvider.autoDispose
    .family<List<ClubPost>, int>((Ref ref, int clubId) {
      return ref.watch(clubApiProvider).clubPosts(clubId);
    });

class ClubPostsSection extends ConsumerWidget {
  const ClubPostsSection({
    super.key,
    required this.clubId,
    this.canPost = false,
  });

  final int clubId;

  /// 能不能发帖。★ 判据是「是不是成员」——非成员看得到圈子但发不了,
  /// 摆一个点下去必被后端拒的按钮是本项目反复出现的一类缺陷。
  final bool canPost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final async = ref.watch(clubPostsProvider(clubId));
    final int? viewerMemberId = ref.watch(authControllerProvider).user?.id;
    final List<ClubMember>? members = ref
        .watch(clubMembersProvider(clubId))
        .value;
    int? clubOwnerMemberId;
    if (members != null) {
      for (final ClubMember member in members) {
        if (member.isOwner) {
          clubOwnerMemberId = member.memberId;
          break;
        }
      }
    }
    final bool viewerIsClubAdmin =
        members?.any(
          (ClubMember member) =>
              member.memberId == viewerMemberId && member.isAdmin,
        ) ??
        false;
    void refresh() => ref.invalidate(clubPostsProvider(clubId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('圈子', style: textTheme.titleMedium),
            const Spacer(),
            if (canPost)
              CupertinoButton(
                key: const Key('club-post-compose'),
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: () async {
                  final bool? posted = await showClubComposeSheet(
                    context,
                    clubId: clubId,
                  );
                  if (posted == true) refresh();
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(CupertinoIcons.pencil, size: 16),
                    SizedBox(width: CyTokens.space1),
                    Text('发动态'),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: CyTokens.space2),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(CyTokens.space4),
            child: Center(child: CupertinoActivityIndicator()),
          ),
          error: (Object e, _) => StatusView(
            icon: CupertinoIcons.exclamationmark_circle,
            message: '圈子动态加载不出来',
            sub: e.toString().replaceFirst('Exception: ', ''),
            onRetry: refresh,
          ),
          data: (List<ClubPost> list) => list.isEmpty
              ? StatusView(
                  icon: CupertinoIcons.chat_bubble_2,
                  message: '这个俱乐部还没有动态',
                  // ★ 空态说清「为什么空」而不是只说「没有」:
                  //   非成员看到的空态和成员看到的不是一回事。
                  sub: canPost ? '发第一条,让成员知道最近在跑什么' : '加入后可以发动态',
                )
              : Column(
                  children: list
                      .map(
                        (ClubPost p) => ClubPostTile(
                          post: p,
                          onChanged: refresh,
                          clubOwnerMemberId: clubOwnerMemberId,
                          viewerIsClubAdmin: viewerIsClubAdmin,
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }
}

/// 发一条圈子动态。文字 + 最多 9 张图,对齐小程序帖子编辑器。
Future<bool?> showClubComposeSheet(
  BuildContext context, {
  required int clubId,
}) {
  return showCupertinoSheet<bool>(
    context: context,
    enableDrag: false,
    showDragHandle: true,
    topGap: 0.12,
    scrollableBuilder:
        (BuildContext context, ScrollController scrollController) =>
            _ComposeSheet(clubId: clubId, scrollController: scrollController),
  );
}

class _ComposeSheet extends ConsumerStatefulWidget {
  const _ComposeSheet({required this.clubId, required this.scrollController});
  final int clubId;
  final ScrollController scrollController;

  @override
  ConsumerState<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends ConsumerState<_ComposeSheet> {
  final TextEditingController _input = TextEditingController();
  final List<String> _images = <String>[];
  bool _sending = false;
  bool _picking = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    // 有没有字决定发送钮的可用性,变了要重建。
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String text = _input.text.trim();
    if ((text.isEmpty && _images.isEmpty) || _sending) return;
    setState(() {
      _sending = true;
      _notice = null;
    });
    try {
      await ref
          .read(clubApiProvider)
          .createPost(
            clubId: widget.clubId,
            content: text,
            images: List<String>.of(_images),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _notice = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _pickImages() async {
    final int remain = 9 - _images.length;
    if (remain <= 0 || _picking || _sending) return;
    setState(() => _picking = true);
    final List<String> added = await pickAndUploadImages(
      context,
      ref,
      maxCount: remain,
    );
    if (!mounted) return;
    setState(() {
      _images.addAll(added.take(9 - _images.length));
      _picking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final CyPalette palette = CyPalette.of(context);
    final bool canSubmit =
        !_sending && (_input.text.trim().isNotEmpty || _images.isNotEmpty);
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      resizeToAvoidBottomInset: true,
      child: SafeArea(
        top: false,
        child: ListView(
          controller: widget.scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space2,
            CyTokens.pageX,
            CyTokens.space5 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '发条动态',
                    style: textTheme.titleLarge?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Semantics(
                  label: '关闭发动态',
                  button: true,
                  child: CupertinoButton(
                    key: const Key('club-compose-close'),
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
            const SizedBox(height: CyTokens.space3),
            Semantics(
              textField: true,
              label: '动态内容',
              child: CupertinoTextField(
                controller: _input,
                autofocus: true,
                enabled: !_sending,
                minLines: 3,
                maxLines: 8,
                maxLength: 300,
                clearButtonMode: OverlayVisibilityMode.editing,
                placeholder: '分享俱乐部路线、战报或公告…',
                padding: const EdgeInsets.all(CyTokens.space3),
                decoration: BoxDecoration(
                  color: palette.bgSurface,
                  border: Border.all(color: palette.borderSubtle),
                  borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                ),
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            Wrap(
              spacing: CyTokens.space2,
              runSpacing: CyTokens.space2,
              children: <Widget>[
                ..._images.asMap().entries.map(
                  (MapEntry<int, String> entry) => SizedBox(
                    width: 88,
                    height: 88,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            CyTokens.radiusMd,
                          ),
                          child: CyNetImage(entry.value, fit: BoxFit.cover),
                        ),
                        Align(
                          alignment: Alignment.topRight,
                          child: Semantics(
                            label: '移除第 ${entry.key + 1} 张图片',
                            button: true,
                            child: CupertinoButton(
                              key: Key('club-compose-remove-${entry.key}'),
                              minimumSize: const Size(44, 44),
                              padding: EdgeInsets.zero,
                              onPressed: _sending
                                  ? null
                                  : () => setState(
                                      () => _images.removeAt(entry.key),
                                    ),
                              child: const Icon(
                                CupertinoIcons.xmark_circle_fill,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_images.length < 9)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.bgSurface,
                      border: Border.all(color: palette.borderSubtle),
                      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                    ),
                    child: CupertinoButton(
                      key: const Key('club-compose-add-image'),
                      minimumSize: const Size(88, 88),
                      padding: EdgeInsets.zero,
                      foregroundColor: palette.textSecondary,
                      onPressed: (_picking || _sending) ? null : _pickImages,
                      child: _picking
                          ? const CupertinoActivityIndicator()
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Icon(CupertinoIcons.photo_on_rectangle),
                                SizedBox(height: CyTokens.space1),
                                Text('添加图片'),
                              ],
                            ),
                    ),
                  ),
              ],
            ),
            if (_notice != null) ...<Widget>[
              const SizedBox(height: CyTokens.space2),
              Semantics(
                liveRegion: true,
                child: Text(
                  _notice!,
                  style: textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ),
            ],
            const SizedBox(height: CyTokens.space3),
            CupertinoButton(
              key: const Key('club-compose-submit'),
              minimumSize: const Size.fromHeight(CyTokens.btnH),
              color: palette.actionPrimaryBg,
              disabledColor: palette.bgSubtle,
              foregroundColor: canSubmit
                  ? palette.actionPrimaryFg
                  : palette.textPlaceholder,
              borderRadius: BorderRadius.circular(CyTokens.radiusPill),
              onPressed: canSubmit ? _submit : null,
              child: _sending
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        CupertinoActivityIndicator(),
                        SizedBox(width: CyTokens.space2),
                        Text('发布中…'),
                      ],
                    )
                  : const Text('发布'),
            ),
          ],
        ),
      ),
    );
  }
}
