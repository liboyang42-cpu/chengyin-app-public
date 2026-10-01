/// 俱乐部客户(按人聚合)与核销详情的模型层。
///
/// 契约真源:小程序 `pages/club/customers/view-model.js`(K1/K2 共用整形层)
/// 与 `ClubCrmAppServiceImpl`(K3 核销详情)。三条纪律照搬:
///   ① 手机号只认服务端渲染好的 `phoneText`,白名单整形,原始号码进不来;
///   ② `paidAmount` 为 null = 本岗位无金额查看权限,不是 0、不是加载失败;
///   ③ 缺字段 / 类型不对一律抛 [FormatException](fail-closed),前端不猜、不补。
library;

/// K1 客户名单页。
class ClubCustomerList {
  const ClubCustomerList({
    required this.total,
    required this.monthNew,
    required this.canEdit,
    required this.items,
  });

  final int total;
  final int monthNew;
  final bool canEdit;
  final List<ClubCustomerItem> items;

  /// 「N 位 · 本月新增 M」——数据统计行,随筛选变化,不是标题。
  String get countText => '$total 位 · 本月新增 $monthNew';

  factory ClubCustomerList.fromJson(Map<String, dynamic> json) {
    final Object? rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException('客户名单回执不完整');
    }
    final List<ClubCustomerItem> items = <ClubCustomerItem>[];
    for (final Object? row in rawItems) {
      if (row is! Map) throw const FormatException('客户名单回执不完整');
      items.add(ClubCustomerItem.fromJson(Map<String, dynamic>.from(row)));
    }
    return ClubCustomerList(
      total: _strictCount(json['total']),
      monthNew: _strictCount(json['monthNew']),
      canEdit: json['canEdit'] == true,
      items: items,
    );
  }
}

class ClubCustomerItem {
  const ClubCustomerItem({
    this.displaySource,
    required this.memberId,
    required this.displayName,
    required this.avatar,
    required this.hasRemark,
    required this.metaText,
    required this.subText,
  });

  final ClubCustomerItemDisplaySource? displaySource;

  final int memberId;
  final String displayName;
  final String avatar;
  final bool hasRemark;
  final String metaText;

  /// 第三行:备注优先,没有备注才退回服务端渲染好的手机号一行。
  final String subText;

  factory ClubCustomerItem.fromJson(Map<String, dynamic> json) {
    final int memberId = _strictPositiveId(json['memberId']);
    final int verifiedCount = _strictCount(json['verifiedCount']);
    final int pendingCount = _strictCount(json['pendingCount']);
    final String remark = _text(json['remark']);
    final String displayName = _text(json['displayName']);
    return ClubCustomerItem(
      displaySource: ClubCustomerItemDisplaySource(
        nameMissing: displayName.isEmpty,
        pendingCount: pendingCount,
        verifiedCount: verifiedCount,
        lastTopicName: _text(json['lastTopicName']),
        lastVisitDate: _text(json['lastVisitDate']),
      ),
      memberId: memberId,
      displayName: displayName.isEmpty ? '未留姓名' : displayName,
      avatar: _text(json['avatar']),
      hasRemark: remark.isNotEmpty,
      metaText: _listMetaText(
        pendingCount: pendingCount,
        verifiedCount: verifiedCount,
        lastTopicName: _text(json['lastTopicName']),
        lastVisitDate: _text(json['lastVisitDate']),
      ),
      subText: remark.isNotEmpty ? remark : _text(json['phoneText']),
    );
  }
}

/// K2 客户详情页。
class ClubCustomerDetail {
  const ClubCustomerDetail({
    required this.summary,
    required this.records,
    required this.tags,
    required this.remark,
    required this.canEdit,
  });

  final ClubCustomerSummary summary;
  final List<ClubCustomerRecord> records;
  final List<String> tags;
  final String remark;
  final bool canEdit;

  String get remarkText => remark.isEmpty ? '还没有备注' : '备注:$remark';

