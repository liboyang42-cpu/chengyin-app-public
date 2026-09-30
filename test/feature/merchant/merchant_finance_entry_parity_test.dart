import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/merchant_access_provider.dart';
import 'package:chengyin_app/core/network/provider_retry.dart';
import 'package:chengyin_app/data/models/merchant_dashboard.dart';
import 'package:chengyin_app/data/models/merchant_finance.dart';
import 'package:chengyin_app/data/models/merchant_ledger.dart';
import 'package:chengyin_app/feature/merchant/merchant_home_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_ledger_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_settlement_view.dart';
import '../../golden/golden_theme.dart';
import 'merchant_access_fixtures.dart' show ownerAccess;

const Key _financeEntryKey = Key('merchant-finance-entry');

GoRouter _router({String initialLocation = '/merchant'}) => GoRouter(
  initialLocation: initialLocation,
  routes: <RouteBase>[
    ShellRoute(
      builder: (BuildContext context, GoRouterState state, Widget child) =>
          child,
      routes: <RouteBase>[
        GoRoute(
          path: '/merchant',
          builder: (BuildContext context, GoRouterState state) =>
              const MerchantHomePage(),
        ),
        GoRoute(
          path: '/merchant/ledger',
          builder: (BuildContext context, GoRouterState state) =>
              MerchantLedgerPage(
                initialView: state.uri.queryParameters['view'] ?? 'redemption',
              ),
        ),
        GoRoute(
          path: '/merchant/aftercare',
          builder: (BuildContext context, GoRouterState state) =>
              const Text('退款售后列表', textDirection: TextDirection.ltr),
        ),
      ],
    ),
  ],
);

Widget _app(GoRouter router, {bool? canReadAftercare}) => ProviderScope(
  retry: chengyinRetry,
  overrides: <dynamic>[
    // 工作台根挂在 access/me 上:给店主身份,财务入口才在。
    merchantAccessProvider.overrideWith((ref) async => ownerAccess()),
    merchantDashboardProvider.overrideWith(
      (ref) async => MerchantDashboard.fromJson(<String, dynamic>{}),
    ),
    businessStatusProvider.overrideWith(
      (ref) async => (open: true, text: '营业中'),
    ),
    merchantTodoProvider.overrideWith(
      (ref) async => MerchantTodo.fromJson(<String, dynamic>{}),
    ),
    merchantEventsProvider.overrideWith(
      (ref) async => <Map<String, dynamic>>[],
    ),
    financeOverviewProvider.overrideWith(
      (ref) async => MerchantSettlementOverview.fromJson(<String, dynamic>{}),
    ),
    settlementEntriesProvider('all').overrideWith(
      (ref) async => const MerchantFinancePage<MerchantSettlementEntry>(
        rows: <MerchantSettlementEntry>[],
        total: 0,
        pageNum: 1,
        pageSize: 20,
      ),
    ),
    transferBatchesProvider.overrideWith(
      (ref) async => const MerchantFinancePage<PublicTransferBatch>(
        rows: <PublicTransferBatch>[],
        total: 0,
        pageNum: 1,
        pageSize: 20,
      ),
    ),
    merchantRedemptionsProvider(
      'all',
    ).overrideWith((ref) async => const MerchantRedemptionPage()),
    if (canReadAftercare != null)
      merchantAftercareEntryProvider.overrideWith(
        (ref) async => canReadAftercare,
      ),
  ].cast(),
  child: MaterialApp.router(theme: merchantGoldenTheme(), routerConfig: router),
);

