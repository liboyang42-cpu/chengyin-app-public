/// 俱乐部动态的评论(`/api/club/post/comment/*`)。
class ClubComment {
  const ClubComment({
    required this.id,
    this.postId,
    this.memberId,
    this.content,
    this.nickname,
    this.avatar,
    this.createTime,
  });

  final int id;
  final int? postId;

  /// 评论作者。★ 拿它判「这条是不是我发的」,决定给删除还是给举报。
  final int? memberId;

  final String? content;
  final String? nickname;
  final String? avatar;
  final String? createTime;

  /// 展示用昵称。★ 兜底文案**不进头像** —— 否则会渲出一个「城」字当姓氏。
  String get displayName {
    final String n = (nickname ?? '').trim();
    return n.isEmpty ? '城瘾用户' : n;
  }

  /// 头像用的名字。拿不到昵称时给 null,让头像走默认图而不是兜底文案首字。
  String? get avatarName {
    final String n = (nickname ?? '').trim();
    return n.isEmpty ? null : n;
  }

  factory ClubComment.fromJson(Map<String, dynamic> json) {
    String? s(String k) {
      final String t = (json[k] ?? '').toString().trim();
      return t.isEmpty ? null : t;
    }

    return ClubComment(
      id: (json['id'] as num?)?.toInt() ?? 0,
      postId: (json['postId'] as num?)?.toInt(),
      memberId: (json['memberId'] as num?)?.toInt(),
      content: s('content'),
      nickname: s('nickname'),
      avatar: s('avatar'),
      createTime: s('createTime'),
    );
  }
}

/// 谁能删这条评论。
///
/// ★ **不是「只能删自己的」** —— 后端 `ApiClubController.canModerate:171-179`
///   放行三种人:
///     ① 评论作者本人
///     ② 俱乐部创建者(club.memberId)
///     ③ 该俱乐部里 role == 1 的管理员
///   这是**社区代管**语义:主理人要能清掉别人发的脏东西。
///
/// ⚠️ 前端按这条决定**显示哪个入口**(删除 or 举报),不是权限判据 ——
///   真正的授权在后端,越权会被 `无权删除` 挡下。
///   前端判宽了只是多显示一个会失败的按钮,判窄了则会让主理人**管不了自己的圈子**。
bool canModerateComment({
  required int? viewerMemberId,
  required int? commentAuthorId,
  required int? clubOwnerMemberId,
  required bool viewerIsClubAdmin,
}) {
  if (viewerMemberId == null) return false;
  if (commentAuthorId != null && viewerMemberId == commentAuthorId) return true;
  if (clubOwnerMemberId != null && viewerMemberId == clubOwnerMemberId) {
    return true;
  }
  return viewerIsClubAdmin;
}

/// 俱乐部成员管理的权限判据。
///
/// ★ 两条接口的权限**不在同一档**,最容易写成一样:
///   · 移除成员    —— 只有**创建者**(ApiClubController:577-579)
///   · 设/取消管理员 —— 也只有**创建者**(:1188)
///   而删评论(canModerateComment)却放行**创建者 + role==1 管理员 + 作者本人**。
///   也就是说:管理员能删评论,但**不能踢人、不能任命别人**。
///   把三者混成同一个「isAdmin」判据,会让管理员看到一堆点了必失败的按钮。
///
/// ⚠️ 这层只决定**显示什么入口**,真正授权在后端。
bool canManageClubMembers({
  required int? viewerMemberId,
  required int? clubOwnerMemberId,
}) {
  if (viewerMemberId == null || clubOwnerMemberId == null) return false;
  return viewerMemberId == clubOwnerMemberId;
}

/// 能不能移除**这一个**成员。
///
/// ★ 创建者不能被移除(后端「不能移除俱乐部创建者」)—— 前端也别给这个按钮,
///   否则主理人会对着自己那一行点一个注定失败的「移除」。
bool canRemoveThisMember({
  required int? viewerMemberId,
  required int? clubOwnerMemberId,
  required int? targetMemberId,
}) {
  if (!canManageClubMembers(
      viewerMemberId: viewerMemberId, clubOwnerMemberId: clubOwnerMemberId)) {
    return false;
  }
  if (targetMemberId == null) return false;
  return targetMemberId != clubOwnerMemberId;
}
