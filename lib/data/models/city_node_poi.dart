import 'validation_method_labels.dart';

/// 城市节点(地图上的可打卡点)。
/// 对齐后端 `CityNodeVO` 与 `/api/city/nodes*`。
class CityNodePoi {
  const CityNodePoi({
    required this.poiId,
    required this.name,
    this.description,
    this.lat,
    this.lng,
    this.radiusM,
    this.tags,
    this.coverImg,
    this.distance,
    this.merchantId,
    this.merchantName,
    this.merchantPhone,
    this.templateId,
    this.templateTitle,
    this.validationMethod,
    this.favorited = false,
  });

  final int poiId;
  final String name;
  final String? description;

  /// ★ 经纬度用可空 —— 后端可能缺,而 (0,0) 是几内亚湾,
  ///   默认成 0 会把点标到大西洋里去。
  final double? lat;
  final double? lng;

  /// 到达判定半径(米)。
  final int? radiusM;

  final String? tags;
  final String? coverImg;

  /// 距离(米)。只在带定位查询时有。
  final double? distance;

  final int? merchantId;
  final String? merchantName;
  final String? merchantPhone;

  final int? templateId;
  final String? templateTitle;

  /// 0 无需验证 / 1 文字作答 / 2 拍照打卡 / 3 选项问答 / 4 到店扫码 /
  /// 5 GPS 到达 / 6 偏好题组 / 7 传感器挑战;其余按 GPS。
  final int? validationMethod;

  final bool favorited;

  /// 坐标是否可用 —— 不可用就**不该标到地图上**。
  bool get hasCoords =>
      lat != null && lng != null && !(lat == 0 && lng == 0);

  /// 距离文案。没给就不显示,不写「0m」。
  String? get distanceText {
    final d = distance;
    if (d == null || d < 0) return null;
    return d < 1000 ? '${d.round()}m' : '${(d / 1000).toStringAsFixed(1)}km';
  }

  /// 到达方式文案(与全 App 共用一份 0–7 码表)。
  /// 空值仍是「到点打卡」;认不出的码明确回落「其他」。
  String get interactionText =>
      validationMethodLabel(validationMethod) ?? '到点打卡';

  /// 标签切成列表。
  List<String> get tagList => (tags ?? '')
      .split(RegExp(r'[,,、;;\s]+'))
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList();

  CityNodePoi copyWith({bool? favorited}) => CityNodePoi(
        poiId: poiId,
        name: name,
        description: description,
        lat: lat,
        lng: lng,
        radiusM: radiusM,
        tags: tags,
        coverImg: coverImg,
        distance: distance,
        merchantId: merchantId,
        merchantName: merchantName,
        merchantPhone: merchantPhone,
        templateId: templateId,
        templateTitle: templateTitle,
        validationMethod: validationMethod,
        favorited: favorited ?? this.favorited,
      );

  factory CityNodePoi.fromJson(Map<String, dynamic> json) {
    return CityNodePoi(
      poiId: (json['poiId'] as num?)?.toInt() ?? 0,
      name: ((json['name'] as String?) ?? '').trim().isEmpty
          ? '未命名地点'
          : (json['name'] as String).trim(),
      description: json['description'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      radiusM: (json['radiusM'] as num?)?.toInt(),
      tags: json['tags'] as String?,
      coverImg: json['coverImg'] as String?,
      distance: (json['distance'] as num?)?.toDouble(),
      merchantId: (json['merchantId'] as num?)?.toInt(),
      merchantName: json['merchantName'] as String?,
      merchantPhone: json['merchantPhone'] as String?,
      templateId: (json['templateId'] as num?)?.toInt(),
      templateTitle: json['templateTitle'] as String?,
      validationMethod: (json['validationMethod'] as num?)?.toInt(),
      favorited: json['favorited'] == true,
    );
  }
}
