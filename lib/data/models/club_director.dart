/// 俱乐部 · 导演台(4-C)的投影模型。
/// 逐条对齐小程序真源 `utils/club-game-director-adapter.js` 的
/// `normalizeClubProjection` 与 `pages/club/topic-detail/director.js` 的行投影
/// (stationView / teamView / roleView / broadcastView / incidentRows / 广播人数)。
///
/// 形状纪律与 `club_topic_ops.dart` 同一条:缺失就是 null /「待确认」,
/// 不拿 0 或空串冒充 —— 广播人数、站点进度、复盘指标在小程序侧都是
/// 「数不出来就明说」,这条是这套页面反复强调的。
library;

/// 投影本身不合法时的形状异常(对齐 directorError 的 code + message)。
class ClubDirectorFormatException implements Exception {
  const ClubDirectorFormatException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

const int _maxSafeInteger = 9007199254740991;

String _text(Object? value) =>
    value is String ? value.trim() : (value == null ? '' : '$value'.trim());

/// 小程序 `safeText`:非字符串、超长、带控制字符都算没有。
String _safeText(Object? value, int maxLength) {
  if (value is! String) return '';
  final String text = value.trim();
  if (text.isEmpty ||
      text.length > maxLength ||
      RegExp(r'[\u0000-\u001f\u007f]').hasMatch(text)) {
    return '';
  }
  return text;
}

/// 小程序 `numberOrNull`:只认真数(Number.isFinite),字符串不算。
int? _numOrNull(Object? value) {
  if (value is int && value.abs() <= _maxSafeInteger) return value;
  if (value is double &&
      value.isFinite &&
      value == value.roundToDouble() &&
      value.abs() <= _maxSafeInteger) {
    return value.toInt();
  }
  return null;
}

bool? _boolOrNull(Object? value) => value is bool ? value : null;

List<Map<String, dynamic>> _mapList(Object? value) => value is List
    ? value.whereType<Map<String, dynamic>>().toList(growable: false)
    : const <Map<String, dynamic>>[];

List<String> _stringList(Object? value) => value is List
    ? value.map((Object? e) => '$e').toList(growable: false)
    : const <String>[];

// ─── 站点 ───

/// 站点的一条 `fallbackPlanOptions`(D8 暂停时能绑的备用方案)。
/// payload 用 `planCode` + `version` 两个键(小程序 submitIncident 原样)。
class ClubDirectorFallbackPlan {
  const ClubDirectorFallbackPlan({
    required this.planCode,
    required this.version,
  });

  final String planCode;
  final int? version;

  static ClubDirectorFallbackPlan? tryFromJson(Map<String, dynamic> raw) {
    final String code = _safeText(raw['planCode'], 64);
    if (code.isEmpty) return null;
    return ClubDirectorFallbackPlan(
      planCode: code,
      version: _numOrNull(raw['version']),
    );
  }
}

class ClubDirectorStation {
  const ClubDirectorStation({
    required this.nodeId,
    required this.status,
    required this.name,
    required this.stationName,
    required this.nodeName,
    required this.issue,
    required this.blockedReason,
    required this.exception,
    required this.pauseReason,
    required this.pauseReasonCode,
    required this.resumeEta,
    required this.fallbackPlanCode,
    required this.pendingVerificationCount,
    required this.fallbackPlanOptions,
  });

  final int? nodeId;

  /// 原样(不转大小写)—— 真源 incidentRows 就是按原样字符串比 'PAUSED'。
  final String status;
  final String name;
  final String stationName;
  final String nodeName;
  final String issue;
  final String blockedReason;
  final String exception;
  final String pauseReason;
  final String pauseReasonCode;
  final String resumeEta;
  final String fallbackPlanCode;
  final int pendingVerificationCount;
  final List<ClubDirectorFallbackPlan> fallbackPlanOptions;

  /// 小程序 `stationView`:name || stationName || nodeName || 未命名节点。
  String get nameText =>
      _firstNotEmpty(<String>[name, stationName, nodeName], '未命名节点');

  String get statusText => status.isEmpty ? 'UNKNOWN' : status;

  /// issue || blockedReason || pauseReason || exception。
  String get issueText => _firstNotEmpty(<String>[
    issue,
    blockedReason,
    pauseReason,
    exception,
  ], '');

  /// 真源 stationPriority:异常在前。3=正常,数字越小越靠前。
  int get priority {
    final String s = status.toUpperCase();
    if (s == 'PAUSED' || s == 'BLOCKED' || s == 'ERROR') return 0;
    if (issue.isNotEmpty || blockedReason.isNotEmpty || exception.isNotEmpty) {
      return 1;
    }
    if (s.isNotEmpty && s != 'READY' && s != 'ACTIVE' && s != 'CLOSED') {
      return 2;
    }
    return 3;
  }

