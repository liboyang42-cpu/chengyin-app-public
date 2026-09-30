import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/models/play_run_session.dart';

/// 本机暂停快照 —— 对齐小程序 `utils/play-run-session.js` 里 `wx.setStorageSync`
/// 的那一半。服务端那份走 `/api/play/run-session/*`(换设备续玩),这份只管
/// **本机**重进时把计时接回去;两半写的是同一个数(暂停那一刻的已用时)。
class PlayRunSessionStore {
  const PlayRunSessionStore(this._storage);

  /// 活动场次按 activityId、自玩按 topicId 隔离:同一主题换一场活动不串用旧计时。
  static const String _prefix = 'play_paused_run_v1:';

  final FlutterSecureStorage _storage;

  static String? keyFor({int? activityId, int? topicId}) {
    final int activity = activityId ?? 0;
    final int topic = topicId ?? 0;
    if (activity > 0) return '${_prefix}a$activity';
    if (topic > 0) return '${_prefix}t$topic';
    return null;
  }

  /// 读快照。没有、读不动、形状不合法一律回 null —— 脏数据不能恢复成
  /// 看起来正常的假会话,宁可从头开始。
  Future<PlayPausedRun?> read({int? activityId, int? topicId}) async {
    final String? key = keyFor(activityId: activityId, topicId: topicId);
    if (key == null) return null;
    try {
      final String? raw = await _storage.read(key: key);
      if (raw == null || raw.isEmpty) return null;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return PlayPausedRun.tryParse(
        _intOrNull(decoded['elapsedSeconds']),
        _intOrNull(decoded['savedAt']),
      );
    } catch (_) {
      return null;
    }
  }

  /// 落盘。存不上不影响游玩(和小程序一样是尽力而为),所以静默失败。
  Future<void> write({
    int? activityId,
    int? topicId,
    required int elapsedSeconds,
    required int savedAt,
  }) async {
    final String? key = keyFor(activityId: activityId, topicId: topicId);
    if (key == null) return;
    try {
      await _storage.write(
        key: key,
        value: jsonEncode(<String, dynamic>{
          'elapsedSeconds': elapsedSeconds,
          'savedAt': savedAt,
        }),
      );
    } catch (_) {}
  }

  Future<void> clear({int? activityId, int? topicId}) async {
    final String? key = keyFor(activityId: activityId, topicId: topicId);
    if (key == null) return;
    try {
      await _storage.delete(key: key);
    } catch (_) {}
  }

  static int? _intOrNull(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}
