import '../../core/util/json_parse.dart' show asInt, asStr;

/// 俱乐部运营四页(event-ops / governance / notify / roles)的模型。
/// 逐条对齐小程序真源 `pages/club/{event-ops,governance,notify,roles}`(@90e66d70)。
///
/// ⚠️ 形状纪律照抄小程序:`*_shape` 函数只在**字段全合法**时返回对象/行,
///   缺字段或字段非法一律返回 null —— 页面据此进「回执坏了」错误态,
///   不拿 0/空串给坏数据兜底(「报名数待确认」与「0 人已报名」是两件事)。

/// 俱乐部访问上下文:`POST /api/club/access/me`。
///
/// ★ 与 p4-club-crm 分支的 `data/models/club_access.dart`(ClubAccess)是同一条
///   后端回执的两个最小消费面:那条线只吃 member:list:read / finance:read;
///   本线要吃 activity:manage / event:checkin / event:operate / member:manage /
///   notify:send + canManageRoles。合并时收敛成一个模型,见 PR 说明。
class ClubOpsAccess {
  const ClubOpsAccess({
    required this.activeDeclared,
    required this.active,
    this.clubId,
    required this.permissions,
    required this.roleCodes,
    required this.canManageRoles,
  });

  /// `active` 字段是否**以布尔形态出现**。小程序 roles 页靠这条区分
  /// 「后端明确说不行」与「回执残缺」:前者该无权限,后者该重试。
  final bool activeDeclared;
  final bool active;
  final int? clubId;
  final Set<String> permissions;
  final List<String> roleCodes;
  final bool canManageRoles;

  bool has(String permission) => permissions.contains(permission);
  bool get isOwner => roleCodes.contains('CLUB_OWNER');

  factory ClubOpsAccess.fromJson(Map<String, dynamic> json) {
    final Object? rawActive = json['active'];
    int? clubId;
    final Object? rawClub = json['club'];
    if (rawClub is Map) {
      clubId = asInt(rawClub['id']);
      if (clubId == 0) clubId = null;
    }
    final Set<String> permissions = <String>{};
    final Object? rawPermissions = json['permissions'];
    if (rawPermissions is List) {
      for (final Object? item in rawPermissions) {
        if (item is String && item.isNotEmpty) permissions.add(item);
      }
    }
    final List<String> roleCodes = <String>[];
    final Object? rawRoles = json['roleCodes'];
    if (rawRoles is List) {
      for (final Object? item in rawRoles) {
        if (item is String && item.isNotEmpty) roleCodes.add(item);
      }
    }
    return ClubOpsAccess(
      activeDeclared: rawActive is bool,
      active: rawActive == true,
      clubId: clubId,
      permissions: permissions,
      roleCodes: roleCodes,
      canManageRoles: json['canManageRoles'] == true,
    );
  }
}

/// 可开场主题:`POST /api/club/event-ops/topics` 列表项。
class EventOpsTopic {
  const EventOpsTopic({required this.id, required this.name});

  final int id;
  final String name;

  /// 无名字回退 `主题 #id`,不假装知道名字(与小程序同口径)。
  factory EventOpsTopic.fromJson(Map<String, dynamic> json) {
    final int id = asInt(json['id']);
    final String name = asStr(json['name']).trim();
    return EventOpsTopic(id: id, name: name.isEmpty ? '主题 #$id' : name);
  }
}

/// 系列场次:`/api/club/event-ops/series/{list,detail}`。
class EventSeries {
  const EventSeries({
    required this.id,
    required this.clubId,
    required this.topicId,
    required this.leadMemberId,
    required this.version,
    required this.recurrenceType,
    required this.capacity,
    required this.waitlistEnabled,
    required this.offerMinutes,
    required this.futureDates,
  });

  final int id;
  final int clubId;
  final int topicId;
  final int leadMemberId;
  final int version;
  final String recurrenceType;
  final int? capacity;
  final bool waitlistEnabled;
  final int offerMinutes;
  final List<String> futureDates;

  static const List<({String value, String label})> recurrences =
      <({String value, String label})>[
        (value: 'ONCE', label: '单次'),
        (value: 'WEEKLY', label: '每周'),
        (value: 'CUSTOM_DATES', label: '自定义日期'),
      ];