  static ClubDirectorStation fromJson(Map<String, dynamic> raw) {
    final Object? plans = raw['fallbackPlanOptions'];
    return ClubDirectorStation(
      nodeId: _numOrNull(raw['nodeId']),
      status: _text(raw['status']),
      name: _text(raw['name']),
      stationName: _text(raw['stationName']),
      nodeName: _text(raw['nodeName']),
      issue: _text(raw['issue']),
      blockedReason: _text(raw['blockedReason']),
      exception: _text(raw['exception']),
      pauseReason: _text(raw['pauseReason']),
      pauseReasonCode: _text(raw['pauseReasonCode']),
      resumeEta: _text(raw['resumeEta']),
      fallbackPlanCode: _text(raw['fallbackPlanCode']),
      // Number(undefined) > 0 是 false —— 缺字段按「没有积压」读,不是按 0 展示。
      pendingVerificationCount:
          _numOrNull(raw['pendingVerificationCount']) ?? 0,
      fallbackPlanOptions: plans is List
          ? plans
                .whereType<Map<String, dynamic>>()
                .map(ClubDirectorFallbackPlan.tryFromJson)
                .whereType<ClubDirectorFallbackPlan>()
                .toList(growable: false)
          : const <ClubDirectorFallbackPlan>[],
    );
  }
}

// ─── 队伍 ───

class ClubDirectorStuckNode {
  const ClubDirectorStuckNode({required this.nodeId, required this.nodeName});

  final int nodeId;
  final String nodeName;
}

class ClubDirectorTeamEvent {
  const ClubDirectorTeamEvent({
    required this.action,
    required this.outcome,
    required this.occurredAt,
  });

  final String action;
  final String outcome;
  final String occurredAt;

  static const Map<String, String> _actionLabels = <String, String>{
    'CONFIRM_ROLE': '身份确认',
    'PLAYER_CHOICE': '剧情选择',
    'PLAYER_SUBMIT': '任务提交',
    'PLAYER_HINT': '玩家提示',
    'PLAYER_REVEAL': '答案揭示',
  };
  static const Map<String, String> _outcomeLabels = <String, String>{
    'APPLIED': '已生效',
    'FAILED': '未生效',
  };

  /// 小程序 `teamView.recentEventText`:两段都认得出来才拼,否则「待确认」。
  String get text {
    final String? actionText = _actionLabels[action];
    final String? outcomeText = _outcomeLabels[outcome];
    if (actionText == null || outcomeText == null) return '';
    return <String>[
      actionText,
      outcomeText,
      occurredAt,
    ].where((String s) => s.isNotEmpty).join(' · ');
  }
}

class ClubDirectorTeam {
  const ClubDirectorTeam({
    required this.teamId,
    required this.status,
    required this.name,
    required this.teamName,
    required this.completedNodes,
    required this.totalNodes,
    required this.blocked,
    required this.blockedReason,
    required this.issue,
    required this.memberCount,
    required this.currentStuckNode,
    required this.hintLevel,
    required this.recentEvent,
  });

  final int? teamId;
  final String status;
  final String name;
  final String teamName;
  final int? completedNodes;
  final int? totalNodes;
  final bool blocked;
  final String blockedReason;
  final String issue;
  final int? memberCount;

  /// 以下三项过 `normalizeClubTeam` 的闸:值不合法就当没下发(删行)。
  final ClubDirectorStuckNode? currentStuckNode;
  final int? hintLevel;
  final ClubDirectorTeamEvent? recentEvent;

  String get nameText => _firstNotEmpty(<String>[name, teamName], '未命名队伍');
  String get statusText => status.isEmpty ? 'UNKNOWN' : status;

  /// 缺数写「进度待确认」—— 不写 0/0。
  String get progressText => completedNodes != null && totalNodes != null
      ? '$completedNodes/$totalNodes 节点'
      : '进度待确认';

  String get issueText => _firstNotEmpty(<String>[blockedReason, issue], '');

  bool get isAbnormal {
    final String s = status.toUpperCase();
    return s == 'BLOCKED' ||
        s == 'PAUSED' ||
        s == 'ERROR' ||
        blocked ||
        blockedReason.isNotEmpty ||
        issue.isNotEmpty;
  }

  String get stuckNodeText => currentStuckNode?.nodeName ?? '待确认';

  String get hintLevelText => switch (hintLevel) {
    1 => '一级提示',
    2 => '二级提示',
    _ => '待确认',
  };

  String get recentEventText => recentEvent?.text ?? '待确认';

  int get priority {
    final String s = status.toUpperCase();
    if (s == 'BLOCKED' || s == 'PAUSED' || s == 'ERROR') return 0;
    if (blocked || blockedReason.isNotEmpty || issue.isNotEmpty) return 1;
    return 2;
  }

