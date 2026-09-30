import 'package:flutter/foundation.dart';

@immutable
class AdvancedPlayRole {
  const AdvancedPlayRole({required this.id, required this.label});

  factory AdvancedPlayRole.fromJson(Map<String, Object?> json) =>
      AdvancedPlayRole(
        id: (json['id'] ?? '').toString().trim(),
        label: (json['label'] ?? '').toString().trim(),
      );

  final String id;
  final String label;

  bool get isUsable => id.isNotEmpty && label.isNotEmpty;
}

@immutable
class AdvancedPlayMultiplayerConfig {
  const AdvancedPlayMultiplayerConfig({
    required this.enabled,
    required this.assignment,
    required this.requiredTurns,
    required this.roles,
  });

  factory AdvancedPlayMultiplayerConfig.fromJson(Map<String, Object?> json) =>
      AdvancedPlayMultiplayerConfig(
        enabled: json['enabled'] == true,
        assignment: (json['assignment'] ?? 'AUTO').toString().toUpperCase(),
        requiredTurns: _integer(json['requiredTurns']) > 0
            ? _integer(json['requiredTurns'])
            : 1,
        roles: _maps(json['roles'])
            .map(AdvancedPlayRole.fromJson)
            .where((AdvancedPlayRole role) => role.isUsable)
            .toList(growable: false),
      );

  final bool enabled;
  final String assignment;
  final int requiredTurns;
  final List<AdvancedPlayRole> roles;

  String roleLabel(String roleId) {
    for (final AdvancedPlayRole role in roles) {
      if (role.id == roleId) return role.label;
    }
    return roleId;
  }
}

@immutable
class AdvancedPlayMember {
  const AdvancedPlayMember({
    required this.memberId,
    required this.name,
    required this.avatar,
    required this.roleId,
  });

  factory AdvancedPlayMember.fromJson(
    Map<String, Object?> json,
    Map<int, String> roles,
  ) {
    final int memberId = _integer(json['memberId']);
    return AdvancedPlayMember(
      memberId: memberId,
      name: (json['name'] ?? '').toString().trim(),
      avatar: (json['avatar'] ?? '').toString().trim(),
      roleId: roles[memberId] ?? '',
    );
  }

  final int memberId;
  final String name;
  final String avatar;
  final String roleId;
}

@immutable
class AdvancedPlayMultiplayerState {
  const AdvancedPlayMultiplayerState({
    required this.roles,
    required this.members,
    required this.completedUnitIds,
    required this.turnIndex,
  });

  factory AdvancedPlayMultiplayerState.fromJson(Map<String, Object?> json) {
    final Map<int, String> roles = <int, String>{};
    for (final MapEntry<String, Object?> entry in _map(json['roles']).entries) {
      final int? memberId = int.tryParse(entry.key);
      final String roleId = (entry.value ?? '').toString().trim();
      if (memberId != null && memberId > 0 && roleId.isNotEmpty) {
        roles[memberId] = roleId;
      }
    }
    return AdvancedPlayMultiplayerState(
      roles: Map<int, String>.unmodifiable(roles),
      members: _maps(json['members'])
          .map((Map<String, Object?> member) {
            return AdvancedPlayMember.fromJson(member, roles);
          })
          .where((AdvancedPlayMember member) => member.memberId > 0)
          .toList(growable: false),
      completedUnitIds:
          (json['completedUnitIds'] is List
                  ? json['completedUnitIds'] as List
                  : const <Object?>[])
              .map((Object? value) => (value ?? '').toString().trim())
              .where((String value) => value.isNotEmpty)
              .toList(growable: false),
      turnIndex: _integer(json['turnIndex']),
    );
  }

  final Map<int, String> roles;
  final List<AdvancedPlayMember> members;
  final List<String> completedUnitIds;
  final int turnIndex;
}

@immutable
class AdvancedPlayMechanics {
  const AdvancedPlayMechanics({
    required this.timerEnabled,
    required this.randomEnabled,
    required this.randomDrawCount,
    required this.branchEnabled,
    required this.leaderboardEnabled,
    required this.leaderboardMetric,
    required this.multiplayer,
  });

