// 他人主页的关注按钮。
//
// ★★ 之前这页只有「关注 N」这个**数字**,没有关注按钮 ——
//   `registrationApi.toggleFollow()` 写好了、零调用方。
//   和圈子那个只读的评论图标是同一形状:看得到数,做不了那件事。
//
// ★★★ isFollow 是**三态**,不是两态。后端 PublicMemberServiceImpl 写得很明确:
//     匿名(未登录)访问时 isFollow **保持 null**,不查关注关系。
//     · 1    → 已关注,点=取关
//     · 0    → 未关注,点=关注
//     · null → 观看者关系未知(没登录)。这时**不能显示一个假的「关注」**,
//              否则用户点下去撞登录墙,而界面刚才还告诉他"你没关注这个人"。
//   把 null 和 0 合并(小程序那边 `isFollow == 1` 就是这么写的)在小程序里
//   无害,因为它总是已登录;App 有真游客态。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/profile_detail.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/feature/profile/user_profile_page.dart';

ProfileDetail _p(Object? isFollow) => ProfileDetail.fromJson(<String, dynamic>{
  'id': 42,
  'nickname': '小李',
  'avatar': '',
  'introduction': '',
  'followNum': 12,
  'fansNum': 34,
  'likeNum': 5,
  if (isFollow != null) 'isFollow': isFollow,
});

Future<void> _pump(WidgetTester t, ProfileDetail p) async {
  await t.binding.setSurfaceSize(const Size(390, 900));
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        otherProfileProvider(42).overrideWith((ref) async => p),
        otherPostsProvider(42).overrideWith(
          (ref) async => <SquarePost>[
            SquarePost(id: 9, memberId: 42, contents: '城市散步日记'),
          ],
        ),
      ].cast(),
      child: const MaterialApp(home: UserProfilePage(memberId: 42)),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  test('★★ isFollow 三态解析:1 / 0 / 缺失', () {
    expect(_p(1).isFollow, isTrue);
    expect(_p(0).isFollow, isFalse);
    expect(_p(null).isFollow, isNull, reason: '匿名时后端有意不下发 —— 不能当成"未关注"');
    // 后端将来若改发布尔,也别炸。
    expect(
      ProfileDetail.fromJson(<String, dynamic>{'isFollow': true}).isFollow,
      isTrue,
    );
  });

  // ⚠️ 断言必须锚到按钮的 key,不能只 find.text('关注') ——
  //   统计行里就有一个「关注 12」的标签,那条断言第一版是**假绿**:
  //   按钮还没写出来它就过了。
  String? _label(WidgetTester t) {
    final Finder f = find.byKey(const Key('profile-follow-btn'));
    if (f.evaluate().isEmpty) return null;
    return (t.widget<Text>(
      find.descendant(of: f, matching: find.byType(Text)),
    )).data;
  }

  testWidgets('★★ 未关注:按钮说「关注」', (WidgetTester t) async {
    await _pump(t, _p(0));
    expect(_label(t), '关注');
  });

  testWidgets('★★ 已关注:按钮说「已关注」—— 不能显示成还没关注', (WidgetTester t) async {
    await _pump(t, _p(1));
    expect(_label(t), '已关注');
  });

  testWidgets('★★★ 关系未知(游客):不许显示假的「关注」', (WidgetTester t) async {
    await _pump(t, _p(null));
    expect(_label(t), '登录后关注', reason: '说清楚"要先登录",而不是先给一个会被登录墙挡住的「关注」');
  });

  testWidgets('他人主页保留推文/成就/关于三页，不暴露「我的」', (WidgetTester t) async {
    await _pump(t, _p(0));
    expect(find.text('推文'), findsOneWidget);
    expect(find.text('成就'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('我的'), findsNothing);
    // 游客态推文栏是登录引导(P1-1):这条流要登录态,不能拿必然 401 的请求当内容。
    // 登录后能看到推文那条断言在 user_profile_page_test.dart(那里注入了登录态)。
    expect(find.text('登录后查看 TA 的动态'), findsOneWidget);
    expect(find.text('城市散步日记'), findsNothing);

    await t.tap(find.text('成就'));
    await t.pumpAndSettle();
    expect(find.text('发布内容'), findsOneWidget);
    expect(find.text('获赞'), findsWidgets);
    expect(find.text('粉丝'), findsWidgets);

    await t.tap(find.text('关于'));
    await t.pumpAndSettle();
    expect(find.text('个人介绍'), findsOneWidget);
  });
}
