/// 订单读模型 —— `utils/order-status.js` +
/// `components/cy/scene-member-order-detail/index.js` 的 `buildOrderTimeline`
/// 的逐条端口。**退款终态只能取 refund_application.payout_status,
/// 不能由报名取消态猜测**(那份文件顶部的原话)。
library;

import '../../data/models/activity.dart';

class OrderStateSummary {
  const OrderStateSummary(this.key, this.text, this.refundText);

  final String key;
  final String text;
  final String refundText;
}

class OrderTimelineRow {
  const OrderTimelineRow({
    required this.key,
    required this.label,
    required this.time,
    required this.done,
  });

  final String key;
  final String label;

  /// 展示时间;'' = 该步没有时刻可说。
  final String time;

  /// true = done(已达成),false = current(卡在这一步)。
  final bool done;
}

/// 后端 datetime 一律是东八区墙钟字符串('2026-09-18 14:03:22' / ISO);
/// 数字按 epoch(10 位秒 / 13 位毫秒)收成同一墙钟。取不到给 null。
int? _chinaEpochMs(Object? value) {
  if (value == null) return null;
  if (value is num) {
    final int n = value.toInt();
    if (n <= 0) return null;
    return '$n'.length == 10 ? n * 1000 : n;
  }
  final String text = (value as String).trim();
  if (text.isEmpty) return null;
  final int? asNum = int.tryParse(text);
  if (asNum != null) {
    if (text.length == 10) return asNum * 1000;
    if (text.length == 13) return asNum;
    return null;
  }
  // 'YYYY-MM-DD HH:mm[:ss]' —— 按东八区解释,与设备时区无关。
  final String iso = text.replaceFirst(' ', 'T');
  final String head = iso.length >= 16 ? iso.substring(0, 16) : iso;
  final DateTime? parsed =
      DateTime.tryParse('$head+08:00') ?? DateTime.tryParse(iso);
  return parsed?.toUtc().millisecondsSinceEpoch;
}

/// `formatRefundDeadline` 的展示形状:YYYY-MM-DD HH:mm(东八区)。
String toDisplayTime(Object? value) {
  final int? ms = _chinaEpochMs(value);
  if (ms == null) return '';
  final DateTime china = DateTime.fromMillisecondsSinceEpoch(
    ms + const Duration(hours: 8).inMilliseconds,
    isUtc: true,
  );
  String two(int v) => v.toString().padLeft(2, '0');
  return '${china.year}-${two(china.month)}-${two(china.day)} '
      '${two(china.hour)}:${two(china.minute)}';
}

/// `payoutSummary`:钱真实走到了哪一步。null = 没有可判的退款申请。
OrderStateSummary? _payoutSummary(RegistrationDetail d) {
  if (!d.hasRefundApplication) return null;
  final int? payout = d.refundPayoutStatus;
  if (payout == 1 || payout == 4) {
    return const OrderStateSummary('refunded', '已退款', '退款已原路退回');
  }
  if (payout == 2) {
    return const OrderStateSummary('refunding', '退款处理中', '原路退款异常，平台正在人工处理');
  }
  if (payout == 3) {
    return const OrderStateSummary('refunding', '退款处理中', '人工退款已处理，等待复核确认');
  }
  // 零元单没有钱可退,不给在途承诺。
  if (d.refundAmount != null && !(d.refundAmount! > 0)) return null;
  // 驳回:不是退款中,回落到订单真实状态。
  if (d.refundApplicationStatus == 2) return null;
  if (d.refundApplicationStatus == 0) {
    return const OrderStateSummary('refunding', '退款审核中', '退款申请已提交，等待平台审核');
  }
  if (payout == 0) {
    return const OrderStateSummary(
      'refunding',
      '退款处理中',
      '微信已受理原路退款，到账以微信退款通知为准',
    );
  }
  if (d.refundApplicationStatus == 1) {
    return const OrderStateSummary('refunding', '退款处理中', '退款已批准，正在提交原路退款');
  }
  return const OrderStateSummary('refunding', '退款处理中', '退款进度更新中，请以微信退款通知为准');
}

