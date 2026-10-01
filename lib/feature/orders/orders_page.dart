import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers.dart';
import '../../core/network/request_session_scope.dart';
import '../club/registration_cancellation_display.dart';
import '../../l10n/strings.dart';
import 'registration_order_strings.dart';
import '../auth/auth_controller.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/activity.dart';
import '../payment/wechat_payment.dart';
import 'payment_result_sheet.dart';
import 'payment_verifier.dart';
import '../../core/widgets/cy_widgets.dart';
import 'order_detail_sheet.dart';
import 'order_list_state.dart';
import '../../core/widgets/cy_native_notice.dart';

/// 我的订单:`POST /api/registration/list`(owner_type=3)。
///
/// ★ 为什么必须有这一页:票夹走 owner_type=2,后端会**强制**
///   registrationStatus=2 只返回已支付的 —— 待支付单在票夹里根本看不见。
///   用户取消支付后若没有这个入口,就只能重新报名建新单,**可能重复付款**。
final myOrdersProvider = FutureProvider.autoDispose<List<MyRegistration>>((
  ref,
) {
  final userId = ref.watch(
    authControllerProvider.select((auth) => auth.user?.id),
  );
  if (userId == null) return Future.value(const <MyRegistration>[]);
  return ref.watch(activityApiProvider).orderList();
});

