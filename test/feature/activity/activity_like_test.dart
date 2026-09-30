// 活动点赞态是**三态**,不是两态。
//
// ★★ 后端 `CmsActivity.isLiked` 注释原话:
//   「自己是否点赞 **0未操作 1已点赞 2已踩**」。
//   写成 bool 会把「踩过」混成「没点过」——那两件事对界面意味着不同的下一步。
//
// ⚠️ 未登录时后端一律置 0(ApiActivityController:267/388
//   `member_id > 0 ? likeMap... : 0`)—— 「没登录」和「没点过」在这个字段上
//   **分不开**。判「要不要弹登录」只能看登录态本身,不能看它。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/activity.dart';

Activity _a(Object? isLiked) => Activity.fromJson(<String, dynamic>{
  'id': 1,
  'name': '静安夜行',
  if (isLiked != null) 'isLiked': isLiked,
});

void main() {
  test('★★ 0/1/2 三态各归各的', () {
    expect(_a(0).likeState, ActivityLikeState.none);
    expect(_a(1).likeState, ActivityLikeState.liked);
    expect(
      _a(2).likeState,
      ActivityLikeState.disliked,
      reason: '「踩过」被当成「没点过」的话,界面会把踩过的活动显示成可赞',
    );
  });

  test('★★ 缺席 / 认不出来一律按「没操作过」,不猜成已赞', () {
    expect(_a(null).likeState, ActivityLikeState.none);
    expect(_a(99).likeState, ActivityLikeState.none);
    expect(_a('yes').likeState, ActivityLikeState.none);
  });

  test('★ liked 是便捷判据,只在真的 1 时为真', () {
    expect(_a(1).liked, isTrue);
    expect(_a(0).liked, isFalse);
    expect(_a(2).liked, isFalse, reason: '踩过不等于赞过');
  });

  test('★★ ActivityDetail 也要解析 —— 详情页的按钮靠它显示状态', () {
    ActivityDetail d(Object? v) => ActivityDetail.fromJson(<String, dynamic>{
      'id': 1,
      'name': '静安夜行',
      if (v != null) 'isLiked': v,
    });
    expect(d(1).liked, isTrue);
    expect(d(2).liked, isFalse, reason: '踩过不是赞过');
    expect(d(null).liked, isFalse);
    expect(d(null).likeState, ActivityLikeState.none);
  });

  test('活动详情保留小程序评分摘要', () {
    final ActivityDetail detail = ActivityDetail.fromJson(<String, dynamic>{
      'id': 1,
      'name': '静安夜行',
      'rating': 5,
      'commentCount': 1,
    });

    expect(detail.rating, 5);
    expect(detail.commentCount, 1);
  });
}