  static String recurrenceLabel(String value) {
    for (final ({String value, String label}) item in recurrences) {
      if (item.value == value) return item.label;
    }
    return value;
  }

  /// 校验失败返回 null(页面进错误态,不兜底)。
  static EventSeries? tryFromJson(
    Map<String, dynamic> json, {
    required int clubId,
  }) {
    final int id = asInt(json['id']);
    final int rowClubId = asInt(json['clubId']);
    final int topicId = asInt(json['topicId']);
    final int leadMemberId = asInt(json['defaultLeadMemberId']);
    final Object? rawVersion = json['version'];
    final Object? rawOffer = json['offerMinutes'];
    final String recurrenceType = asStr(json['recurrenceType']);
    final Object? rawWaitlist = json['waitlistEnabled'];
    if (id <= 0 ||
        rowClubId != clubId ||
        topicId <= 0 ||
        leadMemberId <= 0 ||
        rawVersion is! int ||
        rawVersion < 0 ||
        rawOffer is! int ||
        rawOffer < 5 ||
        rawOffer > 1440 ||
        !recurrences.any(
          (({String value, String label}) item) =>
              item.value == recurrenceType,
        ) ||
        rawWaitlist is! bool) {
      return null;
    }
    final Object? rawCapacity = json['defaultCapacity'];
    int? capacity;
    if (rawCapacity != null) {
      capacity = rawCapacity is int ? rawCapacity : int.tryParse('$rawCapacity');
      if (capacity == null || capacity < 1 || capacity > 10000) return null;
    }
    final Set<String> dates = <String>{};
    final Object? rawDates = json['futureDates'];
    if (rawDates is List) {
      for (final Object? item in rawDates) {
        final String text = asStr(item);
        if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) dates.add(text);
      }
    }
    final List<String> futureDates = dates.toList()..sort();
    return EventSeries(
      id: id,
      clubId: rowClubId,
      topicId: topicId,
      leadMemberId: leadMemberId,
      version: rawVersion,
      recurrenceType: recurrenceType,
      capacity: capacity,
      waitlistEnabled: rawWaitlist,
      offerMinutes: rawOffer,
      futureDates: futureDates,
    );
  }
}

/// 日期清单一行:`/api/club/event-ops/series/occurrences` 列表项。
class SeriesOccurrence {
  const SeriesOccurrence({
    required this.occurrenceId,
    required this.activityId,
    required this.dateText,
    required this.meta,
    required this.badge,
    required this.badgeKind,
    this.displaySource,
  });

  final int? occurrenceId;
  final int? activityId;
  final String dateText;
  final String meta;
  final String badge;
  final String badgeKind;

  /// Explicit provenance for locally composed display strings. Legacy/manual
  /// rows retain their supplied copy when this source is absent.
  final SeriesOccurrenceDisplaySource? displaySource;

  /// ★ signupCount 为 null = 报名数没算出来:既不显示「0 人已报名」也不放开编辑。
  factory SeriesOccurrence.fromJson(Map<String, dynamic> json) {
    final bool cancelled = asStr(json['status']) == 'CANCELLED';
    final int? signup = json['signupCount'] == null
        ? null
        : asInt(json['signupCount']);
    final int? refunded = json['refundedCount'] == null
        ? null
        : asInt(json['refundedCount']);
    final bool editable = json['editable'] == true;
    final String lockReason = asStr(json['lockReason']).trim();
    String meta;
    if (cancelled) {
      meta = refunded == null ? '本场已取消' : '已退款 $refunded 单';
    } else if (signup == null) {
      meta = '报名数待确认';
    } else if (signup == 0) {
      meta = '未开售';
    } else {
      meta = '$signup 人已报名${editable ? '' : ' · 不可编辑'}';
    }
    return SeriesOccurrence(
      displaySource: SeriesOccurrenceDisplaySource(
        occurrenceAt: json['occurrenceAt'],
        cancelled: cancelled,
        signupCount: signup,
        refundedCount: refunded,
        editable: editable,
        lockReason: lockReason,
      ),
      occurrenceId: json['occurrenceId'] == null
          ? null
          : asInt(json['occurrenceId']),
      activityId: json['activityId'] == null ? null : asInt(json['activityId']),
      dateText: occurrenceDateText(json['occurrenceAt']),
      meta: meta,
      badge: cancelled
          ? '本场已取消'
          : (editable ? '编辑' : (lockReason.isEmpty ? '已锁定' : lockReason)),
      badgeKind: cancelled ? 'cancelled' : (editable ? 'editable' : 'locked'),
    );
  }

