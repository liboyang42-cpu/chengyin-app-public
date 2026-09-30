import 'dart:ui' as ui;

import 'package:chengyin_app/core/router/app_router.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/legal/legal_doc_page.dart';
import 'package:chengyin_app/feature/settings/about_page.dart';
import 'package:chengyin_app/feature/settings/settings_page.dart';
import 'package:chengyin_app/feature/publish/my_projects_page.dart';
import 'package:chengyin_app/main.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  testWidgets(
    '普通 builder 路由也使用 Cupertino 转场与左缘返回',
    (WidgetTester tester) async {
      final _RouterHarness harness = await _pumpApp(tester);

      harness.router.push('/legal/terms');
      await tester.pumpAndSettle();

      expect(find.byType(LegalDocPage), findsOneWidget);
      _expectInteractiveCupertinoRoute(tester, find.byType(LegalDocPage));

      await _edgeSwipeBack(tester, find.byType(LegalDocPage));
      expect(find.byType(LegalDocPage), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    '真实路由二级页使用 Cupertino 转场，左缘返回一级我的',
    (WidgetTester tester) async {
      final _RouterHarness harness = await _pumpApp(tester);

      harness.router.go('/profile');
      await tester.pumpAndSettle();
      harness.router.push('/settings');
      await tester.pumpAndSettle();

      expect(find.byType(SettingsPage), findsOneWidget);
      _expectInteractiveCupertinoRoute(tester, find.byType(SettingsPage));

      await _edgeSwipeBack(tester, find.byType(SettingsPage));

      expect(find.byType(SettingsPage), findsNothing);
      _expectSelectedTab(tester, '我的');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    '真实路由三级页左缘返回二级设置，再返回一级我的',
    (WidgetTester tester) async {
      final _RouterHarness harness = await _pumpApp(tester);

      harness.router.go('/profile');
      await tester.pumpAndSettle();
      harness.router.push('/settings');
      await tester.pumpAndSettle();
      harness.router.push('/settings/about');
      await tester.pumpAndSettle();

      expect(find.byType(AboutPage), findsOneWidget);
      _expectInteractiveCupertinoRoute(tester, find.byType(AboutPage));

      await _edgeSwipeBack(tester, find.byType(AboutPage));
      expect(find.byType(AboutPage), findsNothing);
      expect(find.byType(SettingsPage), findsOneWidget);

      await _edgeSwipeBack(tester, find.byType(SettingsPage));
      expect(find.byType(SettingsPage), findsNothing);
      _expectSelectedTab(tester, '我的');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    '五 Tab 切换后，二级页左缘返回当前我的 Tab',
    (WidgetTester tester) async {
      final _RouterHarness harness = await _pumpApp(tester);

      await tester.tap(find.bySemanticsLabel('俱乐部'));
      await tester.pumpAndSettle();
      expect(harness.router.routeInformationProvider.value.uri.path, '/clubs');

      await tester.tap(find.bySemanticsLabel('我的'));
      await tester.pumpAndSettle();
      expect(
        harness.router.routeInformationProvider.value.uri.path,
        '/profile',
      );

      harness.router.push('/settings');
      await tester.pumpAndSettle();
      _expectInteractiveCupertinoRoute(tester, find.byType(SettingsPage));

      await _edgeSwipeBack(tester, find.byType(SettingsPage));

      expect(find.byType(SettingsPage), findsNothing);
      _expectSelectedTab(tester, '我的');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    '真实路由 /my-projects?type=template 默认打开模板 tab',
    (WidgetTester tester) async {
      final _RouterHarness harness = await _pumpApp(tester);

      harness.router.go('/my-projects?type=template');
      await tester.pumpAndSettle();

      expect(find.byType(MyProjectsPage), findsOneWidget);
      // 分段已收进共用层 CyTabs(iOS 26+ 走原生平台视图,不再暴露
      // CupertinoSlidingSegmentedControl),路由判据改核页面入参。
      final MyProjectsPage page = tester.widget<MyProjectsPage>(
        find.byType(MyProjectsPage),
      );
      expect(page.initialTab, MyProjectTypeTab.template);
      expect(
        harness
            .router
            .routeInformationProvider
            .value
            .uri
            .queryParameters['type'],
        'template',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

void _expectSelectedTab(WidgetTester tester, String label) {
  expect(
    tester
        .getSemantics(find.bySemanticsLabel(label))
        .flagsCollection
        .isSelected,
    ui.Tristate.isTrue,
  );
}

void _expectInteractiveCupertinoRoute(WidgetTester tester, Finder page) {
  final ModalRoute<dynamic>? route = ModalRoute.of(tester.element(page));
  expect(route?.settings, isA<CupertinoPage<dynamic>>());
  expect((route! as PageRoute<dynamic>).popGestureEnabled, isTrue);
}

Future<void> _edgeSwipeBack(WidgetTester tester, Finder activePage) async {
  final TestGesture gesture = await tester.startGesture(const Offset(5, 300));
  await gesture.moveBy(const Offset(20, 0));
  await tester.pump();
  await gesture.moveBy(const Offset(500, 0));
  await tester.pump();
  expect(
    tester.getTopLeft(activePage).dx,
    closeTo(500, 1),
    reason: '页面没有跟随 iOS 左缘返回手势移动',
  );
  expect(
    Navigator.of(tester.element(activePage)).userGestureInProgress,
    isTrue,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<_RouterHarness> _pumpApp(WidgetTester tester) async {
  final ProviderContainer container = ProviderContainer(
    retry: (int _, Object _) => null,
  );
  addTearDown(container.dispose);
  await container.read(authControllerProvider.notifier).bootstrap();
  final GoRouter router = container.read(appRouterProvider);

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ChengyinApp()),
  );
  await tester.pumpAndSettle();
  return _RouterHarness(router);
}

class _RouterHarness {
  const _RouterHarness(this.router);

  final GoRouter router;
}
