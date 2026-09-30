/// 商家 CRM 运营台的数据模型 —— 客户名册 / 分群 / 合规触达。
///
/// ★ 真源 = 小程序只读快照 `master@90e66d70` `pages/merchant/customer/index.js`:
///   - 行形状与校验:`shapeRow` / `isCustomerRow` —— **任一畸形行整页 fail-closed**,
///     不许「跳过坏行」:少一行和多一行编的数据同样坏;
///   - 分页回包:`_fetch` 对 `{total, rows, segmentCounts, availableTags,
///     couponDeliveryStatus, notificationDeliveryStatus}` 的 shape 校验;
///   - 触达任务:`shapeCampaign` 的字段与逐人回执;
///   - 幂等号:`createRequestId(kind)` 的格式。
/// 本文件只做「解析 + 展示文案」,不发请求(发请求在 `merchant_crm_console_api.dart`)。
library;

import 'dart:math' as math;

import 'merchant_customer.dart' show relativeTime;

/// 列表每页条数。快照 `PAGE_SIZE = 20`。
const int kCrmCustomerPageSize = 20;

/// 批量标签一次最多 100 人。快照 `openCustomer` 的 `selected.length < 100`。
const int kCrmBatchTagLimit = 100;

/// 批量标签的默认颜色。快照 `submitBatchTag` 写死 `#2E6D5A`(品牌绿)。
const String kCrmBatchTagColor = '#2E6D5A';

/// 分层文案。快照 `TIER_TEXT` —— 认不出的 tier 不写,
/// 把英文枚举原样印给商家没有任何意义。
const Map<String, String> kCrmTierText = <String, String>{
  'pending': '待核销',
  'abnormal': '异常',
  'dormant': '沉睡',
  'repeat': '复购',
  'new': '新客',
};

/// 顶部高频筛选档。快照 `SEGMENTS` —— 数量统一留在标题摘要,chip 只放业务词。
const List<CrmSegmentOption> kCrmSegmentOptions = <CrmSegmentOption>[
  CrmSegmentOption('all', '全部'),
  CrmSegmentOption('repeat', '回头客'),
  CrmSegmentOption('new', '新客'),
  CrmSegmentOption('noted', '有备注'),
];

class CrmSegmentOption {
  const CrmSegmentOption(this.key, this.label);

  final String key;
  final String label;
}

/// 触达渠道文案。快照 wxml 的 `cu-filter-chip`。
const Map<String, String> kCrmChannelText = <String, String>{
  'IN_APP': '站内活动消息',
  'COUPON': '商家优惠券',
};

/// 客户名单查询。快照 `_queryKey()` 的六个字段 + 分页。
class CrmCustomerQuery {
  const CrmCustomerQuery({
    this.pageNum = 1,
    this.keyword = '',
    this.segment = 'all',
    this.tagId,
    this.sourceType,
    this.sourceStart,
    this.sourceEnd,
  });

  final int pageNum;
  final String keyword;

  /// all / repeat / new / noted。
  final String segment;
  final int? tagId;

  /// 1 主题 / 2 活动 / null 全部。快照 `onSourceTap` 只认这三档。
  final int? sourceType;
  final String? sourceStart;
  final String? sourceEnd;

  CrmCustomerQuery copyWith({
    int? pageNum,
    String? keyword,
    String? segment,
    int? tagId,
    bool clearTagId = false,
    int? sourceType,
    bool clearSourceType = false,
    String? sourceStart,
    String? sourceEnd,
    bool clearSourceDates = false,
  }) {
    return CrmCustomerQuery(
      pageNum: pageNum ?? this.pageNum,
      keyword: keyword ?? this.keyword,
      segment: segment ?? this.segment,
      tagId: clearTagId ? null : (tagId ?? this.tagId),
      sourceType: clearSourceType ? null : (sourceType ?? this.sourceType),
      sourceStart: clearSourceDates ? null : (sourceStart ?? this.sourceStart),
      sourceEnd: clearSourceDates ? null : (sourceEnd ?? this.sourceEnd),
    );
  }

