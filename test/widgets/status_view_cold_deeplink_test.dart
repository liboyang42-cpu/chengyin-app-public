// 冷启动深链的「困死」出口。
//
// ★★ App 有 37 条带路径参数的路由,每条都可能被深链直接打开。
//   那种进法**没有上一页**:Navigator.canPop() 为 false,
//   AppBar 连返回钮都不渲染。这时错误态只给「重试」,
//   而重试解决不了「这个 id 根本不存在」—— 人就卡在这一屏。
//
//   小程序 merchant/profile/index.wxml:19 早写死了这条:
//   「冷启动进来的没有上一页,只给『返回』等于把人困死;
//     所以回首页恒在,返回按栈深出。」
//
// ★ 只在真的退不出去时出现 —— 正常从列表点进来有返回钮,
//   再加一个「回首页」是多余的噪音。这一点两条用例分别锁住。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/widgets/status_view.dart';

GoRouter _router({required bool deepLink}) => GoRouter(
  initialLocation: deepLink ? '/detail/9' : '/',
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (_, _) => Scaffold(
        body: Builder(
          builder: (BuildContext c) => TextButton(
            onPressed: () => c.push('/detail/9'),
            child: const Text('go'),
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/detail/:id',
      builder: (_, _) => Scaffold(
        body: StatusView(message: '内容没能加载出来', onRetry: () {}),
      ),
    ),
  ],
);

void main() {
  for (final String root in <String>[
    '/feed',
    '/roam',
    '/template-square',
    '/clubs',
    '/profile',
  ]) {
    testWidgets('★★ tab 根页($root)出错时不给「回首页」—— 它已经在一级页', (WidgetTester t) async {
      // canPop 同样是 false,只判那一条的话一级页会劝用户「回首页」。
      final GoRouter r = GoRouter(
        initialLocation: root,
        routes: <RouteBase>[
          GoRoute(
            path: root,
            builder: (_, _) => Scaffold(
              body: StatusView(message: '内容没能加载出来', onRetry: () {}),
            ),
          ),
        ],
      );
      addTearDown(r.dispose);
      await t.pumpWidget(MaterialApp.router(routerConfig: r));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('status-go-home')), findsNothing);
    });
  }

  testWidgets('★★ 冷启动深链(没有上一页)⇒ 必须给「回首页」', (WidgetTester t) async {
    await t.pumpWidget(
      MaterialApp.router(routerConfig: _router(deepLink: true)),
    );
    await t.pumpAndSettle();
    expect(
      find.byKey(const Key('status-go-home')),
      findsOneWidget,
      reason: '重试解决不了「这个 id 不存在」,没有别的出口人就卡死在这屏',
    );
  });

  testWidgets('★ 正常从列表点进来(退得出去)⇒ 不加这个多余按钮', (WidgetTester t) async {
    await t.pumpWidget(
      MaterialApp.router(routerConfig: _router(deepLink: false)),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(
      find.byKey(const Key('status-go-home')),
      findsNothing,
      reason: '有返回钮时再给「回首页」是噪音',
    );
  });
}
