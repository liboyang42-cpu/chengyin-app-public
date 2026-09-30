import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/login_required.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/square_api.dart';
import '../../data/models/square_post.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';
import 'square_controller.dart';
import 'square_local_draft_store.dart';

bool squarePostEditableFromWorkspace(String lifecycle) => const <String>{
  'DRAFT',
  'PUBLISHED',
  'LIMITED',
  'HIDDEN',
}.contains(lifecycle);

String squareWorkspaceStatusLabel(String lifecycle) => switch (lifecycle) {
  'DRAFT' => '未发布',
  'CHECKING' => '平台审核中，暂不可编辑',
  'PUBLISHED' => '已发布，可编辑后重新审核',
  'LIMITED' => '已限制，可编辑后重新审核',
  'HIDDEN' => '已隐藏，可编辑后重新审核',
  'REMOVED' => '已移除，请先申诉',
  _ => '当前状态不可编辑',
};

String squareLocalDraftSubtitle(SquareLocalDraftEntry entry) =>
    entry.postId == null ? '未保存到服务器 · 仅存在这台设备' : '本机修改稿 · 尚未同步到服务器';

class SquareDraftsPage extends ConsumerStatefulWidget {
  const SquareDraftsPage({super.key});

  @override
  ConsumerState<SquareDraftsPage> createState() => _SquareDraftsPageState();
}

class _SquareDraftsPageState extends ConsumerState<SquareDraftsPage> {
  final List<SquarePost> _extra = <SquarePost>[];
  bool _loadingMore = false;
  bool _exhausted = false;

  int get _memberId => ref.read(authControllerProvider).user?.id ?? 0;

  Future<void> _loadMore(SquareFeedPage first) async {
    if (_loadingMore || _exhausted || !first.hasMore) return;
    final cursor = _extra.isEmpty ? first.nextCursor : _extra.last.id;
    if (cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref.read(squareApiProvider).drafts(cursor: cursor);
      if (!mounted) return;
      final known = <int>{
        ...first.items.map((p) => p.id),
        ..._extra.map((p) => p.id),
      };
      setState(() {
        _extra.addAll(page.items.where((p) => known.add(p.id)));
        _exhausted = !page.hasMore;
      });
    } catch (error) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _showRevisions(SquarePost post) async {
    try {
      final rows = await ref.read(squareApiProvider).revisions(post.id);
      if (!mounted) return;
      // 纯告知不弹 alert(S7):页内轻提示,文案不变。
      CyNativeNotice.show(
        context,
        rows.isEmpty ? '暂无修订' : '已保留 ${rows.length} 个不可变修订版本',
      );
    } catch (error) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    }
  }

  Future<void> _openCompose({SquarePost? post}) async {
    await context.push('/square/compose', extra: post);
    if (!mounted) return;
    ref.invalidate(squareDraftsProvider);
    ref.invalidate(squareLocalDraftsProvider);
  }

  /// 修改稿的本机槽位可能在服务器列表翻页之前就没加载到对应帖文，
  /// 用槽内草稿还原编辑入口所需的字段；打开编辑器后仍会被本机草稿整体覆盖。
  SquarePost _serverPostForLocal(
    SquareLocalDraftEntry entry,
    List<SquarePost> serverItems,
  ) {
    for (final post in serverItems) {
      if (post.id == entry.postId) return post;
    }
    final draft = entry.draft;
    return SquarePost(
      id: draft.id ?? entry.postId!,
      memberId: _memberId,
      contents: draft.contents,
      pics: draft.pics,
      mediaIds: draft.existingMediaIds,
      address: draft.address,
      cityCode: draft.cityCode,
      referenceType: draft.referenceType,
      referenceId: draft.referenceId,
      communityId: draft.communityId,
      version: draft.expectedVersion,
      lifecycle: draft.sourceLifecycle,
      audience: draft.audience,
      commentPolicy: draft.commentPolicy,
      replyApprovalEnabled: draft.replyApprovalEnabled,
      slowModeSeconds: draft.slowModeSeconds,
      disclosureType: draft.disclosureType,
      mentionedMemberIds: draft.mentionedMemberIds,
      safetyLabels: draft.safetyLabels,
    );
  }