  /// 核对回包里的 memberId 与路由参数一致,拒收串号响应。
  factory ClubCustomerDetail.fromJson(
    Map<String, dynamic> json, {
    required int expectedMemberId,
  }) {
    final Object? rawSummary = json['summary'];
    final Object? rawRecords = json['records'];
    final Object? rawTags = json['tags'];
    if (rawSummary is! Map || rawRecords is! List || rawTags is! List) {
      throw const FormatException('客户详情回执不完整');
    }
    final String remark = _text(json['remark']);
    final ClubCustomerSummary summary = ClubCustomerSummary.fromJson(
      Map<String, dynamic>.from(rawSummary),
      remark: remark,
    );
    if (summary.memberId != expectedMemberId) {
      throw const FormatException('客户详情回执串号');
    }
    final List<ClubCustomerRecord> records = <ClubCustomerRecord>[];
    for (final Object? row in rawRecords) {
      if (row is! Map) throw const FormatException('客户详情回执不完整');
      records.add(
        ClubCustomerRecord.fromJson(Map<String, dynamic>.from(row)),
      );
    }
    final List<String> tags = <String>[];
    for (final Object? value in rawTags) {
      final String name = value is String
          ? value.trim()
          : (value is Map ? '${value['name'] ?? ''}'.trim() : '');
      if (name.isEmpty) throw const FormatException('客户详情回执不完整');
      if (!tags.contains(name)) tags.add(name);
    }
    return ClubCustomerDetail(
      summary: summary,
      records: records,
      tags: tags,
      remark: remark,
      canEdit: json['canEdit'] == true,
    );
  }
}

class ClubCustomerSummary {
  const ClubCustomerSummary({
    this.displaySource,
    required this.memberId,
    required this.displayName,
    required this.avatar,
    required this.phoneText,
    required this.lastInteractionText,
    required this.arrivedCount,
    required this.pendingCount,
    required this.refundedCount,
    required this.paidAmountText,
    required this.amountVisible,
  });

  final ClubCustomerSummaryDisplaySource? displaySource;

  final int memberId;
  final String displayName;
  final String avatar;

  /// 服务端渲染好的一行;前端不参与拼装、也拿不到原始号码。
  final String phoneText;
  final String lastInteractionText;
  final int arrivedCount;
  final int pendingCount;
  final int refundedCount;

  /// K2-B:没有财务权限时是「无查看权限」,不是 ¥0。
  final String paidAmountText;
  final bool amountVisible;

  factory ClubCustomerSummary.fromJson(
    Map<String, dynamic> json, {
    required String remark,
  }) {
    final int memberId = _strictPositiveId(json['memberId']);
    final int arrivedCount = _strictCount(json['arrivedCount']);
    final int pendingCount = _strictCount(json['pendingCount']);
    final int refundedCount = _strictCount(json['refundedCount']);
    final Object? rawAmount = json['paidAmount'];
    final double? amount = _strictMoney(rawAmount);
    if (rawAmount != null && rawAmount != '' && amount == null) {
      throw const FormatException('客户详情回执不完整');
    }
    final String displayName = _text(json['displayName']);
    return ClubCustomerSummary(
      displaySource: ClubCustomerSummaryDisplaySource(
        nameMissing: displayName.isEmpty,
        lastInteractionTime: _text(json['lastInteractionTime']),
        remark: remark,
      ),
      memberId: memberId,
      displayName: displayName.isEmpty ? '未留姓名' : displayName,
      avatar: _text(json['avatar']),
      phoneText: _text(json['phoneText']),
      lastInteractionText: _interactionText(
        _text(json['lastInteractionTime']),
        remark,
      ),
      arrivedCount: arrivedCount,
      pendingCount: pendingCount,
      refundedCount: refundedCount,
      paidAmountText: amount == null ? '无查看权限' : '¥${_trimMoney(amount)}',
      amountVisible: amount != null,
    );
  }
}