  /// 请求体。★ 逐键对齐快照:空值发 `null`(不是省键),
  /// `keyword` 发原值(空串也发)。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'pageNum': pageNum,
    'pageSize': kCrmCustomerPageSize,
    'keyword': keyword,
    'segment': segment,
    'tagId': tagId,
    'sourceType': sourceType,
    'sourceStart': sourceStart,
    'sourceEnd': sourceEnd,
  };

  /// 导出任务里的 query。快照 `_customerQuery(1)`(index.js:1195)—— 导出的是
  /// **当前视图**:名册那六个筛选字段一个都不能少,`all`/空关键词折成 null。
  /// (与 [toJson] 的差别就在这两处:名册原样发,导出折空。)
  Map<String, dynamic> toExportQuery() => <String, dynamic>{
    'pageNum': 1,
    'pageSize': kCrmCustomerPageSize,
    'keyword': keyword.isEmpty ? null : keyword,
    ...toFilter().toJson(),
  };

  /// 保存分群用的 filter 形状。快照 `_segmentFilter()`:`all` 折成 null。
  CrmSegmentFilter toFilter() => CrmSegmentFilter(
    segment: segment == 'all' ? null : segment,
    tagId: tagId,
    sourceType: sourceType,
    sourceStart: sourceStart,
    sourceEnd: sourceEnd,
  );

  bool sameQuery(CrmCustomerQuery other) =>
      keyword == other.keyword &&
      segment == other.segment &&
      tagId == other.tagId &&
      sourceType == other.sourceType &&
      sourceStart == other.sourceStart &&
      sourceEnd == other.sourceEnd;

  @override
  bool operator ==(Object other) =>
      other is CrmCustomerQuery &&
      other.pageNum == pageNum &&
      sameQuery(other);

  @override
  int get hashCode => Object.hash(
    pageNum,
    keyword,
    segment,
    tagId,
    sourceType,
    sourceStart,
    sourceEnd,
  );
}

/// 保存分群的筛选条件。形状逐键对齐快照 `_segmentFilter()`。
class CrmSegmentFilter {
  const CrmSegmentFilter({
    this.segment,
    this.tagId,
    this.sourceType,
    this.sourceStart,
    this.sourceEnd,
  });

  final String? segment;
  final int? tagId;
  final int? sourceType;
  final String? sourceStart;
  final String? sourceEnd;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'segment': segment,
    'tagId': tagId,
    'sourceType': sourceType,
    'sourceStart': sourceStart,
    'sourceEnd': sourceEnd,
  };

  factory CrmSegmentFilter.fromJson(Map<String, dynamic> json) {
    return CrmSegmentFilter(
      segment: json['segment'] is String ? json['segment'] as String : null,
      tagId: _positiveId(json['tagId']),
      sourceType: _positiveId(json['sourceType']),
      sourceStart: json['sourceStart'] is String
          ? json['sourceStart'] as String
          : null,
      sourceEnd: json['sourceEnd'] is String
          ? json['sourceEnd'] as String
          : null,
    );
  }
}

/// 客户名册一行。字段逐条对齐快照 `shapeRow` 的白名单产物。
class CrmCustomerRow {
  const CrmCustomerRow({
    required this.memberId,
    required this.name,
    this.avatar,
    this.phone,
    this.contactHint,
    this.latestNote,
    this.arrivedCount = 0,
    this.pendingCount = 0,
    this.refundedCount = 0,
    this.paidAmount,
    this.lastTime,
    this.lastAction = '',
    this.tier = '',
    this.sourceType = '',
    this.teamName,
    this.roleName,
  });

  final int memberId;
  final String name;
  final String? avatar;
  final String? phone;

  /// 没有电话时,服务端给的原因(「未授权展示」等)。
  /// ★ 没号时必须说明为什么 —— 只是空着,商家会当成「这人没留电话」。
  final String? contactHint;
  final String? latestNote;
  final int arrivedCount;
  final int pendingCount;
  final int refundedCount;
  final double? paidAmount;
  final String? lastTime;
  final String lastAction;
  final String tier;