  /// 后端下发 "yyyy-MM-dd HH:mm:ss" 或时间戳;解析不出来就原样显示,
  /// 不编一个日期(与小程序 occurrenceDateText 同口径)。
  static String occurrenceDateText(Object? raw) {
    if (raw == null || asStr(raw).isEmpty) return '日期待确认';
    DateTime? parsed;
    if (raw is num) {
      parsed = DateTime.fromMillisecondsSinceEpoch(raw.toInt() * 1000);
    } else {
      parsed = DateTime.tryParse(asStr(raw).replaceFirst(' ', 'T'));
    }
    if (parsed == null) return asStr(raw);
    const List<String> weeks = <String>['日', '一', '二', '三', '四', '五', '六'];
    String two(int value) => value.toString().padLeft(2, '0');
    return '${parsed.month}月${parsed.day}日 周${weeks[parsed.weekday % 7]} '
        '${two(parsed.hour)}:${two(parsed.minute)}';
  }
}

class SeriesOccurrenceDisplaySource {
  const SeriesOccurrenceDisplaySource({
    required this.occurrenceAt,
    required this.cancelled,
    required this.signupCount,
    required this.refundedCount,
    required this.editable,
    required this.lockReason,
  });

  final Object? occurrenceAt;
  final bool cancelled;
  final int? signupCount;
  final int? refundedCount;
  final bool editable;
  final String lockReason;
}

/// 本场取消状态:`/api/club/event-ops/occurrence/status`。
class OccurrenceStatus {
  const OccurrenceStatus({
    required this.activityId,
    required this.cancelled,
    required this.publishStatus,
    required this.cancelReason,
  });

  final int activityId;
  final bool cancelled;
  final int publishStatus;
  final String cancelReason;

  static OccurrenceStatus? tryFromJson(
    Map<String, dynamic> json, {
    required int activityId,
  }) {
    final int scopedActivityId = asInt(json['activityId']);
    final String occurrenceStatus = asStr(json['occurrenceStatus']);
    final Object? rawPublish = json['publishStatus'];
    final Object? rawCancelled = json['activityCancelled'];
    if (scopedActivityId != activityId ||
        (occurrenceStatus != 'ACTIVE' && occurrenceStatus != 'CANCELLED') ||
        rawCancelled is! bool ||
        rawPublish is! int) {
      return null;
    }
    final bool cancelled = occurrenceStatus == 'CANCELLED';
    if (cancelled && (rawCancelled != true || rawPublish != 0)) return null;
    if (!cancelled && (rawCancelled != false || rawPublish != 1)) return null;
    return OccurrenceStatus(
      activityId: scopedActivityId,
      cancelled: cancelled,
      publishStatus: rawPublish,
      cancelReason: asStr(json['cancelReason']).trim(),
    );
  }
}

/// 取消本场回执:`/api/club/event-ops/cancel`。
class CancellationOutcome {
  const CancellationOutcome({required this.activityId, required this.refundStatus});

  final int activityId;
  final String refundStatus;

  /// 退款进度人话(小程序 cancellationSummary 逐字)。
  String get summary {
    switch (refundStatus) {
      case 'NOT_REQUIRED':
        return '无需退款';
      case 'MANUAL_REVIEW_REQUIRED':
        return '退款需人工跟进';
      case 'ACCEPTED_WITH_MANUAL_REVIEW':
        return '退款任务已受理，部分需人工跟进';
      case 'ACCEPTED':
      case 'REFUND_REQUESTED':
      case 'ALREADY_ACCEPTED':
        return '退款任务已受理';
      default:
        return '退款状态待回读';
    }
  }
}

