// 报名→支付→结果面板一条链(gap-spec-player #3 · 3d 验收:「支付成功弹层出现」)。
//
// 真源纪律逐条锁住:
//  · 零元单不进微信 SDK,直接出「报名成功」面板并自愈关闭;
//  · SDK 明确失败 → fail 面板,「知道了」后回落到页面常驻 submitError,
//    待支付单保留(CTA 换「去支付」原地重试);
//  · 旧幂等键撞终态 409/410 → 换键重建**一次**,再撞就报「订单已过期,请重新报名」;
//  · 同码 409 的「价格已更新」走重报价,不重建;
//  · 支付通道探测说不可用且有待支付金额 → CTA 变「重新检查支付服务」,按下不建单。
//
// 支付方式:整页报名 sheet 走真 widget 树,ActivityApi/AccountApi 用假实现;
// 支付六元组故意给不全的 —— WechatPayment 参数不齐直接返回 failed,
// 不触真实 SDK(见 wechat_payment.dart 的 hasCompleteAppParams 早退)。
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/account_api.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/api/participant_api.dart' show Participant;
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/activity/activity_controller.dart';
import 'package:chengyin_app/feature/activity/activity_detail_page.dart';
import 'package:chengyin_app/feature/activity/participant_picker.dart'
    show participantsProvider;
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/payment/wechat_payment.dart'
    show wechatPaymentFlowGate;

class _FixedAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    user: User(id: 7, nickname: '我', avatar: '', role: 'player'),
    initialized: true,
  );
}

class _FakeAccount implements AccountApi {
  int agreeCalls = 0;

  @override
  Future<void> agreeSignupDataSharing(String requestId) async {
    agreeCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FlowActivityApi implements ActivityApi {
  _FlowActivityApi({required this.createOutcomes, this.ready = true});

  /// 每次 createRegistration 依序消费一个:结果或异常。
  final List<Object> createOutcomes;
  final bool ready;

  int createCalls = 0;
  int readinessCalls = 0;
  final List<String?> requestIds = <String?>[];

  @override
  Future<RegistrationQuote> quote({
    required int ownerId,
    int? ticketId,
    bool usePoints = false,
  }) async => const RegistrationQuote(payAmount: 49, quoteSign: 'signed');

  @override
  Future<({bool ready, String message})> paymentReadiness() async {
    readinessCalls++;
    return (ready: ready, message: ready ? '' : '支付服务暂不可用');
  }

  @override
  Future<RegistrationCreateResult> createRegistration({
    required int ownerId,
    required String realName,
    required String phone,
    int? ticketId,
    String? email,
    String? participateDate,
    bool appPay = true,
    String? requestId,
    bool usePoints = false,
    required String quoteSign,
    int? waitlistOfferId,
    String? waitlistOfferToken,
  }) async {
    createCalls++;
    requestIds.add(requestId);
    final outcome = createOutcomes[createCalls - 1];
    if (outcome is Exception) throw outcome;
    return outcome as RegistrationCreateResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ActivityDetail _activity() => ActivityDetail(
  id: 7,
  name: '静安探店日',
  tickets: <ActivityTicket>[ActivityTicket(id: 11, name: '早鸟单人票', price: 49)],
);

Future<_FlowActivityApi> _openSignup(
  WidgetTester tester,
  _FlowActivityApi api, {
  _FakeAccount? account,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(_FixedAuth.new),
        activityApiProvider.overrideWithValue(api),
        accountApiProvider.overrideWithValue(account ?? _FakeAccount()),
        activityDetailProvider(7).overrideWith((ref) async => _activity()),
        myJoinedActivitiesProvider.overrideWith(
          (ref) async => <MyRegistration>[],
        ),
        participantsProvider.overrideWith((ref) async => <Participant>[]),
      ].cast(),
      child: const MaterialApp(home: ActivityDetailPage(activityId: 7)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('立即报名'));
  await tester.pumpAndSettle();
  // 填表单 + 勾单独同意(建单硬前置),再按主按钮。
  await tester.enterText(find.byType(CupertinoTextField).at(0), '张三');
  await tester.enterText(find.byType(CupertinoTextField).at(1), '13800000000');
  await tester.tap(find.byKey(const Key('signup-data-consent')));
  await tester.pumpAndSettle();
  return api;
}

Future<void> _pressPay(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('signup-pay')));
  // 结果面板入场要跑完整动画,pumpAndSettle 可能被 toast/转圈挂住,用定长。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pump();
}

void main() {
  // wechatPaymentFlowGate 是进程级单例:上一用例若停在面板未关(_submit 的
  // finally 还没跑),闸会被带着泄漏进下一用例。每条进来先释放。
  setUp(wechatPaymentFlowGate.release);

  testWidgets('零元单:不出 SDK,直接出「报名成功」面板,停 2s 后自愈收尾', (tester) async {
    await _openSignup(
      tester,
      _FlowActivityApi(
        createOutcomes: <Object>[
          const RegistrationCreateResult(registrationId: 501),
        ],
      ),
    );
    await _pressPay(tester);
    expect(find.byKey(const Key('payment-result-sheet')), findsOneWidget);
    expect(find.text('报名成功'), findsOneWidget, reason: '验收:支付/报名成功弹层必须真实出现');
    expect(find.text('票已放入票夹，出发前 30 分钟到集合点核验'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('payment-result-sheet')), findsNothing);
    expect(find.text('立即报名'), findsOneWidget, reason: '_finish 应收起报名 sheet');
  });

  testWidgets('SDK 失败:fail 面板 →「知道了」回落 submitError,待支付单原地保留', (tester) async {
    await _openSignup(
      tester,
      _FlowActivityApi(
        createOutcomes: <Object>[
          const RegistrationCreateResult(
            registrationId: 502,
            payParams: <String, String>{'appId': 'wx'}, // 故意不全 → failed
          ),
        ],
      ),
    );
    await _pressPay(tester);
    expect(find.text('这笔没有付成功'), findsOneWidget);
    expect(find.text('支付未完成'), findsOneWidget);

    await tester.tap(find.byKey(const Key('payment-result-close')));
    // sheet 退场动画要逐帧喂,单发大 delta 走不完。
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('payment-result-sheet')), findsNothing);
    expect(find.byKey(const Key('signup-submit-error')), findsOneWidget);
    expect(find.text('去支付'), findsOneWidget, reason: '建单成功支付失败 → 主按钮该换回原地重试付款');
  });