  factory AdvancedPlayMechanics.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> timer = _map(json['timer']);
    final Map<String, Object?> random = _map(json['random']);
    final Map<String, Object?> branch = _map(json['branch']);
    final Map<String, Object?> leaderboard = _map(json['leaderboard']);
    final Map<String, Object?> multiplayer = _map(json['multiplayer']);
    return AdvancedPlayMechanics(
      timerEnabled: timer['enabled'] == true,
      randomEnabled: random['enabled'] == true,
      randomDrawCount: _integer(random['drawCount']),
      branchEnabled: branch['enabled'] == true,
      leaderboardEnabled: leaderboard['enabled'] == true,
      leaderboardMetric: (leaderboard['metric'] ?? 'SCORE').toString(),
      multiplayer: AdvancedPlayMultiplayerConfig.fromJson(multiplayer),
    );
  }

  final bool timerEnabled;
  final bool randomEnabled;
  final int randomDrawCount;
  final bool branchEnabled;
  final bool leaderboardEnabled;
  final String leaderboardMetric;
  final AdvancedPlayMultiplayerConfig multiplayer;

  bool get multiplayerEnabled => multiplayer.enabled;
}

@immutable
class AdvancedPlayDraw {
  const AdvancedPlayDraw({
    required this.id,
    required this.label,
    required this.content,
  });

  factory AdvancedPlayDraw.fromJson(Map<String, Object?> json) =>
      AdvancedPlayDraw(
        id: (json['id'] ?? '').toString(),
        label: (json['label'] ?? '').toString(),
        content: (json['content'] ?? '').toString(),
      );

  final String id;
  final String label;
  final String content;
}

@immutable
class AdvancedPlayBranchOption {
  const AdvancedPlayBranchOption({required this.id, required this.label});

  factory AdvancedPlayBranchOption.fromJson(Map<String, Object?> json) =>
      AdvancedPlayBranchOption(
        id: (json['id'] ?? '').toString(),
        label: (json['label'] ?? '').toString(),
      );

  final String id;
  final String label;
}

@immutable
class AdvancedPlayBranchStep {
  const AdvancedPlayBranchStep({
    required this.id,
    required this.title,
    required this.body,
    required this.terminal,
    required this.options,
  });

