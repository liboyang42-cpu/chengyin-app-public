import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/product.dart';
import 'mall_controller.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_swipe_actions.dart';
import '../../core/widgets/cy_net_image.dart';
import '../auth/login_gate.dart';
import 'cart_checkout_sheet.dart';

/// 积分商城购物车:商品 + 数量增减 + 删除 + 积分合计 + 兑换结算。
class CartPage extends ConsumerWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartListProvider);
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            // 页标题左对齐:Column 默认 crossAxisAlignment 是 center,
            // 不显式 stretch 会把 58rpx 大标题推到屏幕正中,与小程序完全不同。
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const CyPageTitle('购物车'),
              Expanded(
                child: cart.when(
                  loading: () =>
                      const CySkeleton(type: CySkeletonType.card, count: 4),
                  error: (Object err, StackTrace st) => isMallLoginRequired(err)
                      // ★ 购物车 7 个接口对游客全是 401(实测生产),而购物车本来
                      //   按账号存 —— 游客看到的不该是「购物车拉取失败/请检查网络」,
                      //   而该是「登录后查看」+ 一个真能走通的出口。
                      ? StatusView(
                          message: '登录后查看购物车',
                          sub: '购物车按账号存,登录完会自动回到这一页。',
                          icon: Icons.lock_outline,
                          scrollable: true,
                          retryLabel: '去登录',
                          onRetry: () async {
                            if (!await requireLogin(context, ref)) return;
                            ref.invalidate(cartListProvider);
                          },
                        )
                      : StatusView(
                          message: '购物车拉取失败',
                          sub: '请检查网络或稍后再试。',
                          icon: Icons.cloud_off,
                          scrollable: true,
                          onRetry: () => ref.invalidate(cartListProvider),
                        ),
                  data: (List<CartItem> items) {
                    if (items.isEmpty) {
                      return StatusView(
                        message: '购物车空空如也',
                        sub: '去商城逛逛,把想买的商品加进来吧。',
                        icon: Icons.shopping_cart_outlined,
                        scrollable: true,
                        onRetry: () => ref.invalidate(cartListProvider),
                      );
                    }
                    return _CartBody(items: items);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartBody extends ConsumerStatefulWidget {
  const _CartBody({required this.items});
  final List<CartItem> items;

  @override
  ConsumerState<_CartBody> createState() => _CartBodyState();
}

class _CartBodyState extends ConsumerState<_CartBody> {
  /// 同一时刻只允许开一行(iOS 行为),由列表持有。
  Object? _openRow;

  /// 积分合计。★ 只累加**拿得到价**的行。
  double get _total => widget.items
      .where((CartItem e) => e.hasPrice)
      .fold(0, (double sum, CartItem e) => sum + e.subtotalPoints!);

  /// 有没有行拿不到价 —— 有的话合计就是**不完整的**,必须说出来,
  /// 不能让用户拿着一个偏小的数去结账。
  bool get _totalIncomplete => widget.items.any((CartItem e) => !e.hasPrice);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(CyTokens.space4),
            itemCount: widget.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: CyTokens.space3),
            itemBuilder: (context, i) => _CartRow(
              item: widget.items[i],
              openKey: _openRow,
              onOpenChanged: (Object? opened) =>
                  setState(() => _openRow = opened),
            ),
          ),
        ),
        _CartFooter(
          items: widget.items,
          total: _total,
          incomplete: _totalIncomplete,
        ),
      ],
    );
  }
}

class _CartRow extends ConsumerStatefulWidget {
  const _CartRow({
    required this.item,
    required this.openKey,
    required this.onOpenChanged,
  });
  final CartItem item;
  final Object? openKey;
  final ValueChanged<Object?> onOpenChanged;

  @override
  ConsumerState<_CartRow> createState() => _CartRowState();
}

class _CartRowState extends ConsumerState<_CartRow> {
  bool _busy = false;