  static ClubDirectorTeam fromJson(Map<String, dynamic> raw) {
    final Object? stuck = raw['currentStuckNode'];
    ClubDirectorStuckNode? stuckNode;
    if (stuck is Map<String, dynamic>) {
      final int? nodeId = _numOrNull(stuck['nodeId']);
      final String nodeName = _safeText(stuck['nodeName'], 120);
      if (nodeId != null && nodeId > 0 && nodeName.isNotEmpty) {
        stuckNode = ClubDirectorStuckNode(nodeId: nodeId, nodeName: nodeName);
      }
    }
    final int? hintLevel = _numOrNull(raw['hintLevel']);
    final Object? recent = raw['recentEvent'];
    ClubDirectorTeamEvent? event;
    if (recent is Map<String, dynamic>) {
      final String action = _safeText(recent['action'], 64).toUpperCase();
      final String outcome = _safeText(recent['outcome'], 40).toUpperCase();
      if (action.isNotEmpty && outcome.isNotEmpty) {
        event = ClubDirectorTeamEvent(
          action: action,
          outcome: outcome,
          occurredAt: _safeText(recent['occurredAt'], 64),
        );
      }
    }
    return ClubDirectorTeam(
      teamId: _numOrNull(raw['teamId']),
      status: _text(raw['status']),
      name: _text(raw['name']),
      teamName: _text(raw['teamName']),
      completedNodes: _numOrNull(raw['completedNodes']),
      totalNodes: _numOrNull(raw['totalNodes']),
      blocked: raw['blocked'] == true,
      blockedReason: _text(raw['blockedReason']),
      issue: _text(raw['issue']),
      memberCount: _numOrNull(raw['memberCount']),
      currentStuckNode: stuckNode,
      hintLevel: hintLevel != null && hintLevel >= 1 && hintLevel <= 2
          ? hintLevel
          : null,
      recentEvent: event,
    );
  }
}

// ─── 角色 ───

class ClubDirectorRoleOption {
  const ClubDirectorRoleOption({required this.roleCode, required this.label});

  final String roleCode;
  final String label;

  static ClubDirectorRoleOption fromJson(Map<String, dynamic> raw) {
    final String roleCode = _firstNotEmpty(<String>[
      _text(raw['roleCode']),
      _text(raw['code']),
      _text(raw['key']),
    ], '');
    return ClubDirectorRoleOption(
      roleCode: roleCode,
      label: _firstNotEmpty(<String>[
        _text(raw['roleName']),
        _text(raw['name']),
        _text(raw['label']),
        roleCode,
      ], '未命名角色'),
    );
  }
}

class ClubDirectorRole {
  const ClubDirectorRole({
    required this.teamId,
    required this.memberId,
    required this.roleCode,
    required this.confirmationStatus,
    required this.memberName,
    required this.name,
    required this.roleName,
    required this.roleLabel,
    required this.memberCount,
  });

  final int? teamId;
  final int? memberId;
  final String roleCode;
  final String confirmationStatus;
  final String memberName;
  final String name;
  final String roleName;
  final String roleLabel;

  /// 按角色聚合的人数(广播角色档人数优先用它,`roleRecipientCount`)。
  final int? memberCount;

  String get memberNameText =>
      _firstNotEmpty(<String>[memberName, name], '').isNotEmpty
      ? _firstNotEmpty(<String>[memberName, name], '')
      : (memberId == null ? '成员待同步' : '成员 #$memberId');

  String get roleNameText =>
      _firstNotEmpty(<String>[roleName, roleLabel, roleCode], '角色待分配');

  /// 没角色码是「待分配」;有角色码才谈确认状态。
  String get confirmationText {
    if (roleCode.isEmpty) return '待分配';
    return const <String, String>{
          'CONFIRMED': '已确认',
          'PENDING': '待确认',
          'ASSIGNED': '待确认',
          'REJECTED': '未接受',
        }[confirmationStatus] ??
        '确认状态待同步';
  }

  /// 接管的合法来源:有角色码且已确认(小程序 `isConfirmedRoleSource`)。
  bool get isConfirmedRoleSource =>
      roleCode.isNotEmpty && confirmationStatus == 'CONFIRMED';

  static ClubDirectorRole fromJson(Map<String, dynamic> raw) {
    return ClubDirectorRole(
      teamId: _numOrNull(raw['teamId']),
      memberId: _numOrNull(raw['memberId']),
      roleCode: _text(raw['roleCode']),
      confirmationStatus: _firstNotEmpty(<String>[
        _text(raw['confirmationStatus']),
        _text(raw['status']),
      ], '').toUpperCase(),
      memberName: _text(raw['memberName']),
      name: _text(raw['name']),
      roleName: _text(raw['roleName']),
      roleLabel: _text(raw['roleLabel']),
      memberCount: _numOrNull(raw['memberCount']),
    );
  }
}

/// D6 成员行(小程序 `roleMemberRows`,E-04 的可定位投影)。
class ClubDirectorMemberRow {
  const ClubDirectorMemberRow({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.muted,
  });

