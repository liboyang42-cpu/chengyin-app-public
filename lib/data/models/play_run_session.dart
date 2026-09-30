/// 进行中的游戏会话(后端 `player_run_session`,第二轮拍板 22 跨设备续玩)。
///
/// 与小程序 `utils/play-run-session.js` 的快照同形:只记「暂停中的一局 +
/// 已用时」;节点完成本来就在服务端(`/api/play/nodes`),这里不重复。
/// 作用域二选一 —— 活动场次按 activityId、自玩按 topicId,两样都没有不算会话。
final class PlayRunSession {
  const PlayRunSession({
    required this.activityId,
    required this.topicId,
    this.elapsedSeconds,
    this.title = '',
    this.cover = '',
  });

  final int activityId;
  final int topicId;

  /// 已用时(秒)。拿不到合法值时为 null —— 卡上只说「已暂停」,不编一个 00:00。
  final int? elapsedSeconds;

  final String title;
  final String cover;

  /// 有作用域才算一局:两样都是 0 的行落了盘也没处恢复。
  bool get continuable => activityId > 0 || topicId > 0;

  /// 解析一行。作用域不成立时返回 null(小程序 `buildContinueGame` 同样把这一行
  /// 当没有);用时缺失不丢整行 —— 卡上少一行字,好过整张卡不见。
  static PlayRunSession? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final Map<String, dynamic> json = Map<String, dynamic>.from(raw);
    final int activityId = _intOrZero(json['activityId']);
    final int topicId = _intOrZero(json['topicId']);
    if (activityId <= 0 && topicId <= 0) return null;
    final int? elapsed = _intOrNull(json['elapsedSeconds']);
    return PlayRunSession(
      activityId: activityId < 0 ? 0 : activityId,
      topicId: topicId < 0 ? 0 : topicId,
      elapsedSeconds: elapsed != null && elapsed >= 0 ? elapsed : null,
      title: '${json['title'] ?? ''}'.trim(),
      cover: '${json['cover'] ?? ''}'.trim(),
    );
  }

  static int _intOrZero(Object? value) => _intOrNull(value) ?? 0;

  static int? _intOrNull(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}

/// 「暂停中的一局」的读数:本机快照与服务端那一份同形(小程序 `normalizePausedRun`)。
final class PlayPausedRun {
  const PlayPausedRun({required this.elapsedSeconds, required this.savedAt});

  final int elapsedSeconds;
  final int savedAt;

  /// 一次步行行程不可能按周计;超过这个值的快照只可能是脏数据,不当成可恢复会话。
  static const int maxSeconds = 7 * 24 * 3600;

  /// 只认「合法用时 + 有落盘时间」的形状;畸形/越界一律当没有 ——
  /// 否则脏数据会被恢复成看起来正常的假会话。
  static PlayPausedRun? tryParse(int? elapsedSeconds, int? savedAt) {
    if (elapsedSeconds == null ||
        elapsedSeconds < 0 ||
        elapsedSeconds > maxSeconds) {
      return null;
    }
    if (savedAt == null || savedAt <= 0) return null;
    return PlayPausedRun(elapsedSeconds: elapsedSeconds, savedAt: savedAt);
  }

  /// 两台设备各有一份时取较晚落盘的那份(小程序 `newerPausedRun`)。
  static PlayPausedRun? newer(PlayPausedRun? local, PlayPausedRun? remote) {
    if (local == null) return remote;
    if (remote == null) return local;
    return remote.savedAt > local.savedAt ? remote : local;
  }
}
