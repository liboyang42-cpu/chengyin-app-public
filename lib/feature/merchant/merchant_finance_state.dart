/// 商家资金域状态派生(只读展示)。镜像小程序 ledger/index.js 的
/// `financeStateText` / `stateVariant` / `batchStateText` / `groupByDay` / `dayLabel`。
library;

/// displayState → 语义色。1:1 映射,不含业务判断。
String financeStateVariant(String displayState) => switch (displayState) {
      'PENDING_SETTLEMENT' => 'warning',
      'SETTLED' => 'success',
      'ADJUSTMENT_PENDING' => 'danger',
      'ADJUSTED' => 'neutral',
      'REVERSED_BEFORE_SETTLEMENT' => 'neutral',
      'NO_CASH_SETTLEMENT' => 'neutral',
      'LEDGER_ERROR' => 'danger',
      _ => 'neutral',
    };

/// 单条收入/核销的状态文案。
/// NO_CASH_SETTLEMENT 优先用服务端 noCashReason;缺了才落兜底文案。
String financeStateText(
  String displayState, {
  String? noCashReason,
  String? settlementRoute,
  String? destination,
}) {
  if (displayState == 'NO_CASH_SETTLEMENT') {
    if (noCashReason != null && noCashReason.isNotEmpty) return noCashReason;
    return '本次不产生现金结算';
  }
  return switch (displayState) {
    'PENDING_SETTLEMENT' =>
      settlementRoute == 'COOP_ORDER' ? '待主题结算' : '待结算',
    'SETTLED' =>
      destination == 'PERSONAL_ACCOUNT' ? '已入个人账户' : '平台已打款',
    'ADJUSTMENT_PENDING' => '调整中',
    'ADJUSTED' => '已调整',
    'REVERSED_BEFORE_SETTLEMENT' => '核销已撤销',
    'LEDGER_ERROR' => '结算数据异常,已上报',
    _ => '状态待确认',
  };
}

/// 对公批次状态文案。
String batchStateText({
  required String displayState,
  required String holdState,
  required String paymentState,
  required String invoiceState,
  required String netDirection,
}) {
  if (displayState == 'LEDGER_ERROR') return '结算数据异常,已上报';
  if (netDirection == 'ZERO') return '本期无需打款';
  if (netDirection == 'MERCHANT_OWES_PLATFORM') return '调整待处理';
  if (holdState == 'FROZEN') return '结算处理中';
  if (paymentState == 'PAID') {
    return invoiceState == 'ISSUED' ? '平台已打款 · 已开票' : '平台已打款 · 未开票';
  }
  if (paymentState == 'CONFIRMED') return '已确认';
  return '待对账';
}

/// 对公批次语义色。
String batchVariant({
  required String displayState,
  required String paymentState,
}) {
  if (displayState == 'LEDGER_ERROR') return 'danger';
  if (paymentState == 'PAID') return 'success';
  return 'warning';
}

/// 发票状态文案。
String invoiceText(String invoiceState) => switch (invoiceState) {
      'NONE' => '未开票',
      'ISSUED' => '已开票',
      'RED' => '已红冲',
      _ => '',
    };

/// 收入明细 source 枚举 → 文案。
String entrySourceText(String source) => switch (source) {
      'REDEMPTION_FEE' => '核销计酬',
      'COOP_SHARE' => '合作分润',
      'ACTIVITY_SHARE' => '活动分润',
      'MERCHANT_CLAWBACK' => '已执行扣划',
      _ => '调整',
    };

/// 按自然日分组(一组一卡)。日期取 occurredAt 前 10 位,不做时区换算。
List<LedgerDayGroup> groupByDay(List<LedgerRow> rows) {
  final groups = <LedgerDayGroup>[];
  for (final row in rows) {
    if (groups.isEmpty || groups.last.dayKey != row.dayKey) {
      groups.add(LedgerDayGroup(dayKey: row.dayKey, rows: <LedgerRow>[]));
    }
    groups.last.rows.add(row);
  }
  return groups;
}

/// `MM-DD` 形态的日期 → `M 月 D 日`;非日期形态原样返回;空 → 「未标注日期」。
String dayLabel(String dayKey) {
  if (dayKey.isEmpty) return '未标注日期';
  final parts = dayKey.split('-');
  return parts.length == 3 ? '${int.tryParse(parts[1]) ?? parts[1]} 月 ${int.tryParse(parts[2]) ?? parts[2]} 日' : dayKey;
}

/// 核销记录行(已完成字段派生,由页面组装)。
class LedgerRow {
  LedgerRow({
    required this.dayKey,
    required this.title,
    required this.amountDisplay,
    required this.amountTone,
    required this.stateText,
    required this.stateVariant,
    this.timeText = '',
    this.customerDisplayName,
    this.recordType,
    this.recordId,
  });

  final String dayKey;
  final String title;
  final String amountDisplay;

  /// 'pos' | 'neg' | 'mute'
  final String amountTone;
  final String stateText;
  final String stateVariant;
  final String timeText;
  final String? customerDisplayName;
  final String? recordType;
  final String? recordId;
}

class LedgerDayGroup {
  LedgerDayGroup({required this.dayKey, required this.rows});
  final String dayKey;
  final List<LedgerRow> rows;

  String get dayLabelText => dayLabel(dayKey);
}