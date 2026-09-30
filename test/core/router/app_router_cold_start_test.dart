import 'package:chengyin_app/core/router/app_router.dart';
import 'package:chengyin_app/core/router/route_paths.dart';
import 'package:chengyin_app/data/models/coop_finance.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/coop/coop_settlement_detail_page.dart';
import 'package:chengyin_app/feature/feed/feed_page.dart';
import 'package:chengyin_app/feature/mall/cart_page.dart';
import 'package:chengyin_app/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  testWidgets(
    'cold-start anonymous deep link survives auth bootstrap with query',
    (WidgetTester tester) async {
      const deepLink = '/coop/settlement-detail?source=finance&recordId=88';
      tester.binding.platformDispatcher.defaultRouteNameTestValue = deepLink;
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );

      const detailKey = CoopSettlementRef(source: 'finance', recordId: '88');
      const row = CoopFinanceRow(
        topicId: 88,
        topicName: '夜游苏河',
        settled: true,
        myIncome: '80.00',
        myIncomeArrived: true,
      );
      final container = ProviderContainer(
        retry: (int _, Object _) => null,
        overrides: <dynamic>[
          coopSettlementDetailProvider(detailKey).overrideWith(
            (ref) async => const CoopSettlementDetail.finance(row),
          ),
        ].cast(),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ChengyinApp(),
        ),
      );
      await tester.pump();
      // N2(b1 play-4):恢复在途不再把游客可直达的深链扣在 splash ——
      // 单一优先级「显式深链 > 会话恢复 > home」,首帧即落深链且带 query。
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .toString(),
        deepLink,
      );

      await container.read(authControllerProvider.notifier).bootstrap();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final uri = container
          .read(appRouterProvider)
          .routeInformationProvider
          .value
          .uri;
      expect(uri.toString(), deepLink);
      expect(find.byType(CoopSettlementDetailPage), findsOneWidget);
    },
  );

  testWidgets('ordinary cold start settles on home without redirect loop', (
    WidgetTester tester,
  ) async {
    final container = ProviderContainer(retry: (int _, Object _) => null);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ChengyinApp(),
      ),
    );
    await tester.pump();
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/splash',
    );

    await container.read(authControllerProvider.notifier).bootstrap();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final router = container.read(appRouterProvider);
    expect(router.routeInformationProvider.value.uri.path, kHomeRoute);
    expect(find.byType(FeedPage), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    expect(router.routeInformationProvider.value.uri.path, kHomeRoute);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cold-start cart deep link opens the real cart page for guest', (
    WidgetTester tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/cart?source=push';
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
    // N2:购物车页游客可直达(页内登录门),恢复在途首帧即落 /cart。
    expect(
      container
          .read(appRouterProvider)
          .routeInformationProvider
          .value
          .uri
          .toString(),
      '/cart?source=push',
    );
    expect(find.byType(CartPage), findsOneWidget);

    // 恢复完成后落点不许漂移(仍停在深链页)。
    await container.read(authControllerProvider.notifier).bootstrap();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/cart',
    );
    expect(find.byType(CartPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
