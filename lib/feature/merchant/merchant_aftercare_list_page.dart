import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_tabs.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/merchant_aftercare_api.dart';
import '../../data/api/merchant_api.dart';
import '../../data/models/merchant_aftercare.dart';

class MerchantAftercareListPage extends StatefulWidget {
  const MerchantAftercareListPage({
    super.key,
    required this.api,
    this.onOpenDetail,
  });

  final MerchantAftercareGateway api;
  final ValueChanged<int>? onOpenDetail;

  @override
  State<MerchantAftercareListPage> createState() =>
      _MerchantAftercareListPageState();
}

class _MerchantAftercareListPageState extends State<MerchantAftercareListPage> {
  static const int _pageSize = 20;

  MerchantAftercareBucket _bucket = MerchantAftercareBucket.pending;
  List<MerchantAftercareListItem> _items = const <MerchantAftercareListItem>[];
  int _total = 0;
  int _pageNum = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  int _requestToken = 0;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadFirstPage);
  }

  @override
  void dispose() {
    _requestToken += 1;
    super.dispose();
  }

  Future<void> _loadFirstPage() async {
    final int token = ++_requestToken;
    setState(() {
      _loading = true;
      _error = null;
      _items = const <MerchantAftercareListItem>[];
      _total = 0;
    });
    try {
      final MerchantAftercarePage page = await widget.api.listPage(
        bucket: _bucket,
        pageNum: 1,
        pageSize: _pageSize,
      );
      if (!mounted || token != _requestToken) return;
      setState(() {
        _items = page.items;
        _total = page.total;
        _pageNum = page.pageNum;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loading || _loadingMore) return;
    final int token = _requestToken;
    setState(() => _loadingMore = true);
    try {
      final MerchantAftercarePage page = await widget.api.listPage(
        bucket: _bucket,
        pageNum: _pageNum + 1,
        pageSize: _pageSize,
      );
      if (!mounted || token != _requestToken) return;
      setState(() {
        _items = <MerchantAftercareListItem>[..._items, ...page.items];
        _total = page.total;
        _pageNum = page.pageNum;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || token != _requestToken) return;
      setState(() => _loadingMore = false);
    }
  }

  void _selectBucket(String key) {
    final MerchantAftercareBucket next = MerchantAftercareBucket.values
        .firstWhere((MerchantAftercareBucket value) => value.wire == key);
    if (next == _bucket) return;
    setState(() => _bucket = next);
    _loadFirstPage();
  }

  void _open(int refundId) {
    final ValueChanged<int>? callback = widget.onOpenDetail;
    if (callback != null) {
      callback(refundId);
      return;
    }
    context.push('/merchant/aftercare/$refundId');
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space2,
            CyTokens.pageX,
            CyTokens.space2,
          ),
          child: SizedBox(
            width: double.infinity,
            child: CyTabs(
              variant: CyTabsVariant.segmented,
              tabs: MerchantAftercareBucket.values
                  .map(
                    (MerchantAftercareBucket bucket) =>
                        CyTab(key: bucket.wire, label: bucket.label),
                  )
                  .toList(growable: false),
              active: _bucket.wire,
              onChanged: _selectBucket,
            ),
          ),
        ),
        Expanded(child: _body(context)),
      ],
    );
    return CupertinoPageScaffold(
      backgroundColor: CyPalette.of(context).bgPage,
      navigationBar: const CupertinoNavigationBar(middle: Text('退款售后')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(bottom: false, child: content),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const CySkeleton(type: CySkeletonType.list, count: 4);
    }
    final Object? error = _error;
    if (error is MerchantAccessDeniedException) {
      return StatusView(
        icon: CupertinoIcons.lock,
        message: error.message,
        sub: '请联系店主调整经营团队权限',
        large: true,
      );
    }
    if (error is MerchantAftercareApiException && error.isForbidden) {
      return const StatusView(
        icon: CupertinoIcons.lock,
        message: '当前岗位没有售后查看权限',
        sub: '请联系店主调整经营团队权限',
        large: true,
      );
    }
    if (error != null) {
      return StatusView(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: '售后列表没能加载出来',
        sub: error.toString(),
        large: true,
        onRetry: _loadFirstPage,
        retryLabel: '重新加载',
      );
    }
    if (_items.isEmpty) {
      return StatusView(
        icon: CupertinoIcons.doc_text,
        message: switch (_bucket) {
          MerchantAftercareBucket.pending => '没有待回应售后',
          MerchantAftercareBucket.processing => '没有处理中的售后',
          MerchantAftercareBucket.completed => '还没有已完成售后',
        },
        sub: '退款申请会按平台审核与款项真实状态显示在这里',
        large: true,
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        final bool reachedBottom =
            notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - 80 ||
            notification is OverscrollNotification &&
                notification.overscroll > 0;
        if (reachedBottom) _loadMore();
        return false;
      },
      child: RefreshIndicator.adaptive(
        onRefresh: _loadFirstPage,
        child: ListView.separated(
          key: const Key('aftercare-list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            0,
            CyTokens.pageX,
            CyTokens.space8,
          ),
          itemCount: _items.length + 2,
          separatorBuilder: (_, _) => const SizedBox(height: CyTokens.space3),
          itemBuilder: (BuildContext context, int index) {
            if (index == 0) {
              return Text(
                '共 $_total 笔',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: CyPalette.of(context).textSecondary,
                ),
              );
            }
            if (index == _items.length + 1) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(CyTokens.space3),
                  child: _loadingMore
                      ? const CupertinoActivityIndicator()
                      : Text(_hasMore ? '上滑加载更多' : '已经到底了'),
                ),
              );
            }
            final MerchantAftercareListItem item = _items[index - 1];
            return _AftercareCard(
              item: item,
              onPressed: () => _open(item.refundId),
            );
          },
        ),
      ),
    );
  }
}

