import '../../feature/merchant/merchant_money.dart';

/// 商家核销记录一行。对齐后端 `MerchantRedemptionView`。
///
/// ★ 资金域纪律:金额一律**原样保留后端字符串**,前端不解析成 double 再格式化,
///   更不做任何加减 —— 后端注释写死了「这份聚合必须在服务端算:前端只拿得到
///   当前页 rows,对它求和分页后必错,而且错得静默」。
class MerchantRedemption {
  const MerchantRedemption({
    required this.recordKey,
    this.topicName,
    this.chapterName,
    this.storeName,
    this.customerDisplayName,
    this.verificationCodeTail,
    this.settlementAmount,
    this.displayState = '',
    this.noCashReason,
    this.refundState,
    this.occurredAt,
  });

  final String recordKey;
  final String? topicName;
  final String? chapterName;
  final String? storeName;
  final String? customerDisplayName;

  /// 核销码尾号(后端已截断,前端不再处理)。
  final String? verificationCodeTail;

  /// recordKey 的形态是 `"redemption:123"`
  /// (MerchantFinanceQueryService:348 `setRecordKey("redemption:" + id)`)。
  /// 详情接口要的正是拆开的这两段。
  ///
  /// ★ 拆不出来时返回 null,**不要兜个默认 id** —— 拿错 id 去查详情,
  ///   后端会回「记录不可见」,看着像权限问题,其实是解析错了。
  String? get recordType {
    final int at = recordKey.indexOf(':');
    return at > 0 ? recordKey.substring(0, at) : null;
  }

  String? get recordId {
    final int at = recordKey.indexOf(':');
    if (at < 0 || at + 1 >= recordKey.length) return null;
    final String rest = recordKey.substring(at + 1);
    return rest.isEmpty ? null : rest;
  }

  /// 结算金额。**可能为 null(金额尚未成立)或 "0.00"(确认不产生现金)——
  /// 两者含义不同,不许用 `?? 0` 合并。**
  final String? settlementAmount;

  /// 展示态:NO_CASH_SETTLEMENT / PENDING_SETTLEMENT / SETTLED …
  final String displayState;
  final String? noCashReason;
  final String? refundState;
  final DateTime? occurredAt;

  /// 金额展示。对齐小程序 ledger/index.js:107-109 的两分支。
  String get amountDisplay =>
      redemptionAmountDisplay(settlementAmount, displayState);

  /// 金额色调。见 merchant_money.dart:amountToneOf —— 「—」/「待定」落 mute,
  /// 不跟着正数一起渲成绿色。
  AmountTone get amountTone => amountToneOf(amountDisplay);

  /// 状态文案。★ 与后端 displayState 一一对应,不自己发明中间态。
  String get stateText {
    switch (displayState) {
      case 'NO_CASH_SETTLEMENT':
        // 不产生现金时,原因是必须说清的 —— 否则商家只看到「—」会以为是 bug。
        return noCashReason?.isNotEmpty == true ? noCashReason! : '不结现金';
      case 'PENDING_SETTLEMENT':
        return '待结算';
      case 'SETTLED':
        return '已结算';
      default:
        return displayState.isEmpty ? '—' : displayState;
    }
  }

  /// 这一行是否处于退款流程中(要显著标出,否则商家会把已退的算成收入)。
  bool get refunding =>
      refundState != null && refundState!.isNotEmpty && refundState != 'NONE';

  factory MerchantRedemption.fromJson(Map<String, dynamic> json) {
    return MerchantRedemption(
      recordKey: (json['recordKey'] as String?) ?? '',
      topicName: json['topicName'] as String?,
      chapterName: json['chapterName'] as String?,
      storeName: json['storeName'] as String?,
      customerDisplayName: json['customerDisplayName'] as String?,
      verificationCodeTail: json['verificationCodeTail'] as String?,
      settlementAmount: json['settlementAmount'] as String?,
      displayState: (json['displayState'] as String?) ?? '',
      noCashReason: json['noCashReason'] as String?,
      refundState: json['refundState'] as String?,
      occurredAt: json['occurredAt'] == null
          ? null
          : DateTime.tryParse(json['occurredAt'].toString().replaceFirst(' ', 'T')),
    );
  }
}