/// 本场名册成员:`/api/club/event-ops/roster` 各桶行。
class RosterMember {
  const RosterMember({
    required this.memberId,
    required this.nickname,
    required this.correctionVersion,
    required this.state,
  });

  final int memberId;
  final String nickname;
  final int correctionVersion;
  final String state;

  static List<RosterMember>? tryList(Object? raw) {
    if (raw is! List) return null;
    final List<RosterMember> rows = <RosterMember>[];
    for (final Object? item in raw) {
      if (item is! Map<String, dynamic>) return null;
      final int memberId = asInt(item['memberId']);
      if (memberId <= 0) return null;
      final String nickname = asStr(item['nickname']).trim();
      rows.add(
        RosterMember(
          memberId: memberId,
          nickname: nickname.isEmpty ? '成员 #$memberId' : nickname,
          correctionVersion: item['correctionVersion'] is int
              ? item['correctionVersion'] as int
              : 0,
          state: asStr(item['state']),
        ),
      );
    }
    return rows;
  }
}

/// 名册四桶。`phoneIncluded` 必须是 false —— true 说明服务端越界下发了手机号。
class ClubRoster {
  const ClubRoster({
    required this.registered,
    required this.waitlist,
    required this.arrived,
    required this.noShow,
    required this.phoneIncluded,
  });

  final List<RosterMember> registered;
  final List<RosterMember> waitlist;
  final List<RosterMember> arrived;
  final List<RosterMember> noShow;
  final Object? phoneIncluded;

  /// 形状不全返回 null(页面进错误态)。
  static ClubRoster? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final List<RosterMember>? registered = RosterMember.tryList(
      raw['registered'],
    );
    final List<RosterMember>? waitlist = RosterMember.tryList(raw['waitlist']);
    final List<RosterMember>? arrived = RosterMember.tryList(raw['arrived']);
    final List<RosterMember>? noShow = RosterMember.tryList(raw['noShow']);
    if (registered == null ||
        waitlist == null ||
        arrived == null ||
        noShow == null ||
        raw['phoneIncluded'] != false) {
      return null;
    }
    return ClubRoster(
      registered: registered,
      waitlist: waitlist,
      arrived: arrived,
      noShow: noShow,
      phoneIncluded: raw['phoneIncluded'],
    );
  }
}

/// 治理记录行:`/api/club/governance/list`。
class GovernanceBan {
  const GovernanceBan({
    required this.id,
    required this.version,
    required this.sourceType,
    required this.sourceText,
    required this.targetNickname,
    required this.status,
    required this.statusText,
    required this.bannedAtText,
    required this.expiresText,
    required this.unbanReason,
    required this.canClubUnban,
  });

  final int id;
  final int version;
  final String sourceType;
  final String sourceText;
  final String targetNickname;
  final String status;
  final String statusText;
  final String bannedAtText;
  final String expiresText;
  final String unbanReason;
  final bool canClubUnban;

  static String _displayDate(Object? value) {
    final String text = asStr(value);
    if (text.isEmpty) return '';
    return text.replaceFirst('T', ' ').length >= 16
        ? text.replaceFirst('T', ' ').substring(0, 16)
        : text.replaceFirst('T', ' ');
  }