  /// TOPIC / ACTIVITY / MIXED。
  final String sourceType;

  /// 定向广播的分组字段(本线不做广播,行形状保留)。
  final String? teamName;
  final String? roleName;

  /// 列表主标题。没留姓名时兜底。
  String get displayName => name.trim().isEmpty ? '未留姓名' : name.trim();

  /// 头像取首字用的名字。
  /// ★ **兜底文案不能进头像** —— 用 displayName 会把「未」字渲成姓氏。
  String get avatarName => name.trim();

  /// 分层徽标文案。认不出的 tier 给空串(不印英文枚举)。
  String get tierText => kCrmTierText[tier] ?? '';

  /// 待核销的徽标要 warning 色,其余 neutral。快照 wxml `cu-tier` 的 variant 分支。
  bool get tierIsWarning => tier == 'pending';

  String get phoneText => (phone ?? '').trim();
  String get noteText => (latestNote ?? '').trim();
  String get hintText => (contactHint ?? '').trim();

  /// 「核销了『夜跑咖啡路线』· 3 天前」。两截都可能为空,别拼出孤零零的「· 」。
  String actionText(DateTime now) {
    final String action = lastAction.trim();
    final String when = relativeTime(lastTime, now);
    return <String>[action, when].where((String s) => s.isNotEmpty).join(' · ');
  }

  /// 严格解析。**任一字段不合法回 null**,由调用方把整页判成格式异常
  /// (快照 `isCustomerRow` 的纪律:不许过滤坏行,也不许默认成可点击客户)。
  static CrmCustomerRow? tryParse(Map<String, dynamic> json) {
    final int? memberId = _strictId(json['memberId']);
    if (memberId == null) return null;
    final Object? rawName = json['name'];
    if (rawName is! String || rawName.trim().isEmpty) return null;
    if (!_nullableString(json['avatar']) ||
        !_nullableString(json['phone']) ||
        !_nullableString(json['contactHint']) ||
        !_nullableString(json['latestNote'])) {
      return null;
    }
    if (!_nonNegInt(json['arrivedCount']) ||
        !_nonNegInt(json['pendingCount']) ||
        !_nonNegInt(json['refundedCount'])) {
      return null;
    }
    final Object? paid = json['paidAmount'];
    if (paid != null &&
        !(paid is num && paid.isFinite && paid >= 0)) {
      return null;
    }
    if (!_validDateValue(json['lastTime'])) return null;
    final Object? rawAction = json['lastAction'];
    if (rawAction is! String || rawAction.trim().isEmpty) return null;
    final Object? rawTier = json['tier'];
    if (rawTier is! String || !kCrmTierText.containsKey(rawTier)) return null;
    final Object? rawSource = json['sourceType'];
    if (rawSource is! String ||
        !const <String>{'TOPIC', 'ACTIVITY', 'MIXED'}.contains(rawSource)) {
      return null;
    }
    return CrmCustomerRow(
      memberId: memberId,
      name: rawName.trim(),
      avatar: _nullableText(json['avatar']),
      phone: _nullableText(json['phone']),
      contactHint: _nullableText(json['contactHint']),
      latestNote: _nullableText(json['latestNote']),
      arrivedCount: _intValue(json['arrivedCount']),
      pendingCount: _intValue(json['pendingCount']),
      refundedCount: _intValue(json['refundedCount']),
      paidAmount: paid is num ? paid.toDouble() : null,
      lastTime: _dateText(json['lastTime']),
      lastAction: rawAction.trim(),
      tier: rawTier,
      sourceType: rawSource,
      teamName: _nullableText(json['teamName']),
      roleName: _nullableText(json['roleName']),
    );
  }
}

/// 分页回包。快照 `_fetch` 的 shape 校验:total 必须是整数,
/// rows 每一条都必须通过 `isCustomerRow`,否则整页错误。
class CrmCustomerPageData {
  const CrmCustomerPageData({
    required this.rows,
    required this.total,
    required this.segmentCounts,
    required this.availableTags,
    this.couponDeliveryStatus = '',
    this.notificationDeliveryStatus = '',
  });

