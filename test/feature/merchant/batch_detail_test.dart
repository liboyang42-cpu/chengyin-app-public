// 对公打款批次明细。
//
// ★ 之前账本里的批次行**点不进去** —— 列了出来却是个死入口。
//
// ★★★ 三条判据(全部来自后端/资金域定稿,自己写必错):
//   ① 打款日期/凭证号**只在真的打给我了之后**显示 ——
//      反方向(商家欠平台)即使 paymentState=PAID 也不算
//   ② 收入与调整**分开两段**:后端就是分开给的,合并成一个列表
//      商家看不出哪些是扣减
//   ③ 未来节点**不给日期、不写「预计」**——「预计打款日期」这条规则
//      代码里不存在,凭空写是假承诺(资金域定稿附录 C)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/provider_retry.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/models/merchant_finance.dart';
import 'package:chengyin_app/feature/merchant/batch_detail_page.dart';
import '../../golden/golden_theme.dart';

class _FakeApi implements MerchantApi {
  _FakeApi(this.detail);
  final PublicTransferBatchDetail detail;
  @override
  Future<PublicTransferBatchDetail> publicTransferBatchDetail(int id) async =>
      detail;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

PublicTransferBatchDetail _d({
  required Map<String, dynamic> batch,
  List<Map<String, dynamic>> earnings = const <Map<String, dynamic>>[],
  List<Map<String, dynamic>> adjustments = const <Map<String, dynamic>>[],
}) => PublicTransferBatchDetail(
  batch: PublicTransferBatch.fromJson(batch),
  earningEntries: earnings.map(MerchantSettlementEntry.fromJson).toList(),
  adjustments: adjustments.map(MerchantSettlementEntry.fromJson).toList(),
);

Future<void> _pump(WidgetTester t, PublicTransferBatchDetail d) async {
  await t.binding.setSurfaceSize(const Size(390, 1200));
  await t.pumpWidget(
    ProviderScope(
      retry: chengyinRetry,
      overrides: <dynamic>[
        merchantApiProvider.overrideWithValue(_FakeApi(d)),
      ].cast(),
      child: MaterialApp(
        theme: merchantGoldenTheme(),
        home: const BatchDetailPage(batchId: 1),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('★★★ 反方向即使 PAID 也不显示打款日期/凭证', (WidgetTester t) async {
    await _pump(
      t,
      _d(
        batch: <String, dynamic>{
          'batchId': '1',
          'periodYm': '2026-08',
          'amountTotal': '-320.00',
          'netDirection': 'MERCHANT_OWES_PLATFORM',
          'paymentState': 'PAID',
          'paidAt': '2026-08-18 14:30:00',
          'payVoucherNo': 'V998',
        },
      ),
    );
    expect(find.text('打款日期'), findsNothing, reason: '那笔钱是商家欠平台的,说成「已打款给你」正好反了');
    expect(find.text('V998'), findsNothing);
    // 打款进度整块也不该出现。
    expect(find.text('打款进度'), findsNothing);
    // 但状态要说清是什么情况。
    expect(find.text('调整待处理'), findsOneWidget);
  });

  testWidgets('★ 真打给我了才显示日期与凭证', (WidgetTester t) async {
    await _pump(
      t,
      _d(
        batch: <String, dynamic>{
          'batchId': '1',
          'periodYm': '2026-08',
          'amountTotal': '860.00',
          'netDirection': 'PLATFORM_PAYS_MERCHANT',
          'paymentState': 'PAID',
          'invoiceState': 'ISSUED',
          'paidAt': '2026-08-18 14:30:00',
          'payVoucherNo': 'V998',
        },
      ),
    );
    expect(find.text('打款日期'), findsOneWidget);
    // 凭证号整行带「· 复制」:只在屏上显示带不走没有用(小程序同文案)。
    expect(find.text('V998 · 复制'), findsOneWidget);
    expect(find.text('已开票'), findsOneWidget);
    expect(find.text('平台已打款 · 已开票'), findsOneWidget);
  });

  testWidgets('★★★ 收入与调整分开两段,看得出哪些是扣减', (WidgetTester t) async {
    await _pump(
      t,
      _d(
        batch: <String, dynamic>{
          'batchId': '1',
          'netDirection': 'PLATFORM_PAYS_MERCHANT',
          'paymentState': 'CONFIRMED',
        },
        earnings: <Map<String, dynamic>>[
          <String, dynamic>{
            'entryKey': 'e1',
            'source': '静安咖啡核销',
            'signedAmount': '120.00',
          },
        ],
        adjustments: <Map<String, dynamic>>[
          <String, dynamic>{
            'entryKey': 'a1',
            'source': '退款冲回',
            'signedAmount': '-20.00',
          },
        ],
      ),
    );
    expect(find.text('调整'), findsOneWidget, reason: '合并成一个列表商家看不出哪些是扣减');
    expect(find.text('¥120.00'), findsOneWidget);
    expect(find.text('¥-20.00'), findsOneWidget);
  });

  testWidgets('★★★ 未来节点不写日期、不写「预计」', (WidgetTester t) async {
    await _pump(
      t,
      _d(
        batch: <String, dynamic>{
          'batchId': '1',
          'netDirection': 'PLATFORM_PAYS_MERCHANT',
          'paymentState': 'PENDING',
        },
      ),
    );
    expect(find.text('打款进度'), findsOneWidget);
    expect(find.text('批次生成'), findsOneWidget);
    expect(find.text('平台打款'), findsOneWidget);
    expect(
      find.textContaining('预计'),
      findsNothing,
      reason: '「预计打款日期」这条规则代码里不存在,凭空写是假承诺',
    );
  });

  testWidgets('★★ 一条分录都没有时说实话', (WidgetTester t) async {
    await _pump(
      t,
      _d(batch: <String, dynamic>{'batchId': '1', 'amountTotal': '0.00'}),
    );
    expect(find.text('本批次没有可列明的条目'), findsOneWidget);
    expect(find.text('明细在履约成立后逐条计入'), findsOneWidget);
  });

  testWidgets('★★ 金额拿不到显「—」,不兜 0', (WidgetTester t) async {
    await _pump(t, _d(batch: <String, dynamic>{'batchId': '1'}));
    expect(find.text('¥0.00'), findsNothing);
    expect(find.text('—'), findsWidgets);
    // 发票态拿不到时,明细页说「待确认」而不是整块藏起来 ——
    // 列表可以省略,明细页省略会让人以为这批没有发票这回事。
    expect(find.text('发票状态待确认'), findsOneWidget);
  });

  // ★ 批次号缺参/非法是一个**界面态**(小程序 `missing-param`):
  //   深链 `/merchant/ledger/batch/abc` 会落到这里,不能拿 0 去打后端。
  testWidgets('★ 缺少批次标识时说实话，并给一条退路', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(390, 900));
    await t.pumpWidget(
      ProviderScope(
        retry: chengyinRetry,
        overrides: <dynamic>[
          merchantApiProvider.overrideWithValue(
            _FakeApi(_d(batch: <String, dynamic>{'batchId': '1'})),
          ),
        ].cast(),
        child: MaterialApp(
          theme: merchantGoldenTheme(),
          home: const BatchDetailPage(),
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text('缺少结算批次标识'), findsOneWidget);
    expect(find.text('请返回结算列表重新进入'), findsOneWidget);
    expect(find.text('返回上一页'), findsOneWidget);
  });

  // ★「记录不可见」是后端的**越权保护**,不是"加载失败":
  //   照原文说,不给一个点了也没用的重试(merchant_api 批次详情注释)。
  testWidgets('★ 别人的批次说「不可见」，不是「加载失败」', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(390, 900));
    await t.pumpWidget(
      ProviderScope(
        retry: chengyinRetry,
        overrides: <dynamic>[
          merchantApiProvider.overrideWithValue(_ThrowingApi('记录不可见')),
        ].cast(),
        child: MaterialApp(
          theme: merchantGoldenTheme(),
          home: const BatchDetailPage(batchId: 9),
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text('结算批次不可见'), findsOneWidget);
    expect(find.text('这条记录可能已撤回或不属于当前账号'), findsOneWidget);
    expect(find.text('返回结算列表'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('★★ 凭证号整行可复制(复制给回执)', (WidgetTester t) async {
    final List<MethodCall> calls = <MethodCall>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(
      t,
      _d(
        batch: <String, dynamic>{
          'batchId': '1',
          'amountTotal': '860.00',
          'netDirection': 'PLATFORM_PAYS_MERCHANT',
          'paymentState': 'PAID',
          'payVoucherNo': 'V998',
        },
      ),
    );

    // 凭证号是拿去跟财务对账的,只在屏上显示带不走没有用。
    expect(find.text('V998 · 复制'), findsOneWidget);
    await t.tap(find.text('V998 · 复制'));
    await t.pump();

    final MethodCall clipboard = calls.firstWhere(
      (MethodCall c) => c.method == 'Clipboard.setData',
    );
    expect((clipboard.arguments as Map<Object?, Object?>)['text'], 'V998');
    expect(find.text('打款凭证已复制'), findsOneWidget);
  });

  // ★ 刷新失败**不掀桌**:屏上那份详情照旧可用,只在顶上说明它没更新
  //   (小程序 `stale-error`;掀桌等于把已经拿到的结算事实从眼前拿走)。
  testWidgets('★★ 刷新失败保住屏上那份详情', (WidgetTester t) async {
    final _FlipApi api = _FlipApi(
      _d(
        batch: <String, dynamic>{
          'batchId': '1',
          'amountTotal': '860.00',
          'netDirection': 'PLATFORM_PAYS_MERCHANT',
          'paymentState': 'PAID',
          'paidAt': '2026-08-18 14:30:00',
          'payVoucherNo': 'V998',
        },
      ),
      '结算详情数据不完整，请重试',
    );
    await t.binding.setSurfaceSize(const Size(390, 1200));
    await t.pumpWidget(
      ProviderScope(
        retry: chengyinRetry,
        overrides: <dynamic>[
          merchantApiProvider.overrideWithValue(api),
        ].cast(),
        child: MaterialApp(
          theme: merchantGoldenTheme(),
          home: const BatchDetailPage(batchId: 1),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('V998 · 复制'), findsOneWidget);

    ProviderScope.containerOf(
      t.element(find.byType(BatchDetailPage)),
    ).invalidate(batchDetailProvider(1));
    await t.pumpAndSettle();

    expect(find.text('结算详情没有更新'), findsOneWidget);
    expect(find.text('结算详情数据不完整，请重试'), findsOneWidget);
    expect(find.text('V998 · 复制'), findsOneWidget, reason: '旧详情没有失效,别拿走');
    expect(find.text('打款日期'), findsOneWidget);
  });
}

/// 永远抛同一个后端原文。
class _ThrowingApi implements MerchantApi {
  _ThrowingApi(this.message);
  final String message;
  @override
  Future<PublicTransferBatchDetail> publicTransferBatchDetail(int id) async =>
      throw MerchantApiException(message);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// 第一次成功、之后失败 —— 演「刷新失败但旧详情还在」。
class _FlipApi implements MerchantApi {
  _FlipApi(this.detail, this.message);
  final PublicTransferBatchDetail detail;
  final String message;
  bool _served = false;
  @override
  Future<PublicTransferBatchDetail> publicTransferBatchDetail(int id) async {
    if (_served) throw MerchantApiException(message);
    _served = true;
    return detail;
  }
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
