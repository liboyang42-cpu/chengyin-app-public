enum GameReceiptOutcome { pending, applied, failed }

class MerchantGameEntry {
  const MerchantGameEntry({
    required this.activityId,
    required this.topicId,
    required this.activityName,
    required this.stationCount,
    this.startAt = '',
    this.endAt = '',
  });

  factory MerchantGameEntry.fromJson(Map<String, dynamic> json) {
    return MerchantGameEntry(
      activityId: _positive(json['activityId']),
      topicId: _positive(json['topicId']),
      activityName: _text(json['activityName']),
      stationCount: _positive(json['stationCount']),
      startAt: _text(json['startAt']),
      endAt: _text(json['endAt']),
    );
  }

  final int activityId;
  final int topicId;
  final String activityName;
  final int stationCount;
  final String startAt;
  final String endAt;
  bool get valid =>
      activityId > 0 &&
      topicId > 0 &&
      activityName.isNotEmpty &&
      stationCount > 0;
}

class GameChecklistItem {
  const GameChecklistItem({
    required this.code,
    required this.label,
    required this.checked,
  });
  final String code;
  final String label;
  final bool checked;
}

class MerchantStationRecap {
  const MerchantStationRecap({
    required this.arrivedPlayers,
    required this.submissionCount,
    required this.approvedCount,
    required this.rejectedCount,
    required this.recordedCount,
    required this.normalCompletedCount,
    required this.fallbackCompletedCount,
    required this.pauseEventCount,
    required this.authorizedContentCount,
  });
  final int arrivedPlayers;
  final int submissionCount;
  final int approvedCount;
  final int rejectedCount;
  final int recordedCount;
  final int normalCompletedCount;
  final int fallbackCompletedCount;
  final int pauseEventCount;
  final int authorizedContentCount;
}

class MerchantGameStation {
  const MerchantGameStation({
    required this.stationId,
    required this.nodeId,
    required this.nodeName,
    required this.stationCode,
    required this.status,
    required this.revision,
    required this.checklist,
    required this.pendingVerificationCount,
    this.merchantInstruction = '',
    this.hiddenInfoReminder = '',
    this.capacity,
    this.serviceStartAt = '',
    this.serviceEndAt = '',
    this.playerTaskPrompt = '',
    this.recap,
    this.playable = false,
  });

  final int stationId;
  final int nodeId;
  final String nodeName;
  final String stationCode;
  final String status;
  final int revision;
  final List<GameChecklistItem> checklist;
  final int pendingVerificationCount;
  final String merchantInstruction;
  final String hiddenInfoReminder;
  final int? capacity;
  final String serviceStartAt;
  final String serviceEndAt;
  final String playerTaskPrompt;
  final MerchantStationRecap? recap;

  /// 服务端说「本站此刻可以接待玩家」。★ 只是其一:
  /// 界面要不要给现场打卡码,还得过 [MerchantGameProjection.allowsLiveCheckin]。
  final bool playable;

  /// 本站备齐了没(容量 / 清单全勾 / 服务时段完整且先后有序)——真源
  /// `utils/game-session-merchant.js:154` 的 `stationConfigured`。
  bool get _configured =>
      (capacity ?? 0) > 0 &&
      checklist.isNotEmpty &&
      checklist.every((item) => item.checked) &&
      _isServiceDateTime(serviceStartAt) &&
      _isServiceDateTime(serviceEndAt) &&
      serviceStartAt.compareTo(serviceEndAt) < 0;

  static final RegExp _serviceDateTime = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2}) (?:[01]\d|2[0-3]):[0-5]\d$',
  );

  /// `YYYY-MM-DD HH:mm`,且那一天真实存在(2031-02-30 不算)。
  static bool _isServiceDateTime(String value) {
    final Match? m = _serviceDateTime.firstMatch(value);
    if (m == null) return false;
    final int year = int.parse(m.group(1)!);
    final int month = int.parse(m.group(2)!);
    final int day = int.parse(m.group(3)!);
    final DateTime date = DateTime.utc(year, month, day);
    return date.year == year && date.month == month && date.day == day;
  }

  String get statusText =>
      const <String, String>{
        'INVITED': '待接受邀请',
        'ACCEPTED': '已接受 · 待准备',
        'READY': '准备完成',
        'ACTIVE': '运行中',
        'PAUSED': '已暂停',
        'CLOSED': '已结束',
      }[status] ??
      '状态异常';
}

class MerchantGameFallback {
  const MerchantGameFallback({
    required this.sourceNodeId,
    required this.planCode,
    required this.planVersion,
    required this.nodeId,
    required this.nodeName,
    required this.playerMessage,
  });
  final int sourceNodeId;
  final String planCode;
  final int planVersion;
  final int nodeId;
  final String nodeName;
  final String playerMessage;
  bool get valid =>
      sourceNodeId > 0 &&
      planCode.isNotEmpty &&
      planVersion > 0 &&
      nodeId > 0 &&
      nodeId != sourceNodeId &&
      nodeName.isNotEmpty &&
      playerMessage.isNotEmpty;
}

class MerchantGameProjection {
  const MerchantGameProjection({
    required this.sessionId,
    required this.activityId,
    required this.status,
    required this.revision,
    required this.availableActions,
    required this.stations,
    this.fallbackOptions = const <MerchantGameFallback>[],
  });