  Future<void> _deleteLocalDraft(SquareLocalDraftEntry entry) async {
    final confirmed = await cyConfirm(
      context,
      title: '删除这条本机草稿？',
      content: '仅存这台设备，删除后不可恢复。',
      confirmText: '删除',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    final done = await ref
        .read(squareLocalDraftStoreProvider)
        .clear(_memberId, postId: entry.postId);
    if (!mounted) return;
    if (done) {
      ref.invalidate(squareLocalDraftsProvider);
      CyNativeNotice.show(context, '已删除这条本机草稿');
    } else {
      CyNativeNotice.show(context, '删除失败：这台设备没能移除这条草稿，请重试', isError: true);
    }
  }

  Future<void> _showLocalDraftActions(SquareLocalDraftEntry entry) async {
    final selected = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('这条本机草稿'),
        actions: <Widget>[
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(sheetContext).pop(true),
            child: const Text('删除这条本机草稿'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    if (selected != true || !mounted) return;
    await _deleteLocalDraft(entry);
  }

  Future<void> _clearAllLocalDrafts(List<SquareLocalDraftEntry> entries) async {
    final confirmed = await cyConfirm(
      context,
      title: '清空全部本机草稿？',
      content: '共 ${entries.length} 条，删除后不可恢复。',
      confirmText: '全部删除',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    final store = ref.read(squareLocalDraftStoreProvider);
    final memberId = _memberId;
    var failed = 0;
    for (final entry in entries) {
      if (!await store.clear(memberId, postId: entry.postId)) failed++;
    }
    if (!mounted) return;
    ref.invalidate(squareLocalDraftsProvider);
    final removed = entries.length - failed;
    if (failed == 0) {
      CyNativeNotice.show(context, '已清空 ${entries.length} 条本机草稿');
    } else {
      CyNativeNotice.show(
        context,
        removed > 0 ? '已删除 $removed 条，$failed 条删除失败，可逐条重试' : '本机草稿删除失败，请重试',
        isError: true,
      );
    }
  }

  /// 服务器草稿行的「更多」钮 —— 只做删除(修订历史走行尾那颗钟,
  /// 与 `#322` 的裸图标钮收口同一条口径,菜单里不再重复一个入口)。
  Future<void> _showServerDraftActions(SquarePost post) async {
    final selected = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('这条草稿'),
        actions: <Widget>[
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(sheetContext).pop(true),
            child: const Text('删除这条草稿'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    if (selected != true || !mounted) return;
    final confirmed = await cyConfirm(
      context,
      title: '删除这条草稿？',
      content: '将从服务器删除，不可恢复。',
      confirmText: '删除',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    try {
      final msg = await ref.read(squareApiProvider).delete(post.id);
      // 服务器删掉后，这条帖的本机修改稿槽位就成了永远进不去的残留。
      var localRemnant = false;
      final store = ref.read(squareLocalDraftStoreProvider);
      if (await store.read(_memberId, postId: post.id) != null) {
        localRemnant = !await store.clear(_memberId, postId: post.id);
      }
      if (!mounted) return;
      ref.invalidate(squareDraftsProvider);
      ref.invalidate(squareLocalDraftsProvider);
      CyNativeNotice.show(
        context,
        localRemnant
            ? '${msg.isEmpty ? '已删除' : msg}，但本机修改稿未能一并移除，可在草稿列表里删除'
            : (msg.isEmpty ? '已删除' : msg),
        isError: localRemnant,
      );
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        '删除失败：${error.toString().replaceFirst('Exception: ', '')}',
        isError: true,
      );
    }
  }

  /// 页面挂在 CupertinoPageScaffold 下，没有 Material 的 DefaultTextStyle 兜底，
  /// 裸 TextStyle 会落到等宽回退上 —— 小标题一律显式取 Cupertino 系统字族。
  TextStyle _captionStyle() => CupertinoTheme.of(context).textTheme.textStyle
      .copyWith(fontSize: 13, color: CyPalette.of(context).textTertiary);

  Widget _section({String? title, required List<Widget> tiles}) =>
      CupertinoListSection.insetGrouped(
        header: title == null ? null : Text(title, style: _captionStyle()),
        children: tiles,
      );

  Widget _bodyTile({
    required Widget title,
    Widget? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Key? key,
  }) => CupertinoListTile(
    key: key,
    title: title,
    subtitle: subtitle,
    trailing: trailing,
    onTap: onTap,
  );

  List<Widget> _localTiles(
    List<SquareLocalDraftEntry> entries,
    List<SquarePost> serverItems,
  ) => <Widget>[
    for (final entry in entries)
      CupertinoListTile(
        key: ValueKey('square-local-draft-${entry.postId ?? 'new'}'),
        title: Text(
          entry.draft.contents.trim().isEmpty ? '无标题草稿' : entry.draft.contents,
        ),
        subtitle: Text(squareLocalDraftSubtitle(entry)),
        trailing: CupertinoButton(
          key: ValueKey('square-local-draft-more:${entry.postId ?? 'new'}'),
          padding: EdgeInsets.zero,
          onPressed: () => _showLocalDraftActions(entry),
          child: const Icon(CupertinoIcons.ellipsis),
        ),
        onTap:
            squarePostEditableFromWorkspace(
              entry.postId == null ? 'DRAFT' : entry.draft.sourceLifecycle,
            )
            ? () => _openCompose(
                post: entry.postId == null
                    ? null
                    : _serverPostForLocal(entry, serverItems),
              )
            : null,
      ),
  ];

  /// 服务器草稿区（状态行 + 列表行 + 分页按钮），两种布局共用。
  List<Widget> _serverTiles(
    SquareFeedPage page,
    List<SquarePost> serverItems,
  ) => <Widget>[
    for (final post in serverItems)
      CupertinoListTile(
        title: Text((post.contents ?? '').isEmpty ? '无标题草稿' : post.contents!),
        subtitle: Text(squareWorkspaceStatusLabel(post.lifecycle)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CupertinoButton(
              padding: EdgeInsets.zero,
              // L9:裸图标钮也要 44pt;A2:图标钮必须有语义名。
              minimumSize: const Size(44, 44),
              onPressed: () => _showRevisions(post),
              child: const Icon(CupertinoIcons.clock, semanticLabel: '查看修订历史'),
            ),
            CupertinoButton(
              key: ValueKey('square-server-draft-more:${post.id}'),
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: () => _showServerDraftActions(post),
              child: const Icon(
                CupertinoIcons.ellipsis,
                semanticLabel: '这条草稿的操作',
              ),
            ),
          ],
        ),
        onTap: squarePostEditableFromWorkspace(post.lifecycle)
            ? () => _openCompose(post: post)
            : null,
      ),
    if (page.hasMore && !_exhausted)
      CupertinoListTile(
        title: Center(
          child: _loadingMore
              ? const CupertinoActivityIndicator()
              : Text(
                  '加载更多草稿',
                  style: TextStyle(
                    color: CupertinoTheme.of(context).primaryColor,
                  ),
                ),
        ),
        onTap: _loadingMore ? null : () => _loadMore(page),
      ),
  ];

  List<Widget> _serverSectionChildren(AsyncValue<SquareFeedPage> drafts) {
    final page = drafts.value;
    final serverItems = <SquarePost>[...?page?.items, ..._extra];
    return drafts.when(
      loading: () => <Widget>[
        _bodyTile(title: const Center(child: CupertinoActivityIndicator())),
      ],
      error: (error, stack) => <Widget>[
        // 草稿挂在账号下:无 token 一律 401。401 说成「加载失败」会让游客
        // 以为网络有问题,反复重试(2026-09-18 截图实证)。
        if (isLoginRequiredError(error))
          _bodyTile(
            key: const Key('square-drafts-login-required'),
            title: const Text('登录后查看我的草稿'),
            subtitle: const Text('草稿存在账号下,登录完会自动回到这一页。'),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () async {
                if (!await requireLogin(context, ref)) return;
                ref.invalidate(squareDraftsProvider);
              },
              child: const Text('去登录'),
            ),
          )
        else
          _bodyTile(
            title: const Text('服务器草稿加载失败'),
            subtitle: Text(error.toString().replaceFirst('Exception: ', '')),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => ref.invalidate(squareDraftsProvider),
              child: const Text('重试'),
            ),
          ),
      ],
      data: (page) => serverItems.isEmpty
          ? <Widget>[
              _bodyTile(
                title: Text(
                  '暂无服务器草稿或待复审内容',
                  style: TextStyle(color: CyPalette.of(context).textSecondary),
                ),
              ),
            ]
          : _serverTiles(page, serverItems),
    );
  }

  List<Widget> _localSectionChildren(
    AsyncValue<List<SquareLocalDraftEntry>> local,
    List<SquarePost> serverItems,
  ) {
    if (local.isLoading) {
      return <Widget>[
        _bodyTile(title: const Center(child: CupertinoActivityIndicator())),
      ];
    }
    if (local.hasError) {
      return <Widget>[
        _bodyTile(
          title: const Text('本机草稿读取失败'),
          subtitle: const Text('草稿还在这台设备上，重试即可再次列出'),
          trailing: CupertinoButton(
            key: const Key('square-local-drafts-retry'),
            padding: EdgeInsets.zero,
            onPressed: () => ref.invalidate(squareLocalDraftsProvider),
            child: const Text('重试'),
          ),
        ),
      ];
    }
    final entries = local.value ?? const <SquareLocalDraftEntry>[];
    return _localTiles(entries, serverItems);
  }

  @override
  Widget build(BuildContext context) {
    final drafts = ref.watch(squareDraftsProvider);
    final local = ref.watch(squareLocalDraftsProvider);
    final localEntries = local.value ?? const <SquareLocalDraftEntry>[];
    final serverItems = <SquarePost>[...?drafts.value?.items, ..._extra];
    final hasLocalSection =
        local.isLoading || local.hasError || localEntries.isNotEmpty;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('我的草稿'),
        trailing: localEntries.isEmpty
            ? null
            : CupertinoButton(
                key: const Key('square-local-drafts-clear-all'),
                padding: EdgeInsets.zero,
                onPressed: () => _clearAllLocalDrafts(localEntries),
                child: Text(
                  '清空全部',
                  style: TextStyle(color: CyPalette.of(context).statusDanger),
                ),
              ),
      ),
      child: SafeArea(
        child: hasLocalSection
            ? ListView(
                padding: const EdgeInsets.only(bottom: CyTokens.space4),
                children: <Widget>[
                  _section(
                    title: '本机草稿',
                    tiles: _localSectionChildren(local, serverItems),
                  ),
                  _section(
                    title: '服务器草稿',
                    tiles: _serverSectionChildren(drafts),
                  ),
                ],
              )
            : drafts.when(
                loading: () =>
                    const Center(child: CupertinoActivityIndicator()),
                // 草稿挂在账号下:无 token 一律 401。401 说成「加载失败」会让游客
                // 以为网络有问题,反复重试(2026-09-18 截图实证)。
                error: (error, stack) => isLoginRequiredError(error)
                    ? StatusView(
                        key: const Key('square-drafts-login-required'),
                        message: '登录后查看我的草稿',
                        sub: '草稿存在账号下,登录完会自动回到这一页。',
                        icon: CupertinoIcons.lock,
                        retryLabel: '去登录',
                        onRetry: () async {
                          if (!await requireLogin(context, ref)) return;
                          ref.invalidate(squareDraftsProvider);
                        },
                      )
                    : StatusView(
                        message: '草稿加载失败',
                        icon: CupertinoIcons.doc_text,
                        onRetry: () => ref.invalidate(squareDraftsProvider),
                      ),
                data: (page) {
                  final items = <SquarePost>[...page.items, ..._extra];
                  return items.isEmpty
                      ? const StatusView(
                          message: '暂无草稿或待复审内容',
                          icon: CupertinoIcons.doc,
                        )
                      : ListView(
                          padding: const EdgeInsets.only(top: CyTokens.space1),
                          children: <Widget>[
                            _section(tiles: _serverTiles(page, items)),
                          ],
                        );
                },
              ),
      ),
    );
  }
}