Future<void> _pumpHome(WidgetTester tester, GoRouter router) async {
  await tester.binding.setSurfaceSize(const Size(390, 1200));
  await tester.pumpWidget(_app(router));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(_financeEntryKey),
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  test('生产路由把 view query 传给台账页', () {
    final source = File('lib/core/router/app_router.dart').readAsStringSync();

    expect(
      source,
      contains("state.uri.queryParameters['view'] ?? 'redemption'"),
    );
  });

  testWidgets('商家首页使用 Apple 风格「财务」入口且命中区不小于 44pt', (WidgetTester tester) async {
    final router = _router();
    addTearDown(router.dispose);

    await _pumpHome(tester, router);

    final entry = find.byKey(_financeEntryKey);
    expect(tester.widget(entry), isA<CupertinoButton>());
    expect(
      find.descendant(of: entry, matching: find.text('财务')),
      findsOneWidget,
    );
    expect(tester.getSize(entry).height, greaterThanOrEqualTo(44));
    // R10 过渡期:图标不许暗示银行卡(creditcard),用账簿语义的 doc_text。
    final icon = tester.widget<Icon>(
      find.descendant(of: entry, matching: find.byType(Icon)),
    );
    expect(icon.icon, CupertinoIcons.doc_text);
    expect(icon.icon, isNot(CupertinoIcons.creditcard));
  });

  testWidgets('「财务」push 到台账结算视图，pop 回商家首页', (WidgetTester tester) async {
    final router = _router();
    addTearDown(router.dispose);

    await _pumpHome(tester, router);
    await tester.tap(find.byKey(_financeEntryKey));
    await tester.pumpAndSettle();

    expect(router.canPop(), isTrue);
    expect(find.byType(MerchantLedgerPage), findsOneWidget);
    expect(
      find.text('本月个人账户净入账'),
      findsOneWidget,
      reason: '财务入口应默认落在结算，不是核销记录',
    );

    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(MerchantHomePage), findsOneWidget);
  });

  testWidgets('无 view 的台账冷路由仍默认核销记录', (WidgetTester tester) async {
    final router = _router(initialLocation: '/merchant/ledger');
    addTearDown(router.dispose);

    await tester.binding.setSurfaceSize(const Size(390, 1200));
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    expect(find.byType(MerchantLedgerPage), findsOneWidget);
    expect(find.text('这个筛选下没有记录'), findsOneWidget);
    expect(find.text('本月个人账户净入账'), findsNothing);
  });

  testWidgets('view=settlement 深链直接显示结算', (WidgetTester tester) async {
    final router = _router(initialLocation: '/merchant/ledger?view=settlement');
    addTearDown(router.dispose);

    await tester.binding.setSurfaceSize(const Size(390, 1200));
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    expect(find.byType(MerchantLedgerPage), findsOneWidget);
    expect(find.text('本月个人账户净入账'), findsOneWidget);
  });

  testWidgets('有 merchant:aftercare:read 时台账显示「退款售后」入口并 push 到售后列表', (
    WidgetTester tester,
  ) async {
    final router = _router(initialLocation: '/merchant/ledger');
    addTearDown(router.dispose);

    await tester.binding.setSurfaceSize(const Size(390, 1200));
    await tester.pumpWidget(_app(router, canReadAftercare: true));
    await tester.pumpAndSettle();

    final entry = find.byKey(const Key('merchant-aftercare-entry'));
    expect(entry, findsOneWidget);
    expect(find.text('退款售后'), findsOneWidget);
    expect(find.text('查询退款申请，追加商家意见与凭证'), findsOneWidget);

    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/merchant/aftercare');
    expect(find.text('退款售后列表'), findsOneWidget);
  });

  testWidgets('没有能力位时不出现售后入口', (WidgetTester tester) async {
    final router = _router(initialLocation: '/merchant/ledger');
    addTearDown(router.dispose);

    await tester.binding.setSurfaceSize(const Size(390, 1200));
    await tester.pumpWidget(_app(router, canReadAftercare: false));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('merchant-aftercare-entry')), findsNothing);
  });

  testWidgets('未知 view 失败关闭到核销记录', (WidgetTester tester) async {
    final router = _router(initialLocation: '/merchant/ledger?view=unknown');
    addTearDown(router.dispose);

    await tester.binding.setSurfaceSize(const Size(390, 1200));
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    expect(find.text('这个筛选下没有记录'), findsOneWidget);
    expect(find.text('本月个人账户净入账'), findsNothing);
  });
}
