// 账本的「结算」视图。
//
// ★★ 这一页说的是**钱**。两条判据不能错:
//   ① 金额拿不到显 `—`,**不兜 0** ——「没拿到」和「是 0」在这里差别巨大:
//      兜 0 会让商家以为这个月一分没进。
//   ② 「有没有待执行调整」按**笔数**判,不按金额:一笔 +100 和一笔 -100
//      合计是 0,但确实有两笔待处理。⚠️ 小程序用金额判,那是它的 bug,不跟。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/provider_retry.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/models/merchant_finance.dart';
import 'package:chengyin_app/data/models/merchant_ledger.dart';
import 'package:chengyin_app/feature/merchant/merchant_settlement_view.dart';
import '../../golden/golden_theme.dart';

class _FakeMerchantApi implements MerchantApi {
  _FakeMerchantApi({
    required this.overview,
    this.batches = const <PublicTransferBatch>[],
  });

  final MerchantSettlementOverview overview;
  final List<PublicTransferBatch> batches;

  @override
  Future<MerchantSettlementOverview> financeOverview() async => overview;

  @override
  Future<MerchantFinancePage<MerchantSettlementEntry>> settlementEntries({
    String source = 'all',
    int pageNum = 1,
    int pageSize = 20,
  }) async =>
      const MerchantFinancePage<MerchantSettlementEntry>(
          rows: <MerchantSettlementEntry>[],
          total: 0,
          pageNum: 1,
          pageSize: 20);

  @override
  Future<MerchantFinancePage<PublicTransferBatch>> publicTransferBatches({
    int pageNum = 1,
    int pageSize = 20,
  }) async =>
      MerchantFinancePage<PublicTransferBatch>(
          rows: batches, total: batches.length, pageNum: 1, pageSize: 20);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _pump(WidgetTester t, _FakeMerchantApi api) async {
  await t.binding.setSurfaceSize(const Size(390, 1200));
  await t.pumpWidget(ProviderScope(
    retry: chengyinRetry,
    overrides: <dynamic>[
      merchantApiProvider.overrideWithValue(api),
    ].cast(),
    child: MaterialApp(
      // 商家页是**浅色**主题(路由包了 _merchantLight)。
      theme: merchantGoldenTheme(),
      home: const Scaffold(body: MerchantSettlementView()),
    ),
  ));
  await t.pumpAndSettle();
}

MerchantSettlementOverview _ov(Map<String, dynamic> j) =>
    MerchantSettlementOverview.fromJson(j);

void main() {
  testWidgets('★★★ 金额拿不到显「—」,不兜 0', (WidgetTester t) async {
    await _pump(t, _FakeMerchantApi(overview: _ov(<String, dynamic>{})));
    expect(find.text('¥0'), findsNothing,
        reason: '兜 0 会让商家以为这个月一分没进');
    expect(find.text('¥0.00'), findsNothing);
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('★ 有值就照实显示,而且只有一个主数字', (WidgetTester t) async {
    await _pump(
      t,
      _FakeMerchantApi(
          overview: _ov(<String, dynamic>{
        'personalArrivedThisMonthNet': '1280.00',
        'personalArrivedThisMonthGross': '1500.00',
        'personalExecutedAdjustmentsThisMonth': '-220.00',
        'publicPayablePending': '860.00',
      })),
    );
    expect(find.text('本月个人账户净入账'), findsOneWidget);
    expect(find.text('¥1280.00'), findsOneWidget);
    expect(find.text('¥1500.00'), findsOneWidget);
  });

  testWidgets('★★ 净额为负时说「净调整」,不是「净入账 -120」',
      (WidgetTester t) async {
    await _pump(
      t,
      _FakeMerchantApi(
          overview: _ov(<String, dynamic>{
        'personalArrivedThisMonthNet': '-120.00',
      })),
    );
    expect(find.text('本月个人账户净调整'), findsOneWidget,
        reason: '「净入账 -120」会让商家以为自己收到了一笔负钱');
    expect(find.text('本月个人账户净入账'), findsNothing);
  });

  testWidgets('★★★ 调整待处理按笔数判 —— 金额合计为 0 也要提示',
      (WidgetTester t) async {
    await _pump(
      t,
      _FakeMerchantApi(
          overview: _ov(<String, dynamic>{
        // 一笔 +100、一笔 -100:金额合计 0,但确实有两笔待处理。
        'adjustmentPending': '0',
        'adjustmentPendingCount': 2,
      })),
    );
    expect(find.text('2 笔调整待处理'), findsOneWidget,
        reason: '按金额判会漏掉这种 —— 小程序就是这么写的,不跟');
  });

  testWidgets('★★ 两个空态各说各的,不许都说「暂无数据」',
      (WidgetTester t) async {
    await _pump(t, _FakeMerchantApi(overview: _ov(<String, dynamic>{})));
    expect(find.text('还没有已成立的收入明细'), findsOneWidget);
    // 说清去哪找:待结算的还在核销记录里。
    expect(find.text('待主题结算的履约会留在核销记录中'), findsOneWidget);
    expect(find.text('还没有对公打款批次'), findsOneWidget);
  });

  testWidgets('★★ 批次:反方向说「调整待处理」,发票态拿不到就不显示',
      (WidgetTester t) async {
    await _pump(
      t,
      _FakeMerchantApi(
        overview: _ov(<String, dynamic>{}),
        batches: <PublicTransferBatch>[
          PublicTransferBatch.fromJson(<String, dynamic>{
            'batchId': 'B1',
            'periodYm': '2026-08',
            'amountTotal': '-320.00',
            'netDirection': 'MERCHANT_OWES_PLATFORM',
            'paymentState': 'PENDING',
            // invoiceState 缺失
          }),
        ],
      ),
    );
    expect(find.text('调整待处理'), findsOneWidget,
        reason: '说成「待对账」商家会一直等一笔永远不会来的打款');
    expect(find.text('未开票'), findsNothing,
        reason: '拿不到发票态却说「未开票」,商家会去催一张可能已经开了的票');
    expect(find.text('2026-08'), findsOneWidget);
  });
}
