import 'dart:convert';

/// 据点详情里联查的商家公开信息。对齐 `/api/merchant/public-detail` 的
/// 脱敏返回:MmsMerchant 实体去掉隐私/内部字段 + sysCategoryList。
class RoamMerchantInfo {
  const RoamMerchantInfo({
    this.id,
    this.memberId,
    this.name,
    this.logo,
    this.coverImage,
    this.cityRole,
    this.storyTitle,
    this.description,
    this.gallery = const <String>[],
    this.tags = const <String>[],
    this.businessStatus,
    this.address,
    this.chargeType,
    this.categories = const <String>[],
    this.capacity,
    this.availableTime,
    this.suitActivityTypes,
    this.demand,
    this.businessTime,
    this.latitude,
    this.longitude,
  });

  final int? id;
  final int? memberId;
  final String? name;
  final String? logo;
  final String? coverImage;
  final String? cityRole;
  final String? storyTitle;
  final String? description;

  /// gallery/tags 落库是 JSON 字符串;坏 JSON 按空数组兜底
  /// (与小程序 try/catch → [] 一致,拿字符串没有其它恢复手段)。
  final List<String> gallery;
  final List<String> tags;

  /// 0 已打烊 / 非 0 营业中(对齐小程序同名判断)。
  final int? businessStatus;
  final String? address;

  /// 1 收费承接 / 其余免费承接。
  final int? chargeType;

  /// 品类名列表(来自 sysCategoryList[].categoryName)。
  final List<String> categories;
  final int? capacity;
  final String? availableTime;
  final String? suitActivityTypes;
  final String? demand;
  final String? businessTime;
  final double? latitude;
  final double? longitude;

  bool get isOpen => businessStatus != 0;

  String get chargeText => chargeType == 1 ? '收费承接' : '免费承接';

  String get catNames => categories.join(' · ');

  factory RoamMerchantInfo.fromJson(Map<String, dynamic> json) {
    return RoamMerchantInfo(
      id: (json['id'] as num?)?.toInt(),
      memberId: (json['memberId'] as num?)?.toInt(),
      name: json['name'] as String?,
      logo: json['logo'] as String?,
      coverImage: json['coverImage'] as String?,
      cityRole: json['cityRole'] as String?,
      storyTitle: json['storyTitle'] as String?,
      description: json['description'] as String?,
      gallery: parseStringList(json['gallery']),
      tags: parseStringList(json['tags']),
      businessStatus: (json['businessStatus'] as num?)?.toInt(),
      address: json['address'] as String?,
      chargeType: (json['chargeType'] as num?)?.toInt(),
      categories:
          ((json['sysCategoryList'] as List<dynamic>?) ?? const <dynamic>[])
              .whereType<Map>()
              .map((dynamic c) => (c['categoryName'] as String?) ?? '')
              .where((String n) => n.isNotEmpty)
              .toList(),
      capacity: _asInt(json['capacity']),
      availableTime: json['availableTime'] as String?,
      suitActivityTypes: json['suitActivityTypes'] as String?,
      demand: json['demand'] as String?,
      businessTime: json['businessTime'] as String?,
      latitude: _asDouble(json['latitude']),
      longitude: _asDouble(json['longitude']),
    );
  }

  static int? _asInt(Object? raw) {
    if (raw is num) return raw.toInt();
    return raw is String ? int.tryParse(raw.trim()) : null;
  }

  static double? _asDouble(Object? raw) {
    if (raw is num) return raw.toDouble();
    return raw is String ? double.tryParse(raw.trim()) : null;
  }

  /// 既可能是 JSON 数组字符串,也可能是已解析的数组;坏数据一律空数组。
  static List<String> parseStringList(Object? raw) {
    if (raw is List) return raw.whereType<String>().toList();
    if (raw is String && raw.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is List) return decoded.whereType<String>().toList();
      } catch (_) {}
    }
    return <String>[];
  }
}

/// 招牌主推(public-detail 顶层 featured 兄弟键)。
/// 源 scene-roam-poi-detail/index.js:181-186/427-430:
/// featuredType 1=店内活动(featuredId=活动ID,跳活动详情)、2=券(跳券包);
/// 类型缺失/未知时 actionable 为 false —— 卡片只展示,不猜落点。
class RoamFeatured {
  const RoamFeatured({
    this.name = '',
    this.image = '',
    this.featuredType,
    this.featuredId,
  });

  final String name;
  final String image;
  final int? featuredType;
  final int? featuredId;

  factory RoamFeatured.fromJson(Map<String, dynamic> json) {
    final Object? rawType = json['featuredType'];
    final Object? rawId = json['featuredId'];
    return RoamFeatured(
      name: ((json['name'] ?? json['title'] ?? '') as String).trim(),
      image:
          ((json['imgUrl'] ?? json['coverImg'] ?? json['img'] ?? '') as String)
              .trim(),
      // 源判据是 `typeof === 'number'`:字符串类型号一律按缺失处理。
      featuredType: rawType is num ? rawType.toInt() : null,
      featuredId: rawId is num
          ? rawId.toInt()
          : int.tryParse('${rawId ?? ''}'.trim()),
    );
  }

  bool get isUsable => name.isNotEmpty;

  /// 源 actionable:(type==1 且 featuredId 真值) 或 type==2。
  bool get actionable =>
      (featuredType == 1 && featuredId != null && featuredId != 0) ||
      featuredType == 2;
}