  /// "teamId:memberId"。
  final String id;
  final String title;
  final String subtitle;
  final String value;
  final bool muted;
}

/// 接管校验(小程序 `takeoverPayload`):不合法返回 null,由调用方提示。
class ClubDirectorTakeover {
  const ClubDirectorTakeover({
    required this.teamId,
    required this.sourceMemberId,
    required this.targetMemberId,
    required this.reason,
  });

  final int teamId;
  final int sourceMemberId;
  final int targetMemberId;
  final String reason;

  Map<String, dynamic> toPayload() => <String, dynamic>{
    'teamId': teamId,
    'sourceMemberId': sourceMemberId,
    'targetMemberId': targetMemberId,
    'reason': reason,
  };

  static ClubDirectorTakeover? validate({
    required List<ClubDirectorRole> roles,
    required Object? teamId,
    required Object? sourceMemberId,
    required Object? targetMemberId,
    required Object? reason,
  }) {
    final int? team = _positiveId(teamId);
    final int? source = _positiveId(sourceMemberId);
    final int? target = _positiveId(targetMemberId);
    final String why = _text(reason);
    if (team == null ||
        source == null ||
        target == null ||
        source == target ||
        why.isEmpty ||
        why.length > 200) {
      return null;
    }
    ClubDirectorRole? sourceRow;
    ClubDirectorRole? targetRow;
    for (final ClubDirectorRole row in roles) {
      if (row.teamId == team && row.memberId == source) sourceRow = row;
      if (row.teamId == team && row.memberId == target) targetRow = row;
    }
    if (sourceRow == null || !sourceRow.isConfirmedRoleSource) return null;
    if (targetRow == null || targetRow.roleCode.isNotEmpty) return null;
    return ClubDirectorTakeover(
      teamId: team,
      sourceMemberId: source,
      targetMemberId: target,
      reason: why,
    );
  }

  static int? _positiveId(Object? value) {
    final int? id = value is int
        ? value
        : (value is String ? int.tryParse(value) : null);
    return id != null && id > 0 && id <= _maxSafeInteger ? id : null;
  }
}

// ─── 广播 ───

class ClubDirectorBroadcast {
  const ClubDirectorBroadcast({
    required this.content,
    required this.targetType,
    required this.scope,
    required this.targetName,
    required this.roleName,
    required this.receiptStatus,
    required this.status,
  });

  final String content;
  final String targetType;
  final String scope;
  final String targetName;
  final String roleName;
  final String receiptStatus;
  final String status;

  String get contentText => content.isEmpty ? '广播内容待同步' : content;

  String get targetText => _firstNotEmpty(<String>[
    targetName,
    roleName,
    const <String, String>{
          'ALL': '全部玩家',
          'TEAM': '定向队伍',
          'ROLE': '定向角色',
        }[_firstNotEmpty(<String>[targetType, scope], '')] ??
        '',
  ], '范围待确认');

  String get receiptText =>
      const <String, String>{
        'CONFIRMED': '已确认送达',
        'APPLIED': '已确认送达',
        'SUCCESS': '已确认送达',
        'REJECTED': '发送未生效',
        'FAILED': '发送未生效',
        'PENDING': '回执待确认',
        'SENDING': '发送中',
        'SENT': '已送达',
        'PARTIAL': '部分送达',
      }[_firstNotEmpty(<String>[receiptStatus, status], '').toUpperCase()] ??
      '回执待同步';

  static ClubDirectorBroadcast fromJson(Map<String, dynamic> raw) {
    return ClubDirectorBroadcast(
      content: _text(raw['content']),
      targetType: _text(raw['targetType']),
      scope: _text(raw['scope']),
      targetName: _text(raw['targetName']),
      roleName: _text(raw['roleName']),
      receiptStatus: _text(raw['receiptStatus']),
      status: _text(raw['status']),
    );
  }
}

class ClubDirectorBroadcastTarget {
  const ClubDirectorBroadcastTarget({
    required this.id,
    required this.label,
    this.memberCount,
  });

  final Object id;
  final String label;
  final int? memberCount;
}

// ─── 提交(D8 的原料) ───

class ClubDirectorSubmission {
  const ClubDirectorSubmission({
    required this.submissionId,
    required this.teamId,
    required this.nodeName,
    required this.status,
    required this.decisionReason,
  });

  final int submissionId;
  final int? teamId;
  final String nodeName;
  final String status;
  final String decisionReason;

  static ClubDirectorSubmission? tryFromJson(Map<String, dynamic> raw) {
    final int? id = _numOrNull(raw['submissionId']);
    if (id == null) return null;
    return ClubDirectorSubmission(
      submissionId: id,
      teamId: _numOrNull(raw['teamId']),
      nodeName: _text(raw['nodeName']),
      status: _text(raw['status']),
      decisionReason: _text(raw['decisionReason']),
    );
  }
}

// ─── D8 现场事件 ───

enum ClubDirectorIncidentKind { paused, backlog, pendingSubmit, rejected }

class ClubDirectorIncident {
  const ClubDirectorIncident({
    required this.key,
    required this.kind,
    this.nodeId,
    this.submissionId,
    required this.label,
    required this.text,
    required this.sub,
    this.planOptions = const <ClubDirectorFallbackPlan>[],
  });

