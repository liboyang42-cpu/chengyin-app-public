import '../../core/network/dio_client.dart';
import '../models/city_node_poi.dart';

/// 城市节点(地图上的可打卡点)。对齐后端 `ApiCityNodeController`(/api/city)。
class CityNodeApi {
  CityNodeApi(this._client);
  final DioClient _client;

  /// 附近节点:`GET /api/city/nodes?lat=&lng=&radius=`。
  ///
  /// ⚠️ 缺定位时后端返回「缺少定位」—— 那是**前置条件没满足**,
  ///   界面该引导开定位,不是「加载失败 + 重试」。
  Future<List<CityNodePoi>> nearby({
    required double lat,
    required double lng,
    int radius = 3000,
    String? keyword,
    int? categoryId,
    String? tag,
    String? cityRole,
  }) async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/city/nodes',
      queryParameters: <String, dynamic>{
        'lat': lat,
        'lng': lng,
        'radius': radius,
        if (keyword != null && keyword.trim().isNotEmpty)
          'keyword': keyword.trim(),
        'categoryId': ?categoryId,
        if (tag != null && tag.trim().isNotEmpty) 'tag': tag.trim(),
        if (cityRole != null && cityRole.trim().isNotEmpty)
          'cityRole': cityRole.trim(),
      },
    );
    return _rows(resp.data ?? <String, dynamic>{});
  }

  /// 节点详情:`GET /api/city/nodes/{id}`。
  Future<CityNodePoi> detail(int poiId) async {
    final resp =
        await _client.dio.get<Map<String, dynamic>>('/api/city/nodes/$poiId');
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '节点不存在');
    }
    return CityNodePoi.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 切换收藏:`POST /api/city/nodes/{id}/favorite` → `{favorited}`。
  ///
  /// ★ 是**切换**不是"设为收藏" —— 返回的是**新状态**,
  ///   调用方要用返回值更新 UI,而不是自己取反(失败时取反会让状态和服务端对不上)。
  Future<bool> toggleFavorite(int poiId) async {
    final resp = await _client.dio
        .post<Map<String, dynamic>>('/api/city/nodes/$poiId/favorite');
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '操作失败');
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return data['favorited'] == true;
  }

  List<CityNodePoi> _rows(Map<String, dynamic> body) {
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '加载失败');
    }
    final raw = body['data'];
    final rows = raw is List
        ? raw
        : (raw is Map<String, dynamic>
            ? (raw['rows'] as List<dynamic>? ?? const <dynamic>[])
            : const <dynamic>[]);
    return rows
        .whereType<Map<String, dynamic>>()
        .map(CityNodePoi.fromJson)
        // ★ 坐标不可用的点**不进列表** —— 它标不到地图上,
        //   放进来只会变成一个点不动的条目。
        .where((CityNodePoi p) => p.hasCoords)
        .toList();
  }
}
