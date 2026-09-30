import 'package:dio/dio.dart';
import '../../core/network/dio_client.dart';
import '../models/nearby_node.dart';
import '../models/city_resolve.dart';

/// 地图接口(对齐后端 `ApiMapController`)。
class MapApi {
  MapApi(this._client);
  final DioClient _client;

  /// 周边节点:`POST /api/map/nearby`。
  Future<List<NearbyNode>> nearby({
    required double longitude,
    required double latitude,
    double radius = 2000,
    int limit = 50,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/map/nearby',
      data: FormData.fromMap(<String, dynamic>{
        'longitude': longitude.toString(),
        'latitude': latitude.toString(),
        'radius': radius.toString(),
        'limit': limit.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    final list = (body['data'] as List<dynamic>?) ?? <dynamic>[];
    return list
        .map((dynamic e) => NearbyNode.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 定位反查城市:`POST /api/map/reverse-geocode`(表单 longitude/latitude)。
  ///
  /// ★★ 后端在**限流 / 服务不可用**时返回 **HTTP 200 +
  ///   `{city:'', manualInputRequired:true, reason:...}`**,而不是报错。
  ///   ⇒ 那不是失败,是「这次自动定位不成,请手填」。
  ///   当成错误处理会让用户看到"加载失败+重试",而重试大概率还是限流。
  ///
  /// 只有**参数缺失/格式错**才是真错误(那时后端返回非 200)。
  Future<CityResolveResult> reverseGeocode({
    required double longitude,
    required double latitude,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/map/reverse-geocode',
      data: FormData.fromMap(<String, dynamic>{
        'longitude': longitude.toString(),
        'latitude': latitude.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '定位失败');
    }
    return CityResolveResult.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }
}
