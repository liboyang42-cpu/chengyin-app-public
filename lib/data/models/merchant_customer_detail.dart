/// 商家 CRM 客户详情。
///
/// 详情必须与路由中的 [expectedCustomerMemberId] 一致，防止缓存、
/// 并发或后端越权响应把其他客户数据渲染到当前页。
class MerchantCustomerDetail {
  const MerchantCustomerDetail({
    required this.summary,
    required this.systemTags,
    required this.merchantTags,
    required this.timeline,
  });

  final MerchantCustomerSummary summary;
  final List<MerchantCustomerSystemTag> systemTags;
  final List<MerchantCustomerTag> merchantTags;
  final List<MerchantCustomerTimelineItem> timeline;

  factory MerchantCustomerDetail.fromJson(
    Map<String, dynamic> json, {
    required int expectedCustomerMemberId,
  }) {
    final Map<String, dynamic> summaryJson = _requiredMap(
      json['summary'],
      'summary',
    );
    final MerchantCustomerSummary summary = MerchantCustomerSummary.fromJson(
      summaryJson,
    );
    if (summary.customerMemberId != expectedCustomerMemberId) {
      throw const FormatException('客户详情与路由客户 ID 不一致');
    }
    return MerchantCustomerDetail(
      summary: summary,
      systemTags: _requiredList(json['systemTags'], 'systemTags')
          .map(
            (dynamic value) => MerchantCustomerSystemTag.fromJson(
              _requiredMap(value, 'systemTags item'),
            ),
          )
          .toList(growable: false),
      merchantTags: _requiredList(json['merchantTags'], 'merchantTags')
          .map(
            (dynamic value) => MerchantCustomerTag.fromJson(
              _requiredMap(value, 'merchantTags item'),
            ),
          )
          .toList(growable: false),
      timeline: _requiredList(json['timeline'], 'timeline')
          .map(
            (dynamic value) => MerchantCustomerTimelineItem.fromJson(
              _requiredMap(value, 'timeline item'),
            ),
          )
          .toList(growable: false),
    );
  }
}

class MerchantCustomerSummary {
  const MerchantCustomerSummary({
    required this.customerMemberId,
    required this.displayName,
    this.hasNameFallback = false,
    required this.avatar,
    required this.arrivedCount,
    required this.pendingCount,
    required this.refundedCount,
    required this.paidAmount,
    required this.lastInteractionTime,
  });

  final int customerMemberId;
  final String displayName;
  final bool hasNameFallback;
  final String? avatar;
  final int arrivedCount;
  final int pendingCount;
  final int refundedCount;

  /// `null` 表示后端因 `merchant:crm:sensitive:read` 权限未下发。
  /// 它不是 0，也不是“尚未消费”。
  final double? paidAmount;
  final DateTime? lastInteractionTime;

  String get paidAmountText =>
      paidAmount == null ? '无查看权限' : '¥${paidAmount!.toStringAsFixed(2)}';

  String get lastInteractionTimeText => _formatTime(lastInteractionTime);

  factory MerchantCustomerSummary.fromJson(Map<String, dynamic> json) {
    final String name = _text(json['displayName']);
    final String avatar = _text(json['avatar']);
    return MerchantCustomerSummary(
      customerMemberId: _positiveInt(
        json['customerMemberId'],
        'summary.customerMemberId',
      ),
      displayName: name.isEmpty ? '未留姓名' : name,
      hasNameFallback: name.isEmpty,
      avatar: avatar.isEmpty ? null : avatar,
      arrivedCount: _nonNegativeInt(
        json['arrivedCount'],
        'summary.arrivedCount',
      ),
      pendingCount: _nonNegativeInt(
        json['pendingCount'],
        'summary.pendingCount',
      ),
      refundedCount: _nonNegativeInt(
        json['refundedCount'],
        'summary.refundedCount',
      ),
      paidAmount: _nullableMoney(json['paidAmount']),
      lastInteractionTime: _nullableTime(json['lastInteractionTime']),
    );
  }
}

class MerchantCustomerSystemTag {
  const MerchantCustomerSystemTag({required this.code, required this.label});

  static const Set<String> supportedCodes = <String>{
    'ARRIVED',
    'REPEAT',
    'PENDING',
    'REFUNDED',
  };

  final String code;
  final String label;

  factory MerchantCustomerSystemTag.fromJson(Map<String, dynamic> json) {
    final String code = _text(json['code']);
    final String label = _text(json['label']);
    if (!supportedCodes.contains(code) || label.isEmpty) {
      throw const FormatException('系统标签数据无效');
    }
    return MerchantCustomerSystemTag(code: code, label: label);
  }
}

