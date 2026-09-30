/// 商家 AI 店铺参谋。对齐 `POST /api/ai/merchant/insight`。
///
/// 整体分两层：[facts] 是必出的 SQL 聚合事实，[ai] 可以独立降级。
class MerchantInsight {
  const MerchantInsight({
    required this.facts,
    this.ai,
    this.aiError = '',
    this.generatedAt = '',
    this.recommendedTopics = const <MerchantInsightTopic>[],
    this.recommendedPartners = const <MerchantInsightPartner>[],
  });

  final MerchantInsightFacts facts;
  final MerchantInsightAi? ai;
  final String aiError;
  final String generatedAt;

  /// 后端下发的**真实招商中**主题(不是 AI 编的)。
  final List<MerchantInsightTopic> recommendedTopics;

  /// 后端下发的**真实附近**商家。
  final List<MerchantInsightPartner> recommendedPartners;

  factory MerchantInsight.fromJson(Map<String, dynamic> json) {
    final Object? factsRaw = json['facts'];
    if (factsRaw is! Map<String, dynamic>) {
      throw const FormatException('facts is required');
    }
    final Object? aiRaw = json['ai'];
    return MerchantInsight(
      facts: MerchantInsightFacts.fromJson(factsRaw),
      ai: aiRaw is Map<String, dynamic>
          ? MerchantInsightAi.fromJson(aiRaw)
          : null,
      aiError: _string(json['aiError']),
      generatedAt: _string(json['generatedAt']),
      recommendedTopics:
          (json['recommendedTopics'] is List
                  ? json['recommendedTopics'] as List<dynamic>
                  : const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(MerchantInsightTopic.fromJson)
              .toList(growable: false),
      recommendedPartners:
          (json['recommendedPartners'] is List
                  ? json['recommendedPartners'] as List<dynamic>
                  : const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(MerchantInsightPartner.fromJson)
              .toList(growable: false),
    );
  }
}

/// 推荐主题:后端下发的真实招商中主题,点进去是合作中心申请承接。
class MerchantInsightTopic {
  const MerchantInsightTopic({
    this.topicId = 0,
    this.name = '',
    this.coverUrl = '',
    this.reason = '',
  });

  final int topicId;
  final String name;
  final String coverUrl;

  /// 为什么推给你。AI 挂了时后端不给理由,界面用兜底文案。
  final String reason;

  factory MerchantInsightTopic.fromJson(Map<String, dynamic> json) {
    return MerchantInsightTopic(
      topicId: _int(json['topicId']),
      name: _string(json['name']),
      coverUrl: _string(json['coverUrl']),
      reason: _string(json['reason']),
    );
  }
}

/// 推荐联动商家。★ 主体 ID 是 **memberId**(canonical 商家主页),
///   不是商家档案主键 —— 拿错会把用户送到别人的主页。
class MerchantInsightPartner {
  const MerchantInsightPartner({
    this.memberId = 0,
    this.name = '',
    this.coverImage = '',
    this.logo = '',
    this.cityRole = '',
    this.slogan = '',
    this.category = '',
    this.distanceM = 0,
    this.tags = '',
    this.reason = '',
    this.businessStatus = 0,
  });

  final int memberId;
  final String name;
  final String coverImage;
  final String logo;
  final String cityRole;
  final String slogan;
  final String category;

  /// 距离(米)。≤0 表示后端没给,界面不显示距离 —— 不兜一个假的。
  final int distanceM;
  final String tags;
  final String reason;
  final int businessStatus;

  /// 0 已打烊 / 1 营业中(与小程序同一判据);
  /// 缺席时按「0」处理 —— 商家域惯例:不知道就不宣称在营业。
  bool get isOpen => businessStatus == 1;

  /// 距离文案与小程序同一口径:不到 1km 说米,否则一位小数的公里。
  String get distanceText {
    if (distanceM <= 0) return '';
    if (distanceM < 1000) return '${distanceM}m';
    final double km = (distanceM / 100).round() / 10;
    return km % 1 == 0 ? '${km.toInt()}km' : '${km}km';
  }

  /// 后端 tags 是**逗号/顿号分隔串**,不是数组;定稿最多摆 3 枚 chip。
  ///
  /// ⚠️ 分隔符写成 unicode 转义是有意的:全角逗号/顿号直接落在源码里,
  ///   经过某些编辑链路会被规范化成半角,表现是「用全角分隔的标签切不开」
  ///   (2026-08-20 在 merchant_discover_page 踩过)。
  List<String> get tagsArr => tags
      .split(RegExp('[,;\u{FF0C}\u{FF1B}\u{3001}\\s]+'))
      .where((String t) => t.isNotEmpty)
      .take(3)
      .toList(growable: false);

  factory MerchantInsightPartner.fromJson(Map<String, dynamic> json) {
    return MerchantInsightPartner(
      memberId: _int(json['memberId']),
      name: _string(json['name']),
      coverImage: _string(json['coverImage']),
      logo: _string(json['logo']),
      cityRole: _string(json['cityRole']),
      slogan: _string(json['slogan']),
      category: _string(json['category']),
      distanceM: _int(json['distanceM']),
      tags: _string(json['tags']),
      reason: _string(json['reason']),
      businessStatus: _int(json['businessStatus']),
    );
  }
}

class MerchantInsightFacts {
  const MerchantInsightFacts({
    this.window = '',
    this.sampleMembers = 0,
    this.lowSample = false,
    required this.checkin,
    required this.crowd,
    required this.supply,
  });

  final String window;
  final int sampleMembers;
  final bool lowSample;
  final MerchantInsightCheckin checkin;
  final MerchantInsightCrowd crowd;
  final MerchantInsightSupply supply;

  factory MerchantInsightFacts.fromJson(Map<String, dynamic> json) {
    return MerchantInsightFacts(
      window: _string(json['window']),
      sampleMembers: _int(json['sampleMembers']),
      lowSample: json['lowSample'] == true,
      checkin: MerchantInsightCheckin.fromJson(_map(json['checkin'])),
      crowd: MerchantInsightCrowd.fromJson(_map(json['crowd'])),
      supply: MerchantInsightSupply.fromJson(_map(json['supply'])),
    );
  }
}

class MerchantInsightCheckin {
  const MerchantInsightCheckin({
    this.total = 0,
    this.redeemRate,
    this.repeatRate,
    this.avgWaitMinutes,
    this.hourBuckets = const <MerchantInsightHourBucket>[],
  });

  final int total;
  final double? redeemRate;
  final double? repeatRate;
  final int? avgWaitMinutes;
  final List<MerchantInsightHourBucket> hourBuckets;

  String get redeemRateText => merchantInsightPercent(redeemRate);
  String get repeatRateText => merchantInsightPercent(repeatRate);
  int get segmentFillCount => merchantInsightSegmentFill(redeemRate);
  int get repeatSegmentFillCount => merchantInsightSegmentFill(repeatRate);

  factory MerchantInsightCheckin.fromJson(Map<String, dynamic> json) {
    final Object? rawBuckets = json['hourBuckets'];
    return MerchantInsightCheckin(
      total: _int(json['total']),
      redeemRate: _nullableDouble(json['redeemRate']),
      repeatRate: _nullableDouble(json['repeatRate']),
      avgWaitMinutes: _nullableInt(json['avgWaitMinutes']),
      hourBuckets: (rawBuckets is List ? rawBuckets : const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(MerchantInsightHourBucket.fromJson)
          .toList(growable: false),
    );
  }
}

class MerchantInsightHourBucket {
  const MerchantInsightHourBucket({required this.hour, required this.count});

  final int hour;
  final int count;

  factory MerchantInsightHourBucket.fromJson(Map<String, dynamic> json) {
    return MerchantInsightHourBucket(
      hour: _int(json['hour']),
      count: _int(json['count']),
    );
  }
}

class MerchantInsightCrowd {
  const MerchantInsightCrowd({
    this.members = 0,
    this.maleRate,
    this.femaleRate,
    this.interestTop = const <String>[],
  });

  final int members;
  final double? maleRate;
  final double? femaleRate;
  final List<String> interestTop;

  String get sexText {
    if (maleRate == null && femaleRate == null) return '';
    return '男 ${merchantInsightPercent(maleRate)} · '
        '女 ${merchantInsightPercent(femaleRate)}';
  }

  factory MerchantInsightCrowd.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> sex = _map(json['sexRatio']);
    final Object? interests = json['interestTop'];
    return MerchantInsightCrowd(
      members: _int(json['members']),
      maleRate: _nullableDouble(sex['male']),
      femaleRate: _nullableDouble(sex['female']),
      interestTop: (interests is List ? interests : const <dynamic>[])
          .map(_string)
          .where((String value) => value.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class MerchantInsightSupply {
  const MerchantInsightSupply({this.activeOffers = 0, this.quotaUsedRate});

  final int activeOffers;
  final double? quotaUsedRate;

  String get quotaUsedRateText => merchantInsightPercent(quotaUsedRate);
  int get segmentFillCount => merchantInsightSegmentFill(quotaUsedRate);

  factory MerchantInsightSupply.fromJson(Map<String, dynamic> json) {
    return MerchantInsightSupply(
      activeOffers: _int(json['activeOffers']),
      quotaUsedRate: _nullableDouble(json['quotaUsedRate']),
    );
  }
}

class MerchantInsightAi {
  const MerchantInsightAi({
    this.summary = '',
    this.audiences = const <MerchantInsightAudience>[],
    this.suggestions = const <MerchantInsightSuggestion>[],
  });

  final String summary;
  final List<MerchantInsightAudience> audiences;
  final List<MerchantInsightSuggestion> suggestions;

  factory MerchantInsightAi.fromJson(Map<String, dynamic> json) {
    final Object? audiencesRaw = json['audiences'];
    final Object? suggestionsRaw = json['suggestions'];
    return MerchantInsightAi(
      summary: _string(json['summary']),
      audiences: (audiencesRaw is List ? audiencesRaw : const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(MerchantInsightAudience.fromJson)
          .toList(growable: false),
      suggestions: (suggestionsRaw is List ? suggestionsRaw : const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(MerchantInsightSuggestion.fromJson)
          .toList(growable: false),
    );
  }
}

class MerchantInsightAudience {
  const MerchantInsightAudience({this.label = '', this.reason = ''});

  final String label;
  final String reason;

  factory MerchantInsightAudience.fromJson(Map<String, dynamic> json) {
    return MerchantInsightAudience(
      label: _string(json['label']),
      reason: _string(json['reason']),
    );
  }
}

class MerchantInsightSuggestion {
  const MerchantInsightSuggestion({
    this.title = '',
    this.type = '',
    this.timeSlot = '',
    this.audience = '',
    this.reason = '',
  });

  final String title;
  final String type;
  final String timeSlot;
  final String audience;
  final String reason;

  String? get routePath => routeFor(type);

  /// 路由只由客户端白名单决定，不使用模型下发的任意路径。
  static String? routeFor(String type) => switch (type) {
    'topic_coop' => '/merchant/coop',
    'decor' => '/merchant/decor',
    'content' => '/publish/pro',
    _ => null,
  };

  factory MerchantInsightSuggestion.fromJson(Map<String, dynamic> json) {
    return MerchantInsightSuggestion(
      title: _string(json['title']),
      type: _string(json['type']),
      timeSlot: _string(json['timeSlot']),
      audience: _string(json['audience']),
      reason: _string(json['reason']),
    );
  }
}

String merchantInsightPercent(double? value) =>
    value == null ? '—' : '${(value * 100).round()}%';

int merchantInsightSegmentFill(double? value) =>
    value == null ? 0 : (value * 10).round().clamp(0, 10);

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : <String, dynamic>{};

String _string(Object? value) => value?.toString() ?? '';

int _int(Object? value) => _nullableInt(value) ?? 0;

int? _nullableInt(Object? value) => value is num
    ? value.toInt()
    : value == null
    ? null
    : int.tryParse(value.toString());

double? _nullableDouble(Object? value) => value is num
    ? value.toDouble()
    : value == null
    ? null
    : double.tryParse(value.toString());