  factory MerchantGameProjection.fromJson(Map<String, dynamic> json) {
    if (_text(json['perspective']).toUpperCase() != 'MERCHANT') {
      throw const FormatException('FORBIDDEN_PROJECTION');
    }
    final merchant = json['merchant'];
    if (merchant is! Map<String, dynamic> || merchant['stations'] is! List) {
      throw const FormatException('INVALID_MERCHANT_VIEW');
    }
    final actions = (json['availableActions'] as List? ?? const <dynamic>[])
        .map((e) => _text(e).toUpperCase())
        .where((e) => RegExp(r'^[A-Z][A-Z0-9_]{2,63}$').hasMatch(e))
        .toSet();
    final rawStations = merchant['stations'] as List;
    if (rawStations.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('INVALID_STATION');
    }
    final stations = rawStations.cast<Map<String, dynamic>>().map((raw) {
      final rawChecklist = raw['preparationChecklist'];
      if (rawChecklist is! List ||
          rawChecklist.any((item) => item is! Map<String, dynamic>)) {
        throw const FormatException('INVALID_CHECKLIST');
      }
      final checklist = rawChecklist
          .cast<Map<String, dynamic>>()
          .map(
            (e) => GameChecklistItem(
              code: _text(e['code']),
              label: _text(e['label']),
              checked: e['checked'] == true,
            ),
          )
          .toList();
      if (checklist.any((item) => item.code.isEmpty || item.label.isEmpty) ||
          checklist.map((item) => item.code).toSet().length !=
              checklist.length) {
        throw const FormatException('INVALID_CHECKLIST');
      }
      final task = raw['playerTask'];
      final recapRaw = raw['recap'];
      MerchantStationRecap? recap;
      if (recapRaw is Map<String, dynamic> &&
          recapRaw['contentPolicy'] == 'NO_PUBLIC_CONTENT') {
        recap = MerchantStationRecap(
          arrivedPlayers: _nonNegative(recapRaw['arrivedPlayers']),
          submissionCount: _nonNegative(recapRaw['submissionCount']),
          approvedCount: _nonNegative(recapRaw['approvedCount']),
          rejectedCount: _nonNegative(recapRaw['rejectedCount']),
          recordedCount: _nonNegative(recapRaw['recordedCount']),
          normalCompletedCount: _nonNegative(recapRaw['normalCompletedCount']),
          fallbackCompletedCount: _nonNegative(
            recapRaw['fallbackCompletedCount'],
          ),
          pauseEventCount: _nonNegative(recapRaw['pauseEventCount']),
          authorizedContentCount: _nonNegative(
            recapRaw['authorizedContentCount'],
          ),
        );
      }
      return MerchantGameStation(
        stationId: _positive(raw['stationId']),
        nodeId: _positive(raw['nodeId']),
        nodeName: _text(raw['nodeName']),
        stationCode: _text(raw['stationCode']),
        status: _text(raw['status']).toUpperCase(),
        revision: _nonNegative(raw['revision']),
        checklist: checklist,
        pendingVerificationCount: _nonNegative(raw['pendingVerificationCount']),
        merchantInstruction: _text(raw['merchantInstruction']),
        hiddenInfoReminder: _text(raw['hiddenInfoReminder']),
        capacity: raw['capacity'] == null
            ? null
            : _nonNegative(raw['capacity']),
        serviceStartAt: _text(raw['serviceStartAt']),
        serviceEndAt: _text(raw['serviceEndAt']),
        playerTaskPrompt: task is Map<String, dynamic>
            ? _text(task['prompt'])
            : '',
        recap: recap,
        playable: raw['playable'] == true,
      );
    }).toList();
    final fallbackOptions =
        (merchant['fallbackOptions'] as List? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(
              (raw) => MerchantGameFallback(
                sourceNodeId: _positive(raw['sourceNodeId']),
                planCode: _text(raw['planCode']).toUpperCase(),
                planVersion: _positive(raw['planVersion']),
                nodeId: _positive(raw['nodeId']),
                nodeName: _text(raw['nodeName']),
                playerMessage: _text(raw['playerMessage']),
              ),
            )
            .toList();
    if (fallbackOptions.any((item) => !item.valid)) {
      throw const FormatException('INVALID_FALLBACK_OPTIONS');
    }
    final projection = MerchantGameProjection(
      sessionId: _positive(json['sessionId']),
      activityId: _positive(json['activityId']),
      status: _text(json['status']).toUpperCase(),
      revision: _nonNegative(json['revision']),
      availableActions: actions,
      stations: stations,
      fallbackOptions: fallbackOptions,
    );
    if (!projection.valid) {
      throw const FormatException('INVALID_MERCHANT_PROJECTION');
    }
    return projection;
  }

  final int sessionId;
  final int activityId;
  final String status;
  final int revision;
  final Set<String> availableActions;
  final List<MerchantGameStation> stations;
  final List<MerchantGameFallback> fallbackOptions;
  String get perspective => 'MERCHANT';

  /// `availableActions` 是整个商家投影的并集，不是每个站点的授权。
  /// 因此动作还必须同时匹配当前局与当前站点状态。
  bool allowsStationAction(String action, MerchantGameStation station) {
    if (!stations.any((item) => item.stationId == station.stationId) ||
        !availableActions.contains(action)) {
      return false;
    }
    return switch (action) {
      'STATION_ACCEPT' || 'STATION_DECLINE' =>
        (status == 'PREPARING' || status == 'READY') &&
            station.status == 'INVITED',
      'STATION_READY' =>
        (status == 'PREPARING' || status == 'READY') &&
            station.status == 'ACCEPTED',
      'STATION_PAUSE' => status == 'RUNNING' && station.status == 'ACTIVE',
      'STATION_RESUME' => status == 'RUNNING' && station.status == 'PAUSED',
      'VERIFY_SUBMISSION' => status == 'RUNNING' && station.status == 'ACTIVE',
      _ => false,
    };
  }

  /// 能不能给商家出示**现场打卡码**(`chapter-node/live-checkin-code`)。
  ///
  /// ★ 不是读服务端的 `playable` 就完事:真源
  ///   `utils/game-session-merchant.js:158` 把这条判据整个重算了一遍 ——
  ///   码是给玩家当场扫的,扫不动 = 现场卡住,所以宁可不给。
  bool allowsLiveCheckin(MerchantGameStation station) =>
      station.playable &&
      station._configured &&
      (station.status == 'READY' || station.status == 'ACTIVE') &&
      (status == 'READY' || status == 'RUNNING');

  bool get valid =>
      sessionId > 0 &&
      activityId > 0 &&
      revision >= 0 &&
      const <String>{
        'PREPARING',
        'READY',
        'RUNNING',
        'FINISHED',
        'CANCELLED',
      }.contains(status) &&
      stations.every(
        (s) =>
            s.stationId > 0 &&
            s.nodeId > 0 &&
            s.revision >= 0 &&
            (s.recap == null ||
                (s.recap!.arrivedPlayers >= 0 &&
                    s.recap!.submissionCount >= 0 &&
                    s.recap!.approvedCount >= 0 &&
                    s.recap!.rejectedCount >= 0 &&
                    s.recap!.recordedCount >= 0 &&
                    s.recap!.normalCompletedCount >= 0 &&
                    s.recap!.fallbackCompletedCount >= 0 &&
                    s.recap!.pauseEventCount >= 0 &&
                    s.recap!.authorizedContentCount == 0)) &&
            const <String>{
              'INVITED',
              'ACCEPTED',
              'READY',
              'ACTIVE',
              'PAUSED',
              'CLOSED',
            }.contains(s.status),
      );
}

class PlayerGameRole {
  const PlayerGameRole({
    required this.code,
    required this.name,
    required this.confirmed,
    required this.publicBrief,
  });
  final String code;
  final String name;
  final bool confirmed;
  final String publicBrief;
}

class PlayerGameChoice {
  const PlayerGameChoice({required this.id, required this.label});
  final String id;
  final String label;
}

class PlayerGameTask {
  const PlayerGameTask({
    required this.taskCode,
    required this.prompt,
    required this.inputType,
    required this.verificationRequired,
    this.completionPolicy = '',
  });
  final String taskCode;
  final String prompt;
  final String inputType;
  final bool verificationRequired;
  final String completionPolicy;
}

class PlayerGameHintText {
  const PlayerGameHintText({required this.level, required this.text});
  final int level;
  final String text;
}

class PlayerGameHint {
  const PlayerGameHint({
    required this.currentLevel,
    required this.revealedTexts,
    required this.nextLevel,
    required this.nextImpactLabel,
    required this.revealAvailable,
    required this.revealImpactLabel,
  });
  final int currentLevel;
  final List<PlayerGameHintText> revealedTexts;
  final int? nextLevel;
  final String nextImpactLabel;
  final bool revealAvailable;
  final String revealImpactLabel;
}

class PlayerGameFallback {
  const PlayerGameFallback({
    required this.planCode,
    required this.planVersion,
    required this.targetNodeId,
    required this.targetNodeName,
    required this.playerMessage,
  });

