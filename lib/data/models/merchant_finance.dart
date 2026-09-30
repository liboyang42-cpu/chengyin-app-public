/// 商家资金域四条查询的返回体。
///
/// ★★ **金额一律保持 String,不转 double**。
///   后端 DTO 里 `signedAmount` / `amountTotal` / `settlementAmount` 全是 String,
///   那是有意的:钱走十进制,转成 double 再格式化会在分位上飘。
///   前端把它 parse 再 toStringAsFixed(2),等于把后端刻意避开的浮点误差又请回来。
///   要显示就原样显示,要比较大小才临时解析。
///
/// ★★ `signedAmount` **带符号**:调整项是负数。
///   取绝对值或丢掉符号,一笔扣款就会显示成一笔收入 —— 而且总账还对得上,
///   因为错的只是这一行的方向。
library;

/// 分页外壳(后端 `MerchantFinancePage<T>`)。
class MerchantFinancePage<T> {
  const MerchantFinancePage({
    required this.rows,
    required this.total,
    required this.pageNum,
    required this.pageSize,
    this.summary,
  });

  final List<T> rows;
  final int total;
  final int pageNum;
  final int pageSize;

  /// 后端是 Object,形态随接口不同;原样透传,别在这里假设结构。
  final Map<String, dynamic>? summary;

  bool get hasMore => pageNum * pageSize < total;

  static int _int(Object? v) => v is num ? v.toInt() : 0;

