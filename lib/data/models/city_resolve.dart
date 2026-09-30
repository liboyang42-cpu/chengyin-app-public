/// 定位反查城市。对齐后端 `ApiMapController.reverseGeocode`
/// (/api/map/reverse-geocode)。
///
/// ★★ 后端有一条**降级路径**:限流(MAP_RATE_LIMITED)或服务不可用
///   (MAP_UNAVAILABLE)时返回 **HTTP 200 + `manualInputRequired: true`**,
///   而不是报错。
///
///   ⇒ 这**不是失败**,是「这次自动定位不成,请你手填」。
///     当成错误处理会让用户看到"加载失败+重试"——而重试大概率还是限流。
class CityResolveResult {
  const CityResolveResult({
    this.city = '',
    this.manualInputRequired = false,
    this.reason,
  });

  final String city;

  /// 需要用户手填城市。
  final bool manualInputRequired;

  /// MAP_RATE_LIMITED / MAP_UNAVAILABLE。
  final String? reason;

  /// 真的拿到城市了。★ 判据是**城市名非空**,不是"没有 manualInputRequired" ——
  ///   两者理论上应一致,但后端若只置了其一,以城市名为准更安全。
  bool get resolved => city.trim().isNotEmpty;

  /// 给用户的说明。★ 限流与不可用要分开说 ——
  ///   限流是"等一会儿再试也许就好",不可用是"这功能现在没有"。
  String get hint {
    switch (reason) {
      case 'MAP_RATE_LIMITED':
        return '定位服务忙,请手动选择城市(稍后可再试自动定位)';
      case 'MAP_UNAVAILABLE':
        return '定位服务暂时不可用,请手动选择城市';
      default:
        return '请手动选择城市';
    }
  }

  /// 值不值得再试一次自动定位。**只有限流值得** ——
  /// 服务不可用时反复试没有意义。
  bool get worthRetrying => reason == 'MAP_RATE_LIMITED';

  factory CityResolveResult.fromJson(Map<String, dynamic> json) {
    return CityResolveResult(
      city: (json['city'] as String?) ?? '',
      manualInputRequired: json['manualInputRequired'] == true,
      reason: json['reason'] as String?,
    );
  }
}