  final String planCode;
  final int planVersion;
  final int targetNodeId;
  final String targetNodeName;
  final String playerMessage;
}

/// 暂停节点对玩家的对外安排(原因 / 预计恢复)。两项都空就不带这一块 ——
/// 不渲染一个「原因：」后面什么都没有的空壳(小程序 normalizePause 同判据)。
class PlayerGamePause {
  const PlayerGamePause({
    required this.reasonCode,
    required this.reason,
    required this.resumeEta,
  });
  final String reasonCode;
  final String reason;
  final String resumeEta;
}

class PlayerGameSubmission {
  const PlayerGameSubmission({
    required this.submissionId,
    required this.nodeId,
    required this.taskCode,
    required this.status,
    this.decisionReasonCode = '',
    this.decisionReason = '',
  });

  final int submissionId;
  final int nodeId;
  final String taskCode;
  final String status;
  final String decisionReasonCode;
  final String decisionReason;

  String get statusLabel =>
      const <String, String>{
        'PENDING': '待商家核验',
        'APPROVED': '本站已通过',
        'REJECTED': '商家已驳回，可重新提交',
        'RECORDED': '证据已记录',
      }[status] ??
      '核验状态待同步';
}

class PlayerGameTeamAction {
  const PlayerGameTeamAction({
    required this.memberId,
    required this.displayName,
    required this.roleCode,
    required this.status,
  });

  final int memberId;
  final String displayName;
  final String roleCode;
  final String status;

  String get statusLabel =>
      const <String, String>{
        'JOINED': '待分配',
        'ASSIGNED': '待确认身份',
        'CONFIRMED': '身份已确认',
        'IN_PROGRESS': '行动中',
        'SUBMITTED': '等待核验',
        'COMPLETED': '已完成',
        'FALLBACK_COMPLETED': '已通过兜底完成',
      }[status] ??
      '待确认身份';
}

class PlayerGameLeaderboardEntry {
  const PlayerGameLeaderboardEntry({
    required this.rank,
    required this.teamId,
    required this.displayName,
    required this.score,
  });

  final int rank;
  final int teamId;
  final String displayName;
  final int score;
}

class PlayerGameLeaderboard {
  const PlayerGameLeaderboard({required this.entries});
  final List<PlayerGameLeaderboardEntry> entries;
}

class PlayerGameNode {
  const PlayerGameNode({
    required this.nodeId,
    required this.nodeName,
    required this.status,
    required this.stationStatus,
    required this.clue,
    required this.choices,
    this.task,
    this.hint,
    this.fallback,
    this.pause,
    this.submission,
    this.completionStatus = '',
    this.completionSource = '',
  });
  final int nodeId;
  final String nodeName;
  final String status;
  final String stationStatus;
  final String clue;
  final PlayerGameTask? task;
  final PlayerGameHint? hint;
  final PlayerGameFallback? fallback;
  final PlayerGamePause? pause;
  final PlayerGameSubmission? submission;
  final String completionStatus;
  final String completionSource;
  final List<PlayerGameChoice> choices;
}

class PlayerGameEnding {
  const PlayerGameEnding({
    required this.code,
    required this.title,
    required this.summary,
  });
  final String code;
  final String title;
  final String summary;
}

class PlayerGameProjection {
  const PlayerGameProjection({
    required this.snapshotAt,
    required this.sessionId,
    required this.activityId,
    required this.status,
    required this.revision,
    required this.teamId,
    required this.role,
    required this.availableActions,
    required this.nodes,
    required this.visibleVariables,
    this.teamActions = const <PlayerGameTeamAction>[],
    this.leaderboard,
    this.ending,
  });

