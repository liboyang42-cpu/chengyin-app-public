import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../../core/providers.dart' show dioClientProvider;
import '../models/play_run_session.dart';

final playRunSessionApiProvider = Provider<PlayRunSessionGateway>(
  (ref) => PlayRunSessionApi(ref.watch(dioClientProvider)),
);

/// 进行中的游戏会话(跨设备续玩)。作用域**二选一**:活动场次用 activityId、
/// 自玩用 topicId —— 同小程序 `runSessionRequestScope`,两边都给或都不给都算参数有误。
abstract interface class PlayRunSessionGateway {
  Future<List<PlayRunSession>> list();

  /// 读**某一场**服务端那份暂停快照(小程序 `readServerPausedRun`)。
  Future<PlayRunSessionRead> read({int? activityId, int? topicId});

  /// 落盘暂停中的一局(离页/暂停时调)。
  Future<void> save({
    int? activityId,
    int? topicId,
    required int elapsedSeconds,
    required int savedAt,
  });

  /// 作废某一局(结束/通关时调,服务端留 ENDED 墓碑)。
  Future<void> clear({int? activityId, int? topicId, required int savedAt});
}

/// 服务端那一份的读数:小程序 `readServerPausedRun` 的三态 ——
/// `ok=false` = 没读到(断网/报错),调用方沿用本机快照;
/// `ok=true` + `record == null` = 服务端没有可继续的会话,其中 `endedAt > 0`
/// 是另一台设备结束这一局留下的墓碑(比本机快照新就该作废本机那份)。
final class PlayRunSessionRead {
  const PlayRunSessionRead({required this.ok, this.record, this.endedAt = 0});

  final bool ok;
  final PlayPausedRun? record;
  final int endedAt;
}

class PlayRunSessionException implements Exception {
  const PlayRunSessionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// `ApiPlayRunSessionController`(`/api/play/run-session`)的客户端。
/// 写接口只认 `code==200`:写失败不静默成功,也不当成致命 —— 调用方(暂停/离页)
/// 本就不该因为一次落盘失败打断游玩。
class PlayRunSessionApi implements PlayRunSessionGateway {
  PlayRunSessionApi(this._client);

  final DioClient _client;

  @override
  Future<List<PlayRunSession>> list() async {
    final Response<Map<String, dynamic>> response = await _client.dio
        .get<Map<String, dynamic>>('/api/play/run-session/list');
    final Map<String, dynamic> body = _body(response);
    _ensureSuccess(body, '继续游戏加载失败');
    final Object? data = body['data'];
    if (data is! List) {
      throw const PlayRunSessionException('继续游戏回执不完整');
    }
    final List<PlayRunSession> out = <PlayRunSession>[];
    for (final Object? row in data) {
      final PlayRunSession? session = PlayRunSession.tryParse(row);
      if (session != null) out.add(session);
    }
    return out;
  }

  @override
  Future<PlayRunSessionRead> read({int? activityId, int? topicId}) async {
    final Map<String, String> scope = _scope(activityId, topicId);
    final Response<Map<String, dynamic>> response = await _client.dio
        .get<Map<String, dynamic>>(
          '/api/play/run-session',
          queryParameters: scope,
        );
    final Map<String, dynamic> body = _body(response);
    if (_strictInteger(body['code']) != 200) {
      return const PlayRunSessionRead(ok: false);
    }
    final Object? data = body['data'];
    if (data is! Map) return const PlayRunSessionRead(ok: true);
    final Map<String, dynamic> json = Map<String, dynamic>.from(data);
    final String state = '${json['runState'] ?? ''}'.toUpperCase();
    final int savedAt = _strictInteger(json['savedAt']) ?? 0;
    if (state == 'ENDED') {
      return PlayRunSessionRead(ok: true, endedAt: savedAt);
    }
    if (state != 'PAUSED') return const PlayRunSessionRead(ok: true);
    return PlayRunSessionRead(
      ok: true,
      record: PlayPausedRun.tryParse(
        _strictInteger(json['elapsedSeconds']),
        savedAt,
      ),
    );
  }

  @override
  Future<void> save({
    int? activityId,
    int? topicId,
    required int elapsedSeconds,
    required int savedAt,
  }) async {
    final Map<String, String> scope = _scope(activityId, topicId);
    if (elapsedSeconds < 0 || elapsedSeconds > maxPlayRunSeconds) {
      throw const PlayRunSessionException('游玩用时无效，没有落盘');
    }
    if (savedAt <= 0) {
      throw const PlayRunSessionException('落盘时间无效，没有落盘');
    }
    final Response<Map<String, dynamic>> response = await _client.dio
        .post<Map<String, dynamic>>(
          '/api/play/run-session/save',
          data: FormData.fromMap(<String, dynamic>{
            ...scope,
            'elapsedSeconds': elapsedSeconds.toString(),
            'savedAt': savedAt.toString(),
          }),
        );
    _ensureSuccess(_body(response), '暂停进度没有存上');
  }

  @override
  Future<void> clear({
    int? activityId,
    int? topicId,
    required int savedAt,
  }) async {
    final Map<String, String> scope = _scope(activityId, topicId);
    if (savedAt <= 0) {
      throw const PlayRunSessionException('落盘时间无效，没有落盘');
    }
    final Response<Map<String, dynamic>> response = await _client.dio
        .post<Map<String, dynamic>>(
          '/api/play/run-session/clear',
          data: FormData.fromMap(<String, dynamic>{
            ...scope,
            'savedAt': savedAt.toString(),
          }),
        );
    _ensureSuccess(_body(response), '结束这次游玩没有记上');
  }

  /// 与后端 `MAX_PAUSED_SECONDS` 同值:一次步行行程不可能按周计。
  static const int maxPlayRunSeconds = PlayPausedRun.maxSeconds;

  static Map<String, String> _scope(int? activityId, int? topicId) {
    final bool hasActivity = (activityId ?? 0) > 0;
    final bool hasTopic = (topicId ?? 0) > 0;
    if (hasActivity == hasTopic) {
      throw const PlayRunSessionException('场次信息不全，没有落盘');
    }
    return hasActivity
        ? <String, String>{'activityId': activityId.toString()}
        : <String, String>{'topicId': topicId.toString()};
  }

  static Map<String, dynamic> _body(Response<Map<String, dynamic>> response) =>
      response.data ?? <String, dynamic>{};

  static void _ensureSuccess(Map<String, dynamic> body, String fallback) {
    final int? code = _strictInteger(body['code']);
    if (code == 200) return;
    final String message = '${body['msg'] ?? ''}'.trim();
    throw PlayRunSessionException(message.isEmpty ? fallback : message);
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
