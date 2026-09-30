/// 当前会员的角色 + 配额 + 用量:`POST /api/role/info`。
///
/// ★★ 后端注释把它定为**单一事实源**:「下发三端能力位全集,
///   前端 roleGuard 一律读这里」。
///   ⇒ 别在客户端自己推能力(比如"userType==2 就是商家所以能发券")——
///     那是第二份判据,必然和后端漂。
///
/// ★★ 第二条更要紧:「**role 仅『默认视角』,能力由记录推断**;
///   前端据此同时显示玩家+主理人+商家身份并提供视角切换,
///   不再因 role=club 自动跳管理台」。
///   ⇒ 一个人可以**同时**是玩家、主理人、商家。
///     用 role 做 if/else 分支会把另外两个身份藏起来。
library;

class RoleInfo {
  const RoleInfo({
    required this.role,
    required this.permission,
    required this.usage,
    required this.isClubLeader,
    required this.isMerchant,
    this.leaderLevel,
    required this.ownedClubCount,
    required this.maxOwnedClubs,
    required this.ownedClubs,
    required this.joinedClubIds,
  });

  /// 默认视角。**不是唯一身份** —— 见类注释。
  final String role;

  /// 能力位全集。键见后端 permission.put(...):
  /// maxThemes / maxNodesPerTheme / maxEvents / maxCoupons /
  /// canCreateTheme / canCreateEvent / canPublishCoupon / canRedeemCoupon /
  /// nodeTypes / canBranch / canGameMechanic / canOpenAsNode /
  /// canDesignMedal / canCreateGroup / canCreateClub / dataScope / withdrawable
  final Map<String, dynamic> permission;

  /// 当前用量:themes / themesOnline / events / coupons。
  final Map<String, dynamic> usage;

  final bool isClubLeader;
  final bool isMerchant;
  final int? leaderLevel;

  final int ownedClubCount;
  final int maxOwnedClubs;
  final List<Map<String, dynamic>> ownedClubs;
  final List<int> joinedClubIds;

  /// 读一个布尔能力位。
  ///
  /// ★ **缺席返回 false**(能力位缺了就是没有这个能力),
  ///   但缺席与 false 在这里含义相同,所以不需要三态。
  ///   ⚠️ 数值配额不同,见 [quota]。
  bool can(String key) => permission[key] == true;

  /// 读一个数值配额。
  ///
  /// ★★ **缺席返回 null,不是 0**。0 是"一个都不许建"这个真实配置,
  ///   把"没下发"说成 0 会让界面把功能整个锁死,而且没人看得出为什么。
  int? quota(String key) =>
      permission[key] is num ? (permission[key] as num).toInt() : null;

  int used(String key) => usage[key] is num ? (usage[key] as num).toInt() : 0;

  /// 在架主题还能建几个。配额没下发时返回 null(=未知,别显示成 0)。
  int? get themesLeft {
    final int? max = quota('maxThemes');
    if (max == null) return null;
    final int left = max - used('themesOnline');
    return left < 0 ? 0 : left;
  }

  /// ★ 三个身份可以**同时**成立。界面按这三个各自决定露不露,
  ///   不要用 role 做 if/else。
  bool get hasPlayerFace => true; // 所有人都是玩家
  bool get hasLeaderFace => isClubLeader;
  bool get hasMerchantFace => isMerchant;

  static List<Map<String, dynamic>> _maps(Object? v) =>
      (v as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();

  factory RoleInfo.fromJson(Map<String, dynamic> json) => RoleInfo(
        // effectiveRole 与 role 后端下发的是同一个值,取 role 即可。
        role: (json['role'] ?? '').toString(),
        permission:
            (json['permission'] as Map<String, dynamic>?) ?? <String, dynamic>{},
        usage: (json['usage'] as Map<String, dynamic>?) ?? <String, dynamic>{},
        isClubLeader: json['isClubLeader'] == true,
        isMerchant: json['isMerchant'] == true,
        leaderLevel: json['leaderLevel'] is num
            ? (json['leaderLevel'] as num).toInt()
            : null,
        ownedClubCount: json['ownedClubCount'] is num
            ? (json['ownedClubCount'] as num).toInt()
            : 0,
        maxOwnedClubs: json['maxOwnedClubs'] is num
            ? (json['maxOwnedClubs'] as num).toInt()
            : 0,
        ownedClubs: _maps(json['ownedClubs']),
        joinedClubIds: (json['joinedClubIds'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<num>()
            .map((num e) => e.toInt())
            .toList(),
      );
}