  factory PlayerGameProjection.fromJson(Map<String, dynamic> json) {
    if (_text(json['perspective']).toUpperCase() != 'PLAYER') {
      throw const FormatException('FORBIDDEN_PROJECTION');
    }
    final player = json['player'];
    if (player is! Map<String, dynamic>) {
      throw const FormatException('INVALID_PLAYER_VIEW');
    }
    final rawRole = player['role'];
    if (rawRole is! Map<String, dynamic>) {
      throw const FormatException('INVALID_PLAYER_ROLE');
    }
    final role = PlayerGameRole(
      code: _boundedText(rawRole['code'], 64),
      name: _boundedText(rawRole['name'], 80),
      confirmed:
          rawRole['confirmed'] == true ||
          _text(rawRole['status']).toUpperCase() == 'CONFIRMED',
      publicBrief: _boundedText(rawRole['publicBrief'], 500),
    );
    final rawNodes = player['nodes'];
    if (rawNodes is! List ||
        rawNodes.any((Object? value) => value is! Map<String, dynamic>)) {
      throw const FormatException('INVALID_PLAYER_NODES');
    }
    final submissions = _playerSubmissions(player['mySubmissions']);
    final submissionsByNode = <int, PlayerGameSubmission>{
      for (final PlayerGameSubmission item in submissions) item.nodeId: item,
    };
    final nodes = rawNodes
        .cast<Map<String, dynamic>>()
        .map(
          (Map<String, dynamic> raw) => _playerNode(
            raw,
            submission: submissionsByNode[_positive(raw['nodeId'])],
          ),
        )
        .toList();
    if (nodes.any((node) => node.nodeId <= 0)) {
      throw const FormatException('INVALID_PLAYER_NODE');
    }
    final story = player['story'];
    final storyMap = story is Map<String, dynamic>
        ? story
        : const <String, dynamic>{};
    final rawVariables = storyMap['visibleVariables'];
    final variables = rawVariables is Map
        ? Map<String, Object?>.unmodifiable(
            rawVariables.map((key, value) => MapEntry('$key', _scalar(value))),
          )
        : const <String, Object?>{};
    final rawEnding = storyMap['ending'];
    PlayerGameEnding? ending;
    if (rawEnding is Map<String, dynamic>) {
      final value = PlayerGameEnding(
        code: _boundedText(rawEnding['code'], 64),
        title: _boundedText(rawEnding['title'], 160),
        summary: _boundedText(rawEnding['summary'], 1200).isNotEmpty
            ? _boundedText(rawEnding['summary'], 1200)
            : _boundedText(rawEnding['text'], 1200),
      );
      if (value.code.isNotEmpty && value.title.isNotEmpty) ending = value;
    }
    final projection = PlayerGameProjection(
      snapshotAt: _snapshotText(json['snapshotAt']),
      sessionId: _positive(json['sessionId']),
      activityId: _positive(json['activityId']),
      status: _text(json['status']).toUpperCase(),
      revision: _nonNegative(json['revision']),
      teamId: _positive(player['teamId']),
      role: role,
      availableActions: (json['availableActions'] as List? ?? const <dynamic>[])
          .map((value) => _text(value).toUpperCase())
          .where(_playerActionSet.contains)
          .toSet(),
      nodes: nodes,
      visibleVariables: variables,
      teamActions: _playerTeamActions(player['teamActions']),
      leaderboard: _playerLeaderboard(player['leaderboard']),
      ending: ending,
    );
    if (projection.sessionId <= 0 ||
        projection.activityId <= 0 ||
        projection.teamId <= 0 ||
        projection.revision < 0 ||
        !const <String>{
          'PREPARING',
          'READY',
          'RUNNING',
          'FINISHED',
          'CANCELLED',
        }.contains(projection.status)) {
      throw const FormatException('INVALID_PLAYER_PROJECTION');
    }
    return projection;
  }