  final List<CrmCustomerRow> rows;
  final int total;

  /// all / repeat / new / noted / monthlyNew。`null` = 服务端没给这一档,
  /// 不能用 0 伪造。
  final Map<String, int?> segmentCounts;
  final List<CrmAvailableTag> availableTags;
  final String couponDeliveryStatus;
  final String notificationDeliveryStatus;

  /// 摘要文案。快照 `customerSummaryText`。
  String summaryText() {
    final int? total = segmentCounts['all'];
    if (total == null) return '客户数量加载中';
    final int? monthly = segmentCounts['monthlyNew'];
    if (monthly == null) return '$total 位';
    return '$total 位 · 本月新增 $monthly';
  }

  static CrmCustomerPageData? tryParse(Map<String, dynamic> json) {
    final Object? rawTotal = json['total'];
    if (!_intValueOk(rawTotal)) return null;
    final Object? rawRows = json['rows'];
    if (rawRows is! List) return null;
    final List<CrmCustomerRow> rows = <CrmCustomerRow>[];
    for (final Object? row in rawRows) {
      if (row is! Map<String, dynamic>) return null;
      final CrmCustomerRow? parsed = CrmCustomerRow.tryParse(row);
      if (parsed == null) return null;
      rows.add(parsed);
    }
    final Object? rawCounts = json['segmentCounts'];
    final Map<String, dynamic> counts = rawCounts is Map<String, dynamic>
        ? rawCounts
        : const <String, dynamic>{};
    return CrmCustomerPageData(
      rows: rows,
      total: _intValue(rawTotal),
      segmentCounts: <String, int?>{
        for (final String key in const <String>[
          'all',
          'repeat',
          'new',
          'noted',
          'monthlyNew',
        ])
          key: _finiteCount(counts[key]),
      },
      availableTags: CrmAvailableTag.parseList(json['availableTags']),
      couponDeliveryStatus: json['couponDeliveryStatus'] is String
          ? json['couponDeliveryStatus'] as String
          : '',
      notificationDeliveryStatus:
          json['notificationDeliveryStatus'] is String
          ? json['notificationDeliveryStatus'] as String
          : '',
    );
  }
}

/// 客户标签候选。快照 `shapeTags`。
class CrmAvailableTag {
  const CrmAvailableTag({
    required this.id,
    required this.tagName,
    this.tagColor = kCrmBatchTagColor,
  });

  final int id;
  final String tagName;
  final String tagColor;

  static List<CrmAvailableTag> parseList(Object? raw) {
    if (raw is! List) return const <CrmAvailableTag>[];
    final List<CrmAvailableTag> out = <CrmAvailableTag>[];
    for (final Object? item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final int? id = _positiveId(item['id']);
      final Object? name = item['tagName'];
      if (id == null || name is! String || name.trim().isEmpty) continue;
      out.add(
        CrmAvailableTag(
          id: id,
          tagName: name.trim(),
          tagColor: item['tagColor'] is String
              ? item['tagColor'] as String
              : kCrmBatchTagColor,
        ),
      );
    }
    return out;
  }
}

/// 已保存分群。GET `/api/merchant/crm/segments` 的一行。
class CrmSavedSegment {
  const CrmSavedSegment({required this.id, required this.name, this.filter});

  final int id;
  final String name;
  final CrmSegmentFilter? filter;

  static List<CrmSavedSegment> parseList(Object? raw) {
    if (raw is! List) return const <CrmSavedSegment>[];
    final List<CrmSavedSegment> out = <CrmSavedSegment>[];
    for (final Object? item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final int? id = _positiveId(item['id']);
      if (id == null) continue;
      final Object? name = item['name'];
      final Object? filter = item['filter'];
      out.add(
        CrmSavedSegment(
          id: id,
          name: name is String && name.trim().isNotEmpty
              ? name.trim()
              : '已保存分群',
          filter: filter is Map<String, dynamic>
              ? CrmSegmentFilter.fromJson(filter)
              : null,
        ),
      );
    }
    return out;
  }
}

