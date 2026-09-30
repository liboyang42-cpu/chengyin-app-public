// 单笔核销详情(E12)。结构 1:1 跟小程序 pages/merchant/ledger/order-detail。
//
// ★ 这一页的存在意义是**解释那个金额**。所以最要命的错法是:
//   ① 后端没给金额却画个「¥0.00」—— 商家以为系统算错了;
//   ② 后端脱敏(不给资金投影)时还硬画金额行或拿空 displayState 查表,
//      把「后端不肯说」说成「状态不明」;
//   ③ 时间线给未来节点编日期(「预计打款」= 假承诺);
//   ④ 越权保护(记录不可见)被渲染成「加载失败 + 重试」,点一辈子也不会好。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/models/merchant_finance.dart';
import 'package:chengyin_app/feature/merchant/merchant_redemption_detail_page.dart';
import '../../golden/golden_theme.dart';

const ({String recordType, String recordId}) _key = (
  recordType: 'redemption',
  recordId: '7001',
);

Map<String, dynamic> _json({
  String? settlementState = 'PENDING',
  String? settlementRoute = 'CHAPTER_OFFER',
  String? displayState = 'PENDING_SETTLEMENT',
  String? settlementAmount = '12.34',
  String? noCashReason,
  String? fulfillmentState = 'ACTIVE',
  String? occurredAt = '2026-09-01 12:30:45',
  num? unitFee = 8,
  num? headCount = 3,
  String? refundState,
  String? paidAt,
}) => <String, dynamic>{
  'recordKey': 'r-1',
  'topicName': '深夜书店',
  'chapterName': '第一章',
  'storeName': '城南店',
  'fulfillmentState': fulfillmentState,
  'settlementState': settlementState,
  'settlementRoute': settlementRoute,
  'displayState': displayState,
  'settlementAmount': settlementAmount,
  'noCashReason': noCashReason,
  'occurredAt': occurredAt,
  'unitFee': unitFee,
  'headCount': headCount,
  'refundState': refundState,
  'publicSettlement': paidAt == null
      ? null
      : <String, dynamic>{'paidAt': paidAt},
};

