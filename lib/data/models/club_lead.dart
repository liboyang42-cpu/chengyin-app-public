/// 俱乐部带队进度。对齐后端 `ApiClubLeadController.teamProgress`
/// (GET /api/club/lead/team-progress)。
class TeamProgress {
  const TeamProgress({
    this.exists = false,
    this.status,
    this.leaderMemberId,
    this.isLeader = false,
    this.currentChapterId,
    this.chapterName,
    this.broadcast,
    this.broadcastAt,
    this.arrived = 0,
    this.meArrived = false,
    this.members = const <TeamMember>[],
  });

  /// 这一场有没有开队。★ false 时**不是错误** —— 是"还没开始带队",
  ///   界面该给「开始带队」而不是「加载失败」。
  final bool exists;

  final int? status;
  final int? leaderMemberId;

  /// 当前用户是不是队长。★ 决定能不能广播/解锁章节/结算。
  final bool isLeader;

  final int? currentChapterId;
  final String? chapterName;

  /// 队长的最新广播。
  final String? broadcast;
  final String? broadcastAt;

  /// 已到达人数。
  final int arrived;

  /// **我自己**签到没有(后端 `d.meArrived`,真源 index.js 同字段)。
  /// 决定集合态摆「我到了」还是「已签到」。
  final bool meArrived;

  final List<TeamMember> members;

  /// 到达进度文案。★ 队伍为空时不显示「0/0」——
  ///   那既没信息也让人以为出错了。
  String? get arrivedText =>
      members.isEmpty ? null : '$arrived / ${members.length} 人已到';

  /// 全员到齐 —— 队长可以解锁下一章了。
  bool get allArrived => members.isNotEmpty && arrived >= members.length;

  factory TeamProgress.fromJson(Map<String, dynamic> json) {
    return TeamProgress(
      exists: json['exists'] == true,
      status: (json['status'] as num?)?.toInt(),
      leaderMemberId: (json['leaderMemberId'] as num?)?.toInt(),
      isLeader: json['isLeader'] == true,
      currentChapterId: (json['currentChapterId'] as num?)?.toInt(),
      chapterName: json['chapterName'] as String?,
      broadcast: json['broadcast'] as String?,
      broadcastAt: json['broadcastAt']?.toString(),
      arrived: (json['arrived'] as num?)?.toInt() ?? 0,
      meArrived: json['meArrived'] == true || json['meArrived'] == 1,
      members: ((json['members'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(TeamMember.fromJson)
          .toList(),
    );
  }
}

/// 队伍成员。
class TeamMember {
  const TeamMember({
    required this.memberId,
    required this.nickname,
    this.avatar,
    this.done = 0,
    this.arrived = false,
    this.isLeader = false,
  });

  final int memberId;
  final String nickname;
  final String? avatar;

  /// 已完成节点数。
  final int done;
  final bool arrived;
  final bool isLeader;

  /// 显示名。后端拿不到用户时会下发空串 —— 兜底,不显示一片空白。
  String get displayName =>
      nickname.trim().isEmpty ? '队员 $memberId' : nickname.trim();

  factory TeamMember.fromJson(Map<String, dynamic> json) {
    return TeamMember(
      memberId: (json['memberId'] as num?)?.toInt() ?? 0,
      nickname: (json['nickname'] as String?) ?? '',
      avatar: json['avatar'] as String?,
      done: (json['done'] as num?)?.toInt() ?? 0,
      arrived: json['arrived'] == true,
      isLeader: json['isLeader'] == true,
    );
  }
}

/// 队长可做的动作。★ 非队长一个都不给 —— 后端会拒,摆出来就是骗人。
enum LeadAction { broadcast, verifyMemberTicket, unlockChapter, settle }

extension LeadActionX on LeadAction {
  /// 动作名照真源工具行(index.wxml:608/621 与章节放行行)逐字。
  String get label {
    switch (this) {
      case LeadAction.broadcast:
        return '发广播';
      case LeadAction.verifyMemberTicket:
        return '扫成员票核销';
      case LeadAction.unlockChapter:
        return '解锁下一章节';
      case LeadAction.settle:
        return '整团结算';
    }
  }
}

/// 当前可用的队长动作。
///
/// ★ 「解锁下一章」只在**全员到齐**时给 —— 后端也会拦,
///   但前端提前禁用能省一次失败,并且用「还差 N 人」说清在等什么。
List<LeadAction> availableLeadActions(TeamProgress p) {
  if (!p.isLeader || !p.exists) return const <LeadAction>[];
  return <LeadAction>[
    LeadAction.broadcast,
    // ★★ 核销队员票**必须从本团入口走**,不能复用商家首页的通用扫码。
    //   小程序注释原话:「否则请求没有场次身份,后端会 fail closed,
    //   结算也无法区分同主题的不同团」。
    //   ⇒ 判据同其余队长动作(isLeader && exists),且调用时必带本团 activityId。
    LeadAction.verifyMemberTicket,
    if (p.allArrived) LeadAction.unlockChapter,
    LeadAction.settle,
  ];
}

/// 解锁被挡住时的说明。返回 null 表示没被挡。
String? unlockBlockedReason(TeamProgress p) {
  if (!p.isLeader) return null;
  if (p.members.isEmpty) return null;
  if (p.allArrived) return null;
  return '还差 ${p.members.length - p.arrived} 人到达才能解锁下一章';
}