  static List<GovernanceBan>? tryList(Object? raw, int clubId) {
    if (raw is! List) return null;
    const List<String> allowedStatuses = <String>[
      'ACTIVE',
      'UNBANNED',
      'EXPIRED',
    ];
    const List<String> allowedSources = <String>['CLUB', 'PLATFORM'];
    final List<GovernanceBan> rows = <GovernanceBan>[];
    for (final Object? item in raw) {
      if (item is! Map<String, dynamic>) return null;
      final int id = asInt(item['id']);
      final int targetMemberId = asInt(item['targetMemberId']);
      final Object? rawVersion = item['version'];
      final String sourceType = asStr(item['sourceType']);
      final String status = asStr(item['status']);
      final String banReason = asStr(item['banReason']).trim();
      final bool hasExpires =
          item['expiresAt'] != null && asStr(item['expiresAt']).isNotEmpty;
      if (id <= 0 ||
          targetMemberId <= 0 ||
          asInt(item['clubId']) != clubId ||
          !allowedStatuses.contains(status) ||
          rawVersion is! int ||
          rawVersion < 0 ||
          !allowedSources.contains(sourceType) ||
          (sourceType == 'CLUB' && !hasExpires) ||
          banReason.isEmpty) {
        return null;
      }
      final bool platformPermanent =
          sourceType == 'PLATFORM' && !hasExpires;
      final String nickname = asStr(item['targetNickname']).trim();
      rows.add(
        GovernanceBan(
          id: id,
          version: rawVersion,
          sourceType: sourceType,
          sourceText: sourceType == 'PLATFORM' ? '平台治理' : '俱乐部治理',
          targetNickname: nickname.isEmpty ? '成员 #$targetMemberId' : nickname,
          status: status,
          statusText: status == 'ACTIVE'
              ? '封禁中'
              : (status == 'EXPIRED' ? '已到期' : '已解封'),
          bannedAtText: _displayDate(item['bannedAt']).isEmpty
              ? '时间未知'
              : _displayDate(item['bannedAt']),
          expiresText: platformPermanent
              ? '平台永久封禁'
              : '至 ${_displayDate(item['expiresAt'])}',
          unbanReason: asStr(item['unbanReason']).trim(),
          canClubUnban: status == 'ACTIVE' && sourceType == 'CLUB',
        ),
      );
    }
    return rows;
  }
}

/// 我的平台工单:`/api/club/governance/cases/mine`。
class GovernanceCase {
  const GovernanceCase({
    required this.id,
    required this.typeText,
    required this.reason,
    required this.createTimeText,
    required this.status,
    required this.statusText,
    required this.decisionReason,
  });

  final int id;
  final String typeText;
  final String reason;
  final String createTimeText;
  final String status;
  final String statusText;
  final String decisionReason;

  static String reportTargetText(String targetType) {
    if (targetType == 'CLUB') return '俱乐部';
    if (targetType == 'ACTIVITY') return '活动';
    return '成员';
  }

  static List<GovernanceCase>? tryList(Object? raw, int clubId) {
    if (raw is! List) return null;
    const List<String> allowedStatuses = <String>[
      'PENDING',
      'APPROVED',
      'REJECTED',
    ];
    const List<String> reportTargets = <String>['CLUB', 'ACTIVITY', 'MEMBER'];
    final List<GovernanceCase> rows = <GovernanceCase>[];
    for (final Object? item in raw) {
      if (item is! Map<String, dynamic>) return null;
      final int id = asInt(item['id']);
      final String caseType = asStr(item['caseType']);
      final String targetType = asStr(item['targetType']);
      final String status = asStr(item['status']);
      final Object? rawVersion = item['version'];
      final bool validTarget = caseType == 'APPEAL'
          ? targetType == 'BAN'
          : reportTargets.contains(targetType);
      if (id <= 0 ||
          asInt(item['clubId']) != clubId ||
          (caseType != 'REPORT' && caseType != 'APPEAL') ||
          !allowedStatuses.contains(status) ||
          rawVersion is! int ||
          rawVersion < 0 ||
          asInt(item['targetId']) <= 0 ||
          !validTarget) {
        return null;
      }
      rows.add(
        GovernanceCase(
          id: id,
          typeText: caseType == 'APPEAL'
              ? '封禁申诉'
              : '${reportTargetText(targetType)}举报',
          reason: asStr(item['reason']),
          createTimeText: GovernanceBan._displayDate(item['createTime']).isEmpty
              ? '时间未知'
              : GovernanceBan._displayDate(item['createTime']),
          status: status,
          statusText: status == 'PENDING'
              ? '平台处理中'
              : (status == 'APPROVED' ? '已支持' : '未支持'),
          decisionReason: asStr(item['decisionReason']).trim(),
        ),
      );
    }
    return rows;
  }
}

/// 角色定义:`/api/club/roles/list` 的 roles 项。
class RoleOption {
  const RoleOption({
    required this.roleCode,
    required this.name,
    required this.scopeType,
    required this.summary,
  });

  final String roleCode;
  final String name;
  final String scopeType;
  final String summary;

