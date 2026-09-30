import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../models/advanced_play.dart';

sealed class AdvancedPlayException implements Exception {
  const AdvancedPlayException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AdvancedPlayBusinessException extends AdvancedPlayException {
  const AdvancedPlayBusinessException(super.message);
}

class AdvancedPlayTransportException extends AdvancedPlayException {
  const AdvancedPlayTransportException(super.message);
}

class AdvancedPlayContractException extends AdvancedPlayException {
  const AdvancedPlayContractException(super.message);
}

abstract interface class AdvancedPlayGateway {
  Future<AdvancedPlayState> start({
    required int activityId,
    required int topicId,
    required int nodeId,
  });

  Future<AdvancedPlayState> action({
    required int sessionId,
    required int version,
    required String idempotencyKey,
    required String action,
    required Map<String, Object?> payload,
  });

  Future<AdvancedPlayState> state(int sessionId);

  Future<List<AdvancedPlayLeaderboardRow>> leaderboard({
    required int activityId,
    required int topicId,
    required int nodeId,
  });
}

class AdvancedPlayApi implements AdvancedPlayGateway {
  AdvancedPlayApi(this._client);

  final DioClient _client;

  @override
  Future<AdvancedPlayState> start({
    required int activityId,
    required int topicId,
    required int nodeId,
  }) async {
    try {
      final response = await _client.dio.post<Map<String, dynamic>>(
        '/api/play/advanced/start',
        data: <String, Object?>{
          'activityId': activityId,
          'topicId': topicId,
          'nodeId': nodeId,
        },
      );
      final AdvancedPlayState result = _stateFrom(response.data);
      if (result.activityId != activityId ||
          result.topicId != topicId ||
          result.nodeId != nodeId) {
        throw const AdvancedPlayContractException('启动回执与当前节点不匹配');
      }
      return result;
    } on DioException catch (error) {
      throw AdvancedPlayTransportException(_transportMessage(error));
    }
  }

  @override
  Future<AdvancedPlayState> action({
    required int sessionId,
    required int version,
    required String idempotencyKey,
    required String action,
    required Map<String, Object?> payload,
  }) async {
    if (sessionId <= 0 || version < 0 || idempotencyKey.isEmpty) {
      throw const AdvancedPlayContractException('高级玩法动作参数不完整');
    }
    try {
      final response = await _client.dio.post<Map<String, dynamic>>(
        '/api/play/advanced/action',
        data: <String, Object?>{
          'sessionId': sessionId,
          'version': version,
          'idempotencyKey': idempotencyKey,
          'action': action.trim().toUpperCase(),
          'payload': payload,
        },
      );
      final AdvancedPlayState result = _stateFrom(response.data);
      if (result.sessionId != sessionId || result.version <= version) {
        throw const AdvancedPlayContractException('动作回执与本次请求不匹配');
      }
      return result;
    } on DioException catch (error) {
      throw AdvancedPlayTransportException(_transportMessage(error));
    }
  }

  @override
  Future<AdvancedPlayState> state(int sessionId) async {
    try {
      final response = await _client.dio.get<Map<String, dynamic>>(
        '/api/play/advanced/state',
        queryParameters: <String, Object?>{'sessionId': sessionId},
      );
      final AdvancedPlayState result = _stateFrom(response.data);
      if (result.sessionId != sessionId) {
        throw const AdvancedPlayContractException('权威回读与当前玩法局不匹配');
      }
      return result;
    } on DioException catch (error) {
      throw AdvancedPlayTransportException(_transportMessage(error));
    }
  }

  @override
  Future<List<AdvancedPlayLeaderboardRow>> leaderboard({
    required int activityId,
    required int topicId,
    required int nodeId,
  }) async {
    try {
      final response = await _client.dio.get<Map<String, dynamic>>(
        '/api/play/advanced/leaderboard',
        queryParameters: <String, Object?>{
          'activityId': activityId,
          'topicId': topicId,
          'nodeId': nodeId,
        },
      );
      final Object? raw = _dataFrom(response.data);
      if (raw is! List) {
        throw const AdvancedPlayContractException('排行榜回执不完整');
      }
      final List<AdvancedPlayLeaderboardRow> rows =
          <AdvancedPlayLeaderboardRow>[];
      for (final Object? row in raw) {
        if (row is! Map) {
          throw const AdvancedPlayContractException('排行榜回执不完整');
        }
        try {
          rows.add(
            AdvancedPlayLeaderboardRow.fromJson(
              row.map<String, Object?>((key, value) => MapEntry('$key', value)),
            ),
          );
        } on FormatException catch (error) {
          throw AdvancedPlayContractException(error.message.toString());
        }
      }
      return List<AdvancedPlayLeaderboardRow>.unmodifiable(rows);
    } on DioException catch (error) {
      throw AdvancedPlayTransportException(_transportMessage(error));
    }
  }

  AdvancedPlayState _stateFrom(Map<String, dynamic>? body) {
    final Object? raw = _dataFrom(body);
    if (raw is! Map) {
      throw const AdvancedPlayContractException('高级玩法权威回执不完整');
    }
    try {
      return AdvancedPlayState.fromJson(
        raw.map<String, Object?>((key, value) => MapEntry('$key', value)),
      );
    } on FormatException catch (error) {
      throw AdvancedPlayContractException(error.message.toString());
    }
  }

  Object? _dataFrom(Map<String, dynamic>? body) {
    final Map<String, dynamic> value = body ?? <String, dynamic>{};
    final int code = switch (value['code']) {
      final num number => number.toInt(),
      final String text => int.tryParse(text) ?? 0,
      _ => 0,
    };
    if (code != 200) {
      throw AdvancedPlayBusinessException(
        (value['msg'] ?? '高级玩法操作失败').toString(),
      );
    }
    return value['data'];
  }

  String _transportMessage(DioException error) => switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => '结果尚未确认，请核对服务端状态',
    _ => '网络连接失败，请稍后重试',
  };
}
