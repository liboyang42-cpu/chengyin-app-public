import '../../data/models/square_post.dart';

/// 楼中楼:这条回复是在回谁。
///
/// 优先按 `parentId` 找到被回复的那条评论;父评论还没加载出来时,
/// 退回 `repliedToMemberId` 在已加载评论里的作者名。
/// 两者都解不出来就返回 null —— **不显示**比编一个名字强。
String? squareReplyToName(Comment comment, List<Comment> loaded) {
  if (comment.parentId == null && comment.repliedToMemberId == null) {
    return null;
  }
  if (comment.parentId != null) {
    for (final Comment parent in loaded) {
      if (parent.id == comment.parentId) {
        final String name = (parent.memberNickname ?? '').trim();
        if (name.isNotEmpty) return name;
        break;
      }
    }
  }
  final int? memberId = comment.repliedToMemberId;
  if (memberId == null) return null;
  for (final Comment candidate in loaded) {
    if (candidate.memberId != memberId) continue;
    final String name = (candidate.memberNickname ?? '').trim();
    if (name.isNotEmpty) return name;
  }
  return null;
}
