// 订单列表「立即支付」接线(gap-spec-player #3 · 3d):
// SDK 明确失败不再只弹 toast —— 走与报名同一张结果面板,fail 相人工关闭后
// 列表刷新、订单态仍以服务端为准(本地绝不自封成功/失败)。
// 六元组故意给不全:WechatPayment 参数不齐直接返回 failed,不触真实 SDK。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/feature/orders/orders_page.dart';
import 'package:chengyin_app/feature/payment/wechat_payment.dart'
    show wechatPaymentFlowGate;

class _PayApi implements ActivityApi {
  int payAppCalls = 0;
  int statusCalls = 0;
  @override
  Future<RegistrationDetail> ticketInfo(int id) async {
    statusCalls++;
    return RegistrationDetail(id: id, ownerType: 2, ownerId: 7,
      entitlements: const [], paymentStatus: 4, registrationStatus: 3);
  }


  @override
  Future<({bool ready, String message})> paymentReadiness() async =>
      (ready: true, message: '');

  @override
  Future<Map<String, String>> payApp(int registrationId) async {
    payAppCalls++;
    return <String, String>{'appId': 'wx'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpFrames(WidgetTester tester, {int times = 10}) async {
  // sheet 退场动画要逐帧喂,单发大 delta 走不完。
  for (int i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(wechatPaymentFlowGate.release);

  testWidgets('待支付单立即支付:SDK 参数不全→fail 面板→知道了→只刷新列表', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _PayApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          activityApiProvider.overrideWithValue(api),
          myOrdersProvider.overrideWith(
            (ref) async => <MyRegistration>[
              MyRegistration(
                id: 901,
                ownerType: 2,
                ownerId: 7,
                registrationStatus: 1,
                title: '静安探店日',
              ),
            ],
          ),
        ].cast(),
        child: const MaterialApp(home: OrdersPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即支付'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    expect(api.payAppCalls, 1);
    expect(
      find.text('这笔没有付成功'),
      findsOneWidget,
      reason: '支付失败要进结果面板,不再只是一条 toast',
    );
    expect(api.statusCalls, 1);
    expect(find.text('请查看订单确认最终状态，暂不要重复支付。'), findsOneWidget);

    await tester.tap(find.byKey(const Key('payment-result-close')));
    await _pumpFrames(tester);
    expect(find.byKey(const Key('payment-result-sheet')), findsNothing);
    // 列表刷新后订单仍是待支付(服务端真源),按钮还在。
    expect(find.text('立即支付'), findsOneWidget);
  });
}
