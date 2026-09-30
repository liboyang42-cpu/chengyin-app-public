import '../../core/network/dio_client.dart';
import '../models/badge_wall.dart';

/// 勋章墙业务错误(AjaxResult.code != 200),携带后端原文 msg。
class BadgeWallException implements Exception {
  BadgeWallException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 勋章墙接口(对齐后端 ApiBadgeController / ApiMedalController)。
class BadgeWallApi {
  BadgeWallApi(this._client);
  final DioClient _client;

  /// 勋章墙 v2:`POST /api/badge/wall-v2`(需登录)。
  Future<BadgeWallV2> wallV2() async {
    final data = await _post('/api/badge/wall-v2');
    return BadgeWallV2.fromJson(data);
  }

  /// 我的勋章墙:`POST /api/medal/wall`(需登录)。
  Future<MedalWall> medalWall() async {
    final data = await _post('/api/medal/wall');
    return MedalWall.fromJson(data);
  }

  Future<Map<String, dynamic>> _post(String path) async {
    final resp = await _client.dio
        .post<Map<String, dynamic>>(path, data: <String, dynamic>{});
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw BadgeWallException((body['msg'] ?? '加载失败').toString());
    }
    return (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }
}