class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key, this.initialDetailId});

  final int? initialDetailId;

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  int? _payingId;
  int? _cancellingId;
  final Set<(int, int)> _submittedCancellations = <(int, int)>{};
  int? _displayedOrdersUserId;
  OrderListFilter _filter = OrderListFilter.all;
  bool _openedInitialDetail = false;
  Future<void>? _detailPresentation;

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    CyNativeNotice.show(context, msg, isError: isError);
  }

  /// 对待支付单继续支付。结果处理与报名弹窗同一纪律:
  /// 客户端回应不是订单真源,一律只刷新 + 提示,不在本地改订单态。
  Future<void> _pay(MyRegistration order) async {
    if (!wechatPaymentFlowGate.tryAcquire()) {
      _toast(stringsOf(context).registrationOrdersAPaymentIsAlreadyInProgressCompleteItBeforeTryingAgain, isError: true);
      return;
    }
    setState(() => _payingId = order.id);
    try {
      // ★ 支付前先问一次服务端「支付通道通不通」。
      //   ⚠️ 这是**软探测,不是硬闸**:探测本身也可能失败,
      //     把一条正常的支付路径堵死,比让它去试一次更糟。
      //     所以只在**明确说不可用**时提示并停下;探测失败就当没问过,照常走。
      try {
        final ({bool ready, String message}) r = await ref
            .read(activityApiProvider)
            .paymentReadiness();
        if (!r.ready) {
          if (!mounted) return;
          _toast(
            r.message.isEmpty ? stringsOf(context).registrationOrdersPaymentServiceIsUnavailableTryAgainLater : r.message,
            isError: true,
          );
          return;
        }
      } catch (_) {
        // 探测本身失败 —— 不阻断,继续走真实支付
      }

      final params = await ref.read(activityApiProvider).payApp(order.id);
      await const WechatPayment().pay(params);
      if (!mounted) return;
      // SDK responses, including cancellation, cannot prove settlement.
      await _reconcile(order);
    } catch (e) {
      _toast(localizedOrderError(context, e), isError: true);
    } finally {
      wechatPaymentFlowGate.release();
      if (mounted) setState(() => _payingId = null);
    }
  }

  Future<void> _reconcile(MyRegistration order) async {
    final verifier = RegistrationPaymentVerifier(
      requestStatus: (int id) async {
        final d = await ref.read(activityApiProvider).ticketInfo(id);
        return <String, dynamic>{
          'paymentStatus': d.paymentStatus,
          'registrationStatus': d.registrationStatus,
        };
      },
    );
    await _presentResultSheet(
      order,
      reconcile: () => verifier.verify(order.id),
    );
  }

  Future<void> _presentResultSheet(
    MyRegistration order, {
    Future<PaymentVerifyOutcome> Function()? reconcile,
  }) async {
    final PaymentSheetOutcome? r = await showPaymentResultSheet(
      context,
      reconcile: reconcile,
    );
    if (!mounted) return;
    switch (r?.result) {
      case PaymentSheetResult.success:
        ref.invalidate(myOrdersProvider);
        ref.invalidate(orderDetailProvider(order.id));
      case PaymentSheetResult.failed:
      case null:
        // fail 相滑掉与按「知道了」同义;订单态以服务端为准,只刷列表。
        ref.invalidate(myOrdersProvider);
      case PaymentSheetResult.unknown:
        await cyConfirm(
          context,
          title: stringsOf(context).registrationOrdersPaymentResultUnconfirmed,
          content: stringsOf(context).registrationOrdersDoNotPayAgainYetRefreshYourOrdersLaterForTheFinalStatus,
          confirmText: stringsOf(context).registrationOrdersGotIt,
          showCancel: false,
        );
        if (!mounted) return;
        ref.invalidate(myOrdersProvider);
        ref.invalidate(orderDetailProvider(order.id));
    }
  }

  /// 取消报名 / 申请退款。
  ///
  /// ★ 走哪个接口由**是否已支付**决定,不是由界面文案决定 ——
  ///   已支付却调 `/cancel`,票没了钱不退。判据用 registrationStatus == 2,
  ///   与小程序同一条。
  Future<void> _cancel(MyRegistration order, int? owner) async {
    if (owner == null || _cancellingId != null) return;
    final scope = ref.read(authControllerProvider.notifier).requestScope(owner);
    if (!scope.isCurrent() || _submittedCancellations.contains((owner, order.id))) return;
    final bool paid = order.registrationStatus == 2;
    final bool ok = await cyConfirm(
      context,
      title: paid ? stringsOf(context).registrationOrdersCancelRegistrationAndRequestRefund : stringsOf(context).registrationOrdersCancelOrder,
      content: paid
          ? '退款将原路退回微信（预计1～3个工作日），已用积分一并返还。已核销或已过开始时间不可退。确认取消报名？'
          : stringsOf(context).registrationOrdersCancelThisUnpaidOrderThisCannotBeUndone,
      confirmText: paid ? stringsOf(context).registrationOrdersCancelAndRequestRefund : stringsOf(context).registrationOrdersConfirmCancellation,
      cancelText: stringsOf(context).registrationOrdersKeepOrder,
      danger: true,
    );
    if (!ok || !mounted || !scope.isCurrent() || _cancellingId != null || _submittedCancellations.contains((owner, order.id))) return;
    setState(() => _cancellingId = order.id);
    try {
      final outcome = await RequestSessionScope.run(scope, () => ref
          .read(activityApiProvider)
          .cancelRegistrationWithOutcome(registrationId: order.id, paid: paid));
      if (!mounted || !scope.isCurrent()) return;
      _submittedCancellations.add((owner, order.id));
      ref.invalidate(myOrdersProvider);
      _toast(registrationCancellationNotice(context, outcome));
    } catch (e) {
      if (!mounted || !scope.isCurrent()) return;
      if (e is DioException && (e.response == null || (e.response?.statusCode ?? 0) >= 500)) {
        _submittedCancellations.add((owner, order.id));
        ref.invalidate(myOrdersProvider);
        _toast(stringsOf(context).clubCheckinRefundUnknownBody, isError: true);
        return;
      }
      _toast(localizedOrderError(context, e), isError: true);
    } finally {
      if (mounted && scope.isCurrent()) setState(() => _cancellingId = null);
    }
  }

  Future<void> _showOrderDetail(MyRegistration order) {
    final owner = _displayedOrdersUserId;
    final Future<void>? active = _detailPresentation;
    if (active != null) return active.then<void>((_) {});

    final Future<void> presentation = showCupertinoSheet<void>(
      context: context,
      showDragHandle: true,
      scrollableBuilder: (BuildContext context, ScrollController controller) =>
          OrderDetailSheet(
            orderId: order.id,
            scrollController: controller,
            onPay: () => _pay(order),
            onCancel: () => _cancel(order, owner),
          ),
    );
    _detailPresentation = presentation;
    return presentation
        .whenComplete(() {
          if (identical(_detailPresentation, presentation)) {
            _detailPresentation = null;
          }
        })
        .then<void>((_) {});
  }

  void _selectFilter(OrderListFilter filter) {
    if (_filter == filter) return;
    HapticFeedback.selectionClick();
    setState(() => _filter = filter);
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(
      authControllerProvider.select((auth) => auth.user?.id),
    );
    if (_displayedOrdersUserId != userId) _cancellingId = null;
    final orders = ref.watch(myOrdersProvider);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        // 投诉的语境就是「我参与过的单」,入口放这里最顺。
        // ⚠️ 不做「这一单投诉」——后端的判据是**主题**不是订单,
        //   按单发起会让人以为投诉挂在这一单上,而实际是按主题去重的
        //   (同主题已有处理中的投诉就不再建单)。
        trailing: Semantics(
          button: true,
          label: stringsOf(context).registrationOrdersMakeAComplaint,
          child: SizedBox.square(
            dimension: 44,
            child: CupertinoButton(
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
              onPressed: () => GoRouter.of(context).push('/complaint'),
              child: const Icon(CupertinoIcons.exclamationmark_bubble),
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
              CyPageTitle(stringsOf(context).registrationOrdersMyOrders),
              _OrderFilterBar(filter: _filter, onSelected: _selectFilter),
              Expanded(
                child: RefreshIndicator.adaptive(
                  onRefresh: () async => ref.invalidate(myOrdersProvider),
                  child: orders.when(
                    loading: () => CySkeleton(),
                    // ★ 刷新失败但列表已经拿到过时**不丢内容**:小程序同一分支
                    //   (`errorMsg && list.length>0`)保留已加载订单,只在顶部加一条
                    //   刷新失败条;整屏错误只留给「一条都没有」的情况。
                    error: (Object err, StackTrace st) {
                      // Retain a failed refresh only for the same account.
                      final List<MyRegistration>? kept =
                          _displayedOrdersUserId == userId ? orders.value : null;
                      if (kept == null || kept.isEmpty) {
                        return _OrderLoadError(onRetry: _retry);
                      }
                      return Column(
                        children: <Widget>[
                          _OrderRefreshError(onRetry: _retry),
                          Expanded(child: _ordersBody(kept)),
                        ],
                      );
                    },
                    data: (rows) {
                      _displayedOrdersUserId = userId;
                      return _ordersBody(rows);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _retry() => ref.invalidate(myOrdersProvider);

  /// 订单列表正文:数据态与「刷新失败但保留列表」态共用,两处各写一遍会走形。
  Widget _ordersBody(List<MyRegistration> list) {
    final owner = _displayedOrdersUserId;
    if (!_openedInitialDetail && widget.initialDetailId != null) {
      final MyRegistration? target = list
          .where((MyRegistration order) => order.id == widget.initialDetailId)
          .firstOrNull;
      if (target != null) {
        _openedInitialDetail = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showOrderDetail(target);
        });
      }
    }
    if (list.isEmpty) {
      return _OrderEmptyState(
        title: stringsOf(context).registrationOrdersNoCityRouteOrdersYet,
        subtitle: stringsOf(context).registrationOrdersYourOrdersWillAppearHereAfterRegisteringOrBuyingACityRoute,
        action: stringsOf(context).registrationOrdersDiscoverCityRoutes,
        onAction: () => context.go('/feed'),
      );
    }
    final List<MyRegistration> filtered = filterOrderList(list, _filter);
    if (filtered.isEmpty) {
      return _OrderEmptyState(
        title: stringsOf(context).registrationOrdersNoOrdersMatchThisFilter,
        subtitle: stringsOf(context).registrationOrdersTryAnotherStatusToSeeYourOrders,
      );
    }
    return ListView.separated(
      padding: EdgeInsets.all(CyTokens.space4),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => SizedBox(height: CyTokens.space3),
      itemBuilder: (context, i) => _OrderCard(
        order: filtered[i],
        state: summarizeOrderListState(filtered[i]),
        paying: _payingId == filtered[i].id,
        onPay: () => _pay(filtered[i]),
        cancelling: _cancellingId == filtered[i].id,
        onCancel: () => _cancel(filtered[i], owner),
        onOpen: () => _showOrderDetail(filtered[i]),
      ),
    );
  }
}

class _OrderFilterBar extends StatelessWidget {
  const _OrderFilterBar({required this.filter, required this.onSelected});

  final OrderListFilter filter;
  final ValueChanged<OrderListFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      height: 52,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
        child: Row(
          children: <Widget>[
            for (final OrderListFilter item in OrderListFilter.values)
              _OrderFilterPill(
                key: ValueKey<String>('order-filter-${item.name}'),
                label: localOrderModelText(context, item.label),
                selected: filter == item,
                palette: palette,
                reduceMotion: reduceMotion,
                onPressed: () => onSelected(item),
              ),
          ],
        ),
      ),
    );
  }
}

class _OrderFilterPill extends StatelessWidget {
  const _OrderFilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.palette,
    required this.reduceMotion,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final CyPalette palette;
  final bool reduceMotion;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: selected ? stringsOf(context).registrationOrdersSelectedLabel(label) : label,
      child: CupertinoButton(
        minimumSize: const Size(44, 44),
        pressedOpacity: reduceMotion ? 1 : 0.4,
        padding: const EdgeInsets.only(right: CyTokens.space1_5),
        onPressed: onPressed,
        child: ExcludeSemantics(
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : CyMotion.fast,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(
              horizontal: CyTokens.space3,
              vertical: CyTokens.space1_5,
            ),
            decoration: BoxDecoration(
              color: selected ? palette.actionPrimaryBg : palette.bgSubtle,
              borderRadius: BorderRadius.circular(CyTokens.radiusPill),
            ),
            child: Text(
              label,
              style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                fontSize: CyTokens.typeLabel,
                fontWeight: FontWeight.w600,
                color: selected
                    ? palette.actionPrimaryFg
                    : palette.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 已有列表时的刷新失败条:小程序 `.cy-error` 的同分支文案
/// (「订单刷新失败 / 已加载的订单仍为你保留」+ 重试),不抢走已加载的内容。
class _OrderRefreshError extends StatelessWidget {
  const _OrderRefreshError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final CyPalette palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space2,
        CyTokens.space2,
        0,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            CupertinoIcons.exclamationmark_circle,
            size: 18,
            color: palette.textSecondary,
          ),
          const SizedBox(width: CyTokens.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(stringsOf(context).registrationOrdersCouldNotRefreshOrders, style: textTheme.labelLarge),
                Text(
                  stringsOf(context).registrationOrdersPreviouslyLoadedOrdersAreStillAvailable,
                  style: textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          CupertinoButton(
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
            onPressed: onRetry,
            child: Text(stringsOf(context).retry),
          ),
        ],
      ),
    );
  }
}

class _OrderLoadError extends StatelessWidget {
  const _OrderLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(CyTokens.space6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            CupertinoIcons.wifi_exclamationmark,
            size: 48,
            color: CyPalette.of(context).textDisabled,
          ),
          const SizedBox(height: CyTokens.space3),
          Text(stringsOf(context).registrationOrdersCouldNotLoadOrders),
          const SizedBox(height: CyTokens.space1_5),
          Text(
            stringsOf(context).registrationOrdersThereMayBeAConnectionIssueOrADataSyncInProgressTapRetryYourPaidOrdersA,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: CyPalette.of(context).textSecondary,
            ),
          ),
          const SizedBox(height: CyTokens.space4),
          CyNativeButton(label: stringsOf(context).retry, onPressed: onRetry),
        ],
      ),
    ),
  );
}

