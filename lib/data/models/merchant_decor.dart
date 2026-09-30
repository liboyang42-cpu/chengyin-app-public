import 'dart:convert';

/// 店铺装修。对齐后端 `ApiMerchantController.saveDecor`(/api/merchant/decor/save)。
///
/// ⚠️ 后端会跑**内容安全审核**(secMsg),命中违规直接拒 —— 与个人资料同一条:
///   内容被拒时**重试没用**,要改文字。
class MerchantDecor {
  const MerchantDecor({
    this.coverImage,
    this.slogan,
    this.cityRole,
    this.storyTitle,
    this.gallery = const <String>[],
    this.tags = const <String>[],
    this.categoryId,
    this.featuredType,
    this.featuredId,
    this.serviceTag,
    this.serviceText,
    this.locationLat,
    this.locationLng,
    this.locationVerified,
  });

  final String? coverImage;
  final String? slogan;

  /// 在城市里的角色定位(自由文本)。
  final String? cityRole;
  final String? storyTitle;

  /// 相册。新数据存 JSON 数组字符串，读取兼容历史分号格式。
  final List<String> gallery;

  /// 标签。新数据存 JSON 数组字符串，读取兼容历史分号格式。
  final List<String> tags;

  /// 精选内容:类型 + id。★ 两者是一对,**只给一个是无效状态** ——
  ///   后端会存下一条指向空的精选,首页展示时是个空位。
  final int? categoryId;
  final int? featuredType;
  final int? featuredId;
  final String? serviceTag;
  final String? serviceText;
  final double? locationLat;
  final double? locationLng;
  final int? locationVerified;

  bool get featuredConsistent {
    final hasType = featuredType != null && featuredType! > 0;
    final hasId = featuredId != null && featuredId! > 0;
    return hasType == hasId; // 要么都有,要么都没有
  }

  /// 有没有填过任何东西。★ 全空时**不该提交** ——
  ///   一次空提交会白白触发一次内容安全审核。
  bool get hasAnything =>
      (coverImage ?? '').isNotEmpty ||
      (slogan ?? '').trim().isNotEmpty ||
      (cityRole ?? '').trim().isNotEmpty ||
      (storyTitle ?? '').trim().isNotEmpty ||
      gallery.isNotEmpty ||
      tags.isNotEmpty;

  String? get blocker {
    if (!hasAnything) return '至少填一项再保存';
    if (!featuredConsistent) return '精选内容没选完整';
    return null;
  }

  MerchantDecor copyWith({
    String? coverImage,
    String? slogan,
    String? cityRole,
    String? storyTitle,
    List<String>? gallery,
    List<String>? tags,
    int? categoryId,
    int? featuredType,
    int? featuredId,
    String? serviceTag,
    String? serviceText,
    double? locationLat,
    double? locationLng,
    int? locationVerified,
  }) {
    return MerchantDecor(
      coverImage: coverImage ?? this.coverImage,
      slogan: slogan ?? this.slogan,
      cityRole: cityRole ?? this.cityRole,
      storyTitle: storyTitle ?? this.storyTitle,
      gallery: gallery ?? this.gallery,
      tags: tags ?? this.tags,
      categoryId: categoryId ?? this.categoryId,
      featuredType: featuredType ?? this.featuredType,
      featuredId: featuredId ?? this.featuredId,
      serviceTag: serviceTag ?? this.serviceTag,
      serviceText: serviceText ?? this.serviceText,
      locationLat: locationLat ?? this.locationLat,
      locationLng: locationLng ?? this.locationLng,
      locationVerified: locationVerified ?? this.locationVerified,
    );
  }

  /// 清掉精选。★ 与广场发帖的 withoutLink 同理:
  ///   copyWith 把 null 当"不改",清不掉 —— 必须专门给一个方法。
  MerchantDecor withoutFeatured() => MerchantDecor(
    coverImage: coverImage,
    slogan: slogan,
    cityRole: cityRole,
    storyTitle: storyTitle,
    gallery: gallery,
    tags: tags,
    categoryId: categoryId,
    featuredType: null,
    featuredId: null,
    serviceTag: serviceTag,
    serviceText: serviceText,
    locationLat: locationLat,
    locationLng: locationLng,
    locationVerified: locationVerified,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'coverImage': coverImage,
    'slogan': slogan?.trim(),
    'cityRole': cityRole?.trim(),
    'storyTitle': storyTitle?.trim(),
    // 空列表发空串而不是 null —— 后端按字段覆盖,发 null 会被当"不改",
    // 用户删光相册就删不掉了。
    'gallery': jsonEncode(gallery),
    'tags': jsonEncode(tags),
    'categoryId': categoryId,
    'featuredType': featuredType,
    'featuredId': featuredId,
    'serviceTag': serviceTag?.trim(),
    'serviceText': serviceText?.trim(),
    'locationLat': locationLat,
    'locationLng': locationLng,
    'locationVerified': locationVerified,
  };

  factory MerchantDecor.fromJson(Map<String, dynamic> json) {
    List<String> split(Object? raw) {
      if (raw is List) {
        return raw
            .whereType<Object>()
            .map((Object value) => value.toString().trim())
            .where((String value) => value.isNotEmpty)
            .toList();
      }
      final String source = raw?.toString().trim() ?? '';
      if (source.isEmpty) return <String>[];
      if (source.startsWith('[')) {
        try {
          final Object? decoded = jsonDecode(source);
          if (decoded is List) return split(decoded);
        } on FormatException {
          // 历史数据不一定是合法 JSON，继续按分号格式兼容。
        }
      }
      return source
          .split(';')
          .map((String value) => value.trim())
          .where((String value) => value.isNotEmpty)
          .toList();
    }

    int? intOf(Object? raw) =>
        raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
    double? doubleOf(Object? raw) =>
        raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '');
    return MerchantDecor(
      coverImage: json['coverImage'] as String?,
      slogan: json['slogan'] as String?,
      cityRole: json['cityRole'] as String?,
      storyTitle: json['storyTitle'] as String?,
      gallery: split(json['gallery']),
      tags: split(json['tags']),
      categoryId: intOf(json['categoryId']),
      featuredType: intOf(json['featuredType']),
      featuredId: intOf(json['featuredId']),
      serviceTag: json['serviceTag'] as String?,
      serviceText: json['serviceText'] as String?,
      locationLat: doubleOf(json['locationLat']),
      locationLng: doubleOf(json['locationLng']),
      locationVerified: intOf(json['locationVerified']),
    );
  }
}