  final String key;
  final ClubDirectorIncidentKind kind;
  final int? nodeId;
  final int? submissionId;
  final String label;
  final String text;
  final String sub;
  final List<ClubDirectorFallbackPlan> planOptions;

  /// 选中一条事件后能做的处理(小程序 `incidentModesFor`)。
  /// 已驳回是终态 —— 「没有动作」本身就是一种状态,不给假选项。
  List<({String id, String label})> get modes {
    switch (kind) {
      case ClubDirectorIncidentKind.paused:
        return <({String id, String label})>[(id: 'resume', label: '恢复本站')];
      case ClubDirectorIncidentKind.backlog:
        return <({String id, String label})>[(id: 'pause', label: '暂停本站')];
      case ClubDirectorIncidentKind.pendingSubmit:
        return <({String id, String label})>[(id: 'reject', label: '驳回重交')];
      case ClubDirectorIncidentKind.rejected:
        return const <({String id, String label})>[];
    }
  }
}

/// 小程序 `incidentRows`:站点暂停 / 待核验积压来自 stations,提交来自 submissions。
List<ClubDirectorIncident> buildIncidentRows(
  List<ClubDirectorStation> stations,
  List<ClubDirectorSubmission> submissions,
) {
  final List<ClubDirectorIncident> rows = <ClubDirectorIncident>[];
  for (final ClubDirectorStation st in stations) {
    final int? nodeId = st.nodeId;
    if (nodeId == null) continue;
    if (st.status == 'PAUSED') {
      rows.add(
        ClubDirectorIncident(
          key: 'pause:$nodeId',
          kind: ClubDirectorIncidentKind.paused,
          nodeId: nodeId,
          label: '商家暂停',
          text:
              '${_firstNotEmpty(<String>[st.nodeName], '未命名站点')} · '
              '${_firstNotEmpty(<String>[st.pauseReason, st.pauseReasonCode], '未填原因')}'
              '${st.resumeEta.isEmpty ? '' : '，预计 ${st.resumeEta} 恢复'}',
          // 绑了兜底方案的,玩家走到兜底站点会自动记「兜底完成」—— 不是这里点出来的
          sub: st.fallbackPlanCode.isEmpty
              ? '未绑兜底方案'
              : '已绑兜底方案 ${st.fallbackPlanCode}',
          planOptions: st.fallbackPlanOptions,
        ),
      );
    } else if (st.pendingVerificationCount > 0) {
      rows.add(
        ClubDirectorIncident(
          key: 'backlog:$nodeId',
          kind: ClubDirectorIncidentKind.backlog,
          nodeId: nodeId,
          label: '待核验积压',
          text:
              '${_firstNotEmpty(<String>[st.nodeName], '未命名站点')} · '
              '${st.pendingVerificationCount} 条待商家核验',
          sub: '',
          planOptions: st.fallbackPlanOptions,
        ),
      );
    }
  }
  for (final ClubDirectorSubmission sm in submissions) {
    // 真源把非 REJECTED 的提交一律记成「待核验提交」(后端本就只下发
    // PENDING/REJECTED 两档;在这里加判据会偏离真源,不动)。
    final bool rejected = sm.status == 'REJECTED';
    rows.add(
      ClubDirectorIncident(
        key: 'sub:${sm.submissionId}',
        kind: rejected
            ? ClubDirectorIncidentKind.rejected
            : ClubDirectorIncidentKind.pendingSubmit,
        submissionId: sm.submissionId,
        label: rejected ? '任务驳回' : '待核验提交',
        text:
            '${sm.teamId != null ? '队 ${sm.teamId} · ' : ''}'
            '${_firstNotEmpty(<String>[sm.nodeName], '未命名站点')}'
            '${rejected ? ' 已驳回待重交' : ' 提交待核验'}',
        sub: rejected ? sm.decisionReason : '',
      ),
    );
  }
  return rows;
}

// ─── 复盘(最小面:有没有 + 能不能导出 + 指标条) ───

class ClubDirectorRecapMetric {
  const ClubDirectorRecapMetric({
    required this.label,
    required this.valueText,
    required this.unit,
  });

  final String label;
  final String valueText;
  final String unit;
}

class ClubDirectorRecap {
  const ClubDirectorRecap({
    required this.exportAvailable,
    required this.metrics,
  });

  final bool exportAvailable;
  final List<ClubDirectorRecapMetric> metrics;