  Future<void> _changeQty(int qty) async {
    if (qty < 1) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(mallApiProvider)
          .cartUpdate(
            cartId: widget.item.id,
            quantity: qty,
            skuId: widget.item.skuId,
          );
      ref.invalidate(cartListProvider);
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

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await ref.read(mallApiProvider).cartDelete(widget.item.id);
      ref.invalidate(cartListProvider);
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
    final item = widget.item;
    return CySwipeActionsRow(
      key: Key('cart-row-${item.id}'),
      rowKey: item.id,
      openKey: widget.openKey,
      onOpenChanged: widget.onOpenChanged,
      enabled: !_busy,
      // 行内单删按钮收进左滑(#382 P0「我的内容列表左滑操作」rollout);
      // 动作/接口不变 —— onPressed 仍指原 _delete,组件默认
      // 「划到底不执行、必须点一下」。
      trailing: <CyContextualAction>[
        CyContextualAction(
          id: 'cart-delete-${item.id}',
          label: '删除',
          // VoiceOver 文案逐字沿用旧行内钮「删除{商品名}」。
          semanticLabel:
              '删除${item.productName?.isNotEmpty == true ? item.productName! : '商品'}',
          icon: CupertinoIcons.delete,
          destructive: true,
          isEnabled: !_busy,
          onPressed: _delete,
        ),
      ],
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(CyTokens.space3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Thumb(url: item.productPic),
              const SizedBox(width: CyTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      (item.productName?.isNotEmpty ?? false)
                          ? item.productName!
                          : '商品',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: CyType.headline.copyWith(
                        color: CyTokens.textPrimary,
                      ),
                    ),
                    if (item.skuName?.isNotEmpty ?? false) ...<Widget>[
                      const SizedBox(height: CyTokens.space1),
                      Text(
                        item.skuName!,
                        style: CyType.subhead.copyWith(
                          color: CyTokens.textTertiary,
                        ),
                      ),
                    ],
                    const SizedBox(height: CyTokens.space2),
                    Row(
                      children: <Widget>[
                        Text(
                          item.hasPrice
                              ? formatPoints(item.price)
                              // 不写 0 积分 —— 那是「免费」的意思,不是「不知道」
                              : '积分待确认',
                          style: CyType.callout.copyWith(
                            fontWeight: FontWeight.w600,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                            color: CyTokens.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        _QtyStepper(
                          value: item.quantity,
                          onDec: _busy
                              ? null
                              : () => _changeQty(item.quantity - 1),
                          onInc: _busy
                              ? null
                              : () => _changeQty(item.quantity + 1),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 购物车行的数量步进器(下限 1,上限交由后端库存校验)。
class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.value,
    required this.onDec,
    required this.onInc,
  });
  final int value;
  final VoidCallback? onDec;
  final VoidCallback? onInc;

  @override
  Widget build(BuildContext context) {
    final canDec = onDec != null && value > 1;
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
                onPressed: canDec ? onDec : null,
                child: const Icon(CupertinoIcons.minus, size: 16),
              ),
            ),
          ),
          Text('$value', style: CyType.body),
          Semantics(
            button: true,
            label: '增加数量',
            value: '$value',
            enabled: onInc != null,
            child: ExcludeSemantics(
              child: CupertinoButton(
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
                foregroundColor: onInc != null
                    ? CyTokens.textPrimary
                    : CyTokens.textDisabled,
                onPressed: onInc,
                child: const Icon(CupertinoIcons.plus, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartFooter extends ConsumerStatefulWidget {
  const _CartFooter({
    required this.items,
    required this.total,
    this.incomplete = false,
  });

  final List<CartItem> items;
  final bool incomplete;
  final double total;

  @override
  ConsumerState<_CartFooter> createState() => _CartFooterState();
}

class _CartFooterState extends ConsumerState<_CartFooter> {
  bool _preparing = false;

  Future<void> _checkout() async {
    if (_preparing) return;
    if (!await requireLogin(context, ref)) return;
    if (!mounted) return;
    setState(() => _preparing = true);
    try {
      final List<int> cartIds = widget.items
          .map((CartItem item) => item.id)
          .toList(growable: false);
      final CartSettlementPreview preview = await ref
          .read(mallApiProvider)
          .previewSettlement(cartIds);
      if (!mounted) return;
      final int? orderId = await showCupertinoSheet<int>(
        context: context,
        showDragHandle: true,
        topGap: 0.08,
        scrollableBuilder:
            (BuildContext sheetContext, ScrollController scrollController) =>
                CartCheckoutSheet(
                  preview: preview,
                  cartIds: cartIds,
                  scrollController: scrollController,
                  onCompleted: (int id) => Navigator.of(sheetContext).pop(id),
                ),
      );
      if (!mounted || orderId == null) return;
      ref.invalidate(cartListProvider);
      context.go('/mall');
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 页底固定 CTA 属功能层(M8):与商品详情底部条同走 CyFooterBar,
    // 26+ 真玻璃、13–25 回退实色,不再自绘一条材质不一致的实色条。
    return CyFooterBar(
      leading: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            widget.incomplete ? '合计(有商品积分待确认)' : '合计',
            style: CyType.caption1.copyWith(color: CyTokens.textTertiary),
          ),
          Text(
            formatPoints(widget.total),
            style: CyType.title1.copyWith(
              height: 1.15,
              fontWeight: FontWeight.w700,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              color: CyTokens.textPrimary,
            ),
          ),
        ],
      ),
      primary: CyNativeButton(
        key: const Key('mall-cart-checkout'),
        label: _preparing ? '正在准备' : '去兑换',
        onPressed: _preparing ? null : _checkout,
        loading: _preparing,
        width: 140,
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    // 兜底走共用件:加载不出来安静铺一块同色底,不摆 Material 碎图标。
    return CyNetImage(
      url,
      width: 64,
      height: 64,
      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
    );
  }
}
