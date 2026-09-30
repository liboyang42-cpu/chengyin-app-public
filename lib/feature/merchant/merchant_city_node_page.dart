import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/merchant_city_node.dart';
import 'merchant_error_view.dart';

final cityNodesProvider = FutureProvider.autoDispose<CityNodeHome>((ref) {
  return ref.watch(merchantApiProvider).cityNodes();
});

/// 商家城市据点。对齐小程序 `pages/merchant/citynode`。
class MerchantCityNodePage extends ConsumerWidget {
  const MerchantCityNodePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<CityNodeHome> async = ref.watch(cityNodesProvider);
    final TextTheme textTheme = Theme.of(context).textTheme;
    final CyPalette palette = CyPalette.of(context);

    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('成为节点'),
        trailing: CupertinoButton(
          key: const Key('citynode-redeem-entry'),
          onPressed: () =>
              GoRouter.of(context).push('/merchant/city-nodes/redeem'),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          child: Semantics(
            button: true,
            label: '扫码核销玩家到店券',
            child: const Icon(CupertinoIcons.qrcode_viewfinder, size: 22),
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: async.when(
            loading: () => const Center(child: CupertinoActivityIndicator()),
            error: (Object e, _) => merchantErrorView(
              context,
              e,
              what: '据点',
              onRetry: () => ref.invalidate(cityNodesProvider),
            ),
            data: (CityNodeHome home) => RefreshIndicator.adaptive(
              onRefresh: () async => ref.invalidate(cityNodesProvider),
              child: ListView(
                padding: const EdgeInsets.all(CyTokens.pageX),
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '把门店变成漫游地图上的互动据点',
                          style: textTheme.titleMedium,
                        ),
                      ),
                      CupertinoButton(
                        key: const Key('city-node-info'),
                        minimumSize: const Size(44, 44),
                        padding: EdgeInsets.zero,
                        foregroundColor: palette.textSecondary,
                        onPressed: () => cyConfirm(
                          context,
                          title: '据点是什么',
                          content:
                              '据点就是门店在漫游地图上的互动打卡点。投放或认领申请经平台审核通过后，玩家才会在地图看到；到店可按模板完成暗号、问答、拍照、扫码或 GPS 验证。',
                          confirmText: '知道了',
                          showCancel: false,
                        ),
                        child: const Icon(CupertinoIcons.info_circle),
                      ),
                    ],
                  ),
                  if (home.quotaText != null)
                    Text(
                      '在架据点 ${home.used}/${home.max}',
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  const SizedBox(height: CyTokens.space4),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text('我的据点', style: textTheme.titleMedium),
                      ),
                      CupertinoButton(
                        key: const Key('city-node-claim-entry'),
                        minimumSize: const Size(44, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        onPressed: () => _openClaim(context, ref),
                        child: const Text('认领节点'),
                      ),
                      CupertinoButton(
                        key: const Key('city-node-create-entry'),
                        minimumSize: const Size(44, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        onPressed: () async {
                          if (home.quotaExhausted) {
                            CyNativeNotice.show(context, '在架据点已达上限,请先下线其他据点');
                            return;
                          }
                          final Object? ok = await GoRouter.of(
                            context,
                          ).push('/merchant/city-nodes/create');
                          if (ok == true) ref.invalidate(cityNodesProvider);
                        },
                        child: const Text('+ 投放据点'),
                      ),
                    ],
                  ),
                  const SizedBox(height: CyTokens.space2),
                  ...home.applications.map(
                    (CityNodeApplication application) =>
                        _ApplicationTile(application: application),
                  ),
                  if (home.nodes.isEmpty && home.applications.isEmpty)
                    const StatusView(message: '还没有据点', sub: '提交投放申请，把门店放上漫游地图'),
                  ...home.nodes.map((CityNode node) => _NodeTile(node: node)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openClaim(BuildContext context, WidgetRef ref) async {
    final claimed = await showCupertinoSheet<bool>(
      context: context,
      showDragHandle: true,
      topGap: 0.14,
      scrollableBuilder:
          (BuildContext context, ScrollController scrollController) =>
              _ClaimSheet(scrollController: scrollController),
    );
    if (claimed == true) ref.invalidate(cityNodesProvider);
  }
}

/// 我的据点里的一条申请。认领待审时右侧给「撤回申请」——
/// 撤回后节点回到可认领池,别人才能认领(快照 citynode/index.js:308)。
class _ApplicationTile extends ConsumerStatefulWidget {
  const _ApplicationTile({required this.application});

  final CityNodeApplication application;

  @override
  ConsumerState<_ApplicationTile> createState() => _ApplicationTileState();
}

class _ApplicationTileState extends ConsumerState<_ApplicationTile> {
  bool _cancelling = false;

  /// 只有「节点认领 + 待审」可撤回;投放申请与已审结的都不给按钮。
  bool get _canCancel =>
      widget.application.applicationType == 2 && widget.application.status == 0;

  Future<void> _cancel() async {
    setState(() => _cancelling = true);
    try {
      await ref.read(merchantApiProvider).cancelClaim(widget.application.id);
      ref.invalidate(cityNodesProvider);
      if (!mounted) return;
      CyNativeNotice.show(context, '已撤回认领申请');
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final CityNodeApplication application = widget.application;
    return CyCell(
      title: application.displayTitle,
      subtitle: application.statusText,
      showChevron: false,
      trailing: _canCancel
          ? CupertinoButton(
              key: Key('city-node-cancel-claim-${application.id}'),
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: _cancelling ? null : _cancel,
              child: Text(_cancelling ? '撤回中' : '撤回申请'),
            )
          : null,
    );
  }
}

class _NodeTile extends ConsumerStatefulWidget {
  const _NodeTile({required this.node});
  final CityNode node;

  @override
  ConsumerState<_NodeTile> createState() => _NodeTileState();
}

class _NodeTileState extends ConsumerState<_NodeTile> {
  bool _busy = false;

  Future<void> _showPoster() async {
    setState(() => _busy = true);
    try {
      final data = await ref
          .read(merchantApiProvider)
          .nodePosterCode(widget.node.id);
      if (!mounted) return;
      final url = data['qrcodeUrl'] as String?;
      await showCupertinoSheet<void>(
        context: context,
        showDragHandle: true,
        topGap: 0.22,
        scrollableBuilder:
            (BuildContext sheetContext, ScrollController scrollController) {
              final CyPalette palette = CyPalette.of(sheetContext);
              return CupertinoPageScaffold(
                backgroundColor: palette.bgPage,
                navigationBar: const CupertinoNavigationBar(
                  middle: Text('到店打卡码'),
                ),
                child: SafeArea(
                  top: false,
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(CyTokens.pageX),
                    children: <Widget>[
                      if (url != null && url.isNotEmpty)
                        Center(child: CyNetImage(url, width: 200, height: 200))
                      else
                        const Text('打卡码暂时没能生成，请稍后重试'),
                      const SizedBox(height: CyTokens.space3),
                      Text(
                        (data['nodeName'] as String?) ?? widget.node.name,
                        textAlign: TextAlign.center,
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                      const SizedBox(height: CyTokens.space2),
                      Text(
                        '长按保存并打印张贴。玩家到店扫码完成互动。',
                        textAlign: TextAlign.center,
                        style: Theme.of(sheetContext).textTheme.bodySmall
                            ?.copyWith(color: palette.textSecondary),
                      ),
                      Text(
                        '这张码长期有效，请妥善保管。',
                        textAlign: TextAlign.center,
                        style: Theme.of(sheetContext).textTheme.bodySmall
                            ?.copyWith(color: palette.textSecondary),
                      ),
                      const SizedBox(height: CyTokens.space4),
                      CupertinoButton(
                        minimumSize: const Size.fromHeight(44),
                        color: palette.actionPrimaryBg,
                        foregroundColor: palette.actionPrimaryFg,
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
                ),
              );
            },
      );
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleStatus() async {
    final bool online = widget.node.status != 1;
    setState(() => _busy = true);
    try {
      final String message = await ref
          .read(merchantApiProvider)
          .setNodeStatus(widget.node.id, online: online);
      ref.invalidate(cityNodesProvider);
      if (!mounted) return;
      CyNativeNotice.show(context, message);
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: CyTokens.space2),
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: CyPalette.of(context).borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.node.name, style: textTheme.titleSmall),
          if ((widget.node.templateTitle ?? '').isNotEmpty ||
              (widget.node.tagsText ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                <String>[
                  if ((widget.node.templateTitle ?? '').isNotEmpty)
                    widget.node.templateTitle!,
                  if ((widget.node.tagsText ?? '').isNotEmpty)
                    widget.node.tagsText!,
                ].join(' · '),
                style: textTheme.bodySmall?.copyWith(
                  color: CyPalette.of(context).textSecondary,
                ),
              ),
            ),
          const SizedBox(height: CyTokens.space2),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              if (widget.node.validationMethod == 4)
                CupertinoButton(
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  onPressed: _busy ? null : _showPoster,
                  child: const Text('取到店打卡码 ›'),
                ),
              CupertinoButton(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: _busy ? null : _toggleStatus,
                child: Text(widget.node.status == 1 ? '下线' : '上架'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClaimSheet extends ConsumerStatefulWidget {
  const _ClaimSheet({required this.scrollController});

  final ScrollController scrollController;

  @override
  ConsumerState<_ClaimSheet> createState() => _ClaimSheetState();
}

class _ClaimSheetState extends ConsumerState<_ClaimSheet> {
  List<CityNode>? _rows;
  bool _loading = false;
  String? _error;
  int? _claiming;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref.read(merchantApiProvider).claimableNodes();
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _claim(CityNode node) async {
    setState(() => _claiming = node.id);
    try {
      await ref.read(merchantApiProvider).claimNode(node.id);
      if (!mounted) return;
      final BuildContext noticeContext = Navigator.of(context).context;
      Navigator.of(context).pop(true);
      CyNativeNotice.show(noticeContext, '认领申请已提交');
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _claiming = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      resizeToAvoidBottomInset: true,
      navigationBar: const CupertinoNavigationBar(middle: Text('认领平台节点')),
      child: SafeArea(
        top: false,
        child: ListView(
          controller: widget.scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space4,
            CyTokens.pageX,
            CyTokens.space4 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: <Widget>[_body()],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(CyTokens.space5),
        child: Center(child: CupertinoActivityIndicator()),
      );
    }
    if (_error != null) {
      return StatusView(message: '没能加载地点', sub: _error, onRetry: _search);
    }
    final rows = _rows ?? const <CityNode>[];
    if (rows.isEmpty) {
      return const StatusView(message: '暂无可认领节点', sub: '已被认领或有申请审核中的节点不会重复展示');
    }
    return Column(
      children: <Widget>[
        for (final CityNode n in rows)
          CyCell(
            title: n.name,
            subtitle: n.address,
            // 正在提交的那一条禁用,防连点建出两条申请。
            onTap: _claiming == null ? () => _claim(n) : null,
          ),
      ],
    );
  }
}