  /// 与 `loadClubRecapExport` 同一条 ponytail 口径:这里只核到
  /// 「是不是一份 GAME_RECAP_V1」,逐字段核等复盘正文上屏再做。
  static ClubDirectorRecap? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    if (_text(raw['schemaVersion']) != 'GAME_RECAP_V1') return null;
    final bool exportAvailable = raw['exportAvailable'] == true;
    final List<ClubDirectorRecapMetric> metrics = <ClubDirectorRecapMetric>[];
    final Object? rows = raw['metrics'];
    if (rows is List) {
      for (final Object? row in rows) {
        if (row is! Map<String, dynamic>) continue;
        final String label = _firstNotEmpty(<String>[
          _text(row['label']),
          _text(row['name']),
          _text(row['key']),
        ], '');
        final Object? value = row['value'];
        if (label.isEmpty || value == null) continue;
        metrics.add(
          ClubDirectorRecapMetric(
            label: label,
            valueText: '$value',
            unit: _text(row['unit']),
          ),
        );
      }
    }
    return ClubDirectorRecap(
      exportAvailable: exportAvailable,
      metrics: metrics,
    );
  }
}

// ─── 就绪度 ───

class ClubDirectorReadiness {
  const ClubDirectorReadiness({
    required this.requiredStations,
    required this.readyStations,
    required this.teamsReady,
    required this.blockers,
    required this.canStart,
  });

  final int? requiredStations;
  final int? readyStations;
  final bool? teamsReady;
  final bool canStart;
  final List<String> blockers;

  /// 服务端下发的显式 blockers 优先;没有才按三个判据兜底(真源同序)。
  static List<String> _blockers(
    List<String> explicit,
    int? requiredStations,
    int? readyStations,
    bool? teamsReady,
  ) {
    if (explicit.isNotEmpty) return explicit;
    final List<String> blockers = <String>[];
    if (requiredStations == 0) blockers.add('尚未配置可运行站点');
    if (requiredStations != null &&
        readyStations != null &&
        readyStations < requiredStations) {
      blockers.add('${requiredStations - readyStations} 个站点未 READY');
    }
    if (teamsReady == false) blockers.add('仍有队员未分配角色');
    return blockers;
  }

  /// 数不进来就不报分数 —— 「待确认」不许被读成 0/x。
  String get readinessText => readyStations == null || requiredStations == null
      ? '站点准备数据待确认'
      : '$readyStations/$requiredStations 站 READY';
}

// ─── 章节 ───

class ClubDirectorChapterOption {
  const ClubDirectorChapterOption({
    required this.chapterId,
    required this.title,
  });

  final int chapterId;
  final String title;
}

// ─── 投影 ───

/// `normalizeClubProjection` 的移植。坏形状一律抛
/// [ClubDirectorFormatException],由网关层翻成页面可读的错误。
class ClubDirectorProjection {
  const ClubDirectorProjection({
    required this.sessionId,
    required this.activityId,
    required this.status,
    required this.revision,
    required this.currentChapterId,
    required this.chapterOptions,
    required this.availableActions,
    required this.readiness,
    required this.stations,
    required this.teams,
    required this.broadcasts,
    required this.roles,
    required this.roleOptions,
    required this.leaderboardVisible,
    required this.submissions,
    required this.recap,
  });

