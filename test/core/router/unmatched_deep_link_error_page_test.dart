import 'package:chengyin_app/l10n/locale_preference.dart';
// 未匹配深链不许整屏英文 GoException(B1 模拟器报告 P2)。
//
// go_router 默认错误页渲染 `PageNotFoundException`(英文,带 "Page not found:
// /xxx"),模拟器实拍 roam 域未匹配路由整屏埋栈。收口为人话错误页:
// 主标 + 副标 + 困住时「回首页」,且**没有**「重试」(不存在的路由重试是死路)。
import 'package:chengyin_app/core/router/app_router.dart';
import 'package:chengyin_app/core/router/route_error_page.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  testWidgets('冷启动未匹配深链 → 人话错误页,不露英文异常', (WidgetTester tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/no-such-page?from=sms';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final container = ProviderContainer(retry: (int _, Object _) => null);
    addTearDown(container.dispose);
    await container.read(localePreferenceProvider.notifier).select('zh');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ChengyinApp(),
      ),
    );
    await tester.pump();
    await container.read(authControllerProvider.notifier).bootstrap();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(RouteErrorPage), findsOneWidget);
    expect(find.text('这个页面找不到了'), findsOneWidget);
    expect(find.text('链接可能过期或打错了,从首页继续逛'), findsOneWidget);
    // 默认英文错误页的原文一个字都不许出现。
    expect(find.textContaining('no routes for location'), findsNothing);
    expect(find.textContaining('Page not found'), findsNothing);
    expect(find.textContaining('GoException'), findsNothing);
    // 死路按钮:重试对不存在的路由永远不成功,不给。
    expect(find.text('重试'), findsNothing);
    // 冷启动没有上一页 → 必须有「回首页」出口。
    expect(find.text('回首页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('页内 push 未匹配路由 → 有系统返回,不必叠回首页', (WidgetTester tester) async {
    final container = ProviderContainer(retry: (int _, Object _) => null);
    addTearDown(container.dispose);
    await container.read(localePreferenceProvider.notifier).select('zh');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ChengyinApp(),
      ),
    );
    await tester.pump();
    await container.read(authControllerProvider.notifier).bootstrap();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    container.read(appRouterProvider).push('/no-such-page');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(RouteErrorPage), findsOneWidget);
    expect(find.text('这个页面找不到了'), findsOneWidget);
    expect(find.textContaining('Page not found'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