/// `summarizeOrderState` 的端口:订单当前态的唯一读模型。
OrderStateSummary summarizeOrderState(RegistrationDetail d, {DateTime? now}) {
  if ((d.manualRefundCaseStatus ?? '').isNotEmpty) {
    return OrderStateSummary(
      'manual_refund',
      '人工售后',
      (d.refundInfoReason ?? '').isNotEmpty
          ? d.refundInfoReason!
          : '请查看订单的人工处理进度',
    );
  }
  final OrderStateSummary? refund = _payoutSummary(d);
  if (refund != null) return refund;

  switch (d.registrationStatus) {
    case 1:
      return const OrderStateSummary('pending_payment', '待支付', '完成支付后可使用');
    case 3:
      return const OrderStateSummary('cancelled', '已取消', '订单已关闭');
    case 4:
      // 后端 CmsRegistration:4=已过期(closeExpired 关单)。
      return const OrderStateSummary('expired', '已过期', '超时未支付，订单已关闭');
    case 2:
      break;
    default:
      return const OrderStateSummary('unknown', '订单状态更新中', '');
  }

  if (d.verificationStatus == 1) {
    return const OrderStateSummary('completed', '已完成', '已核销订单不可退款');
  }
  if (d.refundable == false) {
    return OrderStateSummary(
      'non_refundable',
      '不可退款',
      (d.refundInfoReason ?? '').isNotEmpty
          ? d.refundInfoReason!
          : '当前订单不可自助退款',
    );
  }

  final int? start =
      _chinaEpochMs(d.ownerStartDate) ?? _chinaEpochMs(d.ownerStartTime);
  final int? end =
      _chinaEpochMs(d.ownerEndDate) ?? _chinaEpochMs(d.ownerEndTime) ?? start;
  final int current = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
  if (end != null && current > end) {
    return const OrderStateSummary('completed', '已完成', '活动已结束');
  }
  if (start != null && current < start) {
    return OrderStateSummary(
      'not_started',
      '未开始',
      (d.refundInfoReason ?? '').isNotEmpty
          ? d.refundInfoReason!
          : '可在退款截止前申请原路退款',
    );
  }
  return OrderStateSummary(
    'in_progress',
    '进行中',
    (d.refundInfoReason ?? '').isNotEmpty
        ? d.refundInfoReason!
        : '可在退款截止前申请原路退款',
  );
}

/// `buildOrderTimeline`:订单进度。顺序逐行照抄真源 ——
/// 创建 → 支付 → (退款 | 核销 [人工售后追加])。
List<OrderTimelineRow> buildOrderTimeline(
  RegistrationDetail d, {
  DateTime? now,
}) {
  final OrderStateSummary summary = summarizeOrderState(d, now: now);
  final String stateKey = summary.key;
  final bool paid = d.paymentStatus == 2;
  final bool verified = d.verificationStatus == 1;
  final List<OrderTimelineRow> rows = <OrderTimelineRow>[
    OrderTimelineRow(
      key: 'created',
      label: '订单已创建',
      time: toDisplayTime(d.createTime),
      done: true,
    ),
  ];

  if (paid) {
    rows.add(
      OrderTimelineRow(
        key: 'paid',
        label: '支付已完成',
        time: toDisplayTime(d.paymentTime),
        done: true,
      ),
    );
  } else if (stateKey == 'cancelled') {
    rows.add(
      const OrderTimelineRow(
        key: 'cancelled',
        label: '订单已取消',
        time: '',
        done: true,
      ),
    );
    return rows;
  } else {
    rows.add(
      const OrderTimelineRow(
        key: 'payment',
        label: '等待支付',
        time: '完成后更新',
        done: false,
      ),
    );
    return rows;
  }

  if (stateKey == 'refunding' || stateKey == 'refunded') {
    final String refundTime = (d.refundPayoutTime ?? '').isNotEmpty
        ? d.refundPayoutTime!
        : (d.refundUpdateTime ?? '');
    rows.add(
      OrderTimelineRow(
        key: 'refund',
        label: stateKey == 'refunded' ? '已退款' : '退款处理中',
        time: toDisplayTime(refundTime),
        done: stateKey == 'refunded',
      ),
    );
    return rows;
  }

  rows.add(
    OrderTimelineRow(
      key: 'verification',
      label: verified
          ? '权益已核销'
          : (stateKey == 'manual_refund' ? '尚未核销' : '等待到店核销'),
      time: verified
          ? toDisplayTime(d.verificationTime)
          : (stateKey == 'manual_refund' ? '' : '完成后更新'),
      done: verified,
    ),
  );
  if (stateKey == 'manual_refund') {
    final String cs = d.manualRefundCaseStatus ?? '';
    rows.add(
      OrderTimelineRow(
        key: 'manual_refund',
        label: summary.refundText,
        time: '',
        done: cs == 'NO_REFUND' || cs == 'MANUAL_REFUND_EVIDENCE_VERIFIED',
      ),
    );
  }
  return rows;
}
