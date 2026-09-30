import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart' show isUnauthorizedError;
import '../../data/models/activity.dart';

/// 小程序 `scene-member-order-history` 的八个横滑筛选，顺序是公开页面契约。
enum OrderListFilter {
  all,
  pendingPayment,
  notStarted,
  inProgress,
  completed,
  refunding,
  refunded,
  nonRefundable,
}

extension OrderListFilterDisplay on OrderListFilter {
  String get label => switch (this) {
    OrderListFilter.all => '全部',
    OrderListFilter.pendingPayment => '待支付',
    OrderListFilter.notStarted => '未开始',
    OrderListFilter.inProgress => '进行中',
    OrderListFilter.completed => '已完成',
    OrderListFilter.refunding => '退款中',
    OrderListFilter.refunded => '已退款',
    OrderListFilter.nonRefundable => '不可退款',
  };

  OrderListState? get state => switch (this) {
    OrderListFilter.all => null,
    OrderListFilter.pendingPayment => OrderListState.pendingPayment,
    OrderListFilter.notStarted => OrderListState.notStarted,
    OrderListFilter.inProgress => OrderListState.inProgress,
    OrderListFilter.completed => OrderListState.completed,
    OrderListFilter.refunding => OrderListState.refunding,
    OrderListFilter.refunded => OrderListState.refunded,
    OrderListFilter.nonRefundable => OrderListState.nonRefundable,
  };
}

/// `cancelled` 保留为全部列表的行状态，但小程序没有单列「已取消」筛选，不能加第九项。
enum OrderListState {
  pendingPayment,
  notStarted,
  inProgress,
  completed,
  refunding,
  refunded,
  nonRefundable,
  cancelled,
  unknown,
}

extension OrderListStateDisplay on OrderListState {
  String get label => switch (this) {
    OrderListState.pendingPayment => '待支付',
    OrderListState.notStarted => '未开始',
    OrderListState.inProgress => '进行中',
    OrderListState.completed => '已完成',
    OrderListState.refunding => '退款中',
    OrderListState.refunded => '已退款',
    OrderListState.nonRefundable => '不可退款',
    OrderListState.cancelled => '已取消',
    OrderListState.unknown => '订单状态更新中',
  };
}

OrderListState summarizeOrderListState(MyRegistration order, {DateTime? now}) {
  // 后端的退款打款状态优先级最高。null 表示没申请，0 则是确已申请且正在处理。
  final int? payout = order.refundPayoutStatus;
  if (payout != null) {
    return payout == 1 || payout == 4
        ? OrderListState.refunded
        : OrderListState.refunding;
  }

  if (order.registrationStatus == 1) return OrderListState.pendingPayment;
  if (order.registrationStatus == 3) return OrderListState.cancelled;
  if (order.registrationStatus != 2) return OrderListState.unknown;
  if (order.verificationStatus == 1) return OrderListState.completed;
  if (order.refundable == false) return OrderListState.nonRefundable;

  final DateTime current = now ?? DateTime.now();
  final DateTime? start = _parseOrderDate(order.startDate);
  final DateTime? end = _parseOrderDate(order.endDate ?? order.startDate);
  if (end != null && current.isAfter(end)) return OrderListState.completed;
  if (start != null && current.isBefore(start)) {
    return OrderListState.notStarted;
  }
  return OrderListState.inProgress;
}

/// 退款筛选归为「退款中」，但行卡需要保留小程序对人工处理中的更精确提示。
String orderListStateLabel(MyRegistration order, {DateTime? now}) {
  final OrderListState state = summarizeOrderListState(order, now: now);
  if (state == OrderListState.refunding &&
      (order.refundPayoutStatus == 2 || order.refundPayoutStatus == 3)) {
    return '退款处理中';
  }
  return state.label;
}

List<MyRegistration> filterOrderList(
  List<MyRegistration> rows,
  OrderListFilter filter, {
  DateTime? now,
}) {
  final OrderListState? target = filter.state;
  if (target == null) return List<MyRegistration>.unmodifiable(rows);
  return rows
      .where(
        (MyRegistration order) =>
            summarizeOrderListState(order, now: now) == target,
      )
      .toList(growable: false);
}

DateTime? _parseOrderDate(String? value) {
  final String text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  return DateTime.tryParse(text.replaceFirst(' ', 'T'));
}

/// 错误落点收口(口径同 participation 域 #283 的 `_userErrorText`):
/// API 层抛的中文原话透传;Dio 网络异常不把 `DioException [...]` 英文原文
/// 抛给用户;401 说「登录状态已失效」,不让人对着一条死路反复点重试。
String orderUserErrorText(Object error) => switch (error) {
  DioException e when isUnauthorizedError(e) => '登录状态已失效，请重新登录',
  DioException _ => '网络异常，请重试',
  _ => error.toString().replaceFirst('Exception: ', ''),
};