  /// 固定角色人话说明(小程序 ROLE_SUMMARY 逐字)。
  static const Map<String, String> summaries = <String, String>{
    'CLUB_CO_OWNER': '可维护俱乐部资料、成员与活动；不能分配角色',
    'CLUB_OPERATOR': '可管理内容、入会审核与成员通知；活动与现场权限按场次单独委派',
    'EVENT_LEAD': '仅负责当前场次的现场执行与核销',
    'EVENT_CHECKIN': '仅负责当前场次核销，不获得成员或财务权限',
  };

  /// 本俱乐部可选俱乐部级角色;带 activityId 时只可选场次级角色。
  static const List<String> clubRoleCodes = <String>[
    'CLUB_CO_OWNER',
    'CLUB_OPERATOR',
  ];
  static const List<String> eventRoleCodes = <String>[
    'EVENT_LEAD',
    'EVENT_CHECKIN',
  ];

  static bool allowed(String roleCode, {required bool eventScoped}) =>
      eventScoped
      ? eventRoleCodes.contains(roleCode)
      : clubRoleCodes.contains(roleCode);
}

/// 已生效的委派行:`/api/club/roles/list` 的 assignments 项。
class RoleAssignment {
  const RoleAssignment({
    required this.id,
    required this.targetMemberId,
    required this.memberName,
    required this.roleCode,
    required this.roleName,
    required this.scopeType,
    required this.scopeId,
    required this.version,
  });

  final int id;
  final int targetMemberId;
  final String memberName;
  final String roleCode;
  final String roleName;
  final String scopeType;
  final int scopeId;
  final int version;

  String get roleSummary => RoleOption.summaries[roleCode] ?? '';
}

/// `roles/list` 的合法形状:roles + assignments。
class RoleScopeData {
  const RoleScopeData({required this.roles, required this.assignments});

  final List<RoleOption> roles;
  final List<RoleAssignment> assignments;

  /// 形状/strict 校验失败返回 null(页面进错误态,不兜底)。
  static RoleScopeData? tryFromJson(
    Object? raw, {
    required int clubId,
    int? activityId,
  }) {
    if (raw is! Map<String, dynamic>) return null;
    final Object? rawRoles = raw['roles'];
    final Object? rawAssignments = raw['assignments'];
    if (rawRoles is! List || rawAssignments is! List) return null;
    final bool eventScoped = activityId != null && activityId > 0;
    final List<RoleOption> roles = <RoleOption>[];
    for (final Object? item in rawRoles) {
      if (item is! Map<String, dynamic>) return null;
      final String roleCode = asStr(item['roleCode']);
      if (!RoleOption.allowed(roleCode, eventScoped: eventScoped)) continue;
      final String name = asStr(item['name']);
      if (asStr(item['scopeType']) != (eventScoped ? 'EVENT' : 'CLUB') ||
          name.isEmpty ||
          item['permissions'] is! List) {
        return null;
      }
      roles.add(
        RoleOption(
          roleCode: roleCode,
          name: name,
          scopeType: asStr(item['scopeType']),
          summary: RoleOption.summaries[roleCode] ?? '',
        ),
      );
    }
    if (roles.isEmpty) return null;
    final List<RoleAssignment> assignments = <RoleAssignment>[];
    for (final Object? item in rawAssignments) {
      if (item is! Map<String, dynamic>) return null;
      final int id = asInt(item['id']);
      final int targetMemberId = asInt(item['targetMemberId']);
      final Object? rawVersion = item['version'];
      final String roleCode = asStr(item['roleCode']);
      if (id <= 0 ||
          targetMemberId <= 0 ||
          rawVersion is! int ||
          rawVersion < 0 ||
          !RoleOption.allowed(roleCode, eventScoped: eventScoped)) {
        continue;
      }
      final String scopeType = asStr(item['scopeType']);
      if (eventScoped) {
        if (scopeType != 'EVENT' || asInt(item['scopeId']) != activityId) {
          return null;
        }
      } else if (scopeType != 'CLUB' || asInt(item['scopeId']) != clubId) {
        return null;
      }
      final String memberName = asStr(item['memberName']).trim();
      assignments.add(
        RoleAssignment(
          id: id,
          targetMemberId: targetMemberId,
          memberName: memberName.isEmpty ? '成员 #$targetMemberId' : memberName,
          roleCode: roleCode,
          roleName: asStr(item['roleName']),
          scopeType: scopeType,
          scopeId: asInt(item['scopeId']),
          version: rawVersion,
        ),
      );
    }
    return RoleScopeData(roles: roles, assignments: assignments);
  }
}