class ClubCustomerRecord {
  const ClubCustomerRecord({
    this.displaySource,
    required this.key,
    required this.topicId,
    required this.title,
    required this.dayText,
    required this.monthText,
    required this.statusLabel,
    required this.tone,
  });

  final ClubCustomerRecordDisplaySource? displaySource;

  final String key;
  final int? topicId;
  final String title;
  final String dayText;
  final String monthText;
  final String statusLabel;

  /// success / warning / danger / muted。
  final String tone;

  static const Map<String, String> _statusText = <String, String>{
    'VERIFIED': '已核销',
    'PENDING': '待核销',
    'CONTACTED': '已接洽',
    'REFUNDED': '已退款',
    'REGISTERED': '报名记录',
  };
  static const Map<String, String> _statusTone = <String, String>{
    'VERIFIED': 'success',
    'PENDING': 'warning',
    'CONTACTED': 'warning',
    'REFUNDED': 'danger',
    'REGISTERED': 'muted',
  };

  factory ClubCustomerRecord.fromJson(Map<String, dynamic> json) {
    final String key = _text(json['key']);
    final String statusCode = _text(json['statusCode']);
    final String? label = _statusText[statusCode];
    if (key.isEmpty || label == null) {
      throw const FormatException('客户详情回执不完整');
    }
    final Object? rawTopicId = json['topicId'];
    return ClubCustomerRecord(
      displaySource: ClubCustomerRecordDisplaySource(
        titleMissing: _text(json['title']).isEmpty,
        occurredAt: json['occurredAt'],
        statusCode: statusCode,
      ),
      key: key,
      topicId: _tryPositiveId(rawTopicId),
      title: _text(json['title']).isEmpty ? '未命名活动' : _text(json['title']),
      dayText: _dayOf(json['occurredAt']),
      monthText: _monthOf(json['occurredAt']),
      statusLabel: label,
      tone: _statusTone[statusCode] ?? 'muted',
    );
  }
}

/// Source facts retained solely for localized presentation; legacy/manual
/// models without provenance keep their original supplied display strings.
class ClubCustomerItemDisplaySource {
  const ClubCustomerItemDisplaySource({required this.nameMissing,
    required this.pendingCount, required this.verifiedCount,
    required this.lastTopicName, required this.lastVisitDate});
  final bool nameMissing;
  final int pendingCount;
  final int verifiedCount;
  final String lastTopicName;
  final String lastVisitDate;
}

class ClubCustomerSummaryDisplaySource {
  const ClubCustomerSummaryDisplaySource({required this.nameMissing,
    required this.lastInteractionTime, required this.remark});
  final bool nameMissing;
  final String lastInteractionTime;
  final String remark;
}

class ClubCustomerRecordDisplaySource {
  const ClubCustomerRecordDisplaySource({required this.titleMissing,
    required this.occurredAt, required this.statusCode});
  final bool titleMissing;
  final Object? occurredAt;
  final String statusCode;
}

/// K3 核销详情(俱乐部端)。
class ClubCheckinDetail {
  const ClubCheckinDetail({
    required this.registrationId,
    required this.displayName,
    required this.avatar,
    required this.phoneText,
    required this.phoneVisible,
    required this.sessionTimeText,
    required this.statusCode,
    required this.statusText,
    required this.statusTimeText,
    required this.topicName,
    required this.topicCover,
    required this.orderNo,
    required this.ticketText,
    required this.orderTimeText,
    required this.paidAmountText,
    required this.verifyTimeText,
    required this.storeName,
    required this.operatorName,
    required this.railStep,
    required this.canRefund,
  });

  final int registrationId;
  final String displayName;
  final String avatar;
  final String phoneText;
  final bool phoneVisible;
  final String sessionTimeText;
  final String statusCode;
  final String statusText;
  final String statusTimeText;
  final String topicName;
  final String topicCover;
  final String orderNo;
  final String ticketText;
  final String orderTimeText;
  final String paidAmountText;
  final String verifyTimeText;
  final String storeName;
  final String operatorName;