class _OrderEmptyState extends StatelessWidget {
  const _OrderEmptyState({
    required this.title,
    required this.subtitle,
    this.action,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(CyTokens.space6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            CupertinoIcons.ticket,
            size: 56,
            color: CyPalette.of(context).textDisabled,
          ),
          const SizedBox(height: CyTokens.space3),
          Text(title),
          const SizedBox(height: CyTokens.space1_5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: CyPalette.of(context).textSecondary,
            ),
          ),
          if (action != null && onAction != null) ...<Widget>[
            const SizedBox(height: CyTokens.space4),
            CyNativeButton(label: action!, onPressed: onAction),
          ],
        ],
      ),
    ),
  );
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.state,
    required this.paying,
    required this.onPay,
    required this.cancelling,
    required this.onCancel,
    this.onOpen,
  });
  final MyRegistration order;
  final OrderListState state;
  final bool paying;
  final VoidCallback onPay;
  final bool cancelling;
  final VoidCallback onCancel;
  final VoidCallback? onOpen;

  Color _stateColor(CyPalette palette) => switch (state) {
    OrderListState.pendingPayment => CyTokens.statusDanger,
    OrderListState.notStarted => CyTokens.statusInfo,
    OrderListState.inProgress => CyTokens.statusSuccess,
    OrderListState.refunding => CyTokens.statusWarning,
    OrderListState.refunded => CyTokens.statusSuccess,
    OrderListState.completed ||
    OrderListState.nonRefundable ||
    OrderListState.cancelled ||
    OrderListState.unknown => palette.textTertiary,
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final CyPalette palette = CyPalette.of(context);
    return Card(
      child: CupertinoButton(
        onPressed: onOpen,
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        child: Padding(
          padding: EdgeInsets.all(CyTokens.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: (order.registrationNo ?? '').isEmpty
                        ? const SizedBox.shrink()
                        : Text(
                            stringsOf(context).registrationOrdersOrderNumberValue(order.registrationNo.toString()),
                            style: textTheme.labelMedium?.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                  ),
                  SizedBox(width: CyTokens.space3),
                  Text(
                    localOrderModelText(context, orderListStateLabel(order)),
                    style: textTheme.labelMedium?.copyWith(
                      color: _stateColor(palette),
                    ),
                  ),
                ],
              ),
              SizedBox(height: CyTokens.space3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    key: Key('order-card-cover-${order.id}'),
                    width: 128,
                    height: 90,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                      child: CyNetImage(order.imgUrl, fit: BoxFit.cover),
                    ),
                  ),
                  SizedBox(width: CyTokens.space3),
                  Expanded(
                    child: _OrderCardSummary(
                      order: order,
                      textTheme: textTheme,
                    ),
                  ),
                ],
              ),
              // 金额:后端 `CmsRegistration` 一直有下发 payableAmount,此前没解析也没渲染,
              // 于是整页看不到「付了多少钱」—— 那正是用户打开订单最先要找的东西。
              // 待支付单显示的是「还要付多少」,已支付单显示的是「付了多少」,同一个字段。
              if (order.payableAmount != null) ...<Widget>[
                SizedBox(height: CyTokens.space1_5),
                Text(
                  order.payableAmount! > 0
                      ? '¥${order.payableAmount!.toStringAsFixed(2)}'
                      : stringsOf(context).registrationOrdersFree,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
              SizedBox(height: CyTokens.space3),
              Row(children: <Widget>[..._actions(context)]),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context) => switch (state) {
    OrderListState.pendingPayment => <Widget>[
      Expanded(
        child: CyNativeButton(
          label: cancelling ? stringsOf(context).registrationOrdersProcessing : stringsOf(context).registrationOrdersCancelOrder,
          role: CyNativeButtonRole.destructive,
          onPressed: cancelling ? null : onCancel,
          loading: cancelling,
        ),
      ),
      const SizedBox(width: CyTokens.space2),
      Expanded(
        child: CyNativeButton(
          label: paying ? stringsOf(context).registrationOrdersPaymentInProgress : stringsOf(context).registrationOrdersPayNow,
          onPressed: paying ? null : onPay,
          loading: paying,
        ),
      ),
    ],
    OrderListState.notStarted || OrderListState.inProgress => <Widget>[
      Expanded(
        child: CyNativeButton(
          label: cancelling ? stringsOf(context).registrationOrdersProcessing : stringsOf(context).registrationOrdersRequestRefund,
          role: CyNativeButtonRole.destructive,
          onPressed: cancelling ? null : onCancel,
          loading: cancelling,
        ),
      ),
      const SizedBox(width: CyTokens.space2),
      Expanded(
        child: CyNativeButton(label: stringsOf(context).registrationOrdersViewTickets, onPressed: onOpen),
      ),
    ],
    OrderListState.completed || OrderListState.nonRefundable => <Widget>[
      Expanded(
        child: CyNativeButton(
          label: state == OrderListState.completed ? stringsOf(context).registrationOrdersViewDetails : stringsOf(context).registrationOrdersViewTickets,
          onPressed: onOpen,
        ),
      ),
    ],
    OrderListState.refunding || OrderListState.refunded => <Widget>[
      Expanded(
        child: CyNativeButton(label: stringsOf(context).registrationOrdersViewRefundDetails, onPressed: onOpen),
      ),
    ],
    OrderListState.cancelled || OrderListState.unknown => const <Widget>[],
  };
}