/// 受众人数回执:`/api/club/event-notification/audience-counts`。
/// ⚠️ 服务端对「算不出来」的分组回 null —— 不拿 0 兜底。
class AudienceCounts {
  const AudienceCounts(this.counts);

  final Map<String, int?> counts;

  static AudienceCounts? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final Object? rawCounts = raw['counts'];
    if (rawCounts is! Map) return null;
    final Map<String, int?> counts = <String, int?>{};
    rawCounts.forEach((Object? key, Object? value) {
      if (key is! String) return;
      counts[key] = value is num ? value.toInt() : null;
    });
    return AudienceCounts(counts);
  }
}

/// 受众预览:`/api/club/event-notification/preview`。
class NotificationPreview {
  const NotificationPreview({
    required this.recipientCount,
    required this.phoneIncluded,
    required this.inApp,
    required this.wechatSubscription,
  });

  final int recipientCount;
  final Object? phoneIncluded;
  final String inApp;
  final String wechatSubscription;

  /// 非法形状(手机号越界 / 渠道状态不符)返回 null → 页面进错误态。
  static NotificationPreview? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final Object? rawCount = raw['recipientCount'];
    final int? count = rawCount is int
        ? rawCount
        : int.tryParse(asStr(rawCount));
    if (count == null ||
        count < 0 ||
        raw['phoneIncluded'] != false ||
        asStr(raw['inApp']) != 'AVAILABLE' ||
        asStr(raw['wechatSubscription']) != 'UNAVAILABLE') {
      return null;
    }
    return NotificationPreview(
      recipientCount: count,
      phoneIncluded: raw['phoneIncluded'],
      inApp: asStr(raw['inApp']),
      wechatSubscription: asStr(raw['wechatSubscription']),
    );
  }
}

/// 群发任务回执:`/api/club/event-notification/{send,retry}` 的 data。
class NotificationCampaign {
  const NotificationCampaign({
    required this.id,
    required this.totalCount,
    required this.successCount,
    required this.failedCount,
  });

  final int id;
  final int totalCount;
  final int successCount;
  final int failedCount;

  static NotificationCampaign? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final int id = asInt(raw['id']);
    if (id <= 0) return null;
    return NotificationCampaign(
      id: id,
      totalCount: asInt(raw['totalCount']),
      successCount: asInt(raw['successCount']),
      failedCount: asInt(raw['failedCount']),
    );
  }
}

/// 候补的七种状态(小程序 `pages/activity/baoming` 的 WAITLIST_STATES)。
const List<String> kWaitlistStates = <String>[
  'NONE',
  'WAITING',
  'OFFERED',
  'CLAIMED',
  'CONVERTED',
  'CANCELLED',
  'EXPIRED',
];

/// 能不能候补(小程序 WAITLIST_ELIGIBILITIES)。`ELIGIBLE` 是唯一能加入的一档。
const List<String> kWaitlistEligibilities = <String>[
  'NO_SERIES',
  'WAITLIST_CLOSED',
  'NOT_MEMBER',
  'ALREADY_REGISTERED',
  'ELIGIBLE',
  'BLOCKED',
];

/// 满员票种的候补真状态:`POST /api/club/event-ops/waitlist/status` 的 data。
///
/// ★ 这是**玩家侧**的候补(小程序在 `pages/activity/baoming`,俱乐部运营页只读
///   名册里的候补名单)。`entry` 就是回执本体,前端不复刻任何策略:
///   后端给 `waitlistJoinAllowed` + `eligibilityState` 两个字段表态,
///   前端只做「两个字段自洽」的校验(不自洽 = 回执坏了,进错误态而不是猜)。
class EventWaitlistStatus {
  const EventWaitlistStatus({
    required this.state,
    required this.eligibility,
    required this.joinAllowed,
    required this.entryId,
    required this.registrationId,
    required this.offerToken,
    required this.offerExpiresAt,
  });

