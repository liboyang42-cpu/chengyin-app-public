import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:chengyin_app/data/api/coop_api.dart';
import 'package:chengyin_app/data/models/coop_finance.dart';
import 'package:chengyin_app/data/models/coop_mybiz.dart';
import 'package:chengyin_app/feature/coop/coop_finance_page.dart';
import 'package:chengyin_app/feature/coop/coop_mybiz_page.dart';
import 'package:chengyin_app/feature/coop/coop_settlement_detail_page.dart';

class _FakeCoopApi implements CoopApi {
  const _FakeCoopApi({this.financeRows = const [], this.myBizData = const {}});

  final List<CoopFinanceRow> financeRows;
  final Map<String, dynamic> myBizData;

  @override
  Future<List<CoopFinanceRow>> finance() async => financeRows;

  @override
  Future<Map<String, dynamic>> myBiz() async => myBizData;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _routerApp({required Widget home, required List<dynamic> overrides}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(
        path: '/coop/settlement-detail',
        builder: (_, GoRouterState state) => CoopSettlementDetailPage(
          source: state.uri.queryParameters['source'] ?? '',
          recordId: state.uri.queryParameters['recordId'] ?? '',
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp.router(routerConfig: router),
  );
}

Widget _coldStartRouterApp({
  required String source,
  required String recordId,
  required List<dynamic> overrides,
}) {
  final router = GoRouter(
    initialLocation:
        '/coop/settlement-detail?source=$source&recordId=$recordId',
    routes: <RouteBase>[
      GoRoute(
        path: '/coop/settlement-detail',
        builder: (_, GoRouterState state) => CoopSettlementDetailPage(
          source: state.uri.queryParameters['source'] ?? '',
          recordId: state.uri.queryParameters['recordId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/coop-finance',
        builder: (_, _) => const Scaffold(body: Text('合作结算落点')),
      ),
      GoRoute(
        path: '/merchant/ledger',
        builder: (_, GoRouterState state) => Scaffold(
          body: Text(
            state.uri.queryParameters['view'] == 'settlement' &&
                    state.uri.queryParameters['source'] == 'coop'
                ? '商家合作结算台账落点'
                : '台账参数错误',
          ),
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('mybiz 结算卡片点进精确 recordId，返回后仍是 mybiz 列表', (tester) async {
    const row = CoopSettlementRow(
      id: 71,
      topicId: 9,
      amount: 38.5,
      status: 1,
      payeeType: 'merchant',
      verifiedHeads: 3,
      verifiedSales: 128,
    );
    const biz = CoopMyBiz(
      fulfillmentRate: 100,
      violationCount: 0,
      avgRating: 0,
      reviewCount: 0,
      settlements: <CoopSettlementRow>[row],
    );
    await tester.pumpWidget(
      _routerApp(
        home: const CoopMyBizPage(),
        overrides: <dynamic>[
          coopMyBizProvider.overrideWith((ref) async => biz),
          coopSettlementDetailProvider(
            const CoopSettlementRef(source: 'ledger', recordId: '71'),
          ).overrideWith(
            (ref) async => const CoopSettlementDetail.merchant(row),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('主题 #9'));
    await tester.pumpAndSettle();
    expect(find.text('结算详情'), findsOneWidget);
    expect(find.text('¥38.50'), findsWidgets);
    expect(find.text('核销人数'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('返回'));
    await tester.pumpAndSettle();
    expect(find.text('近 90 天履约率'), findsOneWidget);
  });

  testWidgets('finance 结算卡片以 topicId 作 recordId 打开主办分润详情', (tester) async {
    const row = CoopFinanceRow(
      topicId: 88,
      topicName: '夜游苏河',
      settled: true,
      totalSales: '300.00',
      verifiedSales: '200.00',
      merchantTotal: '120.00',
      merchantPaid: '100.00',
      myIncome: '80.00',
      myIncomeArrived: true,
    );
    await tester.pumpWidget(
      _routerApp(
        home: const CoopFinancePage(),
        overrides: <dynamic>[
          coopFinanceProvider.overrideWith(
            (ref) async => <CoopFinanceRow>[row],
          ),
          coopSettlementDetailProvider(
            const CoopSettlementRef(source: 'finance', recordId: '88'),
          ).overrideWith(
            (ref) async => const CoopSettlementDetail.finance(row),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('夜游苏河'));
    await tester.pumpAndSettle();
    expect(find.text('主办分润'), findsOneWidget);
    expect(find.text('总销售额'), findsOneWidget);
    expect(find.text('¥80.00'), findsWidgets);
  });

  testWidgets('finance 详情对齐金额分解与结算进度', (tester) async {
    const key = CoopSettlementRef(source: 'finance', recordId: '88');
    const row = CoopFinanceRow(
      topicId: 88,
      topicName: '夜游苏河',
      settled: true,
      totalSales: '300.00',
      verifiedSales: '200.00',
      platformAmount: '20.00',
      merchantTotal: '120.00',
      myIncome: '60.00',
      myIncomeArrived: false,
      merchantPayableTime: '2026-08-29 12:30:00',
      merchantPayoutTime: '2026-08-30 09:15:00',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          coopSettlementDetailProvider(key).overrideWith(
            (ref) async => const CoopSettlementDetail.finance(row),
          ),
        ].cast(),
        child: const MaterialApp(
          home: CoopSettlementDetailPage(source: 'finance', recordId: '88'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('金额分解'), findsOneWidget);
    expect(find.text('平台服务费'), findsOneWidget);
    expect(find.text('¥20.00'), findsOneWidget);
    expect(find.text('我的分润'), findsNWidgets(2));
    expect(find.text('结算进度'), findsOneWidget);
    expect(find.text('主题已结算'), findsOneWidget);
    expect(find.text('我的分润待入账'), findsOneWidget);
    expect(find.text('商家应收可入账'), findsOneWidget);
    expect(find.text('2026-08-29 12:30'), findsOneWidget);
    expect(find.text('商家应收已打款'), findsOneWidget);
    expect(find.text('2026-08-30 09:15'), findsOneWidget);
  });

  testWidgets('ledger 详情展示创建结算与实际到账时间线', (tester) async {
    const key = CoopSettlementRef(source: 'ledger', recordId: '71');
    const row = CoopSettlementRow(
      id: 71,
      topicId: 9,
      amount: 38.5,
      status: 1,
      payeeType: 'merchant',
      shareMode: 1,
      shareRate: 15,
      verifiedHeads: 3,
      verifiedSales: 128,
      createTime: '2026-08-20 08:03:22',
      settleTime: '2026-08-21 10:30:00',
      payoutTime: '2026-08-22 09:16:00',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          coopSettlementDetailProvider(key).overrideWith(
            (ref) async => const CoopSettlementDetail.merchant(row),
          ),
        ].cast(),
        child: const MaterialApp(
          home: CoopSettlementDetailPage(source: 'ledger', recordId: '71'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('金额分解'), findsOneWidget);
    expect(find.text('我的分润'), findsNWidgets(2));
    expect(find.text('结算记录已创建'), findsOneWidget);
    expect(find.text('2026-08-20 08:03'), findsOneWidget);
    expect(find.text('合作已结算'), findsOneWidget);
    expect(find.text('2026-08-21 10:30'), findsOneWidget);
    expect(find.text('已入余额'), findsNWidgets(2));
    expect(find.text('2026-08-22 09:16'), findsOneWidget);
  });

  testWidgets('ledger 待入账没有预计时间时不伪造日期', (tester) async {
    const key = CoopSettlementRef(source: 'ledger', recordId: '71');
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          coopSettlementDetailProvider(key).overrideWith(
            (ref) async => const CoopSettlementDetail.merchant(
              CoopSettlementRow(id: 71, status: 0),
            ),
          ),
        ].cast(),
        child: const MaterialApp(
          home: CoopSettlementDetailPage(source: 'ledger', recordId: '71'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('等待入账'), findsOneWidget);
    expect(find.text('时间待确认'), findsOneWidget);
  });

  testWidgets('finance 冷启动返回合作结算列表', (tester) async {
    const key = CoopSettlementRef(source: 'finance', recordId: '88');
    await tester.pumpWidget(
      _coldStartRouterApp(
        source: 'finance',
        recordId: '88',
        overrides: <dynamic>[
          coopSettlementDetailProvider(key).overrideWith(
            (ref) async => const CoopSettlementDetail.finance(
              CoopFinanceRow(topicId: 88, topicName: '夜游苏河'),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('返回'));
    await tester.pumpAndSettle();
    expect(find.text('合作结算落点'), findsOneWidget);
  });

  testWidgets('ledger 冷启动返回商家合作结算台账', (tester) async {
    const key = CoopSettlementRef(source: 'ledger', recordId: '71');
    await tester.pumpWidget(
      _coldStartRouterApp(
        source: 'ledger',
        recordId: '71',
        overrides: <dynamic>[
          coopSettlementDetailProvider(key).overrideWith(
            (ref) async =>
                const CoopSettlementDetail.merchant(CoopSettlementRow(id: 71)),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('返回'));
    await tester.pumpAndSettle();
    expect(find.text('商家合作结算台账落点'), findsOneWidget);
  });

  test('JSON 保留结算详情需要的金额时间与布尔语义', () {
    final finance = CoopFinanceRow.fromJson(<String, dynamic>{
      'topicId': 88,
      'topicName': '夜游苏河',
      'settled': 1,
      'platformAmount': '20.50',
      'myIncomeArrived': '1',
      'merchantPayableTime': '2026-08-29 12:30:00',
      'merchantPayoutTime': '2026-08-30 09:15:00',
    });
    expect(finance.settled, isTrue);
    expect(finance.platformAmount, '20.50');
    expect(finance.myIncomeArrived, isTrue);

    final merchant = CoopSettlementRow.fromJson(<String, dynamic>{
      'id': 71,
      'status': '1',
      'createTime': '2026-08-20 08:03:22',
      'settleTime': '2026-08-21 10:30:00',
      'updateTime': '2026-08-22 09:16:00',
    });
    expect(merchant.status, 1);
    expect(merchant.createTime, '2026-08-20 08:03:22');
    expect(merchant.settleTime, '2026-08-21 10:30:00');
    expect(merchant.updateTime, '2026-08-22 09:16:00');
  });

  testWidgets('找不到 source+recordId 时显式报错，不展示别的记录', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          coopApiProvider.overrideWithValue(const _FakeCoopApi()),
        ].cast(),
        child: const MaterialApp(
          home: CoopSettlementDetailPage(source: 'finance', recordId: '404'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('这条结算记录不存在或已不可见'), findsOneWidget);
  });

  test('provider 只按 source+recordId 选中 finance 对应记录', () async {
    const wanted = CoopFinanceRow(topicId: 88, topicName: '夜游苏河');
    final container = ProviderContainer(
      overrides: <dynamic>[
        coopApiProvider.overrideWithValue(
          const _FakeCoopApi(
            financeRows: <CoopFinanceRow>[
              CoopFinanceRow(topicId: 77, topicName: '不是这条'),
              wanted,
            ],
          ),
        ),
      ].cast(),
    );
    addTearDown(container.dispose);
    final detail = await container.read(
      coopSettlementDetailProvider(
        const CoopSettlementRef(source: 'finance', recordId: '88'),
      ).future,
    );
    expect(detail.finance?.topicName, '夜游苏河');
  });

  test('provider 从 mybiz settlements 只选 ledger recordId', () async {
    final container = ProviderContainer(
      overrides: <dynamic>[
        coopApiProvider.overrideWithValue(
          const _FakeCoopApi(
            myBizData: <String, dynamic>{
              'settlements': <dynamic>[
                <String, dynamic>{'id': 70, 'topicId': 7},
                <String, dynamic>{'id': 71, 'topicId': 9, 'amount': 38.5},
              ],
            },
          ),
        ),
      ].cast(),
    );
    addTearDown(container.dispose);
    final detail = await container.read(
      coopSettlementDetailProvider(
        const CoopSettlementRef(source: 'ledger', recordId: '71'),
      ).future,
    );
    expect(detail.merchant?.id, 71);
    expect(detail.merchant?.topicId, 9);
  });

  testWidgets('已结算但分润金额缺席时是金额待确认，不冒充待入账', (tester) async {
    const key = CoopSettlementRef(source: 'finance', recordId: '88');
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          coopSettlementDetailProvider(key).overrideWith(
            (ref) async => const CoopSettlementDetail.finance(
              CoopFinanceRow(
                topicId: 88,
                topicName: '夜游苏河',
                settled: true,
                myIncome: null,
              ),
            ),
          ),
        ].cast(),
        child: const MaterialApp(
          home: CoopSettlementDetailPage(source: 'finance', recordId: '88'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('金额待确认'), findsOneWidget);
    expect(find.text('待入账'), findsNothing);
  });

  test('结算状态和分润模式只接受 canonical 0/1/2', () {
    for (final value in <Object>['01', '+1', 3, 'unknown']) {
      final row = CoopSettlementRow.fromJson(<String, dynamic>{
        'id': 1,
        'status': value,
        'shareMode': value,
      });
      expect(row.status, isNull, reason: 'status=$value must fail closed');
      expect(
        row.shareMode,
        isNull,
        reason: 'shareMode=$value must fail closed',
      );
    }
    expect(
      CoopSettlementRow.fromJson(const <String, dynamic>{
        'id': 1,
        'status': ' 1 ',
        'shareMode': 2.0,
      }),
      isA<CoopSettlementRow>()
          .having((row) => row.status, 'status', 1)
          .having((row) => row.shareMode, 'shareMode', 2),
    );
  });

  // 提现行(真源 scene-merchant-profit wxml:13-17):三态 + R10 客服弹窗。
  group('finance:提现行', () {
    final withdrawBtn = find.byKey(const Key('coop-finance-withdraw'));

    Future<void> pumpFinance(
      WidgetTester tester,
      List<CoopFinanceRow> rows,
    ) async {
      await tester.pumpWidget(
        _routerApp(
          home: const CoopFinancePage(),
          overrides: <dynamic>[
            coopFinanceProvider.overrideWith((ref) async => rows),
          ],
        ),
      );
      await tester.pumpAndSettle();
    }

    bool withdrawEnabled(WidgetTester tester) =>
        tester.widget<CyNativeButton>(withdrawBtn).onPressed != null;

    testWidgets('有已入账分润:可点,弹的是客服微信号,不发任何提现请求', (
      WidgetTester tester,
    ) async {
      await pumpFinance(
        tester,
        const <CoopFinanceRow>[
          CoopFinanceRow(
            topicId: 88,
            topicName: '夜游苏河',
            settled: true,
            myIncome: '80.00',
            myIncomeArrived: true,
          ),
        ],
      );
      expect(withdrawBtn, findsOneWidget);
      expect(withdrawEnabled(tester), isTrue);
      expect(find.text('联系平台客服提现'), findsOneWidget);

      await tester.tap(withdrawBtn);
      await tester.pumpAndSettle();
      // 真源 withdraw-cs.js:弹窗只给微信号 + 返回/复制,没有提交按钮。
      expect(find.textContaining('客服微信号：18000000000'), findsOneWidget);
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('返回'), findsOneWidget);
    });

    testWidgets('已结算但入账金额读不到:说「待确认」,按钮禁用', (
      WidgetTester tester,
    ) async {
      await pumpFinance(
        tester,
        const <CoopFinanceRow>[
          CoopFinanceRow(
            topicId: 88,
            topicName: '夜游苏河',
            settled: true,
            myIncome: null,
          ),
        ],
      );
      expect(find.text('已入账金额待确认'), findsOneWidget);
      expect(withdrawEnabled(tester), isFalse);
      // unknown ≠ 0:不许串成「暂无已入账分润」。
      expect(find.text('暂无已入账分润'), findsNothing);
    });

    testWidgets('没有主题也照给提现行:说「暂无已入账分润」', (
      WidgetTester tester,
    ) async {
      await pumpFinance(tester, const <CoopFinanceRow>[]);
      expect(find.text('还没有合作结算'), findsOneWidget);
      expect(withdrawBtn, findsOneWidget);
      expect(find.text('暂无已入账分润'), findsOneWidget);
      expect(withdrawEnabled(tester), isFalse);
    });
  });
}
