/// 用户模型。
/// `role` = RBAC 角色,登录即落地,是写权限的**单一真源**(与后端/小程序一致)。
class User {
  User({
    required this.id,
    required this.nickname,
    required this.avatar,
    required this.role,
    this.userType,
    this.xp = 0,
    this.level = 1,
  });

  final int id;
  final String nickname;
  final String avatar;
  final String role;

  /// 后端 `ums_member.user_type`。★ **不能省** —— role 未回填时它是唯一判据。
  /// 可空:后端两套结构里 AppUser 那套根本不下发它,`null` ≠ `1`。
  final int? userType;

  final int xp;
  final int level;

  /// 兼容两套后端结构:登录返回 UmsMember(id/nickname/role/levelId/point)、
  /// userInfo 返回 AppUser(userId/nickName,无 role/level/point)。
  factory User.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v, int fallback) => v is num ? v.toInt() : fallback;
    return User(
      id: asInt(json['id'] ?? json['userId'], 0),
      nickname: (json['nickname'] ?? json['nickName'] ?? '') as String,
      avatar: (json['avatar'] ?? '') as String,
      // ★ 不在这里兜 'player' —— 兜了就把「role 没回填」和「确实是玩家」合并了,
      //   而这两种情况下 userType 兜底该不该生效**正好相反**。解析保留原样,
      //   身份判断交给 effectiveRole。
      role: (json['role'] ?? '') as String,
      userType: json['userType'] is num
          ? (json['userType'] as num).toInt()
          : int.tryParse('${json['userType'] ?? ''}'),
      xp: asInt(json['point'] ?? json['xp'], 0),
      level: asInt(json['levelId'] ?? json['level'], 1),
    );
  }

  /// 展示身份。**逐字镜像后端 `RoleServiceImpl.resolveRole`**
  /// (chengyinhub-system/.../RoleServiceImpl.java:38-55)与小程序
  /// `utils/identity/identity-policy.js:resolveRole`:
  ///   role 非空优先 → 否则 userType==2 判 merchant → 其余 player。
  ///
  /// ★ 三端必须同口径。App 此前把 userType 整个丢掉、role 缺席兜成 'player',
  ///   于是「role 没回填的商家」在小程序是商家视角、在 App 是玩家视角 ——
  ///   同一个账号两个产品长相,而且不报错。
  String get effectiveRole {
    if (role.isNotEmpty) return role;
    if (userType == 2) return 'merchant';
    return 'player';
  }

  /// 商家视角。8 个页面(设置/活动详情/模板/模板详情/官方收件箱/我的官方活动/
  /// 合作邀约/达人列表)在小程序里按它切浅色主题,不是整条路由恒浅。
  bool get isMerchantView => effectiveRole == 'merchant';
}