  final String state;
  final String eligibility;
  final bool joinAllowed;

  /// 候补记录 id(`state == NONE` 时没有)。
  final int? entryId;
  final int? registrationId;

  /// 只有 `OFFERED` 才会短期下发原始 token。
  final String offerToken;
  final String offerExpiresAt;

  bool get isWaiting => state == 'WAITING';
  bool get isOffered => state == 'OFFERED';

  /// 我是不是正持有一个**还没过期**的候补名额。
  ///
  /// 后端策略上限 120 分钟,超出同样 fail-closed(小程序 offerDeadlineIsFuture
  /// 的原话:不能拿异常长的过期时间扩张付款窗口)。
  bool offerActive({DateTime? now}) {
    if (!isOffered || offerToken.isEmpty) return false;
    final DateTime? deadline = _parseOfferDeadline(offerExpiresAt);
    if (deadline == null) return false;
    final int delay = deadline.difference(now ?? DateTime.now()).inMilliseconds;
    return delay > 0 && delay <= 121 * 60 * 1000;
  }

  String get eligibilityMessage {
    switch (eligibility) {
      case 'NO_SERIES':
        return '本活动未配置候补';
      case 'WAITLIST_CLOSED':
        return '本场候补已关闭';
      case 'NOT_MEMBER':
        return '仅俱乐部正常成员可加入候补';
      case 'ALREADY_REGISTERED':
        return '你已有该票种的有效报名';
      case 'BLOCKED':
        return '你当前无法参与该俱乐部';
      default:
        return '当前暂不可加入候补';
    }
  }

  /// 能不能点「加入候补」:票种满 + 后端放行 + 当前状态可重新排队 + 没有请求在飞
  /// (小程序 `waitlistCanJoin` 的四条合取,一条不省)。
  bool canJoin({required bool ticketSoldOut, bool busy = false}) {
    const List<String> joinable = <String>[
      'NONE',
      'AVAILABLE',
      'CANCELLED',
      'EXPIRED',
    ];
    return ticketSoldOut &&
        eligibility == 'ELIGIBLE' &&
        joinAllowed &&
        joinable.contains(state) &&
        !busy;
  }

  static EventWaitlistStatus? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final String state = asStr(raw['state']).toUpperCase();
    final String eligibility = asStr(raw['eligibilityState']).toUpperCase();
    final Object? rawJoinAllowed = raw['waitlistJoinAllowed'];
    if (!kWaitlistStates.contains(state) ||
        !kWaitlistEligibilities.contains(eligibility) ||
        rawJoinAllowed is! bool) {
      return null;
    }
    final bool joinAllowed = rawJoinAllowed;
    if (joinAllowed != (eligibility == 'ELIGIBLE')) return null;

    final int id = asInt(raw['id']);
    final int registrationId = asInt(raw['registrationId']);
    if (state != 'NONE' && id <= 0) return null;
    if ((state == 'CLAIMED' || state == 'CONVERTED') && registrationId <= 0) {
      return null;
    }
    final String offerToken = asStr(raw['offerToken']);
    final String offerExpiresAt = asStr(raw['offerExpiresAt']);
    if (state == 'OFFERED' &&
        (offerToken.isEmpty || offerExpiresAt.isEmpty)) {
      return null;
    }
    return EventWaitlistStatus(
      state: state,
      eligibility: eligibility,
      joinAllowed: joinAllowed,
      entryId: id > 0 ? id : null,
      registrationId: registrationId > 0 ? registrationId : null,
      offerToken: offerToken,
      offerExpiresAt: offerExpiresAt,
    );
  }
}

/// 过期时间的容错解析(小程序 parseOfferDeadline:先按原样,不成就把 `-` 换 `/`)。
DateTime? _parseOfferDeadline(String raw) {
  if (raw.isEmpty) return null;
  final DateTime? direct = DateTime.tryParse(raw);
  if (direct != null) return direct;
  return DateTime.tryParse(raw.replaceAll('-', '/'));
}
