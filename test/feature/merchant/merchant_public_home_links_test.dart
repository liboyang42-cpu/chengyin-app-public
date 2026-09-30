import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/data/models/merchant.dart';
import 'package:chengyin_app/feature/merchant/merchant_discover_page.dart';
import '../../golden/golden_theme.dart' show merchantGoldenTheme;

Widget _app({required Merchant merchant}) {
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const MerchantDiscoverPage()),
      GoRoute(
        path: '/merchant/public-home/member/:id',
        builder: (_, GoRouterState state) =>
            Scaffold(body: Text('member ${state.pathParameters['id']}')),
      ),
    ],
  );
  return ProviderScope(
    overrides: <dynamic>[
      discoverMerchantsProvider(
        '',
      ).overrideWith((ref) async => <Merchant>[merchant]),
    ].cast(),
    child: MaterialApp.router(
      theme: merchantGoldenTheme(),
      routerConfig: router,
    ),
  );
}

void main() {
  testWidgets('发现商家点击后以 memberId 打开 canonical 公开主页', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(merchant: Merchant(id: 7, memberId: 100096, name: '静安咖啡')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('discover-merchant-7')));
    await tester.pumpAndSettle();

    expect(find.text('member 100096'), findsOneWidget);
    expect(find.text('member 7'), findsNothing);
  });

  test('canonical member 路由与 legacy merchant id 路由不共用语义', () {
    const canonical = '/merchant/public-home/member/100096';
    const legacy = '/merchant/public-home/7';
    expect(canonical, isNot(legacy));
    expect(canonical, contains('/member/'));
  });

  testWidgets('缺少 memberId 时失败关闭，不用 merchantId 猜主页', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(merchant: Merchant(id: 7, name: '无主体商家')));
    await tester.pumpAndSettle();

    final Semantics semantics = tester.widget(
      find.byKey(const Key('discover-merchant-7')),
    );
    expect(semantics.properties.enabled, isTrue);
    expect(semantics.properties.hint, '该商家暂不可查看');

    await tester.tap(find.byKey(const Key('discover-merchant-7')));
    await tester.pump();

    expect(find.textContaining('该商家暂不可查看'), findsOneWidget);
    expect(find.text('member 7'), findsNothing);
  });
}
