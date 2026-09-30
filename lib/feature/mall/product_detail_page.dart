import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/product.dart';
import '../auth/login_gate.dart';
import 'mall_controller.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_net_image.dart';

/// 商品详情:主图 / 名 / 价格 / 库存 / 规格 + 加入购物车(底部弹窗选数量)。
class ProductDetailPage extends ConsumerWidget {
  const ProductDetailPage({super.key, required this.productId});
  final int productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(productDetailProvider(productId));
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        trailing: Semantics(
          button: true,
          label: '购物车',
          child: SizedBox.square(
            dimension: 44,
            child: CupertinoButton(
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
              onPressed: () => context.push('/cart'),
              child: const Icon(CupertinoIcons.cart),
            ),
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            // 页标题左对齐:Column 默认 crossAxisAlignment 是 center,
            // 不显式 stretch 会把 58rpx 大标题推到屏幕正中,与小程序完全不同。
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const CyPageTitle('商品详情'),
              Expanded(
                child: detail.when(
                  loading: () => const CySkeleton(type: CySkeletonType.detail),
                  error: (Object err, StackTrace st) => isMallLoginRequired(err)
                      // ★ 游客从列表点卡片必然走到这里:列表 `/api/product/list` 对游客
                      //   200(所以卡片看得见、点得动),详情 `/api/product/info` 却 401
                      //   —— 同一个商品的两个读接口口径不一致,死路落在详情页。
                      //   通用错误态在这里是误导:重试永远还是 401,也没有登录出口,
                      //   换成可恢复的登录引导(判据同活动详情页 2026-08-18)。
                      ? StatusView(
                          message: '登录后查看商品详情',
                          sub: '这一步需要登录,登录完会自动回到这一页。',
                          icon: Icons.lock_outline,
                          scrollable: true,
                          retryLabel: '去登录',
                          onRetry: () async {
                            if (!await requireLogin(context, ref)) return;
                            ref.invalidate(productDetailProvider(productId));
                          },
                        )
                      : StatusView(
                          message: '商品拉取失败',
                          sub: '请检查网络或稍后再试。',
                          icon: Icons.cloud_off,
                          scrollable: true,
                          onRetry: () =>
                              ref.invalidate(productDetailProvider(productId)),
                        ),
                  data: (Product p) => _DetailBody(product: p),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final images = product.albumList.isNotEmpty
        ? product.albumList
        : <String>[
            if (product.pic != null && product.pic!.isNotEmpty) product.pic!,
          ];
    return Stack(
      children: <Widget>[
        ListView(
          padding: EdgeInsets.fromLTRB(
            CyTokens.space4,
            CyTokens.space4,
            CyTokens.space4,
            CyTokens.space8 * 2,
          ),
          children: <Widget>[
            _MainImage(url: images.isNotEmpty ? images.first : null),
            const SizedBox(height: CyTokens.space4),
            Text(
              product.productName.isEmpty ? '未命名商品' : product.productName,
              style: CyType.headline.copyWith(
                height: CyTokens.leadingTight,
                color: CyTokens.textPrimary,
              ),
            ),
            const SizedBox(height: CyTokens.space2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  formatPoints(product.pricePoints),
                  style: CyType.title1.copyWith(
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                    color: CyTokens.textPrimary,
                  ),
                ),
                if (product.originalPricePoints != null) ...<Widget>[
                  const SizedBox(width: CyTokens.space2),
                  Text(
                    formatPoints(product.originalPricePoints),
                    style: CyType.subhead.copyWith(
                      color: CyTokens.textTertiary,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: CyTokens.space2),
            Text(
              '库存 ${product.stock}${product.unit ?? ''}',
              style: CyType.caption1.copyWith(color: CyTokens.textTertiary),
            ),
            if (product.skuList.isNotEmpty) ...<Widget>[
              const SizedBox(height: CyTokens.space5),
              const CySectionTitle('规格'),
              const SizedBox(height: CyTokens.space2),
              Wrap(
                spacing: CyTokens.space2,
                runSpacing: CyTokens.space2,
                children: product.skuList
                    .map(
                      (ProductSku s) => Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: CyTokens.space3,
                          vertical: CyTokens.space1_5,
                        ),
                        decoration: BoxDecoration(
                          color: CyTokens.bgSubtle,
                          borderRadius: BorderRadius.circular(
                            CyTokens.radiusPill,
                          ),
                          border: Border.all(color: CyTokens.borderSubtle),
                        ),
                        child: Text(
                          s.skuName?.isNotEmpty ?? false ? s.skuName! : '默认规格',
                          style: CyType.caption1.copyWith(
                            color: CyTokens.textSecondary,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _BottomBar(product: product),
        ),
      ],
    );
  }
}

class _BottomBar extends ConsumerWidget {
  const _BottomBar({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool hasAvailableSku = product.skuList.any(
      (ProductSku sku) => sku.id > 0 && sku.stock > 0 && sku.price != null,
    );
    final bool missingSku = product.skuList.isEmpty;
    // 详情接口已返回可下单的 SKU；加购及服务端校验也以 SKU 库存为准。
    // 商品聚合库存可能滞后，不能用它覆盖明确可用的 SKU。
    final bool soldOut = !missingSku && !hasAvailableSku;
    return CyFooterBar(
      primary: CyNativeButton(
        label: missingSku ? '暂无可用规格' : (soldOut ? '已售罄' : '加入购物车'),
        onPressed: soldOut || missingSku
            ? null
            : () async {
                if (!await requireLogin(context, ref)) return;
                if (!context.mounted) return;
                showCupertinoSheet<void>(
                  context: context,
                  showDragHandle: true,
                  topGap: 0.28,
                  scrollableBuilder:
                      (
                        BuildContext context,
                        ScrollController scrollController,
                      ) => _AddToCartSheet(
                        product: product,
                        scrollController: scrollController,
                      ),
                );
              },
      ),
    );
  }
}

/// 加购弹窗:数量增减(>=1,<=stock),提交后刷新购物车。
class _AddToCartSheet extends ConsumerStatefulWidget {
  const _AddToCartSheet({
    required this.product,
    required this.scrollController,
  });

  final Product product;
  final ScrollController scrollController;

  @override
  ConsumerState<_AddToCartSheet> createState() => _AddToCartSheetState();
}

class _AddToCartSheetState extends ConsumerState<_AddToCartSheet> {
  int _qty = 1;
  int? _selectedSkuId;
  bool _busy = false;

  ProductSku? get _selectedSku {
    for (final ProductSku sku in widget.product.skuList) {
      if (sku.id == _selectedSkuId) return sku;
    }
    return null;
  }

  int get _maxQty {
    final int stock = _selectedSku?.stock ?? 0;
    return stock > 0 ? stock : 1;
  }

  @override
  void initState() {
    super.initState();
    for (final ProductSku sku in widget.product.skuList) {
      if (sku.id > 0 && sku.stock > 0 && sku.price != null) {
        _selectedSkuId = sku.id;
        break;
      }
    }
  }

  void _selectSku(ProductSku sku) {
    if (_busy || sku.id <= 0 || sku.stock <= 0 || sku.price == null) return;
    setState(() {
      _selectedSkuId = sku.id;
      if (_qty > sku.stock) _qty = sku.stock;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final ProductSku? sku = _selectedSku;
    if (sku == null || sku.id <= 0 || sku.stock <= 0 || sku.price == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(mallApiProvider)
          .cartAdd(productId: widget.product.id, skuId: sku.id, quantity: _qty);
      if (!mounted) return;
      ref.invalidate(cartListProvider);
      Navigator.of(context).pop();
      CyNativeNotice.show(context, '已加入购物车');
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
    final ProductSku? selectedSku = _selectedSku;
    return CupertinoPageScaffold(
      backgroundColor: CyTokens.bgSurface,
      child: SafeArea(
        top: false,
        child: ListView(
          controller: widget.scrollController,
          padding: EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space4,
            CyTokens.pageX,
            CyTokens.space5 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: <Widget>[
            Text(
              widget.product.productName.isEmpty
                  ? '商品'
                  : widget.product.productName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CyType.headline.copyWith(color: CyTokens.textPrimary),
            ),
            const SizedBox(height: CyTokens.space2),
            Text(
              formatPoints(selectedSku?.price),
              style: CyType.title1.copyWith(
                height: 1.15,
                fontWeight: FontWeight.w700,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                color: CyTokens.textPrimary,
              ),
            ),
            const SizedBox(height: CyTokens.space5),
            Text(
              '规格',
              style: CyType.subhead.copyWith(color: CyTokens.textSecondary),
            ),
            const SizedBox(height: CyTokens.space2),
            Wrap(
              spacing: CyTokens.space2,
              runSpacing: CyTokens.space2,
              children: widget.product.skuList
                  .map((ProductSku sku) {
                    final bool selected = sku.id == _selectedSkuId;
                    final bool enabled =
                        !_busy &&
                        sku.id > 0 &&
                        sku.stock > 0 &&
                        sku.price != null;
                    return Semantics(
                      button: true,
                      selected: selected,
                      enabled: enabled,
                      label:
                          '${sku.skuName?.isNotEmpty == true ? sku.skuName! : '默认规格'}${sku.stock <= 0 ? '，已售罄' : ''}',
                      child: CupertinoButton(
                        key: Key('mall-sku-${sku.id}'),
                        minimumSize: const Size(44, 44),
                        padding: const EdgeInsets.symmetric(
                          horizontal: CyTokens.space3,
                          vertical: CyTokens.space2,
                        ),
                        color: selected
                            ? CyTokens.bgElevated
                            : CyTokens.bgSubtle,
                        disabledColor: CyTokens.bgSubtle,
                        borderRadius: BorderRadius.circular(
                          CyTokens.radiusPill,
                        ),
                        onPressed: enabled ? () => _selectSku(sku) : null,
                        child: Text(
                          '${sku.skuName?.isNotEmpty == true ? sku.skuName! : '默认规格'}${sku.stock <= 0 ? ' · 已售罄' : ''}',
                          style: CyType.body.copyWith(
                            color: enabled
                                ? CyTokens.textPrimary
                                : CyTokens.textDisabled,
                          ),
                        ),
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
            const SizedBox(height: CyTokens.space5),
            Row(
              children: <Widget>[
                Text(
                  '数量',
                  style: CyType.subhead.copyWith(color: CyTokens.textSecondary),
                ),
                const Spacer(),
                _QtyStepper(
                  value: _qty,
                  min: 1,
                  max: _maxQty,
                  onChanged: _busy ? null : (int v) => setState(() => _qty = v),
                ),
              ],
            ),
            const SizedBox(height: CyTokens.space5),
            CyNativeButton(
              label: selectedSku == null ? '请选择可用规格' : '确认加入',
              onPressed: _busy || selectedSku == null ? null : _submit,
              loading: _busy,
            ),
          ],
        ),
      ),
    );
  }
}

/// 数量加减步进器(边界:>=min,<=max)。onChanged 为 null 时禁用。
class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final int value;
  final int min;
  final int max;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final canDec = onChanged != null && value > min;
    final canInc = onChanged != null && value < max;
    return Container(
      decoration: BoxDecoration(
        color: CyTokens.bgElevated,
        borderRadius: BorderRadius.circular(CyTokens.radiusSm),
        border: Border.all(color: CyTokens.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Semantics(
            button: true,
            label: '减少数量',
            value: '$value',
            enabled: canDec,
            child: ExcludeSemantics(
              child: CupertinoButton(
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
                foregroundColor: canDec
                    ? CyTokens.textPrimary
                    : CyTokens.textDisabled,
                onPressed: canDec ? () => onChanged!(value - 1) : null,
                child: const Icon(CupertinoIcons.minus, size: 18),
              ),
            ),
          ),
          Text('$value', style: CyType.body),
          Semantics(
            button: true,
            label: '增加数量',
            value: '$value',
            enabled: canInc,
            child: ExcludeSemantics(
              child: CupertinoButton(
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
                foregroundColor: canInc
                    ? CyTokens.textPrimary
                    : CyTokens.textDisabled,
                onPressed: canInc ? () => onChanged!(value + 1) : null,
                child: const Icon(CupertinoIcons.plus, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MainImage extends StatelessWidget {
  const _MainImage({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    // 兜底走共用件:加载不出来安静铺一块同色底,不摆 Material 碎图标。
    return CyNetImage(
      url,
      width: double.infinity,
      height: 240,
      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
    );
  }
}