class _AftercareCard extends StatelessWidget {
  const _AftercareCard({required this.item, required this.onPressed});

  final MerchantAftercareListItem item;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '打开售后 ${item.refundNoText}',
      child: CupertinoButton(
        key: Key('aftercare-item-${item.refundId}'),
        padding: EdgeInsets.zero,
        minimumSize: const Size.fromHeight(44),
        pressedOpacity: MediaQuery.disableAnimationsOf(context) ? 1 : 0.72,
        onPressed: onPressed,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(CyTokens.space4),
          decoration: BoxDecoration(
            color: palette.bgSurface,
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
            border: Border.all(color: palette.cardBorder),
            boxShadow: palette.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.sourceText,
                          style: textTheme.bodySmall?.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                        const SizedBox(height: CyTokens.space1),
                        Text(
                          item.refundNoText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleSmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: CyTokens.space3),
                  Text(
                    item.refundAmountText,
                    style: textTheme.titleMedium?.copyWith(
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CyTokens.space3),
              Wrap(
                spacing: CyTokens.space2,
                runSpacing: CyTokens.space1,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _StatusPill(label: item.processingText),
                  Text(
                    item.merchantOpinionText,
                    style: textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
              if (item.reason != null) ...<Widget>[
                const SizedBox(height: CyTokens.space3),
                Text(item.reason!, style: textTheme.bodyMedium),
              ],
              const SizedBox(height: CyTokens.space3),
              Divider(height: 1, color: palette.borderSubtle),
              const SizedBox(height: CyTokens.space3),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _minute(item.createTime) ?? '时间待确认',
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    item.canRespond ? '去回应' : '查看详情',
                    style: textTheme.bodySmall?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: CyTokens.space1),
                  Icon(
                    CupertinoIcons.chevron_forward,
                    size: 15,
                    color: palette.textSecondary,
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: CyTokens.space2,
      vertical: CyTokens.space1,
    ),
    decoration: BoxDecoration(
      color: CyPalette.of(context).bgSubtle,
      borderRadius: BorderRadius.circular(CyTokens.radiusPill),
    ),
    child: Text(label, style: Theme.of(context).textTheme.bodySmall),
  );
}

String? _minute(DateTime? value) {
  if (value == null) return null;
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