/// 本月汇总条。对齐 `MerchantRedemptionSummary`。
///
/// ★ 三个值**全部由服务端算好下发**,前端只负责显示。
class MerchantRedemptionSummary {
  const MerchantRedemptionSummary({
    this.count = 0,
    this.pendingAmount,
    this.arrivedAmount,
  });

  final int count;
  final String? pendingAmount;
  final String? arrivedAmount;

  String get pendingDisplay => summaryMoney(pendingAmount);
  String get arrivedDisplay => summaryMoney(arrivedAmount);

  factory MerchantRedemptionSummary.fromJson(Map<String, dynamic> json) {
    return MerchantRedemptionSummary(
      count: (json['count'] as num?)?.toInt() ?? 0,
      pendingAmount: json['pendingAmount'] as String?,
      arrivedAmount: json['arrivedAmount'] as String?,
    );
  }
}

/// 核销记录分页结果。
class MerchantRedemptionPage {
  const MerchantRedemptionPage({
    this.rows = const <MerchantRedemption>[],
    this.summary = const MerchantRedemptionSummary(),
    this.total = 0,
  });

  final List<MerchantRedemption> rows;
  final MerchantRedemptionSummary summary;
  final int total;

  factory MerchantRedemptionPage.fromJson(Map<String, dynamic> json) {
    return MerchantRedemptionPage(
      rows: ((json['rows'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(MerchantRedemption.fromJson)
          .toList(),
      summary: json['summary'] is Map<String, dynamic>
          ? MerchantRedemptionSummary.fromJson(
              json['summary'] as Map<String, dynamic>)
          : const MerchantRedemptionSummary(),
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 商家结算概览(`/api/merchant/finance/overview`)。
///
/// ★ 后端把这五个口径称作「**互不偷算**」(MerchantSettlementOverview 的类注释)——
///   意思是它们各自独立、**前端不许再做加减**。金额一律是 CNY 两位字符串,
///   保持字符串原样展示,不转 double 再格式化(会引入精度与舍入差异,
///   而这是对账口径,差一分就对不上)。
///
/// 五个口径各自回答一个不同的问题:
///   · personalArrivedThisMonthGross —— 本月个人渠道**到账毛额**
///   · personalExecutedAdjustmentsThisMonth —— 本月**已执行**的调整(带符号,可为负)
///   · personalArrivedThisMonthNet —— 净额。服务端算的是 gross + adjustments,
///     **前端不要自己再算一遍** —— 两边算法一旦漂移,页面上就会出现自相矛盾的三个数
///   · publicPayablePending —— 对公**待打款**
///   · adjustmentPending / Count —— **待执行**的调整及笔数
class MerchantSettlementOverview {
  const MerchantSettlementOverview({
    this.personalArrivedThisMonthGross,
    this.personalExecutedAdjustmentsThisMonth,
    this.personalArrivedThisMonthNet,
    this.publicPayablePending,
    this.adjustmentPending,
    this.adjustmentPendingCount = 0,
  });

  /// ★ 全部可空:后端某一档没有数据时**不下发该字段**,
  ///   而「没有这个口径」和「这个口径是 0」在对账页上是两回事。
  final String? personalArrivedThisMonthGross;
  final String? personalExecutedAdjustmentsThisMonth;
  final String? personalArrivedThisMonthNet;
  final String? publicPayablePending;
  final String? adjustmentPending;
  final int adjustmentPendingCount;

  /// 有没有待执行的调整。★ 判据用**笔数**不用金额 ——
  /// 一笔 +100 和一笔 -100 的待执行调整,金额合计是 0,但确实有两笔待处理。
  bool get hasPendingAdjustment => adjustmentPendingCount > 0;

  factory MerchantSettlementOverview.fromJson(Map<String, dynamic> json) {
    String? s(String k) {
      final Object? v = json[k];
      if (v == null) return null;
      final String t = v.toString().trim();
      return t.isEmpty ? null : t;
    }

    return MerchantSettlementOverview(
      personalArrivedThisMonthGross: s('personalArrivedThisMonthGross'),
      personalExecutedAdjustmentsThisMonth:
          s('personalExecutedAdjustmentsThisMonth'),
      personalArrivedThisMonthNet: s('personalArrivedThisMonthNet'),
      publicPayablePending: s('publicPayablePending'),
      adjustmentPending: s('adjustmentPending'),
      adjustmentPendingCount:
          (json['adjustmentPendingCount'] as num?)?.toInt() ?? 0,
    );
  }
}
