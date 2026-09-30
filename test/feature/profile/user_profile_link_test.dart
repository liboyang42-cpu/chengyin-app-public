// 他人主页:链接里没有 memberId 时,说的是"链接不完整",不是"加载失败"。
//
// ★ 真源 `pages/userinfo/userinfo.wxml` 的 missingUser 态:不渲 profile 组件、
//   不拉接口,直接告诉用户是哪一段坏了,出口是「回到我的主页」。
//   App 原来把这种链接丢给 /api/user/public-info(memberId=0),
//   用户看到的是"看不到这个人的主页" —— 他会以为这个人有问题,而不是链接有问题。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/profile_detail.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/feature/profile/user_profile_page.dart';

int _calls = 0;

Future<void> _pump(WidgetTester t, int memberId) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        otherProfileProvider(memberId).overrideWith((Ref ref) async {
          _calls += 1;
          return ProfileDetail(
            id: memberId,
            nickname: '阿城',
            avatar: '',
            introduction: '',
            levelId: 0,
            point: 0,
            followNum: 0,
            fansNum: 0,
            likeNum: 0,
            topicNum: 0,
            activityNum: 0,
          );
        }),
        // 推文那一支也钉住:不钉就会去打真网络,而骨架屏是**无限循环**动画,
        // pumpAndSettle 永远等不到静止(仓库里已记过这条)。
        otherPostsProvider(
          memberId,
        ).overrideWith((Ref ref) async => const <SquarePost>[]),
      ].cast(),
      child: MaterialApp(home: UserProfilePage(memberId: memberId)),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() => _calls = 0);

  testWidgets('★ 链接缺用户:id<=0 时说的是链接不完整,且不拉接口', (WidgetTester t) async {
    await _pump(t, 0);
    expect(find.text('这个主页链接不完整'), findsOneWidget);
    expect(find.text('链接里没有用户信息，暂时无法打开个人主页。'), findsOneWidget);
    expect(find.text('回到我的主页'), findsOneWidget);
    expect(_calls, 0, reason: 'id=0 也去问一次后端 = 拿一个必然失败的请求换一句假错误');
  });

  testWidgets('★ 有 id 才拉接口(守卫不能把正常链接也挡掉)', (WidgetTester t) async {
    await _pump(t, 42);
    expect(_calls, greaterThanOrEqualTo(1));
    expect(find.text('阿城'), findsOneWidget);
    expect(find.text('这个主页链接不完整'), findsNothing);
    // 主 CTA 与真源 components/cy/profile/index.wxml:119 逐字一致(「发消息」,不是「发私信」)。
    expect(find.text('发消息'), findsOneWidget);
  });
}