/// 商家有效券。GET `/api/merchant/crm/campaigns/coupons` 的一行。
class CrmCoupon {
  const CrmCoupon({required this.id, required this.name});

  final int id;
  final String name;

  static List<CrmCoupon> parseList(Object? raw) {
    if (raw is! List) return const <CrmCoupon>[];
    final List<CrmCoupon> out = <CrmCoupon>[];
    for (final Object? item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final int? id = _positiveId(item['id']);
      if (id == null) continue;
      final Object? name = item['name'];
      out.add(
        CrmCoupon(
          id: id,
          name: name is String && name.trim().isNotEmpty
              ? name.trim()
              : '优惠券',
        ),
      );
    }
    return out;
  }
}

/// 触达预览。POST `/api/merchant/crm/campaigns/preview` 的 data。
///
/// 快照 wxml 用 `|| 0` 兜底渲染,所以这里缺字段回 0,不判失败。
class CrmCampaignPreview {
  const CrmCampaignPreview({
    this.totalCount = 0,
    this.recipientLimit = 200,
    this.consentedCount = 0,
    this.frequencyLimitedCount = 0,
    this.deliverableCount = 0,
  });

  final int totalCount;
  final int recipientLimit;
  final int consentedCount;
  final int frequencyLimitedCount;
  final int deliverableCount;

  static CrmCampaignPreview? tryParse(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    return CrmCampaignPreview(
      totalCount: _count(value['totalCount']),
      recipientLimit: _count(value['recipientLimit'], fallback: 200),
      consentedCount: _count(value['consentedCount']),
      frequencyLimitedCount: _count(value['frequencyLimitedCount']),
      deliverableCount: _count(value['deliverableCount']),
    );
  }
}

/// 触达任务的一个收件人回执。快照 `shapeCampaign` 的 recipients 分支。
class CrmCampaignRecipient {
  const CrmCampaignRecipient({
    this.recipientId,
    required this.customerName,
    required this.status,
    this.failureCode = '',
    this.failureMessage = '',
    this.messageReceiptId,
    this.couponHistoryId,
    this.deliveredAt,
  });

  final int? recipientId;
  final String customerName;

  /// DELIVERED / PENDING / 其余失败码。
  final String status;
  final String failureCode;
  final String failureMessage;
  final int? messageReceiptId;
  final int? couponHistoryId;
  final Object? deliveredAt;

  String statusText() {
    if (status == 'DELIVERED') return '已送达';
    return failureMessage.trim().isNotEmpty ? failureMessage.trim() : '待处理';
  }

  static CrmCampaignRecipient? tryParse(Map<String, dynamic> json) {
    final Object? name = json['customerName'];
    return CrmCampaignRecipient(
      recipientId: _positiveId(json['recipientId']),
      customerName: name is String && name.trim().isNotEmpty
          ? name.trim()
          : '未留姓名',
      status: _textValue(json['status'], fallback: 'PENDING'),
      failureCode: _textValue(json['failureCode']),
      failureMessage: _textValue(json['failureMessage']),
      messageReceiptId: _positiveId(json['messageReceiptId']),
      couponHistoryId: _positiveId(json['couponHistoryId']),
      deliveredAt: json['deliveredAt'],
    );
  }
}

/// 合规触达任务。快照 `shapeCampaign` —— 字段宽松解析(与导出任务的
/// 白名单不同:那是「读不懂就别显示」,这里服务端只会给这些态)。
class CrmCampaignTask {
  const CrmCampaignTask({
    this.id,
    this.status = '',
    this.title = '',
    this.channel = '',
    this.recipientCount = 0,
    this.deliveredCount = 0,
    this.noConsentCount = 0,
    this.frequencySkippedCount = 0,
    this.failedCount = 0,
    this.retryableCount = 0,
    this.recipients = const <CrmCampaignRecipient>[],
  });

  final int? id;

