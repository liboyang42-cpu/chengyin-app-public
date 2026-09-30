import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/models/merchant_marketing.dart';
import 'package:chengyin_app/feature/merchant/merchant_customer_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_marketing_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_orders_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_crm_console_api.dart';

void main() {
  testWidgets('商家高频页使用 iOS 原生导航壳且 200% 字号不遮挡正文', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final cases =
        <({Widget page, List<dynamic> overrides, String title, String anchor})>[
          (
            page: const MerchantOrdersPage(),
            overrides: <dynamic>[
              merchantOrdersProvider.overrideWith(
                (_) async => const <Map<String, dynamic>>[],
              ),
            ],
            title: '订单',
            anchor: '还没有订单',
          ),
          (
            page: const MerchantCustomerPage(),
            overrides: <dynamic>[
              // 能力位与名册都走替身:这一条只验导航壳与 200% 字号排版。
              merchantCrmAccessProvider.overrideWith(
                (_) async => const MerchantCrmAccess(canReadCrm: true),
              ),
              merchantCrmConsoleApiProvider.overrideWithValue(
                FakeCrmConsoleApi(),
              ),
            ],
            title: '客户',
            anchor: '还没有客户',
          ),
          (
            page: const MerchantMarketingPage(),
            overrides: <dynamic>[
              merchantMarketingProvider.overrideWith(
                (_) async => const MerchantMarketing(),
              ),
            ],
            title: '营销',
            anchor: '优惠券',
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
      expect(find.text(testCase.title), findsOneWidget);
      expect(
        find.bySemanticsLabel(testCase.title),
        findsOneWidget,
        reason: '${testCase.title} 导航标题必须能被 VoiceOver 读出',
      );
      expect(find.text(testCase.anchor), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(testCase.anchor)).dy,
        greaterThanOrEqualTo(
          tester.getBottomLeft(find.byType(CupertinoNavigationBar)).dy,
        ),
        reason: '${testCase.title} 正文不能被透明导航栏遮住',
      );
      expect(tester.takeException(), isNull, reason: testCase.title);
    }
  });

  testWidgets('商家订单页有系统返回键并支持左缘滑返', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          merchantOrdersProvider.overrideWith(
            (_) async => const <Map<String, dynamic>>[],
          ),
        ].cast(),
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Builder(
            builder: (BuildContext context) => CupertinoButton(
              minimumSize: const Size(44, 44),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const MerchantOrdersPage(),
                ),
              ),
              child: const Text('打开商家订单'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开商家订单'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoNavigationBarBackButton), findsOneWidget);
    expect(
      tester.getSize(find.byType(CupertinoNavigationBarBackButton)).height,
      greaterThanOrEqualTo(44),
    );

    await tester.dragFrom(const Offset(1, 420), const Offset(360, 0));
    await tester.pumpAndSettle();
    expect(find.text('打开商家订单'), findsOneWidget);
  });
}