  /// 履约轨迹位置:已退款 = -1(整条不亮),其余走到哪亮到哪。
  final int railStep;
  final bool canRefund;

  static const List<({String key, String label, String tone})> rail = <({String key, String label, String tone})>[
    (key: 'signed', label: '已报名', tone: 'success'),
    (key: 'contacted', label: '已接洽', tone: 'warning'),
    (key: 'verified', label: '已核销', tone: 'success'),
    (key: 'reviewed', label: '已评价', tone: 'success'),
  ];

  List<ClubCheckinRailStep> buildRail() {
    return <ClubCheckinRailStep>[
      for (int i = 0; i < rail.length; i += 1)
        ClubCheckinRailStep(
          key: rail[i].key,
          label: rail[i].label,
          tone: railStep >= 0 && i <= railStep ? rail[i].tone : 'muted',
          current: i == railStep,
        ),
    ];
  }

  factory ClubCheckinDetail.fromJson(
    Map<String, dynamic> json, {
    required int expectedRegistrationId,
  }) {
    final int registrationId = _strictPositiveId(json['registrationId']);
    if (registrationId != expectedRegistrationId) {
      throw const FormatException('核销详情回执串号');
    }
    final String statusCode = _text(json['statusCode']);
    const Set<String> knownStatus = <String>{
      'REFUNDED',
      'REVIEWED',
      'VERIFIED',
      'CONTACTED',
      'PENDING',
    };
    final Object? rawRailStep = json['railStep'];
    final int? railStep = rawRailStep is num
        ? rawRailStep.toInt()
        : int.tryParse('${rawRailStep ?? ''}');
    if (!knownStatus.contains(statusCode) || railStep == null) {
      throw const FormatException('核销详情回执不完整');
    }
    return ClubCheckinDetail(
      registrationId: registrationId,
      displayName: _text(json['displayName']).isEmpty
          ? '未留姓名'
          : _text(json['displayName']),
      avatar: _text(json['avatar']),
      phoneText: _text(json['phoneText']),
      phoneVisible: json['phoneVisible'] == true,
      sessionTimeText: _text(json['sessionTimeText']),
      statusCode: statusCode,
      statusText: _text(json['statusText']),
      statusTimeText: _text(json['statusTimeText']),
      topicName: _text(json['topicName']),
      topicCover: _text(json['topicCover']),
      orderNo: _text(json['orderNo']),
      ticketText: _text(json['ticketText']),
      orderTimeText: _text(json['orderTimeText']),
      paidAmountText: _text(json['paidAmountText']),
      verifyTimeText: _text(json['verifyTimeText']),
      storeName: _text(json['storeName']),
      operatorName: _text(json['operatorName']),
      railStep: railStep,
      canRefund: json['canRefund'] == true,
    );
  }
}

class ClubCheckinRailStep {
  const ClubCheckinRailStep({
    required this.key,
    required this.label,
    required this.tone,
    required this.current,
  });

  final String key;
  final String label;
  final String tone;
  final bool current;
}

const int kClubTagMaxLength = 12;
const int kClubTagMaxCount = 8;
const int kClubRemarkMaxLength = 200;

/// 标签与备注的编辑草稿:白名单字段 + 长度越界当场拦下(不指望服务端兜底)。
({bool valid, String error, List<String> tags, String remark})
buildClubTagRemarkDraft(List<String> tagsValue, String remarkValue) {
  final String remark = remarkValue.trim();
  if (remark.length > kClubRemarkMaxLength) {
    return (
      valid: false,
      error: '备注最多 $kClubRemarkMaxLength 字',
      tags: const <String>[],
      remark: '',
    );
  }
  final List<String> tags = <String>[];
  for (final String value in tagsValue) {
    final String name = value.trim();
    if (name.isEmpty) continue;
    if (name.length > kClubTagMaxLength) {
      return (
        valid: false,
        error: '单个标签最多 $kClubTagMaxLength 字',
        tags: const <String>[],
        remark: '',
      );
    }
    if (!tags.contains(name)) tags.add(name);
  }
  if (tags.length > kClubTagMaxCount) {
    return (
      valid: false,
      error: '标签最多 $kClubTagMaxCount 个',
      tags: const <String>[],
      remark: '',
    );
  }
  return (valid: true, error: '', tags: tags, remark: remark);
}

