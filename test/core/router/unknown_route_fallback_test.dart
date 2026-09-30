// 未匹配的深链兜底。
//
// ★ 起因(2026-09-18,b1-sim-orders 真跑):用 App 唯一注册的 URL scheme
//   (`wxYOURAPPID`,见 ios/Runner/Info.plist)打开深链,go_router 匹配不上
//   location,**裸渲染它自带的 CupertinoErrorScreen** —— 一屏英文
//   「Page Not Found」+ `GoException: no routes for location: …` 原文,
//   底下的「Home」按钮 go 的还是 `/`(本仓没这条路由,点了还是这一屏)。
//   用户视角就是「App 坏了」,而且退不出去。
//
// 判据:任何未匹配的 location 都要落到仓内兜底页(中文提示 + 回首页),
// 且这一屏**不许抛异常**。

import 'package:chengyin_app/core/router/route_paths.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/feed/feed_page.dart';
import 'package:chengyin_app/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  Future<ProviderContainer> bootDeepLink(
    WidgetTester tester,
    String loc,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = loc;
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final container = ProviderContainer(retry: (int _, Object _) => null);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ChengyinApp(),
      ),
    );
    await tester.pump();
    await container.read(authControllerProvider.notifier).bootstrap();
    await tester.pump();
    // 兜底页是 CupertinoPage 推入的,动画没走完时按钮还在屏外 ——
    // 这时 tap() 会落在空处(警告 "would not hit test")。
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  // ★ 两种形状都收:带 scheme 的(`wxYOURAPPID://orders` 没有 path)和普通
  //   拼错的路径。兜底页必须对两者一致 —— 只按 `uri.path` 判「困没困住」的
  //   写法正好把前者漏掉(它的 path 是空字符串),而前者才是真跑撞上的那条。
  for (final String loc in <String>['wxYOURAPPID://orders', '/orders-typo']) {
    testWidgets('未匹配深链 $loc → 中文兜底页,不抛异常', (WidgetTester tester) async {
      await bootDeepLink(tester, loc);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('这个页面'),
        findsOneWidget,
        reason: '不许把 go_router 的英文错误屏给用户看',
      );
      expect(find.byKey(const Key('status-go-home')), findsOneWidget);
    });
  }

  testWidgets('兜底页的「回首页」真的回得去', (WidgetTester tester) async {
    await bootDeepLink(tester, 'wxYOURAPPID://orders');
    expect(find.byKey(const Key('status-go-home')), findsOneWidget);

    await tester.tap(find.byKey(const Key('status-go-home')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byType(FeedPage),
      findsOneWidget,
      reason: '「回首页」必须落到一级首页 $kHomeRoute(不是 go_router 自带的 `/`)',
    );
  });
}