  testWidgets('旧幂等键撞终态 409:换键重建一次,成功出面板', (tester) async {
    final api = _FlowActivityApi(
      createOutcomes: <Object>[
        const RegistrationCheckoutException(409, '该幂等键对应的报名已取消/已过期，请重新发起报名'),
        const RegistrationCreateResult(registrationId: 503),
      ],
    );
    await _openSignup(tester, api);
    await _pressPay(tester);
    expect(api.createCalls, 2);
    // 放面板自然走完(2s hold + 退场),不把 open 的 sheet 留到 teardown。
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(api.requestIds[0], isNotNull);
    expect(api.requestIds[1], isNotNull);
    expect(api.requestIds[0], isNot(api.requestIds[1]), reason: '重建必须换新幂等键');
    expect(find.text('报名成功'), findsOneWidget);
  });

  testWidgets('重建后再撞同样的错:只重建一次,报「订单已过期,请重新报名」', (tester) async {
    final api = _FlowActivityApi(
      createOutcomes: <Object>[
        const RegistrationCheckoutException(410, '订单已过期,请重新报名'),
        const RegistrationCheckoutException(410, '订单已过期,请重新报名'),
      ],
    );
    await _openSignup(tester, api);
    await _pressPay(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(api.createCalls, 2, reason: '识别面只允许自动换键重建一次');
    expect(find.text('订单已过期,请重新报名'), findsOneWidget);
  });

  testWidgets('同码 409 的「价格已更新」走重报价,不重建', (tester) async {
    final api = _FlowActivityApi(
      createOutcomes: <Object>[
        const RegistrationCheckoutException(409, '价格已更新，请重新确认'),
      ],
    );
    await _openSignup(tester, api);
    await _pressPay(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(api.createCalls, 1);
    expect(find.byKey(const Key('signup-submit-error')), findsOneWidget);
    expect(find.text('价格已更新，请重新确认'), findsOneWidget);
  });

  testWidgets('支付通道探测不可用:CTA 变「重新检查支付服务」,按下不建单', (tester) async {
    final api = _FlowActivityApi(
      createOutcomes: <Object>[
        const RegistrationCreateResult(registrationId: 5),
      ],
      ready: false,
    );
    await _openSignup(tester, api);
    await tester.pumpAndSettle();
    expect(find.text('重新检查支付服务'), findsOneWidget);
    await tester.tap(find.byKey(const Key('signup-pay')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(api.createCalls, 0, reason: '没通就拦下,重新探测而非硬发起支付');
    expect(api.readinessCalls, greaterThanOrEqualTo(2));
  });
}