class _OrderCardSummary extends StatelessWidget {
  const _OrderCardSummary({required this.order, required this.textTheme});

  final MyRegistration order;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final OrderListMode? mode = order.orderMode;
    final String time = _formatOrderTimeRange(order.startDate, order.endDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (mode != null)
          Row(
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: CyPalette.of(context).bgSubtle,
                  borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space1_5,
                    vertical: 2,
                  ),
                  child: Text(
                    localOrderModelText(context, mode.label),
                    style: textTheme.labelSmall?.copyWith(
                      color: mode == OrderListMode.freeExplore
                          ? CyTokens.statusSuccess
                          : CyTokens.statusInfo,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: CyTokens.space1_5),
              Expanded(
                child: Text(
                  localOrderModelText(context, mode.summary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
              ),
            ],
          ),
        if (mode != null) const SizedBox(height: CyTokens.space1_5),
        if ((order.title ?? '').isNotEmpty)
          Text(
            order.title!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleSmall,
          ),
        if (time.isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space2),
          _OrderMeta(icon: CupertinoIcons.time, text: time),
        ],
        if ((order.addressName ?? '').isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space1_5),
          _OrderMeta(icon: CupertinoIcons.location, text: order.addressName!),
        ],
      ],
    );
  }
}

class _OrderMeta extends StatelessWidget {
  const _OrderMeta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Icon(icon, size: 13, color: CyPalette.of(context).textSecondary),
      const SizedBox(width: CyTokens.space1),
      Expanded(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: CyPalette.of(context).textSecondary,
          ),
        ),
      ),
    ],
  );
}

String _formatOrderTimeRange(String? rawStart, String? rawEnd) {
  DateTime? parse(String? value) {
    final String text = value?.trim() ?? '';
    return text.isEmpty ? null : DateTime.tryParse(text.replaceFirst(' ', 'T'));
  }

  String format(DateTime value) =>
      '${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  final DateTime? start = parse(rawStart);
  final DateTime? end = parse(rawEnd);
  if (start != null && end != null) return '${format(start)} - ${format(end)}';
  if (start != null) return format(start);
  if (end != null) return format(end);
  return '';
}
