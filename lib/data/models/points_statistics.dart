/// 积分统计(`/api/user/points/statistics`)。
///
/// ★ App 此前没接 —— 积分页只有流水,**没有「我在所有人里排第几」**这层。
class PointsStatistics {
  const PointsStatistics({
    this.weekPoints,
    this.rankPercentage,
    this.totalUsers,
    this.userRank,
  });

  /// 本周获得的积分。★ 可空 —— 后端是 BigDecimal,拿不到时别兜 0:
  /// 「这周没赚到」和「统计没算出来」是两回事。
  final String? weekPoints;

  /// 超过百分之多少的人。后端给的是**字符串**(可能带 % 号),
  /// 原样展示 —— 转成 double 再格式化会引入舍入差异,而这是个对外的名次。
  final String? rankPercentage;

  final int? totalUsers;

  /// 我的名次。★ 可空:**没有名次**(比如本周零积分未入榜)和「第 0 名」是两回事。
  final int? userRank;

  /// 有没有可展示的名次。★ 判据要 rank 与 total **都**在 ——
  /// 只有 rank 没有 total 时,「第 12 名」这句话是悬空的。
  bool get hasRank => userRank != null && userRank! > 0 && totalUsers != null;

  factory PointsStatistics.fromJson(Map<String, dynamic> json) {
    String? s(String k) {
      final String t = (json[k] ?? '').toString().trim();
      return t.isEmpty ? null : t;
    }

    return PointsStatistics(
      weekPoints: s('weekPoints'),
      rankPercentage: s('rankPercentage'),
      totalUsers: (json['totalUsers'] as num?)?.toInt(),
      userRank: (json['userRank'] as num?)?.toInt(),
    );
  }
}

/// 我邀请过的人(`/api/user/invite_list`)。
class InvitedMember {
  const InvitedMember({
    required this.id,
    this.nickname,
    this.avatar,
    this.createTime,
  });

  final int id;
  final String? nickname;
  final String? avatar;

  /// 加入时间。
  final String? createTime;

  /// 展示名。★ 兜底文案**不进头像** —— 否则渲出一个「城」字当姓氏。
  String get displayName {
    final String n = (nickname ?? '').trim();
    return n.isEmpty ? '城瘾用户' : n;
  }

  String? get avatarName {
    final String n = (nickname ?? '').trim();
    return n.isEmpty ? null : n;
  }

  factory InvitedMember.fromJson(Map<String, dynamic> json) {
    String? s(String k) {
      final String t = (json[k] ?? '').toString().trim();
      return t.isEmpty ? null : t;
    }

    return InvitedMember(
      id: (json['id'] as num?)?.toInt() ?? 0,
      nickname: s('nickname'),
      avatar: s('avatar'),
      createTime: s('createTime'),
    );
  }
}
