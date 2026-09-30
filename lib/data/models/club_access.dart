/// 俱乐部访问上下文(`POST /api/club/access/me`)。
///
/// 判定真源是小程序 `utils/access-gate.js#decideClubGate`:
/// 只有**明确**的拒绝(active=false / club 范围不符 / 权限串缺失 / 401·403)
/// 才拦;回执坏了判 unknown、**不拦** —— 把网络问题栽成「没权限」比不拦更坏,
/// 后端本来就会拦。
class ClubAccess {
  const ClubAccess({
    required this.active,
    this.clubId,
    this.clubName,
    required this.permissions,
    required this.roleCodes,
    this.eventAccesses = const <ClubEventAccess>[],
    this.delegatedRoleCount = 0,
  });

  final bool active;
  final int? clubId;
  final String? clubName;
  final Set<String> permissions;
  final List<String> roleCodes;

  /// 场次级委派(领队 / 核销员)：小程序 `shapeEventAccesses(access.eventAccesses)`。
  /// 这些角色的权限不在俱乐部级 `permissions` 里，而在每一场的 `eventAccesses[i].permissions`，
  /// 只能靠「有任一场次授权」把管理入口开给他们(hasEventScope)。
  final List<ClubEventAccess> eventAccesses;

  /// 「角色与权限」行右侧的「N 已委派」。只有 ROLE_MANAGE 拿得到这个数，
  /// 治理信息不进公开 detail，所以缺省 0 就不显示尾标。
  final int delegatedRoleCount;

  bool has(String permission) => permissions.contains(permission);

  // —— 细粒度权限位（逐字对齐小程序 `pages/club/detail/index.js` 的 has(...)）——
  bool get canManageClub => has('club:write');
  bool get canManageContent => has('club:content:manage');
  bool get canApproveMembersByPerms => has('club:member:approve');
  bool get canManageMembers => has('club:member:manage');
  bool get canManageRoles => has('club:role:manage');
  bool get canSendNotify => has('club:notify:send');
  bool get canManageActivities => has('club:activity:manage');
  bool get canOperateEvents => has('club:event:operate');
  bool get canCheckInEvents => has('club:event:checkin');

  /// 有没有任何场次级授权（领队/核销员只能从这条路进管理 tab）。
  bool get hasEventScope => eventAccesses.isNotEmpty;

  /// 管理 tab 是否出现：任一**细粒度**管理权限或有场次授权。
  /// 主理人/旧式管理员的 legacy 判据在 [Club.canGovern]，两者在页面侧再取并集
  /// （小程序 `canUseManageTab = legacyCanGovern || <这些权限位> || hasEventScope`）。
  bool get canUseManageTabByPerms =>
      canManageClub ||
      canApproveMembersByPerms ||
      canManageMembers ||
      canManageContent ||
      canManageRoles ||
      canSendNotify ||
      canManageActivities ||
      canOperateEvents ||
      canCheckInEvents ||
      canReadFinance ||
      hasEventScope;

  /// 客户名单 / 客户详情页的 need(小程序 `cy-access-gate need="club:member:list:read"`)。
  bool get canReadMembers => has('club:member:list:read');

  /// 俱乐部分润页的 need(小程序 `need="club:finance:read"`)。
  bool get canReadFinance => has('club:finance:read');

  /// `active` 不是 bool 就抛 FormatException —— 由门禁判 unknown,不拦。
  factory ClubAccess.fromJson(Map<String, dynamic> json) {
    final Object? active = json['active'];
    if (active is! bool) {
      throw const FormatException('俱乐部权限回执不完整');
    }
    int? clubId;
    String? clubName;
    final Object? rawClub = json['club'];
    if (rawClub is Map) {
      final Object? rawId = rawClub['id'];
      clubId = rawId is num ? rawId.toInt() : int.tryParse('${rawId ?? ''}');
      final String name = '${rawClub['name'] ?? ''}'.trim();
      clubName = name.isEmpty ? null : name;
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
    final List<ClubEventAccess> eventAccesses = <ClubEventAccess>[];
    final Object? rawEventAccesses = json['eventAccesses'];
    if (rawEventAccesses is List) {
      for (final Object? item in rawEventAccesses) {
        if (item is! Map) continue;
        final ClubEventAccess? row = ClubEventAccess.tryParse(
          Map<String, dynamic>.from(item),
        );
        if (row != null) eventAccesses.add(row);
      }
    }
    final int delegatedRoleCount = json['delegatedRoleCount'] is num
        ? (json['delegatedRoleCount'] as num).toInt()
        : 0;
    return ClubAccess(
      active: active,
      clubId: clubId,
      clubName: clubName,
      permissions: permissions,
      roleCodes: roleCodes,
      eventAccesses: eventAccesses,
      delegatedRoleCount: delegatedRoleCount < 0 ? 0 : delegatedRoleCount,
    );
  }
}

/// 一场活动（主题）的场次级授权投影。
class ClubEventAccess {
  const ClubEventAccess({
    required this.activityId,
    required this.topicId,
    required this.roleCodes,
    required this.permissions,
  });

  final int activityId;
  final int topicId;
  final List<String> roleCodes;
  final Set<String> permissions;

  bool has(String permission) => permissions.contains(permission);

  /// 坏行跳过而不是整份拒收：管理 tab 只要数得出「有没有场次授权」就够，
  /// 单行字段缺漏不该把人锁在门外（后端各操作页仍会各自拦权限）。
  static ClubEventAccess? tryParse(Map<String, dynamic> json) {
    final int? activityId = _positiveId(json['activityId']);
    final int? topicId = _positiveId(json['topicId']);
    if (activityId == null || topicId == null) return null;
    final List<String> roleCodes = <String>[];
    final Object? rawRoles = json['roleCodes'];
    if (rawRoles is List) {
      for (final Object? item in rawRoles) {
        if (item is String && item.isNotEmpty) roleCodes.add(item);
      }
    }
    final Set<String> permissions = <String>{};
    final Object? rawPerms = json['permissions'];
    if (rawPerms is List) {
      for (final Object? item in rawPerms) {
        if (item is String && item.isNotEmpty) permissions.add(item);
      }
    }
    if (roleCodes.isEmpty) return null;
    return ClubEventAccess(
      activityId: activityId,
      topicId: topicId,
      roleCodes: roleCodes,
      permissions: permissions,
    );
  }

  static int? _positiveId(Object? value) {
    if (value is num) return value.toInt() > 0 ? value.toInt() : null;
    final int? parsed = int.tryParse('${value ?? ''}'.trim());
    return (parsed != null && parsed > 0) ? parsed : null;
  }
}
