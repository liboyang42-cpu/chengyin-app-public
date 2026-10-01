import 'club_api_messages.dart';
import '../../l10n/strings.dart';
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
            Text(stringsOf(context).clubAuxPostsCircle, style: textTheme.titleMedium),
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(CupertinoIcons.pencil, size: 16),
                    const SizedBox(width: CyTokens.space1),
                    Text(stringsOf(context).clubAuxCompose),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: CyTokens.space2),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(CyTokens.space4),
            child: Center(child: const CupertinoActivityIndicator()),
          ),
          error: (Object e, _) => StatusView(
            icon: CupertinoIcons.exclamationmark_circle,
            message: stringsOf(context).clubAuxPostsError,
            sub: clubApiErrorMessage(context, e),
            onRetry: refresh,
          ),
          data: (List<ClubPost> list) => list.isEmpty
              ? StatusView(
                  icon: CupertinoIcons.chat_bubble_2,
                  message: stringsOf(context).clubAuxPostsEmpty,
                  // ★ 空态说清「为什么空」而不是只说「没有」:
                  //   非成员看到的空态和成员看到的不是一回事。
                  sub: canPost ? stringsOf(context).clubAuxFirstPost : stringsOf(context).clubAuxJoinToPost,
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
        _notice = clubApiErrorMessage(context, e);
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
                    stringsOf(context).clubAuxComposeTitle,
                    style: textTheme.titleLarge?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Semantics(
                  label: stringsOf(context).clubAuxCloseCompose,
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
              label: stringsOf(context).clubAuxPostContent,
              child: CupertinoTextField(
                controller: _input,
                autofocus: true,
                enabled: !_sending,
                minLines: 3,
                maxLines: 8,
                maxLength: 300,
                clearButtonMode: OverlayVisibilityMode.editing,
                placeholder: stringsOf(context).clubAuxPostPlaceholder,
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
                            label: stringsOf(context).clubAuxRemoveImage(entry.key + 1),
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
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                const Icon(CupertinoIcons.photo_on_rectangle),
                                const SizedBox(height: CyTokens.space1),
                                Text(stringsOf(context).clubAuxAddImage),
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
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const CupertinoActivityIndicator(),
                        const SizedBox(width: CyTokens.space2),
                        Text(stringsOf(context).clubAuxPublishing),
                      ],
                    )
                  : Text(stringsOf(context).clubAuxPublish),
            ),
          ],
        ),
      ),
    );
  }
}