  factory AdvancedPlayBranchStep.fromJson(Map<String, Object?> json) =>
      AdvancedPlayBranchStep(
        id: (json['id'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        body: (json['body'] ?? '').toString(),
        terminal: json['terminal'] == true,
        options: _maps(
          json['options'],
        ).map(AdvancedPlayBranchOption.fromJson).toList(growable: false),
      );

  final String id;
  final String title;
  final String body;
  final bool terminal;
  final List<AdvancedPlayBranchOption> options;
}

@immutable
class AdvancedPlayBranch {
  const AdvancedPlayBranch({
    required this.currentStepId,
    required this.currentStep,
  });

  factory AdvancedPlayBranch.fromJson(Map<String, Object?> json) =>
      AdvancedPlayBranch(
        currentStepId: (json['currentStepId'] ?? '').toString(),
        currentStep: json['currentStep'] is Map
            ? AdvancedPlayBranchStep.fromJson(_map(json['currentStep']))
            : null,
      );

  final String currentStepId;
  final AdvancedPlayBranchStep? currentStep;
}

@immutable
class AdvancedPlayState {
  const AdvancedPlayState({
    required this.sessionId,
    required this.activityId,
    required this.topicId,
    required this.nodeId,
    required this.status,
    required this.version,
    required this.score,
    required this.readyForBase,
    required this.deadlineAt,
    required this.mechanics,
    required this.draws,
    required this.branch,
    required this.playKit,
    required this.multiplayer,
    this.present = kAdvancedPlayPresentFullscreen,
  });

  factory AdvancedPlayState.fromJson(Map<String, Object?> json) {
    final int sessionId = _integer(json['sessionId']);
    final int nodeId = _integer(json['nodeId']);
    if (sessionId <= 0 || nodeId <= 0 || json['version'] is! num) {
      throw const FormatException('高级玩法权威状态不完整');
    }
    return AdvancedPlayState(
      sessionId: sessionId,
      activityId: _integer(json['activityId']),
      topicId: _integer(json['topicId']),
      nodeId: nodeId,
      status: (json['status'] ?? 'UNKNOWN').toString(),
      version: _integer(json['version']),
      score: _integer(json['score']),
      readyForBase: json['readyForBase'] == true,
      deadlineAt: _dateFromMillis(json['deadlineAt']),
      mechanics: AdvancedPlayMechanics.fromJson(_map(json['config'])),
      draws: _maps(
        json['draws'],
      ).map(AdvancedPlayDraw.fromJson).toList(growable: false),
      branch: json['branch'] is Map
          ? AdvancedPlayBranch.fromJson(_map(json['branch']))
          : null,
      playKit: Map<String, Object?>.unmodifiable(_map(json['playKit'])),
      multiplayer: AdvancedPlayMultiplayerState.fromJson(
        _map(json['multiplayer']),
      ),
      present: _presentOf(json['present']),
    );
  }

  final int sessionId;
  final int activityId;
  final int topicId;
  final int nodeId;
  final String status;
  final int version;
  final int score;
  final bool readyForBase;
  final DateTime? deadlineAt;
  final AdvancedPlayMechanics mechanics;
  final List<AdvancedPlayDraw> draws;
  final AdvancedPlayBranch? branch;
  final Map<String, Object?> playKit;
  final AdvancedPlayMultiplayerState multiplayer;

  /// 会话视图**根层**的呈现方式(契约 §1.5,真源 `playkit-view.js` 的
  /// `presentOf`)。⚠️ a4-playkit-storyflow 的最小消费面:统一解析层在
  /// a4-playkit-present 线上,合流时以那边为准。
  final String present;

  bool get isInlinePresent => present == kAdvancedPlayPresentInline;

  bool get isRunning => status == 'RUNNING';
  bool get isMultiplayer => mechanics.multiplayerEnabled;
  bool get needsUnavailableStepVerification {
    final Object? raw = playKit['steps'];
    if (raw is! Map) return false;
    return raw['reached'] != true;
  }

  int remainingSeconds(DateTime now) {
    final DateTime? deadline = deadlineAt;
    if (deadline == null) return 0;
    final int milliseconds = deadline.difference(now).inMilliseconds;
    return milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
  }
}

@immutable
class AdvancedPlayLeaderboardRow {
  const AdvancedPlayLeaderboardRow({
    required this.rank,
    required this.ownerId,
    required this.displayName,
    required this.score,
    required this.elapsedSeconds,
    required this.completedUnits,
  });

  factory AdvancedPlayLeaderboardRow.fromJson(Map<String, Object?> json) {
    final int rank = _requiredInteger(json['rank']);
    final int ownerId = _requiredInteger(json['ownerId']);
    final int score = _requiredInteger(json['score'], allowNegative: true);
    final int elapsedSeconds = _requiredInteger(
      json['elapsedSeconds'],
      allowZero: true,
    );
    final int completedUnits = _requiredInteger(
      json['completedUnits'],
      allowZero: true,
    );
    final Object? rawDisplayName = json['displayName'];
    if (rawDisplayName is! String || rawDisplayName.trim().isEmpty) {
      throw const FormatException('排行榜回执不完整');
    }
    return AdvancedPlayLeaderboardRow(
      rank: rank,
      ownerId: ownerId,
      displayName: rawDisplayName,
      score: score,
      elapsedSeconds: elapsedSeconds,
      completedUnits: completedUnits,
    );
  }

  final int rank;
  final int ownerId;
  final String displayName;
  final int score;
  final int elapsedSeconds;
  final int completedUnits;

  String metricValue(String metric) => switch (metric) {
    'ELAPSED_TIME' => '${elapsedSeconds}s',
    'COMPLETED_UNITS' => '$completedUnits',
    _ => '$score',
  };
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map) return <String, Object?>{};
  return value.map<String, Object?>((key, value) => MapEntry('$key', value));
}

/// 会话视图根层 `present` 的取值(契约 §1.5)。
const String kAdvancedPlayPresentInline = 'inline';
const String kAdvancedPlayPresentFullscreen = 'fullscreen';

/// 逐字真源 `utils/playkit-view.js` 的 `presentOf`:只认 inline,其余(含缺失)
/// 一律 fullscreen —— 存量模板行为逐字不变。
String _presentOf(Object? value) => value == kAdvancedPlayPresentInline
    ? kAdvancedPlayPresentInline
    : kAdvancedPlayPresentFullscreen;

List<Map<String, Object?>> _maps(Object? value) =>
    (value is List ? value : const <Object?>[])
        .whereType<Map>()
        .map(_map)
        .toList(growable: false);

int _integer(Object? value) => value is num ? value.toInt() : 0;

int _requiredInteger(
  Object? value, {
  bool allowZero = false,
  bool allowNegative = false,
}) {
  if (value is! num ||
      !value.isFinite ||
      value.truncateToDouble() != value.toDouble()) {
    throw const FormatException('排行榜回执不完整');
  }
  final int result = value.toInt();
  if (allowNegative) return result;
  if (allowZero ? result < 0 : result <= 0) {
    throw const FormatException('排行榜回执不完整');
  }
  return result;
}

DateTime? _dateFromMillis(Object? value) {
  if (value is! num || value.toInt() <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(value.toInt());
}
