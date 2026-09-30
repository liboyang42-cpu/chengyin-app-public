import 'package:chengyin_app/feature/assets/assets_page.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/orders/orders_page.dart';
import 'package:chengyin_app/feature/publish/my_projects_page.dart';
import '../../support/fixed_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('订单资产与项目页使用 iOS 原生导航壳且 200% 字号不遮挡正文', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final cases = <({Widget page, List<dynamic> overrides, String anchor})>[
      (
        page: const OrdersPage(),
        overrides: <dynamic>[
          myOrdersProvider.overrideWith((_) async => const []),
        ],
        anchor: '我的订单',
      ),
      (
        page: const AssetsPage(),
        overrides: <dynamic>[
          // 账本内容只在登录态出现(游客是页内登录门),这里锁登录态。
          authControllerProvider.overrideWith(
            () => FixedAuth(signedInAuthState()),
          ),
          pointsListProvider.overrideWith((_) async => const []),
          balanceListProvider.overrideWith((_) async => const []),
          walletStagesProvider.overrideWith((_) async => null),
        ],
        anchor: '收益明细',
      ),
      (
        page: const MyProjectsPage(liquidGlassSupported: false),
        overrides: <dynamic>[
          myProjectsProvider.overrideWith((_) async => const []),
          myProjectTemplatesProvider.overrideWith((_) async => const []),
        ],
        anchor: '我的项目',
      ),
    ];

    for (final testCase in cases) {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: testCase.overrides.cast(),
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.iOS),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(390, 844),
                textScaler: TextScaler.linear(2),
              ),
              child: testCase.page,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoPageScaffold), findsOneWidget);
      expect(find.byType(CupertinoNavigationBar), findsOneWidget);
      expect(find.byType(Scaffold), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(find.text(testCase.anchor), findsWidgets);
      expect(
        tester.getTopLeft(find.text(testCase.anchor).first).dy,
        greaterThanOrEqualTo(
          tester.getBottomLeft(find.byType(CupertinoNavigationBar)).dy,
        ),
        reason: '${testCase.anchor} 不能被透明导航栏遮住',
      );
      expect(tester.takeException(), isNull, reason: testCase.anchor);
    }
  });

  testWidgets('订单页保留原投诉入口并支持系统返回键与左缘滑返', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          myOrdersProvider.overrideWith((_) async => const []),
        ].cast(),
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Builder(
            builder: (BuildContext context) => CupertinoButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => const OrdersPage()),
              ),
              child: const Text('打开订单'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开订单'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoNavigationBarBackButton), findsOneWidget);
    expect(find.bySemanticsLabel('发起投诉'), findsOneWidget);

    await tester.dragFrom(const Offset(1, 420), const Offset(360, 0));
    await tester.pumpAndSettle();
    expect(find.text('打开订单'), findsOneWidget);
  });
}