  /// READY / SENDING / SUCCESS / PARTIAL_FAILED / NO_ELIGIBLE / FAILED。
  final String status;
  final String title;
  final String channel;
  final int recipientCount;
  final int deliveredCount;
  final int noConsentCount;
  final int frequencySkippedCount;
  final int failedCount;
  final int retryableCount;
  final List<CrmCampaignRecipient> recipients;

  /// 结果区标题。快照 wxml `cu-campaign-result-title`。
  String get statusText => switch (status) {
    'SUCCESS' => '发送成功',
    'PARTIAL_FAILED' => '部分完成',
    'NO_ELIGIBLE' => '暂无可触达人群',
    _ => '处理中',
  };

  bool get isPartialFailed => status == 'PARTIAL_FAILED';

  /// 历史列表的显示名:没标题就用渠道兜底。
  String get listTitle => title.trim().isNotEmpty
      ? title.trim()
      : (channel == 'COUPON' ? '优惠券触达' : '站内消息触达');

  static CrmCampaignTask? tryParse(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final Map<String, dynamic> json = value;
    final Object? rawRecipients = json['recipients'];
    final List<CrmCampaignRecipient> recipients = rawRecipients is List
        ? rawRecipients
              .whereType<Map<String, dynamic>>()
              .map(CrmCampaignRecipient.tryParse)
              .whereType<CrmCampaignRecipient>()
              .toList(growable: false)
        : const <CrmCampaignRecipient>[];
    return CrmCampaignTask(
      id: _positiveId(json['id']),
      status: _textValue(json['status']),
      title: _textValue(json['title']),
      channel: _textValue(json['channel']),
      recipientCount: _count(json['recipientCount']),
      deliveredCount: _count(json['deliveredCount']),
      noConsentCount: _count(json['noConsentCount']),
      frequencySkippedCount: _count(json['frequencySkippedCount']),
      failedCount: _count(json['failedCount']),
      retryableCount: _count(json['retryableCount']),
      recipients: recipients,
    );
  }
}

/// 定向广播的请求体。逐键对齐快照 `_castPayload()`(index.js:806-823)——
/// 与客户名册同源的筛选 + 服务端认识的范围收窄(选中的队伍名/角色中文名)。
class CrmBroadcastPayload {
  const CrmBroadcastPayload({
    required this.keyword,
    required this.segment,
    this.tagId,
    this.sourceType,
    this.sourceStart,
    this.sourceEnd,
    required this.scope,
    this.groups = const <String>[],
  });

  final String keyword;
  final String segment;
  final int? tagId;
  final int? sourceType;
  final String? sourceStart;
  final String? sourceEnd;

  /// `ALL` / `TEAM` / `ROLE`(快照把三档中文 tab 折成这三个值)。
  final String scope;

  /// 选中的队伍名 / 角色名。scope 为 ALL 时服务端不收这个字段。
  final List<String> groups;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'keyword': keyword,
    'segment': segment,
    'tagId': tagId,
    'sourceType': sourceType,
    'sourceStart': sourceStart,
    'sourceEnd': sourceEnd,
    'scope': scope,
    'groups': scope == 'ALL' ? const <String>[] : groups,
  };
}

/// 服务端重算的触达预览。POST `/api/merchant/crm/broadcast/preview` 的 data。
///
/// ★★ 九个必填字段**全须是非负整数**,缺一个就整块 null ——
///   快照 `shapeBroadcastPreview` 的纪律:人数没算出来时报错,
///   绝不拿 0 冒充真值(那会让人以为「这批客户一个都收不到」)。
class CrmBroadcastPreview {
  const CrmBroadcastPreview({
    required this.audienceCount,
    required this.consentedCount,
    required this.noConsentCount,
    required this.frequencyLimitedCount,
    required this.deliverableCount,
    required this.recipientLimit,
    required this.merchantDailyLimit,
    required this.merchantDailyUsed,
    required this.merchantDailyRemaining,
    required this.filterTotalCount,
  });

  final int audienceCount;
  final int consentedCount;
  final int noConsentCount;
  final int frequencyLimitedCount;
  final int deliverableCount;
  final int recipientLimit;
  final int merchantDailyLimit;
  final int merchantDailyUsed;
  final int merchantDailyRemaining;

