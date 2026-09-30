import '../../core/network/dio_client.dart';
import '../models/growth.dart';

/// 成长中心业务错误(AjaxResult.code != 200),携带后端原文 msg。
class GrowthException implements Exception {
  GrowthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 成长接口(对齐后端 ApiGrowthController)。
class GrowthApi {
  GrowthApi(this._client);
  final DioClient _client;

  /// 成长中心:`POST /api/growth/center`(需登录)。
  /// 后端 success(MemberGrowthCenterVO):growth/points/badges/missions。
  Future<GrowthCenter> center() async {
    final data = await _post('/api/growth/center');
    return GrowthCenter.fromJson(data as Map<String, dynamic>? ?? <String, dynamic>{});
  }

  /// 排行榜:`POST /api/growth/leaderboard`(需登录)。
  /// metric: point / exp;period: total / week;limit: 取前 N。
  Future<GrowthLeaderboard> leaderboard({
    required String metric,
    required String period,
    int limit = 50,
  }) async {
    final data = await _post(
      '/api/growth/leaderboard',
      data: <String, dynamic>{
        'metric': metric,
        'period': period,
        'limit': limit,
      },
    );
    return GrowthLeaderboard.fromJson(data as Map<String, dynamic>? ?? <String, dynamic>{});
  }

  /// 我的成长进度:`POST /api/play/growth`(需登录)。
  /// 只读消费端点在 play 域、供成长中心概览用,放在成长侧 API 里避免与
  /// 并行会话改 play_api.dart 撞车。
  Future<PlayGrowth> playGrowth() async {
    final data = await _post('/api/play/growth');
    return PlayGrowth.fromJson(data as Map<String, dynamic>? ?? <String, dynamic>{});
  }

  /// 我已通关的活动:`POST /api/play/my-completed`(需登录)。
  Future<List<CompletedActivity>> myCompleted() async {
    final data = await _post('/api/play/my-completed');
    final rows = data is List<dynamic> ? data : <dynamic>[];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(CompletedActivity.fromJson)
        .toList();
  }

  Future<dynamic> _post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    final resp = await _client.dio
        .post<Map<String, dynamic>>(path, data: data ?? <String, dynamic>{});
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw GrowthException((body['msg'] ?? '加载失败').toString());
    }
    return body['data'];
  }
}
