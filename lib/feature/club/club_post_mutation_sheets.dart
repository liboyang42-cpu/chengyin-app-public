import 'club_api_messages.dart';
import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/club_api.dart';
import '../../data/models/club_post.dart';
import 'club_image_picker.dart';

Future<bool?> showClubPostEditSheet(
  BuildContext context, {
  required ClubPost post,
}) => showCupertinoSheet<bool>(
  context: context,
  enableDrag: false,
  showDragHandle: true,
  topGap: 0.12,
  scrollableBuilder: (BuildContext context, ScrollController controller) =>
      _ClubPostEditSheet(post: post, scrollController: controller),
);

class _ClubPostEditSheet extends ConsumerStatefulWidget {
  const _ClubPostEditSheet({
    required this.post,
    required this.scrollController,
  });
  final ClubPost post;
  final ScrollController scrollController;

  @override
  ConsumerState<_ClubPostEditSheet> createState() => _ClubPostEditSheetState();
}

class _ClubPostEditSheetState extends ConsumerState<_ClubPostEditSheet> {
  late final TextEditingController _input;
  late final List<String> _images;
  String? _requestId;
  String? _requestFingerprint;
  bool _sending = false;
  bool _picking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: widget.post.content ?? '');
    _images = List<String>.of(widget.post.images);
    _input.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _input.removeListener(_changed);
    _input.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final int remaining = 9 - _images.length;
    if (remaining <= 0 || _picking || _sending) return;
    setState(() => _picking = true);
    try {
      final List<String> added = await pickAndUploadImages(
        context,
        ref,
        maxCount: remaining,
      );
      if (!mounted) return;
      setState(() => _images.addAll(added));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _submit() async {
    final String content = _input.text.trim();
    if (_sending || (content.isEmpty && _images.isEmpty)) return;
    final String requestFingerprint = '$content\u0000${_images.join('\u0000')}';
    if (_requestFingerprint != requestFingerprint) {
      _requestFingerprint = requestFingerprint;
      _requestId = ClubApi.newPostMutationRequestId('update', widget.post.id);
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(clubApiProvider)
          .updatePost(
            postId: widget.post.id,
            content: content,
            images: List<String>.of(_images),
            version: widget.post.version,
            requestId: _requestId!,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = clubApiErrorMessage(context, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canSubmit =
        !_sending && (_input.text.trim().isNotEmpty || _images.isNotEmpty);
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(CyTokens.pageX),
      children: <Widget>[
        Row(
          children: <Widget>[
            // ★ 必须有可点的出口:这张 sheet 是 `enableDrag: false`,而
            //   `CupertinoSheetRoute` 的遮罩**点不动**(`barrierDismissible => false`),
            //   没有这颗「取消」就只剩「保存成功」一条路 —— 改错了想放弃都出不去。
            CupertinoButton(
              key: const Key('club-post-edit-cancel'),
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.of(context).pop(),
              child: Text(stringsOf(context).clubPostEditCancel),
            ),
            const SizedBox(width: CyTokens.space2),
            Expanded(
              child: Text(
                stringsOf(context).clubPostEditTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            CupertinoButton(
              key: const Key('club-post-edit-submit'),
              onPressed: canSubmit ? _submit : null,
              child: Text(_sending ? stringsOf(context).clubPostEditSaving : stringsOf(context).clubPostEditSave),
            ),
          ],
        ),
        CupertinoTextField(
          key: const Key('club-post-edit-input'),
          controller: _input,
          maxLength: 300,
          minLines: 5,
          maxLines: 10,
          placeholder: stringsOf(context).clubPostEditPlaceholder,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space2),
            child: Text(_error!, key: const Key('club-post-edit-error')),
          ),
        if (_images.isNotEmpty)
          Wrap(
            spacing: CyTokens.space1,
            runSpacing: CyTokens.space1,
            children: List<Widget>.generate(
              _images.length,
              (int index) => Stack(
                children: <Widget>[
                  CyNetImage(
                    _images[index],
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover,
                  ),
                  Positioned(
                    right: 0,
                    // 与发布器同款:24pt 图标钮必须有 44×44 命中区 + 语义标签
                    // (L9/§9.4-1;正例 club_posts_section 移除钮)。
                    child: Semantics(
                      label: stringsOf(context).clubPostEditRemoveImage(index + 1),
                      button: true,
                      child: CupertinoButton(
                        minimumSize: const Size(44, 44),
                        padding: EdgeInsets.zero,
                        onPressed: _sending
                            ? null
                            : () => setState(() => _images.removeAt(index)),
                        child: const Icon(CupertinoIcons.xmark_circle_fill),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        CupertinoButton(
          onPressed: _images.length < 9 && !_sending ? _pick : null,
          child: Text(_picking ? stringsOf(context).clubPostEditUploading : stringsOf(context).clubPostEditAddImages(_images.length)),
        ),
      ],
    );
  }
}

Future<void> showClubPostHistorySheet(
  BuildContext context, {
  required int postId,
}) => showCupertinoSheet<void>(
  context: context,
  showDragHandle: true,
  topGap: 0.16,
  scrollableBuilder: (BuildContext context, ScrollController controller) =>
      _ClubPostHistorySheet(postId: postId, scrollController: controller),
);

class _ClubPostHistorySheet extends ConsumerStatefulWidget {
  const _ClubPostHistorySheet({
    required this.postId,
    required this.scrollController,
  });
  final int postId;
  final ScrollController scrollController;

  @override
  ConsumerState<_ClubPostHistorySheet> createState() =>
      _ClubPostHistorySheetState();
}

class _ClubPostHistorySheetState extends ConsumerState<_ClubPostHistorySheet> {
  late Future<List<ClubPostRevision>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ClubPostRevision>> _load() =>
      ref.read(clubApiProvider).postHistory(widget.postId);

  void _retry() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) => Column(
    // ★ 标题与关闭钉在顶部:加载/空/错误三态原来一个按钮都没有,而这张
    //   sheet 唯一的出口是下滑 —— 关闭钮必须在任何状态下都点得到。
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(
          CyTokens.pageX,
          CyTokens.space2,
          CyTokens.space1,
          0,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                stringsOf(context).clubPostHistoryTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Semantics(
              label: stringsOf(context).clubPostHistoryClose,
              button: true,
              child: CupertinoButton(
                key: const Key('club-post-history-close'),
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).pop(),
                child: const ExcludeSemantics(
                  child: Icon(CupertinoIcons.xmark_circle_fill),
                ),
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: FutureBuilder<List<ClubPostRevision>>(
          future: _future,
          builder:
              (
                BuildContext context,
                AsyncSnapshot<List<ClubPostRevision>> snap,
              ) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CupertinoActivityIndicator());
                }
                if (snap.hasError) {
                  return StatusView(
                    key: const Key('club-post-history-error'),
                    message: stringsOf(context).clubPostHistoryFailed,
                    sub: clubApiErrorMessage(context, snap.error!),
                    onRetry: _retry,
                  );
                }
                final List<ClubPostRevision> rows =
                    snap.data ?? const <ClubPostRevision>[];
                if (rows.isEmpty) {
                  return StatusView(
                    key: Key('club-post-history-empty'),
                    message: stringsOf(context).clubPostHistoryEmpty,
                    sub: stringsOf(context).clubPostHistoryEmptyBody,
                  );
                }
                return ListView.separated(
                  key: const Key('club-post-history-list'),
                  controller: widget.scrollController,
                  padding: const EdgeInsets.all(CyTokens.pageX),
                  itemCount: rows.length,
                  separatorBuilder: (BuildContext context, int _) => Divider(
                    height: 1,
                    thickness: 0.5,
                    color: CupertinoColors.separator.resolveFrom(context),
                  ),
                  // 版本 + 时间是次级元信息(小字 + 系统次级色),正文才是这一条的主体。
                  // 原先三行同字号同字重,扫一眼分不出哪句是可读的正文。
                  itemBuilder: (BuildContext context, int index) {
                    final ClubPostRevision row = rows[index];
                    final TextStyle meta = TextStyle(
                      fontSize: CyTokens.typeLabel,
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                    );
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: CyTokens.space3,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Text(stringsOf(context).clubPostHistoryVersion(row.snapshotVersion), style: meta),
                              const Spacer(),
                              Text(row.createTime ?? stringsOf(context).clubPostHistoryUnknownTime, style: meta),
                            ],
                          ),
                          if ((row.content ?? '').trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: CyTokens.space1,
                              ),
                              child: Text(row.content!.trim()),
                            ),
                          if (row.images.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: CyTokens.space1,
                              ),
                              child: Text(
                                stringsOf(context).clubPostHistoryImages(row.images.length),
                                style: meta,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
        ),
      ),
    ],
  );
}
