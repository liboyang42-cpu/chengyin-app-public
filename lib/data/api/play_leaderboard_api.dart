import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../../core/providers.dart' show dioClientProvider;
import '../models/play_leaderboard.dart';

final playLeaderboardApiProvider = Provider<PlayLeaderboardGateway>((ref) {
  return PlayLeaderboardApi(ref.watch(dioClientProvider));
});

abstract interface class PlayLeaderboardGateway {
  Future<PlayLeaderboard> fetch({int? activityId, int? topicId});
}

class PlayLeaderboardException implements Exception {
  const PlayLeaderboardException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 同行者榜 API。活动场次与自玩主题是两个互斥会话，禁止同时或都不发送。
class PlayLeaderboardApi implements PlayLeaderboardGateway {
  PlayLeaderboardApi(this._client);

  final DioClient _client;

  @override
  Future<PlayLeaderboard> fetch({int? activityId, int? topicId}) async {
    final bool hasActivity = activityId != null;
    final bool hasTopic = topicId != null;
    if (hasActivity == hasTopic ||
        (activityId != null && activityId <= 0) ||
        (topicId != null && topicId <= 0)) {
      throw const PlayLeaderboardException('场次信息不完整');
    }
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/api/play/leaderboard',
      queryParameters: <String, dynamic>{
        if (hasActivity) 'activityId': activityId,
        if (hasTopic) 'topicId': topicId,
      },
    );
    final Map<String, dynamic> body = response.data ?? <String, dynamic>{};
    final int? code = _strictInteger(body['code']);
    if (code == null) {
      throw const PlayLeaderboardException('同行者榜回执不完整');
    }
    if (code != 200) {
      throw PlayLeaderboardException((body['msg'] ?? '同行者榜加载失败').toString());
    }
    final Object? data = body['data'];
    if (data is! Map) {
      throw const PlayLeaderboardException('同行者榜回执不完整');
    }
    try {
      return PlayLeaderboard.fromJson(Map<String, dynamic>.from(data));
    } on FormatException {
      throw const PlayLeaderboardException('同行者榜回执不完整');
    }
  }
}

int? _strictInteger(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.toInt()) {
    return value.toInt();
  }
  if (value is String) return int.tryParse(value);
  return null;
}