  factory ClubDirectorProjection.fromJson(Map<String, dynamic> raw) {
    if (_text(raw['perspective']).toUpperCase() != 'CLUB') {
      throw const ClubDirectorFormatException(
        'OWNER_REQUIRED',
        '仅活动所属俱乐部主理人可进入导演台',
      );
    }
    final List<String> availableActions = _stringList(raw['availableActions']);
    final Object? clubRaw = raw['club'];
    final Map<String, dynamic>? club = clubRaw is Map<String, dynamic>
        ? clubRaw
        : null;
    // 「还没有局但能 PREPARE」是合法空壳(开局入口);其余没有 club 块的都不给进。
    final bool mayPrepareWithoutSession =
        club == null &&
        _text(raw['status']).toUpperCase() == 'NOT_PREPARED' &&
        _numOrNull(raw['revision']) == 0 &&
        availableActions.contains('PREPARE');
    if (club == null && !mayPrepareWithoutSession) {
      throw const ClubDirectorFormatException(
        'OWNER_REQUIRED',
        '仅活动所属俱乐部主理人可进入导演台',
      );
    }
    final Map<String, dynamic> source = club ?? const <String, dynamic>{};
    final Object? readinessRaw = source['readiness'];
    final Map<String, dynamic> readinessMap =
        readinessRaw is Map<String, dynamic>
        ? readinessRaw
        : const <String, dynamic>{};
    final int? requiredStations = _numOrNull(readinessMap['requiredStations']);
    final int? readyStations = _numOrNull(readinessMap['readyStations']);
    final bool? teamsReady = _boolOrNull(readinessMap['teamsReady']);
    final bool canStart =
        _text(raw['status']).toUpperCase() == 'READY' &&
        requiredStations != null &&
        requiredStations > 0 &&
        readyStations == requiredStations &&
        teamsReady == true &&
        availableActions.contains('START');

    final int? currentChapterId = _numOrNull(raw['currentChapterId']);
    final List<ClubDirectorChapterOption> chapterOptions =
        _mapList(source['chapterOptions'])
            .map((Map<String, dynamic> item) {
              final int? id = _numOrNull(item['chapterId']);
              if (id == null || id <= 0) return null;
              if (item['unlocked'] == true || item['unlockable'] == false) {
                return null;
              }
              return ClubDirectorChapterOption(
                chapterId: id,
                title: _text(item['title']),
              );
            })
            .whereType<ClubDirectorChapterOption>()
            .toList(growable: false);

    final List<ClubDirectorStation> stations = _stableSortByPriority(
      _mapList(source['stations']).map(ClubDirectorStation.fromJson).toList(),
      (ClubDirectorStation s) => s.priority,
    );
    final List<ClubDirectorTeam> teams = _stableSortByPriority(
      _mapList(source['teams']).map(ClubDirectorTeam.fromJson).toList(),
      (ClubDirectorTeam t) => t.priority,
    );

    return ClubDirectorProjection(
      sessionId: _numOrNull(raw['sessionId']),
      activityId: _numOrNull(raw['activityId']),
      status: _text(raw['status']),
      revision: _numOrNull(raw['revision']),
      currentChapterId: currentChapterId,
      chapterOptions: chapterOptions,
      availableActions: availableActions,
      readiness: ClubDirectorReadiness(
        requiredStations: requiredStations,
        readyStations: readyStations,
        teamsReady: teamsReady,
        blockers: ClubDirectorReadiness._blockers(
          _stringList(readinessMap['blockers']),
          requiredStations,
          readyStations,
          teamsReady,
        ),
        canStart: canStart,
      ),
      stations: stations,
      teams: teams,
      broadcasts: _mapList(
        source['broadcasts'],
      ).map(ClubDirectorBroadcast.fromJson).toList(growable: false),
      roles: _mapList(
        source['roles'],
      ).map(ClubDirectorRole.fromJson).toList(growable: false),
      roleOptions: _mapList(source['roleOptions'])
          .map(ClubDirectorRoleOption.fromJson)
          .where((ClubDirectorRoleOption o) => o.roleCode.isNotEmpty)
          .toList(growable: false),
      leaderboardVisible:
          _boolOrNull(source['leaderboardVisible']) ??
          _boolOrNull(
            source['leaderboard'] is Map<String, dynamic>
                ? (source['leaderboard'] as Map<String, dynamic>)['visible']
                : null,
          ),
      submissions: _mapList(source['submissions'])
          .map(ClubDirectorSubmission.tryFromJson)
          .whereType<ClubDirectorSubmission>()
          .toList(growable: false),
      recap: ClubDirectorRecap.tryFromJson(source['recap']),
    );
  }

  final int? sessionId;
  final int? activityId;
  final String status;
  final int? revision;
  final int? currentChapterId;

  /// 已过适配器闸(有 id、未解锁、可解锁);手动解锁还要再排除当前章节。
  final List<ClubDirectorChapterOption> chapterOptions;
  final List<String> availableActions;
  final ClubDirectorReadiness readiness;
  final List<ClubDirectorStation> stations;
  final List<ClubDirectorTeam> teams;
  final List<ClubDirectorBroadcast> broadcasts;
  final List<ClubDirectorRole> roles;
  final List<ClubDirectorRoleOption> roleOptions;
  final bool? leaderboardVisible;
  final List<ClubDirectorSubmission> submissions;
  final ClubDirectorRecap? recap;

  bool hasAction(String action) => availableActions.contains(action);

  String get sessionStatusText =>
      const <String, String>{
        'NOT_PREPARED': '未准备',
        'DRAFT': '草稿',
        'PREPARING': '准备中',
        'READY': '待开局',
        'RUNNING': '进行中',
        'FINISHED': '已结束',
        'CANCELLED': '已取消',
      }[status.toUpperCase()] ??
      '状态待确认';

  String get readinessText => readiness.readinessText;

  bool get canPrepare => hasAction('PREPARE');
  bool get canStart => readiness.canStart;
  bool get canFinish => hasAction('FINISH');
  bool get canAssignRoles =>
      hasAction('ASSIGN_ROLES') && roleOptions.isNotEmpty;
  bool get canTakeoverRoles => hasAction('TAKEOVER_ROLE');
  bool get canBroadcast => hasAction('BROADCAST');
  bool get canToggleLeaderboard =>
      leaderboardVisible != null && hasAction('SET_LEADERBOARD_VISIBILITY');
  bool get canExportRecap => recap?.exportAvailable ?? false;

  /// 手动解锁的候选:适配器闸之上再排除「当前章节」,标题兜底 `章节 #id`
  /// (小程序 applyProjection 的同一段 filter + map)。
  List<ClubDirectorChapterOption> get unlockChapterOptions => chapterOptions
      .where(
        (ClubDirectorChapterOption o) =>
            currentChapterId == null || o.chapterId != currentChapterId,
      )
      .map(
        (ClubDirectorChapterOption o) => ClubDirectorChapterOption(
          chapterId: o.chapterId,
          title: o.title.isEmpty ? '章节 #${o.chapterId}' : o.title,
        ),
      )
      .toList(growable: false);