  /// 筛出的名单总数。快照缺省时**折成 audienceCount**(不是 0)。
  final int filterTotalCount;

  static const List<String> _requiredKeys = <String>[
    'audienceCount',
    'consentedCount',
    'noConsentCount',
    'frequencyLimitedCount',
    'deliverableCount',
    'recipientLimit',
    'merchantDailyLimit',
    'merchantDailyUsed',
    'merchantDailyRemaining',
  ];

  static CrmBroadcastPreview? tryParse(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    for (final String key in _requiredKeys) {
      if (!_nonNegInt(value[key])) return null;
    }
    final int audience = _intValue(value['audienceCount']);
    return CrmBroadcastPreview(
      audienceCount: audience,
      consentedCount: _intValue(value['consentedCount']),
      noConsentCount: _intValue(value['noConsentCount']),
      frequencyLimitedCount: _intValue(value['frequencyLimitedCount']),
      deliverableCount: _intValue(value['deliverableCount']),
      recipientLimit: _intValue(value['recipientLimit']),
      merchantDailyLimit: _intValue(value['merchantDailyLimit']),
      merchantDailyUsed: _intValue(value['merchantDailyUsed']),
      merchantDailyRemaining: _intValue(value['merchantDailyRemaining']),
      filterTotalCount: _nonNegInt(value['filterTotalCount'])
          ? _intValue(value['filterTotalCount'])
          : audience,
    );
  }
}

/// 每日本商家还能发几条(<=0 = 今天发满了)。快照 `sendCast` 的判据。
bool crmBroadcastDailyExhausted(CrmBroadcastPreview preview) =>
    preview.merchantDailyRemaining <= 0;

/// 预览口径文案。快照 `broadcastPreviewText` —— 只说服务端真值:
/// X=本次真会收到的人数,Y=未同意,Z=已同意但今日已收过。
String crmBroadcastPreviewText(CrmBroadcastPreview preview) {
  String text =
      '将发送给 ${preview.deliverableCount} 位已同意接收商家消息的客户，'
      '另有 ${preview.noConsentCount} 位未同意不会收到（站内消息）';
  if (preview.frequencyLimitedCount > 0) {
    text += '；另有 ${preview.frequencyLimitedCount} 位今日已收到过，不再重复发送';
  }
  if (preview.filterTotalCount > preview.audienceCount) {
    text += '。本次名单单次上限 ${preview.recipientLimit} 人';
  }
  return text;
}

/// 草稿期的人数估算。快照 `castEstimateText` —— 在点发送之前就说清
/// 「这是按当前筛选估的,真值以服务端重算为准」。
String crmCastEstimateText(int count) => '$count 人 · 点发送先核一遍可触达人数';

/// 发送回执。POST `/api/merchant/crm/broadcast` 的 data。
///
/// ★ 只认服务端留痕:id 必须是正整数,status 必须在这三档里,
///   六个人数必须齐 —— 否则整块 null(「发送结果异常，请重试并按结果核对」)。
class CrmBroadcastResult {
  const CrmBroadcastResult({
    required this.id,
    required this.status,
    required this.audienceCount,
    required this.consentedCount,
    required this.noConsentCount,
    required this.frequencySkippedCount,
    required this.deliveredCount,
    required this.failedCount,
  });

  final int id;

  /// SUCCESS / PARTIAL_FAILED / FAILED。
  final String status;
  final int audienceCount;
  final int consentedCount;
  final int noConsentCount;
  final int frequencySkippedCount;
  final int deliveredCount;
  final int failedCount;

  /// 结果标题。快照 wxml `cast-result-title` 的三档。
  String get statusText => switch (status) {
    'SUCCESS' => '已发送',
    'PARTIAL_FAILED' => '部分送达',
    _ => '未送达',
  };

  static const List<String> _countKeys = <String>[
    'audienceCount',
    'consentedCount',
    'noConsentCount',
    'frequencySkippedCount',
    'deliveredCount',
    'failedCount',
  ];