// ---- 整形工具(照搬小程序 view-model.js 的口径) ----

String _listMetaText({
  required int pendingCount,
  required int verifiedCount,
  required String lastTopicName,
  required String lastVisitDate,
}) {
  if (pendingCount > 0) {
    final String head = '待核销 $pendingCount 张';
    return lastTopicName.isEmpty ? head : '$head · 最近参加「$lastTopicName」';
  }
  final String head = '核销 $verifiedCount 次';
  final String day = _monthDay(lastVisitDate);
  return day.isEmpty ? head : '$head · 最近 $day';
}

String _interactionText(String lastInteractionTime, String remark) {
  final String day = _chineseDay(lastInteractionTime);
  if (day.isEmpty) return '尚未发生互动';
  return remark.isEmpty ? '最近互动 $day' : '最近互动 $day · $remark';
}

String _text(Object? value) => value is String ? value.trim() : '';

int _strictPositiveId(Object? value) {
  final int? parsed = _strictInt(value);
  if (parsed == null || parsed <= 0) {
    throw const FormatException('回执标识不合法');
  }
  return parsed;
}

int? _tryPositiveId(Object? value) {
  final int? parsed = _strictInt(value);
  return parsed == null || parsed <= 0 ? null : parsed;
}

int _strictCount(Object? value) {
  final int? parsed = _strictInt(value);
  if (parsed == null || parsed < 0) {
    throw const FormatException('回执计数不合法');
  }
  return parsed;
}

int? _strictInt(Object? value) {
  if (value is num) {
    if (!value.isFinite || value != value.truncateToDouble()) return null;
    return value.toInt();
  }
  if (value is String) {
    final num? parsed = num.tryParse(value.trim());
    if (parsed == null || !parsed.isFinite) return null;
    if (parsed != parsed.truncateToDouble()) return null;
    return parsed.toInt();
  }
  return null;
}

double? _strictMoney(Object? value) {
  if (value == null || value == '') return null;
  final double? parsed = value is num
      ? value.toDouble()
      : double.tryParse('$value');
  if (parsed == null || !parsed.isFinite || parsed < 0) return null;
  return parsed;
}

String _trimMoney(double amount) {
  if (amount == amount.truncateToDouble()) return amount.toInt().toString();
  return amount.toStringAsFixed(2);
}

({String year, String month, String day})? _dateParts(Object? value) {
  final String source = '${value ?? ''}'.replaceFirst('T', ' ');
  final RegExpMatch? matched = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})',
  ).firstMatch(source);
  if (matched == null) return null;
  return (
    year: matched.group(1)!,
    month: matched.group(2)!,
    day: matched.group(3)!,
  );
}

String _monthDay(Object? value) {
  final parts = _dateParts(value);
  return parts == null ? '' : '${parts.month}-${parts.day}';
}

String _dayOf(Object? value) => _numberOf(_dateParts(value)?.day);

String _monthOf(Object? value) {
  final parts = _dateParts(value);
  return parts == null ? '' : '${_numberOf(parts.month)}月';
}

String _chineseDay(Object? value) {
  final parts = _dateParts(value);
  return parts == null ? '' : '${_numberOf(parts.month)}月${_numberOf(parts.day)}日';
}

String _numberOf(String? value) {
  if (value == null) return '';
  return (int.tryParse(value) ?? 0).toString();
}