  bool get canUnlockChapter =>
      hasAction('UNLOCK_CHAPTER') && unlockChapterOptions.isNotEmpty;

  /// 小程序 `roleMemberRows`:D6 选成员的行(带可定位 id)。
  List<ClubDirectorMemberRow> get roleMemberRows {
    final Map<int, String> teamNames = <int, String>{
      for (final ClubDirectorTeam t in teams)
        if (t.teamId != null) t.teamId!: t.nameText,
    };
    return roles
        .where((ClubDirectorRole r) => r.teamId != null && r.memberId != null)
        .map(
          (ClubDirectorRole r) => ClubDirectorMemberRow(
            id: '${r.teamId}:${r.memberId}',
            title: r.memberNameText,
            subtitle: teamNames[r.teamId] ?? '队伍 #${r.teamId}',
            value: r.roleNameText,
            muted: r.roleCode.isEmpty,
          ),
        )
        .toList(growable: false);
  }

  /// 接管的合法来源行(小程序 `refreshTakeoverCandidates` 的 filter)。
  List<ClubDirectorRole> get takeoverCandidates => roles
      .where((ClubDirectorRole r) => r.isConfirmedRoleSource)
      .toList(growable: false);

  List<ClubDirectorIncident> get incidents =>
      buildIncidentRows(stations, submissions);

  // ─── 广播:范围 → 候选目标 → 人数 ───

  /// 小程序 `broadcastTargets`。
  List<ClubDirectorBroadcastTarget> broadcastTargets(String targetType) {
    switch (targetType) {
      case 'TEAM':
        return teams
            .where((ClubDirectorTeam t) => t.teamId != null)
            .map(
              (ClubDirectorTeam t) => ClubDirectorBroadcastTarget(
                id: t.teamId!,
                label: t.nameText,
                memberCount: t.memberCount,
              ),
            )
            .toList(growable: false);
      case 'ROLE':
        return roleOptions
            .map(
              (ClubDirectorRoleOption o) =>
                  ClubDirectorBroadcastTarget(id: o.roleCode, label: o.label),
            )
            .toList(growable: false);
      default:
        return const <ClubDirectorBroadcastTarget>[
          ClubDirectorBroadcastTarget(id: '', label: '全部在场玩家'),
        ];
    }
  }

  /// 小程序 `broadcastRecipientCount`。数不出来返回 null ——
  /// 界面必须写「人数待确认」,不写 0。
  int? broadcastRecipientCount(ClubDirectorBroadcastTarget? selected) {
    if (selected == null) return null;
    if (selected.label == '全部在场玩家') {
      final List<ClubDirectorTeam> rows = teams;
      if (rows.isEmpty ||
          rows.any((ClubDirectorTeam t) => t.memberCount == null)) {
        return null;
      }
      return rows.fold<int>(0, (int sum, t) => sum + t.memberCount!);
    }
    if (selected.memberCount != null && selected.id is int) {
      return selected.memberCount;
    }
    if (selected.id is String) {
      return _roleRecipientCount(selected.id as String);
    }
    return null;
  }

  /// 小程序 `roleRecipientCount`:优先整表聚合数,退而点人;两头都不全 → null。
  int? _roleRecipientCount(String roleCode) {
    final List<ClubDirectorRole> rows = roles;
    if (rows.isEmpty) return null;
    final bool completeAggregates = rows.every(
      (ClubDirectorRole r) => r.roleCode.isNotEmpty && r.memberCount != null,
    );
    if (completeAggregates) {
      return rows.fold<int>(
        0,
        (int sum, r) => sum + (r.roleCode == roleCode ? r.memberCount! : 0),
      );
    }
    final bool completeAssignments = rows.every(
      (ClubDirectorRole r) => r.roleCode.isNotEmpty && r.memberId != null,
    );
    if (!completeAssignments) return null;
    return <int>{
      for (final ClubDirectorRole r in rows)
        if (r.roleCode == roleCode) r.memberId!,
    }.length;
  }
}

String _firstNotEmpty(List<String> values, String fallback) {
  for (final String value in values) {
    if (value.isNotEmpty) return value;
  }
  return fallback;
}

/// 稳定排序(小程序 `stablePrioritySort` 同语义):优先级一样保持原序。
List<T> _stableSortByPriority<T>(List<T> list, int Function(T) priorityOf) {
  final List<(int, int, T)> tagged = <(int, int, T)>[
    for (int i = 0; i < list.length; i++) (priorityOf(list[i]), i, list[i]),
  ];
  tagged.sort(
    ((int, int, T) a, (int, int, T) b) =>
        a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
  );
  return tagged.map(((int, int, T) e) => e.$3).toList(growable: false);
}
