/// 资金域的状态文案 / 语义色。**逐条抄小程序 pages/merchant/ledger,别简化**。
///
/// ★★★ 这些分支对商家意味着完全不同的动作:
///   「待主题结算」和「待结算」是两种等法;
///   「已入个人账户」和「平台已打款」是两个去处;
///   「本期无需打款」和「调整待处理」一个不用管、一个要处理。
///   合并任何两条,商家就会按错的方式行动。
///
/// ⚠️ 这里**只做映射,不做业务判断** —— 零现金的具体原因由服务端
///   `noCashReason` 给(小程序注释原话),前端不猜。
library;

/// 一条资金记录(核销记录 / 结算条目)的状态文案。
///
/// ⚠️ `noCashReason` 只有核销记录(MerchantRedemptionView)有;
///   结算条目(MerchantSettlementEntry)后端**不下发**这个字段 ——
///   那时落到兜底句,而不是编一个原因。
String financeStateText({
  required String? displayState,
  String? noCashReason,
  String? settlementRoute,
  String? destination,
}) {
  if (displayState == 'NO_CASH_SETTLEMENT') {
    final String r = (noCashReason ?? '').trim();
    // 有原因就说原因;没有就说事实,不替服务端编一个理由。
    return r.isEmpty ? '本次不产生现金结算' : r;
  }
  return switch (displayState) {
    // 两种等法不一样:走主题结算的要等主题结算完。
    'PENDING_SETTLEMENT' =>
      settlementRoute == 'COOP_ORDER' ? '待主题结算' : '待结算',
    // 两个去处不一样:进个人账户 vs 平台对公打款。
    'SETTLED' =>
      destination == 'PERSONAL_ACCOUNT' ? '已入个人账户' : '平台已打款',
    'ADJUSTMENT_PENDING' => '调整中',
    'ADJUSTED' => '已调整',
    'REVERSED_BEFORE_SETTLEMENT' => '核销已撤销',
    'LEDGER_ERROR' => '结算数据异常,已上报',
    // ★ 认不出来的状态说「状态待确认」——不许猜成「待结算」,
    //   那会让商家以为钱在路上。
    _ => '状态待确认',
  };
}

/// 状态语义色。1:1 映射,**不含业务判断**(小程序注释原话)。
FinanceTone financeTone(String? displayState) => switch (displayState) {
      'PENDING_SETTLEMENT' => FinanceTone.warning,
      'SETTLED' => FinanceTone.success,
      'ADJUSTMENT_PENDING' => FinanceTone.danger,
      'LEDGER_ERROR' => FinanceTone.danger,
      'ADJUSTED' => FinanceTone.neutral,
      'REVERSED_BEFORE_SETTLEMENT' => FinanceTone.neutral,
      'NO_CASH_SETTLEMENT' => FinanceTone.neutral,
      _ => FinanceTone.neutral,
    };

enum FinanceTone { warning, success, danger, neutral }