class MerchantCustomerTag {
  const MerchantCustomerTag({
    required this.id,
    required this.tagName,
    required this.tagColor,
  });

  final int id;
  final String tagName;
  final String tagColor;

  factory MerchantCustomerTag.fromJson(Map<String, dynamic> json) {
    final String tagName = _text(json['tagName']);
    final String tagColor = _text(json['tagColor']).toUpperCase();
    if (tagName.isEmpty || !_hexColor.hasMatch(tagColor)) {
      throw const FormatException('店内标签数据无效');
    }
    return MerchantCustomerTag(
      id: _positiveInt(json['id'], 'merchantTags.id'),
      tagName: tagName,
      tagColor: tagColor,
    );
  }
}

class MerchantCustomerTimelineItem {
  const MerchantCustomerTimelineItem({
    required this.key,
    required this.type,
    required this.title,
    required this.description,
    required this.occurredAt,
    required this.noteId,
    required this.noteVersion,
    required this.correctsNoteId,
  });

  static const Map<String, String> typeTexts = <String, String>{
    'NOTE': '跟进',
    'NOTE_CORRECTION': '更正',
    'ARRIVED': '到店',
    'REFUNDED': '退款',
    'REGISTERED': '报名',
    'CAMPAIGN': '触达',
  };

  final String key;
  final String type;
  final String title;
  final String description;
  final DateTime? occurredAt;
  final int? noteId;
  final int? noteVersion;
  final int? correctsNoteId;

  String get typeText => typeTexts[type]!;
  String get occurredAtText => _formatTime(occurredAt);
  bool get canManageNote =>
      (type == 'NOTE' || type == 'NOTE_CORRECTION') &&
      noteId != null &&
      noteVersion != null;

  factory MerchantCustomerTimelineItem.fromJson(Map<String, dynamic> json) {
    final String key = _text(json['key']);
    final String type = _text(json['type']);
    if (key.isEmpty || !typeTexts.containsKey(type)) {
      throw const FormatException('客户时间线数据无效');
    }
    final String title = _text(json['title']);
    return MerchantCustomerTimelineItem(
      key: key,
      type: type,
      title: title.isEmpty ? typeTexts[type]! : title,
      description: _text(json['description']),
      occurredAt: _nullableTime(json['occurredAt']),
      noteId: _nullablePositiveInt(json['noteId']),
      noteVersion: _nullableNonNegativeInt(json['noteVersion']),
      correctsNoteId: _nullablePositiveInt(json['correctsNoteId']),
    );
  }
}

final RegExp _hexColor = RegExp(r'^#[0-9A-F]{6}$');

Map<String, dynamic> _requiredMap(dynamic value, String field) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('$field 不完整');
}

List<dynamic> _requiredList(dynamic value, String field) {
  if (value is List<dynamic>) return value;
  throw FormatException('$field 不完整');
}

String _text(dynamic value) => value is String ? value.trim() : '';

int _positiveInt(dynamic value, String field) {
  final int? parsed = value is int
      ? value
      : int.tryParse(value?.toString() ?? '');
  if (parsed == null || parsed <= 0) throw FormatException('$field 无效');
  return parsed;
}

int? _nullablePositiveInt(dynamic value) {
  if (value == null || value == '') return null;
  final int? parsed = value is int ? value : int.tryParse(value.toString());
  return parsed != null && parsed > 0 ? parsed : null;
}

int _nonNegativeInt(dynamic value, String field) {
  final int? parsed = value is int
      ? value
      : int.tryParse(value?.toString() ?? '');
  if (parsed == null || parsed < 0) throw FormatException('$field 无效');
  return parsed;
}

int? _nullableNonNegativeInt(dynamic value) {
  if (value == null || value == '') return null;
  final int? parsed = value is int ? value : int.tryParse(value.toString());
  return parsed != null && parsed >= 0 ? parsed : null;
}

double? _nullableMoney(dynamic value) {
  if (value == null || value == '') return null;
  final double? parsed = value is num
      ? value.toDouble()
      : double.tryParse(value.toString());
  if (parsed == null || !parsed.isFinite || parsed < 0) {
    throw const FormatException('summary.paidAmount 无效');
  }
  return parsed;
}

DateTime? _nullableTime(dynamic value) {
  final String raw = _text(value);
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw.replaceFirst(' ', 'T'))?.toLocal();
}

String _formatTime(DateTime? value) {
  if (value == null) return '';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