  /// 这份投影是什么时候的服务端快照(`yyyy-MM-dd HH:mm:ss`);形状不对就是空串。
  final String snapshotAt;
  final int sessionId;
  final int activityId;
  final String status;
  final int revision;
  final int teamId;
  final PlayerGameRole role;
  final Set<String> availableActions;
  final List<PlayerGameNode> nodes;
  final Map<String, Object?> visibleVariables;
  final List<PlayerGameTeamAction> teamActions;
  final PlayerGameLeaderboard? leaderboard;
  final PlayerGameEnding? ending;
  String get perspective => 'PLAYER';
}

PlayerGameNode _playerNode(
  Map<String, dynamic> raw, {
  PlayerGameSubmission? submission,
}) {
  final rawTask = raw['playerTask'];
  PlayerGameTask? task;
  if (rawTask is Map<String, dynamic>) {
    final candidate = PlayerGameTask(
      taskCode: _boundedText(rawTask['taskCode'], 64),
      prompt: _boundedText(rawTask['prompt'], 500),
      inputType: _text(rawTask['inputType']).toUpperCase(),
      verificationRequired: rawTask['verificationRequired'] == true,
      completionPolicy: _text(rawTask['completionPolicy']).toUpperCase(),
    );
    if (candidate.taskCode.isNotEmpty &&
        candidate.prompt.isNotEmpty &&
        const <String>{'TEXT', 'SCAN', 'PHOTO'}.contains(candidate.inputType)) {
      task = candidate;
    }
  }
  final rawHint = raw['hint'];
  PlayerGameHint? hint;
  if (rawHint is Map<String, dynamic>) {
    final current = _nonNegative(rawHint['currentLevel']).clamp(0, 2);
    final texts = (rawHint['revealedTexts'] as List? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(
          (value) => PlayerGameHintText(
            level: _positive(value['level']),
            text: _boundedText(value['text'], 1200),
          ),
        )
        .where((value) => value.level <= current && value.text.isNotEmpty)
        .toList();
    final next = _positive(rawHint['nextLevel']);
    final nextImpactLabel = _boundedText(rawHint['nextImpactLabel'], 160);
    final revealImpactLabel = _boundedText(rawHint['revealImpactLabel'], 200);
    hint = PlayerGameHint(
      currentLevel: current,
      revealedTexts: texts,
      nextLevel: next == current + 1 && next <= 2 && nextImpactLabel.isNotEmpty
          ? next
          : null,
      nextImpactLabel: nextImpactLabel,
      revealAvailable:
          rawHint['revealAvailable'] == true && revealImpactLabel.isNotEmpty,
      revealImpactLabel: revealImpactLabel,
    );
  }
  final choices = (raw['allowedChoices'] as List? ?? const <dynamic>[])
      .whereType<Map<String, dynamic>>()
      .map(
        (value) => PlayerGameChoice(
          id: _boundedText(value['id'], 64),
          label: _boundedText(value['label'], 160),
        ),
      )
      .where((value) => value.id.isNotEmpty && value.label.isNotEmpty)
      .toList();
  PlayerGameFallback? fallback;
  final Object? rawFallback = raw['fallback'];
  if (_text(raw['personalState']).toUpperCase() == 'PAUSED' &&
      rawFallback is Map<String, dynamic>) {
    final PlayerGameFallback candidate = PlayerGameFallback(
      planCode: _boundedText(rawFallback['planCode'], 64).toUpperCase(),
      planVersion: _positive(rawFallback['planVersion']),
      targetNodeId: _positive(rawFallback['targetNodeId']),
      targetNodeName: _boundedText(rawFallback['targetNodeName'], 120),
      playerMessage: _boundedText(rawFallback['playerMessage'], 200),
    );
    if (RegExp(r'^[A-Z][A-Z0-9_]{1,63}$').hasMatch(candidate.planCode) &&
        candidate.planVersion > 0 &&
        candidate.targetNodeId > 0 &&
        candidate.targetNodeName.isNotEmpty &&
        candidate.playerMessage.isNotEmpty) {
      fallback = candidate;
    }
  }
  PlayerGamePause? pause;
  final Object? rawPause = raw['pause'];
  if (_text(raw['personalState']).toUpperCase() == 'PAUSED' &&
      rawPause is Map<String, dynamic>) {
    final PlayerGamePause candidate = PlayerGamePause(
      reasonCode: _boundedText(rawPause['reasonCode'], 40).toUpperCase(),
      reason: _boundedText(rawPause['reason'], 200),
      resumeEta: _boundedText(rawPause['resumeEta'], 64),
    );
    if (candidate.reason.isNotEmpty || candidate.resumeEta.isNotEmpty) {
      pause = candidate;
    }
  }
  return PlayerGameNode(
    nodeId: _positive(raw['nodeId']),
    nodeName: _boundedText(raw['nodeName'], 120),
    status: _text(raw['personalState']).toUpperCase(),
    stationStatus: _text(raw['stationStatus'] ?? raw['status']).toUpperCase(),
    clue: _boundedText(raw['clue'], 1200),
    task: task,
    hint: hint,
    fallback: fallback,
    pause: pause,
    submission: submission,
    completionStatus: _text(raw['completionStatus']).toUpperCase(),
    completionSource: _boundedText(raw['completionSource'], 64).toUpperCase(),
    choices: choices,
  );
}

List<PlayerGameSubmission> _playerSubmissions(Object? value) {
  const Set<String> statuses = <String>{
    'PENDING',
    'APPROVED',
    'REJECTED',
    'RECORDED',
  };
  return (value is List ? value : const <dynamic>[])
      .whereType<Map<String, dynamic>>()
      .map((Map<String, dynamic> raw) {
        final String status = _text(raw['status']).toUpperCase();
        return PlayerGameSubmission(
          submissionId: _positive(raw['submissionId']),
          nodeId: _positive(raw['nodeId']),
          taskCode: _boundedText(raw['taskCode'], 64),
          status: statuses.contains(status) ? status : '',
          decisionReasonCode: status == 'REJECTED'
              ? _boundedText(raw['reasonCode'] ?? raw['decisionReasonCode'], 64)
              : '',
          decisionReason: status == 'REJECTED'
              ? _boundedText(raw['reason'] ?? raw['decisionReason'], 300)
              : '',
        );
      })
      .where(
        (PlayerGameSubmission item) =>
            item.submissionId > 0 &&
            item.nodeId > 0 &&
            item.taskCode.isNotEmpty &&
            item.status.isNotEmpty,
      )
      .toList(growable: false);
}

List<PlayerGameTeamAction> _playerTeamActions(Object? value) {
  const Set<String> statuses = <String>{
    'JOINED',
    'ASSIGNED',
    'CONFIRMED',
    'IN_PROGRESS',
    'SUBMITTED',
    'COMPLETED',
    'FALLBACK_COMPLETED',
  };
  return (value is List ? value : const <dynamic>[])
      .whereType<Map<String, dynamic>>()
      .map((Map<String, dynamic> raw) {
        final String status = _text(raw['status']).toUpperCase();
        return PlayerGameTeamAction(
          memberId: _positive(raw['memberId']),
          displayName: _boundedText(raw['displayName'], 80),
          roleCode: _boundedText(raw['roleCode'], 64),
          status: statuses.contains(status) ? status : 'ASSIGNED',
        );
      })
      .where((PlayerGameTeamAction item) => item.memberId > 0)
      .toList(growable: false);
}

PlayerGameLeaderboard? _playerLeaderboard(Object? value) {
  if (value is! Map<String, dynamic> || value['visible'] != true) return null;
  final List<PlayerGameLeaderboardEntry> entries =
      (value['entries'] is List ? value['entries'] as List : const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(
            (Map<String, dynamic> raw) => PlayerGameLeaderboardEntry(
              rank: _positive(raw['rank']),
              teamId: _positive(raw['teamId']),
              displayName: _boundedText(raw['displayName'], 80),
              score: _nonNegative(raw['score']),
            ),
          )
          .where(
            (PlayerGameLeaderboardEntry item) =>
                item.rank > 0 && item.teamId > 0 && item.score >= 0,
          )
          .toList(growable: false);
  return PlayerGameLeaderboard(entries: entries);
}

const Set<String> _playerActionSet = <String>{
  'CONFIRM_ROLE',
  'PLAYER_CHOICE',
  'PLAYER_SUBMIT',
  'PLAYER_HINT',
  'PLAYER_REVEAL',
};

/// 导演台(俱乐部视角)的写动作 —— 小程序 `director.js` executeAction 的调用面。
/// 其中暂停/恢复两条是 CLUB_ 前缀的俱乐部专用词:商家那三个词的实现写死了
/// 「站点属于当前商家」,俱乐部走进去必然被拒(真源注释原话)。
const Set<String> clubDirectorActions = <String>{
  'PREPARE',
  'START',
  'FINISH',
  'ASSIGN_ROLES',
  'TAKEOVER_ROLE',
  'BROADCAST',
  'UNLOCK_CHAPTER',
  'SET_LEADERBOARD_VISIBILITY',
  'CLUB_STATION_PAUSE',
  'CLUB_STATION_RESUME',
  'CLUB_REJECT_SUBMISSION',
};

/// 俱乐部动作里唯二挂在具体站点上的(其余动作整局为对象,nodeId 必须为空)。
const Set<String> clubDirectorNodeActions = <String>{
  'CLUB_STATION_PAUSE',
  'CLUB_STATION_RESUME',
};

class GameSessionCommand {
  GameSessionCommand({
    required this.activityId,
    required this.nodeId,
    required this.requestId,
    required this.expectedRevision,
    required this.action,
    required this.payload,
  }) {
    if (activityId <= 0 ||
        (nodeId != null && nodeId! <= 0) ||
        expectedRevision < 0 ||
        !RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(requestId) ||
        !const <String>{
          'STATION_ACCEPT',
          'STATION_DECLINE',
          'STATION_READY',
          'STATION_PAUSE',
          'STATION_RESUME',
          'VERIFY_SUBMISSION',
          ..._playerActionSet,
          ...clubDirectorActions,
        }.contains(action)) {
      throw const FormatException('INVALID_GAME_COMMAND');
    }
    // nodeId 的有无按动作族判:玩家除 CONFIRM_ROLE 外都挂站点;俱乐部除
    // 暂停/恢复外都整局为对象;商家一律挂站点。
    final bool requiresNode =
        action != 'CONFIRM_ROLE' && !clubDirectorActions.contains(action) ||
        clubDirectorNodeActions.contains(action);
    if (requiresNode != (nodeId != null)) {
      throw const FormatException('INVALID_GAME_COMMAND');
    }
    _validatePlayerPayload(action, payload);
    _validateClubPayload(action, payload);
  }

  factory GameSessionCommand.playerConfirmRole({
    required int activityId,
    required String requestId,
    required int expectedRevision,
  }) => GameSessionCommand(
    activityId: activityId,
    nodeId: null,
    requestId: requestId,
    expectedRevision: expectedRevision,
    action: 'CONFIRM_ROLE',
    payload: const <String, dynamic>{},
  );

  factory GameSessionCommand.playerSubmit({
    required int activityId,
    required int nodeId,
    required String requestId,
    required int expectedRevision,
    required String taskCode,
    required List<String> evidenceUrls,
  }) => GameSessionCommand(
    activityId: activityId,
    nodeId: nodeId,
    requestId: requestId,
    expectedRevision: expectedRevision,
    action: 'PLAYER_SUBMIT',
    payload: <String, dynamic>{
      'taskCode': taskCode,
      'evidenceUrls': evidenceUrls,
    },
  );

  factory GameSessionCommand.playerHint({
    required int activityId,
    required int nodeId,
    required String requestId,
    required int expectedRevision,
    required int level,
  }) => GameSessionCommand(
    activityId: activityId,
    nodeId: nodeId,
    requestId: requestId,
    expectedRevision: expectedRevision,
    action: 'PLAYER_HINT',
    payload: <String, dynamic>{'level': level},
  );

  factory GameSessionCommand.playerReveal({
    required int activityId,
    required int nodeId,
    required String requestId,
    required int expectedRevision,
  }) => GameSessionCommand(
    activityId: activityId,
    nodeId: nodeId,
    requestId: requestId,
    expectedRevision: expectedRevision,
    action: 'PLAYER_REVEAL',
    payload: const <String, dynamic>{},
  );

  factory GameSessionCommand.playerChoice({
    required int activityId,
    required int nodeId,
    required String requestId,
    required int expectedRevision,
    required String choiceId,
  }) => GameSessionCommand(
    activityId: activityId,
    nodeId: nodeId,
    requestId: requestId,
    expectedRevision: expectedRevision,
    action: 'PLAYER_CHOICE',
    payload: <String, dynamic>{'choiceId': choiceId},
  );
  final int activityId;
  final int? nodeId;
  final String requestId;
  final int expectedRevision;
  final String action;
  final Map<String, dynamic> payload;
  Map<String, dynamic> toJson() => <String, dynamic>{
    'activityId': activityId,
    'nodeId': nodeId,
    'requestId': requestId,
    'expectedRevision': expectedRevision,
    'action': action,
    'payload': payload,
  };
}

/// 俱乐部视角的一局里「复盘导出」这一块要用的两个事实。
///
/// ⚠️ 只取这两个。完整的俱乐部投影在 `club_director.dart`
///   (`ClubDirectorProjection`),复盘正文(漏斗 / 节点完成 / 榜单)仍归 4-C。
///   缺的字段宁可没有,不拿 0/空串兜底 ——
///   与 `club_topic_ops.dart` 同一条形状纪律。
class ClubRecapState {
  const ClubRecapState({
    required this.recapAvailable,
    required this.exportAvailable,
  });

  /// 服务端下发了 `recap`(= 复盘已生成)。false 时页面原样写
  /// 「复盘尚未生成,不会把缺失指标显示为零。」。
  final bool recapAvailable;

  /// `recap.exportAvailable === true` —— 导出按钮的唯一闸。
  final bool exportAvailable;
}

const String _recapExportSchema = 'GAME_RECAP_EXPORT_V1';
const String _recapSchema = 'GAME_RECAP_V1';

/// 真源 `utils/game-session-client.js` 的 `normalizeClubRecapExport`:把服务端
/// 下发的导出收敛成**进剪贴板的那一份** —— 白名单字段 + 真源同款顺序。
///
/// 任一处不合格返回 null,调用方换成「复盘导出数据无效」(真源同一句)。
/// 为什么不是原样透传:小程序 `copyRecap` 复制的是 normalize 之后的结构,
/// 白名单本身是一道隐私闸(小程序契约用例断言导出里不许出现
/// phone / memberId / evidence 之类),后端将来多下发一个字段不该跟着进剪贴板。
Map<String, dynamic>? normalizeClubRecapExport(
  Object? raw, {
  required int activityId,
}) {
  if (raw is! Map<String, dynamic>) return null;
  final int? rawActivityId = _safeInteger(raw['activityId']);
  final int sessionId = _positive(raw['sessionId']);
  final String generatedAt = _text(raw['generatedAt']);
  final Map<String, dynamic>? recap = _normalizeClubRecap(raw['recap']);
  if (_text(raw['schemaVersion']) != _recapExportSchema ||
      rawActivityId != activityId ||
      sessionId <= 0 ||
      !_secondPrecision(generatedAt) ||
      recap == null) {
    return null;
  }
  return <String, dynamic>{
    'schemaVersion': _recapExportSchema,
    'generatedAt': generatedAt,
    'activityId': rawActivityId,
    'sessionId': sessionId,
    'recap': recap,
  };
}

class GameSessionReceipt {
  const GameSessionReceipt({
    required this.activityId,
    required this.requestId,
    required this.action,
    required this.outcome,
    required this.receiptId,
    required this.revision,
    this.result = const <String, dynamic>{},
  });
  final int activityId;
  final String requestId;
  final String action;
  final GameReceiptOutcome outcome;
  final String receiptId;
  final int revision;
  final Map<String, dynamic> result;
}

void _validatePlayerPayload(String action, Map<String, dynamic> payload) {
  if (!_playerActionSet.contains(action)) return;
  switch (action) {
    case 'CONFIRM_ROLE':
    case 'PLAYER_REVEAL':
      if (payload.isNotEmpty) {
        throw const FormatException('INVALID_GAME_COMMAND');
      }
      return;
    case 'PLAYER_CHOICE':
      if (_boundedText(payload['choiceId'], 64).isEmpty) {
        throw const FormatException('INVALID_GAME_COMMAND');
      }
      return;
    case 'PLAYER_HINT':
      final level = payload['level'];
      if (level is! int || level < 1 || level > 2) {
        throw const FormatException('INVALID_GAME_COMMAND');
      }
      return;
    case 'PLAYER_SUBMIT':
      if (_boundedText(payload['taskCode'], 64).isEmpty ||
          payload['evidenceUrls'] is! List<String>) {
        throw const FormatException('INVALID_GAME_COMMAND');
      }
      final evidence = payload['evidenceUrls'] as List<String>;
      if (evidence.isEmpty ||
          evidence.length > 6 ||
          evidence.any((value) => !_evidenceValid(value))) {
        throw const FormatException('INVALID_GAME_COMMAND');
      }
      return;
  }
}

bool _evidenceValid(String value) {
  final evidence = value.trim();
  if (evidence.isEmpty ||
      evidence.length > 512 ||
      RegExp(r'[\x00-\x1F\x7F]').hasMatch(evidence)) {
    return false;
  }
  if (evidence.startsWith('text:') || evidence.startsWith('scan:')) {
    final encoded = evidence.substring(5);
    try {
      final decoded = Uri.decodeComponent(encoded);
      return decoded.trim().isNotEmpty &&
          decoded.length <= (evidence.startsWith('text:') ? 300 : 256) &&
          Uri.encodeComponent(decoded) == encoded;
    } on FormatException {
      return false;
    }
  }
  final uri = Uri.tryParse(evidence);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.host.isNotEmpty &&
      RegExp(r'\.(?:jpe?g|png|webp)$', caseSensitive: false).hasMatch(uri.path);
}

int _positive(Object? value) {
  final int? n = _safeInteger(value);
  return n != null && n > 0 ? n : 0;
}

int _nonNegative(Object? value) {
  final int? n = _safeInteger(value);
  return n != null && n >= 0 ? n : -1;
}

int? _safeInteger(Object? value) {
  const int maxSafeInteger = 9007199254740991;
  return value is int && value.abs() <= maxSafeInteger ? value : null;
}

String _text(Object? value) => value is String ? value.trim() : '';

/// 服务端快照时间:只认 `yyyy-MM-dd HH:mm:ss` 且日历合法 —— 乱码时间宁可不显示,
/// 不把「状态更新于」写成一句假话(小程序 safeSnapshotAt 同判据)。
String _snapshotText(Object? value) {
  if (value is! String) return '';
  final String text = value.trim();
  final RegExpMatch? match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$',
  ).firstMatch(text);
  if (match == null) return '';
  final int year = int.parse(match[1]!);
  final int month = int.parse(match[2]!);
  final int day = int.parse(match[3]!);
  final int hour = int.parse(match[4]!);
  final int minute = int.parse(match[5]!);
  final int second = int.parse(match[6]!);
  if (year < 1000 ||
      month < 1 ||
      month > 12 ||
      day < 1 ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return '';
  }
  final DateTime parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return '';
  }
  return text;
}

String _boundedText(Object? value, int maxLength) {
  final text = _text(value);
  return text.length <= maxLength ? text : '';
}

Object? _scalar(Object? value) =>
    value is bool || value is num || value is String ? value : null;

int? _clubPositiveId(Object? value) {
  final int? id = _safeInteger(value);
  return id != null && id > 0 ? id : null;
}

/// 俱乐部写动作的 payload 闸 —— 与 `director.js` 各 confirm* 里的前端守卫
/// 同一条:不合法的写根本不该发出去(发出去也只会被后端拒回一个读不懂的错)。
void _validateClubPayload(String action, Map<String, dynamic> payload) {
  if (!clubDirectorActions.contains(action)) return;
  const invalid = FormatException('INVALID_GAME_COMMAND');
  switch (action) {
    case 'PREPARE':
    case 'START':
    case 'FINISH':
    case 'CLUB_STATION_RESUME':
      if (payload.isNotEmpty) throw invalid;
      return;
    case 'ASSIGN_ROLES':
      if (_clubPositiveId(payload['teamId']) == null) throw invalid;
      final Object? assignments = payload['assignments'];
      if (assignments is! List || assignments.isEmpty) throw invalid;
      for (final Object? item in assignments) {
        if (item is! Map) throw invalid;
        if (_clubPositiveId(item['memberId']) == null) throw invalid;
        if (_boundedText(item['roleCode'], 64).isEmpty) throw invalid;
      }
      return;
    case 'TAKEOVER_ROLE':
      final int? teamId = _clubPositiveId(payload['teamId']);
      final int? source = _clubPositiveId(payload['sourceMemberId']);
      final int? target = _clubPositiveId(payload['targetMemberId']);
      final String reason = _boundedText(payload['reason'], 200);
      if (teamId == null ||
          source == null ||
          target == null ||
          source == target ||
          reason.isEmpty) {
        throw invalid;
      }
      return;
    case 'BROADCAST':
      final String targetType = _text(payload['targetType']);
      if (!const <String>{'ALL', 'TEAM', 'ROLE'}.contains(targetType)) {
        throw invalid;
      }
      if (_boundedText(payload['content'], 200).isEmpty) throw invalid;
      if (targetType == 'TEAM' &&
          _clubPositiveId(payload['targetId']) == null) {
        throw invalid;
      }
      if (targetType == 'ROLE' &&
          _boundedText(payload['roleCode'], 64).isEmpty) {
        throw invalid;
      }
      return;
    case 'UNLOCK_CHAPTER':
      if (_clubPositiveId(payload['chapterId']) == null ||
          _boundedText(payload['reason'], 200).isEmpty) {
        throw invalid;
      }
      return;
    case 'SET_LEADERBOARD_VISIBILITY':
      if (payload['visible'] is! bool) throw invalid;
      return;
    case 'CLUB_STATION_PAUSE':
      final String reason = _text(payload['reason']);
      if (_boundedText(payload['reasonCode'], 64).isEmpty ||
          reason.length < 2 ||
          _text(payload['resumeEta']).isEmpty) {
        throw invalid;
      }
      final Object? planCode = payload['fallbackPlanCode'];
      if (planCode != null &&
          (_boundedText(planCode, 64).isEmpty ||
              _clubPositiveId(payload['fallbackPlanVersion']) == null)) {
        throw invalid;
      }
      return;
    case 'CLUB_REJECT_SUBMISSION':
      final String reason = _text(payload['reason']);
      if (_clubPositiveId(payload['submissionId']) == null ||
          _boundedText(payload['reasonCode'], 64).isEmpty ||
          reason.length < 2) {
        throw invalid;
      }
      return;
  }
}

Map<String, dynamic>? _normalizeClubRecap(Object? raw) {
  if (raw is! Map<String, dynamic>) return null;
  final String schemaVersion = _text(raw['schemaVersion']);
  final String generatedAt = _text(raw['generatedAt']);
  final Object? exportAvailable = raw['exportAvailable'];
  final Object? metrics = raw['metrics'];
  final Object? stations = raw['stations'];
  if (schemaVersion != _recapSchema ||
      !_secondPrecision(generatedAt) ||
      exportAvailable is! bool ||
      metrics is! List ||
      stations is! List) {
    return null;
  }
  final List<Map<String, dynamic>>? normalizedMetrics = _recapMetrics(metrics);
  final List<Map<String, dynamic>>? normalizedStations = _recapStations(
    stations,
  );
  final Map<String, dynamic>? funnel =
      _integerFields(raw['funnel'], const <String>[
        'paidPlayers',
        'arrivedPlayers',
        'taskSubmitters',
        'normalCompleters',
        'fallbackCompleters',
        'finishedTeams',
      ]);
  final Map<String, dynamic>? hints = _integerFields(
    raw['hints'],
    const <String>['level1Uses', 'level2Uses', 'answerReveals'],
  );
  final Map<String, dynamic>? incidents =
      _integerFields(raw['incidents'], const <String>[
        'merchantPauseEvents',
        'merchantFallbackCompletions',
        'playerRejectedSubmissions',
      ]);
  final Map<String, dynamic>? collaboration = _integerFields(
    raw['collaboration'],
    const <String>['eligibleTeams', 'completedTeams', 'ratePercent'],
  );
  final Map<String, dynamic>? takeovers = _integerFields(
    raw['takeovers'],
    const <String>['count'],
  );
  if (normalizedMetrics == null ||
      normalizedStations == null ||
      funnel == null ||
      hints == null ||
      incidents == null ||
      collaboration == null ||
      takeovers == null) {
    return null;
  }
  if ((collaboration['ratePercent'] as int) > 100 ||
      (collaboration['completedTeams'] as int) >
          (collaboration['eligibleTeams'] as int)) {
    return null;
  }
  return <String, dynamic>{
    'schemaVersion': _recapSchema,
    'generatedAt': generatedAt,
    'metrics': normalizedMetrics,
    'funnel': funnel,
    'hints': hints,
    'incidents': incidents,
    'collaboration': collaboration,
    'takeovers': takeovers,
    'stations': normalizedStations,
    'exportAvailable': exportAvailable,
  };
}

List<Map<String, dynamic>>? _recapMetrics(List<Object?> raw) {
  final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
  final Set<String> keys = <String>{};
  for (final Object? item in raw) {
    if (item is! Map<String, dynamic>) return null;
    final String key = _text(item['key']).toUpperCase();
    final String label = _boundedText(item['label'], 120);
    final int value = _nonNegative(item['value']);
    final String? unit = _optionalText(item['unit'], 32);
    if (!RegExp(r'^[A-Z][A-Z0-9_]{1,63}$').hasMatch(key) ||
        label.isEmpty ||
        value < 0 ||
        unit == null ||
        !keys.add(key)) {
      return null;
    }
    out.add(<String, dynamic>{
      'key': key,
      'label': label,
      'value': value,
      'unit': unit,
    });
  }
  return out;
}

List<Map<String, dynamic>>? _recapStations(List<Object?> raw) {
  final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
  final Set<int> nodeIds = <int>{};
  for (final Object? item in raw) {
    if (item is! Map<String, dynamic>) return null;
    final int nodeId = _positive(item['nodeId']);
    final String nodeName = _boundedText(item['nodeName'], 120);
    final Map<String, dynamic>? counts = _integerFields(item, const <String>[
      'arrivedPlayers',
      'submissionCount',
      'normalCompletedCount',
      'fallbackCompletedCount',
      'rejectedCount',
      'pauseEventCount',
    ]);
    if (nodeId <= 0 ||
        nodeName.isEmpty ||
        counts == null ||
        !nodeIds.add(nodeId)) {
      return null;
    }
    out.add(<String, dynamic>{
      'nodeId': nodeId,
      'nodeName': nodeName,
      ...counts,
    });
  }
  return out;
}

Map<String, dynamic>? _integerFields(Object? raw, List<String> fields) {
  if (raw is! Map<String, dynamic>) return null;
  final Map<String, dynamic> out = <String, dynamic>{};
  for (final String field in fields) {
    final int value = _nonNegative(raw[field]);
    if (value < 0) return null;
    out[field] = value;
  }
  return out;
}

/// 真源 `safeOptionalText`:必须是字符串;可空串,超长算不合格。
String? _optionalText(Object? value, int maxLength) {
  if (value is! String) return null;
  final String text = value.trim();
  return text.length <= maxLength ? text : null;
}

/// 真源 `validDateTimeSeconds`:秒级时刻且日期真实存在(2 月 30 日不算)。
bool _secondPrecision(String value) {
  final Match? match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2}) ([01]\d|2[0-3]):([0-5]\d):([0-5]\d)$',
  ).firstMatch(value);
  if (match == null) return false;
  final int year = int.parse(match.group(1)!);
  final int month = int.parse(match.group(2)!);
  final int day = int.parse(match.group(3)!);
  final DateTime date = DateTime.utc(year, month, day);
  return date.year == year && date.month == month && date.day == day;
}