/// 对公打款批次的状态文案。**四层分支,逐条抄**。
///
/// ★★★ 前三条是**特殊情况**,不能落进 [_batchPaymentText] 的常规话术:
///   · 结算数据异常 → 商家该等平台处理,不是等打款
///   · 本期无需打款 → 不用管
///   · 平台欠商家的反方向(MERCHANT_OWES_PLATFORM)→ 要处理调整
String batchStateText({
  required String? displayState,
  required String? netDirection,
  required String? paymentState,
  required String? invoiceState,
  required String? holdState,
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

FinanceTone batchTone({
  required String? displayState,
  required String? paymentState,
}) {
  if (displayState == 'LEDGER_ERROR') return FinanceTone.danger;
  return paymentState == 'PAID' ? FinanceTone.success : FinanceTone.warning;
}

/// 发票态。⚠️ 认不出来时返回 null(整块不显示),**不写「未开票」**——
/// 「拿不到」和「没开」是两件事,后者会让商家以为该去催开票。
String? invoiceText(String? invoiceState) => switch (invoiceState) {
      'NONE' => '未开票',
      'ISSUED' => '已开票',
      'RED' => '已红冲',
      _ => null,
    };

/// 打款进度的一个节点。
class BatchTimelineNode {
  const BatchTimelineNode({
    required this.label,
    required this.state,
    this.at,
  });

  final String label;

  /// done 已发生 / now 正在办 / todo 还没到
  final String state;

  /// ★★ **只有服务端真给了时间戳的节点才有**。
  ///   资金域定稿附录 C:「预计打款日期」这条规则**代码里不存在**,
  ///   凭空写「预计 X 日到账」是**假承诺**。
  ///   ⇒ 未来节点只写状态名,不给日期、不写「预计」。
  final String? at;
}

/// 对公打款进度。
///
/// ★★ 判据是**业务事实,不是时间戳**(小程序注释原话):
///   批次对象存在 ⇒「批次生成」这件事必然已发生,恒实心。
///   往后走几步只看 paymentState。
///
/// ⚠️ 「批次生成」「对账确认」两个节点**永远没有日期** ——
///   后端 `PublicTransferBatch` VO 里根本没有 createdAt / confirmedAt
///   (2026-08-20 读 VO 核实)。小程序那两行读的是 undefined。
///   ⇒ 不给 App 模型补这两个字段:补了也永远是 null,徒增一份看着像有其实没有的数据。
List<BatchTimelineNode> batchTimeline({
  required String? netDirection,
  required String? paymentState,
  String? paidAt,
  String? payVoucherNo,
}) {
  // ★ 只有「平台打给商家」这个方向才谈打款进度。
  //   反方向(商家欠平台)显示一条打款时间线是答非所问。
  if (netDirection != 'PLATFORM_PAYS_MERCHANT') {
    return const <BatchTimelineNode>[];
  }

  final String paid = (paidAt ?? '').trim();
  final String voucher = (payVoucherNo ?? '').trim();
  final String? paidLine = paid.isEmpty
      ? null
      : (voucher.isEmpty
          ? _minute(paid)
          : '${_minute(paid)} · 凭证 $voucher');

  final int doneThrough = switch (paymentState) {
    'PAID' => 3,
    'CONFIRMED' => 2, // 对账已确认,正在等打款
    _ => 1, // 批次已生成,正在等对账
  };
  final bool hasCurrent = paymentState != 'PAID';

  final List<(String, String?)> raw = <(String, String?)>[
    ('批次生成', null),
    ('对账确认', null),
    ('平台打款', paidLine),
  ];

  return <BatchTimelineNode>[
    for (int i = 0; i < raw.length; i++)
      BatchTimelineNode(
        label: raw[i].$1,
        at: raw[i].$2,
        state: i < doneThrough
            ? 'done'
            : (hasCurrent && i == doneThrough ? 'now' : 'todo'),
      ),
  ];
}

/// 服务端时间串截到分钟。拿不到返回原串(不猜、不补零)。
String _minute(String raw) => raw.length >= 16 ? raw.substring(0, 16) : raw;

/// 这个批次算不算「已经打给我了」。
///
/// ★★ 两个条件缺一不可:方向是平台付给商家 **且** 已打款。
///   只看 paymentState=='PAID' 会把**反方向**的批次也说成「已打款」——
///   那笔钱是商家欠平台的,说成已打款正好反了。
bool batchIsPaidToMerchant({
  required String? netDirection,
  required String? paymentState,
}) =>
    netDirection == 'PLATFORM_PAYS_MERCHANT' && paymentState == 'PAID';

/// 核销**详情页**(`pages/merchant/ledger/order-detail`)的状态文案。
///
/// ⚠️ 与台账列表的 [financeStateText] **不是同一张表** —— 小程序两页各写一份,
///   详情页的「待结算」说的是「随主题结算发放至个人账户」,对账异常也换了话术。
///   合并任一条,两页里必有一页对不上原文。
String financeRedemptionStateText({
  required String? displayState,
  String? noCashReason,
  String? settlementRoute,
}) {
  if (displayState == 'NO_CASH_SETTLEMENT') {
    final String r = (noCashReason ?? '').trim();
    return r.isEmpty ? '本次不产生现金结算' : r;
  }
  return switch (displayState) {
    'PENDING_SETTLEMENT' => '随主题结算发放至个人账户',
    'SETTLED' =>
      settlementRoute == 'CHAPTER_OFFER' ? '平台已打款' : '已入个人账户',
    'ADJUSTMENT_PENDING' => '调整中',
    'ADJUSTED' => '已调整',
    'REVERSED_BEFORE_SETTLEMENT' => '核销已撤销',
    'LEDGER_ERROR' => '结算数据对不上，请联系客服',
    _ => '状态待确认',
  };
}

/// 核销详情的「结算进度」时间线(真源 `buildTimeline` + `progressStep`)。
///
/// ★ 只对走**章节供给**的结算画进度:其它去向的时间线规则不在这一页。
/// ★★ 未来节点**不给日期、不写「预计」**——资金域定稿附录 C:
///    「预计打款日期」这条规则代码里不存在,凭空写是假承诺。
List<BatchTimelineNode> redemptionTimeline({
  required String? settlementState,
  required String? settlementRoute,
  String? occurredAt,
  String? paidAt,
}) {
  if (settlementRoute != 'CHAPTER_OFFER') return const <BatchTimelineNode>[];
  String? minute(String? raw) {
    final String v = (raw ?? '').trim();
    if (v.isEmpty) return null;
    return v.length >= 16 ? v.substring(0, 16) : v;
  }

  final List<(String, String?)> raw = <(String, String?)>[
    ('核销成功', minute(occurredAt)),
    ('生成结算单', null),
    ('对账确认', null),
    ('平台打款', minute(paidAt)),
  ];
  // 判据是**业务事实,不是有没有时间戳**:SETTLED/ADJUSTED 系列 = 打款已发生
  // (ADJUSTMENT_PENDING 待办的是另一条去向,不在这条线上);PENDING = 卡在第一步;
  // 其余(NOT_APPLICABLE / ERROR)= 核销发生过,但后面不会再推进。
  final (int doneThrough, bool hasCurrent) = switch (settlementState) {
    'SETTLED' || 'ADJUSTED' || 'ADJUSTMENT_PENDING' => (raw.length, false),
    'PENDING' => (1, true),
    _ => (1, false),
  };
  return <BatchTimelineNode>[
    for (int i = 0; i < raw.length; i++)
      BatchTimelineNode(
        label: raw[i].$1,
        at: raw[i].$2,
        state: i < doneThrough
            ? 'done'
            : (hasCurrent && i == doneThrough ? 'now' : 'todo'),
      ),
  ];
}

/// 核销详情**没有资金投影**时的状态文案(真源 `fulfillmentStateText`)。
///
/// ★ 与 [financeRedemptionStateText] 是**两条路**:后端脱敏时三条资金字段全不给,
///   这一页就退回到只说履约事实,而不是拿一个空 displayState 去查表 ——
///   查表会落到「状态待确认」,把「后端不肯说结算」说成「状态不明」。
String financeFulfillmentStateText(String? fulfillmentState) =>
    switch (fulfillmentState) {
      'ACTIVE' => '核销有效',
      'REVERSED' => '核销已撤销',
      _ => '核销状态待确认',
    };

/// 核销详情徽标的语义色(真源 `stateVariant`,1:1 映射、不含业务判断)。
///
/// ⚠️ 只有**明确异常**才给 danger:LEDGER_ERROR 是「结算数据对不上」,要人去看;
///   ADJUSTMENT_PENDING 是「原款已结、负向调整待办」,也得出声。
///   零现金/已调整/已撤销都是**说完就完了**的中性事实,染红反而是误导。
String financeStateVariant({
  required bool canReadFinance,
  String? displayState,
  String? fulfillmentState,
}) {
  if (!canReadFinance) {
    return fulfillmentState == 'ACTIVE' ? 'success' : 'neutral';
  }
  return switch (displayState) {
    'PENDING_SETTLEMENT' => 'warning',
    'SETTLED' => 'success',
    'ADJUSTMENT_PENDING' || 'LEDGER_ERROR' => 'danger',
    _ => 'neutral',
  };
}