  static const List<String> _statuses = <String>[
    'SUCCESS',
    'PARTIAL_FAILED',
    'FAILED',
  ];

  static CrmBroadcastResult? tryParse(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final int? id = _positiveId(value['id']);
    final String status = _textValue(value['status']);
    if (id == null || !_statuses.contains(status)) return null;
    for (final String key in _countKeys) {
      if (!_nonNegInt(value[key])) return null;
    }
    return CrmBroadcastResult(
      id: id,
      status: status,
      audienceCount: _intValue(value['audienceCount']),
      consentedCount: _intValue(value['consentedCount']),
      noConsentCount: _intValue(value['noConsentCount']),
      frequencySkippedCount: _intValue(value['frequencySkippedCount']),
      deliveredCount: _intValue(value['deliveredCount']),
      failedCount: _intValue(value['failedCount']),
    );
  }
}

/// 触达的送达规则文案。快照 wxml:
/// `CONSENT_REQUIRED` → 「仅触达已同意客户」,其余 → 「规则待同步」。
String crmDeliveryStatusText(String status) =>
    status == 'CONSENT_REQUIRED' ? '仅触达已同意客户' : '规则待同步';

/// 幂等请求号。格式对齐快照 `createRequestId(kind)`:
/// `crm-<kind>-<36 进制时间>-<36 进制随机>`。**重试要复用同一个值。**
String newCrmRequestId(String kind) {
  final String stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final String rand = math.Random().nextInt(0xFFFFFF).toRadixString(36);
  return 'crm-$kind-$stamp-$rand';
}

// ---------------------------------------------------------------- 解析工具

/// 严格正整数 ID(快照 `strictPositiveSafeId`)。JSON 数字到 Dart 可能是
/// int 或 double,都收。
int? _strictId(Object? value) =>
    value is num && value.isFinite && value > 0 && value == value.floorToDouble()
    ? value.toInt()
    : null;

/// 宽松正整数(快照 `positiveSafeId`:先 Number() 再判)。
int? _positiveId(Object? value) {
  final num? n = value is num
      ? value
      : num.tryParse('${value ?? ''}'.trim());
  if (n == null || !n.isFinite || n <= 0) return null;
  return n.toInt();
}

bool _nullableString(Object? value) =>
    value == null || value is String;

String? _nullableText(Object? value) => value is String ? value : null;

bool _nonNegInt(Object? value) => _intValueOk(value);

bool _intValueOk(Object? value) =>
    value is num && value.isFinite && value >= 0 && value == value.floorToDouble();

int _intValue(Object? value) => _intValueOk(value) ? (value as num).toInt() : 0;

/// 快照 `finiteCount`:'' 和缺失都算「没给」,不合法也算「没给」。
int? _finiteCount(Object? value) {
  if (value == null || value == '') return null;
  final num? n = value is num ? value : num.tryParse('$value');
  if (n == null || !n.isFinite || n < 0) return null;
  return n.toInt();
}

/// 时间字段 → 可被 `relativeTime` 解析的字符串。
/// 数字按毫秒时间戳换算成 ISO(快照 `toTimestamp` 认数字时间戳)。
String? _dateText(Object? value) {
  if (value is num && value.isFinite) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt()).toIso8601String();
  }
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

/// 快照 `validDateValue`:数字(时间戳)或非空、可解析的字符串。
bool _validDateValue(Object? value) {
  if (value is num) return value.isFinite;
  if (value is String) {
    return value.trim().isNotEmpty && DateTime.tryParse(value) != null;
  }
  return false;
}

/// 数字字段:数字或数字串,缺省 [fallback]。
int _count(Object? value, {int fallback = 0}) {
  if (value is num && value.isFinite) return value.toInt();
  final num? n = num.tryParse('${value ?? ''}'.trim());
  return n != null && n.isFinite ? n.toInt() : fallback;
}

String _textValue(Object? value, {String fallback = ''}) {
  if (value is String) return value;
  if (value == null) return fallback;
  return '$value';
}