Future<void> _pump(
  WidgetTester tester,
  Object? Function() load, {
  String type = 'redemption',
  String id = '7001',
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 900));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        merchantRedemptionDetailProvider(_key).overrideWith((Ref ref) async {
          final Object? v = load();
          if (v is Exception) throw v;
          return MerchantRedemptionView.fromJson(v! as Map<String, dynamic>);
        }),
      ].cast(),
      child: MaterialApp.router(
        theme: merchantGoldenTheme(),
        routerConfig: GoRouter(
          initialLocation: '/merchant/redemption',
          routes: <RouteBase>[
            GoRoute(
              path: '/merchant/redemption',
              builder: (BuildContext context, GoRouterState state) =>
                  MerchantRedemptionDetailPage(recordType: type, recordId: id),
            ),
            GoRoute(
              path: '/assets',
              builder: (BuildContext context, GoRouterState state) =>
                  const Text('我的资产页'),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('hero:金额 / 状态徽标 / 计提规则 / 核销时间 / 结算去向', (
    WidgetTester tester,
  ) async {
    await _pump(tester, () => _json(settlementRoute: 'COOP_ORDER'));

    expect(find.text('深夜书店 · 第一章 · 我的收入'), findsOneWidget);
    expect(find.text('¥12.34'), findsOneWidget);
    expect(find.text('随主题结算发放至个人账户'), findsOneWidget);
    expect(find.text('城南店'), findsOneWidget);
    // 单价 × 人头:后端没同时给这两个数就不该有这一行(见下一条)。
    expect(find.text('¥8/人 × 3'), findsOneWidget);
    // 秒级串截到分钟。
    expect(find.text('2026-09-01 12:30'), findsOneWidget);
    expect(find.text('个人账户 · 去我的资产'), findsOneWidget);
  });

  testWidgets('★ 结算去向是可点入口,落到「我的资产」', (WidgetTester tester) async {
    await _pump(tester, () => _json(settlementRoute: 'COOP_ORDER'));
    await tester.tap(find.text('个人账户 · 去我的资产'));
    await tester.pumpAndSettle();
    expect(find.text('我的资产页'), findsOneWidget);
  });

  testWidgets('★★ 零现金:金额说「—」而不是 ¥0.00,徽标说服务端给的原因', (WidgetTester tester) async {
    await _pump(
      tester,
      () => _json(
        displayState: 'NO_CASH_SETTLEMENT',
        settlementAmount: null,
        noCashReason: '本场为零现金开售,权益由平台补贴',
      ),
    );
    expect(find.text('—'), findsOneWidget);
    expect(find.text('¥0.00'), findsNothing);
    expect(find.text('本场为零现金开售,权益由平台补贴'), findsOneWidget);
  });

  testWidgets('★★ 脱敏(后端不给资金投影):不画金额行,只说履约事实', (WidgetTester tester) async {
    await _pump(
      tester,
      () => _json(
        settlementState: null,
        settlementRoute: null,
        displayState: null,
        settlementAmount: null,
      ),
    );
    expect(find.text('深夜书店 · 第一章 · 我的收入'), findsNothing);
    expect(find.text('深夜书店 · 第一章'), findsOneWidget);
    expect(find.text('待定'), findsNothing);
    expect(find.text('—'), findsNothing);
    // ★ 不能拿空 displayState 去查资金表 —— 那会落到「状态待确认」,
    //   把「后端不肯说结算」说成「状态不明」。
    expect(find.text('核销有效'), findsOneWidget);
    expect(find.text('结算进度'), findsNothing);
  });

  testWidgets('★★ 计提规则缺任一(单价/人头)整行不画 —— 不猜', (WidgetTester tester) async {
    await _pump(tester, () => _json(headCount: null));
    expect(find.text('计提规则'), findsNothing);
  });

  testWidgets('★★ 时间线:待结算是「正在办」,未来节点不给日期', (WidgetTester tester) async {
    await _pump(tester, () => _json(settlementState: 'PENDING'));
    expect(find.text('结算进度'), findsOneWidget);
    for (final String label in <String>['核销成功', '生成结算单', '对账确认', '平台打款']) {
      expect(find.text(label), findsOneWidget);
    }
    // 只有核销那一节点有真时间(hero 的「核销时间」行 + 时间线节点,共两处);
    // 「预计打款日」这类文案一个字都不许出现。
    expect(find.textContaining('预计'), findsNothing);
    expect(find.text('2026-09-01 12:30'), findsNWidgets(2));
  });

  testWidgets('★ 已结算把「平台打款」落到时间戳', (WidgetTester tester) async {
    await _pump(
      tester,
      () => _json(
        settlementState: 'SETTLED',
        displayState: 'SETTLED',
        paidAt: '2026-09-10 09:05:00',
      ),
    );
    // hero 的核销时间行 + 时间线末节点,共两处。
    expect(find.text('2026-09-10 09:05'), findsOneWidget);
    expect(find.text('平台已打款'), findsOneWidget);
  });

  testWidgets('★ 不是章节供给的结算没有「结算进度」这条线', (WidgetTester tester) async {
    await _pump(tester, () => _json(settlementRoute: 'COOP_ORDER'));
    expect(find.text('结算进度'), findsNothing);
    expect(find.text('核销成功'), findsNothing);
  });

  testWidgets('缺参:说清缺什么 + 一个「返回上一页」', (WidgetTester tester) async {
    await _pump(tester, () => _json(), type: '', id: '');
    expect(find.text('缺少核销记录标识'), findsOneWidget);
    expect(find.text('请返回核销记录列表重新进入'), findsOneWidget);
    expect(find.text('返回上一页'), findsOneWidget);
  });

  testWidgets('★★ 记录不可见是越权保护:给「返回核销列表」,不给重试', (WidgetTester tester) async {
    await _pump(tester, () => MerchantApiException('记录不可见'));
    expect(find.text('核销记录不可见'), findsOneWidget);
    expect(find.text('这条记录不属于当前商家,或已被移除'), findsOneWidget);
    expect(find.text('返回核销列表'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('★★ 传输层失败才说「网络不稳定」', (WidgetTester tester) async {
    await _pump(
      tester,
      () => DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      ),
    );
    expect(find.text('核销详情没加载出来'), findsOneWidget);
    expect(find.text('网络不稳定，请检查连接后重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('★★ 网关 5xx:异常英文原文只进日志,不上屏', (WidgetTester tester) async {
    await _pump(
      tester,
      () => DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.badResponse,
        response: Response<String>(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 502,
          data: 'DioException [bad response]: status code of 502 ...',
        ),
      ),
    );
    expect(find.textContaining('status code of 502'), findsNothing);
    // 5xx 口径并到 main 上 #235 落盘的共用话术(英文原文仍只进 debugPrint)。
    expect(find.text('服务暂时不可用，请稍后重试'), findsNothing);
    expect(find.text('网络异常，请稍后重试'), findsOneWidget);
  });

  testWidgets('★ HTTP 非 200 但后端回了「记录不可见」:仍判越权,不折成服务故障', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      () => DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.badResponse,
        response: Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 403,
          data: <String, dynamic>{'msg': '记录不可见'},
        ),
      ),
    );
    expect(find.text('核销记录不可见'), findsOneWidget);
    expect(find.text('返回核销列表'), findsOneWidget);
  });

  testWidgets('★★ 业务错误照后端原文,不许栽成网络问题', (WidgetTester tester) async {
    await _pump(tester, () => MerchantApiException('核销详情数据不完整，请重试'));
    expect(find.text('核销详情没加载出来'), findsOneWidget);
    expect(find.text('核销详情数据不完整，请重试'), findsOneWidget);
    expect(find.text('网络不稳定，请检查连接后重试'), findsNothing);
  });
}