  factory MerchantFinancePage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) item,
  ) =>
      MerchantFinancePage<T>(
        rows: (json['rows'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(item)
            .toList(),
        total: _int(json['total']),
        pageNum: _int(json['pageNum']),
        pageSize: _int(json['pageSize']),
        summary: json['summary'] as Map<String, dynamic>?,
      );
}

/// 已成立收入与调整明细的一行。
class MerchantSettlementEntry {
  const MerchantSettlementEntry({
    required this.entryKey,
    this.claimRef,
    this.settlementRoute,
    this.entryKind,
    this.source,
    this.sourceId,
    this.destination,
    this.signedAmount,
    this.headCount,
    this.occurredAt,
    this.arrivalAt,
    this.displayState,
    this.refKind,
    this.refId,
  });

  final String entryKey;
  final Map<String, dynamic>? claimRef;
  final String? settlementRoute;
  final String? entryKind;
  final String? source;
  final String? sourceId;
  final String? destination;

  /// ★ **带符号**的金额字符串,调整项为负。null = 后端没给,**不是 0**。
  final String? signedAmount;

  final int? headCount;
  final String? occurredAt;
  final String? arrivalAt;
  final String? displayState;
  final String? refKind;
  final String? refId;

  /// 是不是一笔扣减。只用来决定配色/图标,**不改动金额本身**。
  bool get isDeduction => (signedAmount ?? '').trimLeft().startsWith('-');

  factory MerchantSettlementEntry.fromJson(Map<String, dynamic> json) =>
      MerchantSettlementEntry(
        entryKey: (json['entryKey'] ?? '').toString(),
        claimRef: json['claimRef'] as Map<String, dynamic>?,
        settlementRoute: json['settlementRoute']?.toString(),
        entryKind: json['entryKind']?.toString(),
        source: json['source']?.toString(),
        sourceId: json['sourceId']?.toString(),
        destination: json['destination']?.toString(),
        // ⚠️ 不写 `?? '0.00'` —— 缺席和零元是两回事。
        signedAmount: json['signedAmount']?.toString(),
        headCount:
            json['headCount'] is num ? (json['headCount'] as num).toInt() : null,
        occurredAt: json['occurredAt']?.toString(),
        arrivalAt: json['arrivalAt']?.toString(),
        displayState: json['displayState']?.toString(),
        refKind: json['refKind']?.toString(),
        refId: json['refId']?.toString(),
      );
}

/// 对公结算批次。
class PublicTransferBatch {
  const PublicTransferBatch({
    required this.batchId,
    this.periodYm,
    this.amountTotal,
    this.netDirection,
    this.paymentState,
    this.invoiceState,
    this.holdState,
    this.displayState,
    this.paidAt,
    this.payVoucherNo,
  });

  final String batchId;
  final String? periodYm;

  /// 批次总额(String,原样显示)。
  final String? amountTotal;

  /// 净额方向。⚠️ 缺席时是 null,**不能兜成"收"** ——
  /// 方向猜错会把一笔应付显示成应收。
  final String? netDirection;

  final String? paymentState;
  final String? invoiceState;
  final String? holdState;
  final String? displayState;
  final String? paidAt;
  final String? payVoucherNo;

  factory PublicTransferBatch.fromJson(Map<String, dynamic> json) =>
      PublicTransferBatch(
        batchId: (json['batchId'] ?? '').toString(),
        periodYm: json['periodYm']?.toString(),
        amountTotal: json['amountTotal']?.toString(),
        netDirection: json['netDirection']?.toString(),
        paymentState: json['paymentState']?.toString(),
        invoiceState: json['invoiceState']?.toString(),
        holdState: json['holdState']?.toString(),
        displayState: json['displayState']?.toString(),
        paidAt: json['paidAt']?.toString(),
        payVoucherNo: json['payVoucherNo']?.toString(),
      );
}

/// 批次详情:批次头 + 收入分录 + 调整分录。
class PublicTransferBatchDetail {
  const PublicTransferBatchDetail({
    required this.batch,
    required this.earningEntries,
    required this.adjustments,
  });

  final PublicTransferBatch batch;

  /// 收入分录。
  final List<MerchantSettlementEntry> earningEntries;

  /// 调整分录(通常是负数)。★ 与收入分开两个列表是**后端的分法**,
  /// 前端合并成一个列表展示会让人看不出哪些是扣减。
  final List<MerchantSettlementEntry> adjustments;

  static List<MerchantSettlementEntry> _entries(Object? raw) =>
      (raw as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(MerchantSettlementEntry.fromJson)
          .toList();

  factory PublicTransferBatchDetail.fromJson(Map<String, dynamic> json) =>
      PublicTransferBatchDetail(
        batch: PublicTransferBatch.fromJson(
            (json['batch'] as Map<String, dynamic>?) ?? <String, dynamic>{}),
        earningEntries: _entries(json['earningEntries']),
        adjustments: _entries(json['adjustments']),
      );
}

/// 单笔核销的详情。
class MerchantRedemptionView {
  const MerchantRedemptionView({
    required this.recordKey,
    this.recordType,
    this.recordId,
    this.topicName,
    this.chapterName,
    this.storeName,
    this.customerDisplayName,
    this.verificationCodeTail,
    this.settlementAmount,
    this.fulfillmentState,
    this.settlementState,
    this.settlementRoute,
    this.displayState,
    this.noCashReason,
    this.occurredAt,
    this.unitFee,
    this.headCount,
    this.refundState,
    this.publicSettlementPaidAt,
  });

  final String recordKey;
  final String? recordType;
  final String? recordId;
  final String? topicName;
  final String? chapterName;
  final String? storeName;

  /// 顾客展示名。后端已按 PII 规则处理过,**前端不要再加工**。
  final String? customerDisplayName;

  /// 核销码尾号(后端只给尾号,不给全码)。
  final String? verificationCodeTail;

  /// 结算金额(String)。
  final String? settlementAmount;

  final String? fulfillmentState;
  final String? settlementState;
  final String? settlementRoute;
  final String? displayState;

  /// 零现金原因。非空 = 这笔不结钱,界面必须把原因说出来,
  /// 否则商家看到「¥0.00」会以为系统算错了。
  final String? noCashReason;

  /// 核销发生时间(服务端原样串,展示截到分钟)。
  final String? occurredAt;

  /// 计提两件套:单价 × 人头。**缺任一就不拼**(真源 accrualRuleText 不猜)。
  final num? unitFee;
  final num? headCount;

  /// 退款态:REVIEWING / REJECTED / REFUNDING / REFUNDED。
  final String? refundState;

  /// 对公结算的到账时间(`publicSettlement.paidAt`)。
  final String? publicSettlementPaidAt;

  static bool _has(String? v) => v != null && v.trim().isNotEmpty;

  /// 资金投影是否可见。后端脱敏时三个字段**要么全给、要么全不给**
  /// (真源 `hasFinanceProjection`),不能只看其中一个。
  bool get canReadFinance =>
      _has(settlementState) && _has(settlementRoute) && _has(displayState);

  /// 卡1 标题:主题 · 章节;都没有就叫「核销记录」。
  String get titleText {
    final String t = <String?>[topicName, chapterName]
        .where(_has)
        .join(' · ');
    return t.isEmpty ? '核销记录' : t;
  }

  /// 金额文本。**后端没给金额就是没有**(null),这时看 [amountFallback]。
  /// ⚠️ 真源 `settlementAmountText` 就是这个语义 —— 把「没有数」折成「¥0.00」
  ///    或反过来把 0 折成「—」,商家都会按错的方式理解这笔钱。
  String? get amountText {
    final String v = (settlementAmount ?? '').trim();
    return v.isEmpty ? null : '¥$v';
  }

  /// 金额缺席时的占位:零现金 = **确认不产生现金**(—);
  /// 其余 = **金额还没成立**(待定)。两句话不能混。
  String get amountFallback =>
      displayState == 'NO_CASH_SETTLEMENT' ? '—' : '待定';

  /// 计提规则。只有服务端给了单价与人头才拼,拼不出整行不渲染。
  String? get accrualRuleText {
    final num? fee = unitFee;
    final num? heads = headCount;
    if (fee == null || heads == null) return null;
    String trim(num v) {
      final String s = v.toString();
      return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
    }

    return '¥${trim(fee)}/人 × ${trim(heads)}';
  }

  /// 退款态文案。认不出来的状态**整行不渲染**,不写「退款异常」吓人。
  String? get refundText => switch (refundState) {
        'REVIEWING' => '审核中',
        'REJECTED' => '已驳回',
        'REFUNDING' => '退款中',
        'REFUNDED' => '已退款',
        _ => null,
      };

  /// 核销时间,截到分钟(后端给的是秒级串)。
  String? get occurredAtMinute {
    final String v = (occurredAt ?? '').trim();
    if (v.isEmpty) return null;
    return v.length >= 16 ? v.substring(0, 16) : v;
  }

  factory MerchantRedemptionView.fromJson(Map<String, dynamic> json) =>
      MerchantRedemptionView(
        recordKey: (json['recordKey'] ?? '').toString(),
        recordType: json['recordType']?.toString(),
        recordId: json['recordId']?.toString(),
        topicName: json['topicName']?.toString(),
        chapterName: json['chapterName']?.toString(),
        storeName: json['storeName']?.toString(),
        customerDisplayName: json['customerDisplayName']?.toString(),
        verificationCodeTail: json['verificationCodeTail']?.toString(),
        settlementAmount: json['settlementAmount']?.toString(),
        fulfillmentState: json['fulfillmentState']?.toString(),
        settlementState: json['settlementState']?.toString(),
        settlementRoute: json['settlementRoute']?.toString(),
        displayState: json['displayState']?.toString(),
        noCashReason: json['noCashReason']?.toString(),
        occurredAt: json['occurredAt']?.toString(),
        unitFee: json['unitFee'] as num?,
        headCount: json['headCount'] as num?,
        refundState: json['refundState']?.toString(),
        publicSettlementPaidAt: (json['publicSettlement']
            as Map<String, dynamic>?)?['paidAt']?.toString(),
      );
}
