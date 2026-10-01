import '../../support/fixed_auth.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:chengyin_app/core/widgets/cy_native_notice.dart';
import 'package:chengyin_app/data/api/coop_api.dart';
import 'package:chengyin_app/data/models/merchant_coop.dart';
import 'package:chengyin_app/feature/coop/coop_list_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_coop_page.dart';
import 'package:chengyin_app/feature/payment/wechat_payment.dart';

class _AccountAuth extends AuthController {
  @override
  AuthState build() => signedInAuthState();
  void changeAccount() => state = AuthState(initialized: true,
      user: User(id: 2, nickname: 'B', avatar: '', role: 'player'));
}

class _FakeCoopApi implements CoopApi {
  _FakeCoopApi(
    this.params, {
    this.paymentStatus = 'pending',
    this.inviteCount = 1,
  });

  final Map<String, String> params;
  final String paymentStatus;
  final int inviteCount;
  int? depositInviteId;
  int? statusInviteId;
  int inviteListCalls = 0;
  int depositCalls = 0;
  int statusCalls = 0;

  @override
  Future<Map<String, dynamic>> inviteList() async {
    inviteListCalls++;
    return <String, dynamic>{
      'received': List<dynamic>.generate(
        inviteCount,
        (int index) => <String, dynamic>{
          'id': 42 + index,
          'inviteType': 0,
          'fromId': 7,
          'toType': 'merchant',
          'toId': 8,
          'topicId': 9,
          'status': 1,
          'shareMode': 0,
          'depositOwed': true,
          'partner': <String, dynamic>{'name': '静安咖啡'},
        },
      ),
      'sent': <dynamic>[],
    };
  }

  @override
  Future<Map<String, String>> createDeposit(int inviteId) async {
    depositCalls++;
    depositInviteId = inviteId;
    return params;
  }

  @override
  Future<String> depositStatus(int inviteId) async {
    statusCalls++;
    statusInviteId = inviteId;
    return paymentStatus;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const Map<String, String> _validPayParams = <String, String>{
  'appId': 'wx-app',
  'partnerId': 'merchant',
  'prepayId': 'prepay',
  'packageValue': 'Sign=WXPay',
  'nonceStr': 'nonce',
  'timeStamp': '1700000000',
  'sign': 'signature',
};

Widget _app({
  required _FakeCoopApi api,
  required bool configured,
  required Future<WechatPayOutcome> Function(Map<String, String>) pay,
}) {
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(_AccountAuth.new),
      coopApiProvider.overrideWithValue(api),
      coopDepositPaymentConfiguredProvider.overrideWithValue(configured),
      coopDepositPayProvider.overrideWithValue(pay),
      coopDepositPaymentGateProvider.overrideWithValue(WechatPaymentGate()),
      // 「收到的」这一档还并了官方邀约那一路(真源 2026-09-15 收编),不挡掉
      // 它会发真的商家请求,pumpAndSettle 永远不静。
      merchantInvitesProvider.overrideWith(
        (ref) async => const <MerchantInvite>[],
      ),
    ],
    child: const MaterialApp(home: CoopListPage()),
  );
}

void main() {
  testWidgets('account switch during native payment prevents old deposit readback and notice', (tester) async {
    final api = _FakeCoopApi(_validPayParams, paymentStatus: 'success');
    final payment = Completer<WechatPayOutcome>();
    await tester.pumpWidget(_app(api: api, configured: true, pay: (_) => payment.future));
    await tester.pumpAndSettle();
    await tester.tap(find.text('缴纳保证金'));
    await tester.pump();
    expect(api.depositCalls, 1);
    final container = ProviderScope.containerOf(tester.element(find.byType(CoopListPage)));
    (container.read(authControllerProvider.notifier) as _AccountAuth).changeAccount();
    await tester.pump();
    payment.complete(WechatPayOutcome.success);
    await tester.pumpAndSettle();
    expect(api.statusCalls, 0);
    expect(find.text('保证金已到账'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  tearDown(CyNativeNotice.hide);

  testWidgets('SDK success 但服务端 pending 时不得说已到账', (WidgetTester tester) async {
    final api = _FakeCoopApi(_validPayParams);
    Map<String, String>? paidWith;
    await tester.pumpWidget(
      _app(
        api: api,
        configured: true,
        pay: (Map<String, String> params) async {
          paidWith = params;
          return WechatPayOutcome.success;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('缴纳保证金'));
    await tester.pumpAndSettle();

    expect(api.depositInviteId, 42);
    expect(paidWith, _validPayParams);
    expect(api.statusInviteId, 42);
    expect(api.inviteListCalls, greaterThanOrEqualTo(2));
    expect(find.text('保证金支付处理中，请稍后刷新'), findsOneWidget);
    expect(find.text('保证金已到账'), findsNothing);
  });

  testWidgets('只有服务端 success 才提示保证金已到账', (WidgetTester tester) async {
    final api = _FakeCoopApi(_validPayParams, paymentStatus: 'success');
    await tester.pumpWidget(
      _app(
        api: api,
        configured: true,
        pay: (_) async => WechatPayOutcome.success,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('缴纳保证金'));
    await tester.pumpAndSettle();

    expect(api.statusInviteId, 42);
    expect(find.text('保证金已到账'), findsOneWidget);
  });

  for (final outcome in <WechatPayOutcome>[
    WechatPayOutcome.cancelled,
    WechatPayOutcome.failed,
    WechatPayOutcome.unknown,
  ]) {
    testWidgets('SDK ${outcome.name} 仍回读服务端保证金状态', (WidgetTester tester) async {
      final api = _FakeCoopApi(_validPayParams);
      await tester.pumpWidget(
        _app(api: api, configured: true, pay: (_) async => outcome),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('缴纳保证金'));
      await tester.pumpAndSettle();

      expect(api.statusInviteId, 42);
      expect(api.statusCalls, 1);
    });
  }

  testWidgets('连点缴纳保证金只建一次单', (WidgetTester tester) async {
    final api = _FakeCoopApi(_validPayParams);
    final completer = Completer<WechatPayOutcome>();
    await tester.pumpWidget(
      _app(api: api, configured: true, pay: (_) => completer.future),
    );
    await tester.pumpAndSettle();

    final Finder button = find.text('缴纳保证金');
    await tester.tap(button);
    await tester.tap(button);
    await tester.pump();
    expect(api.depositCalls, 1);

    completer.complete(WechatPayOutcome.cancelled);
    await tester.pumpAndSettle();
  });

  testWidgets('两条邀请并发点击也只允许创建一笔保证金订单', (WidgetTester tester) async {
    final api = _FakeCoopApi(_validPayParams, inviteCount: 2);
    final completer = Completer<WechatPayOutcome>();
    await tester.pumpWidget(
      _app(api: api, configured: true, pay: (_) => completer.future),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('coop-deposit-42')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('coop-deposit-43')));
    await tester.pump();

    expect(api.depositCalls, 1);
    expect(find.text('已有一笔支付正在处理中，请完成后再试'), findsOneWidget);

    completer.complete(WechatPayOutcome.cancelled);
    await tester.pumpAndSettle();
  });

  testWidgets('微信未配置时不建单，用 Apple 风格页内反馈明确说明', (WidgetTester tester) async {
    final api = _FakeCoopApi(_validPayParams);
    var paymentCalls = 0;
    await tester.pumpWidget(
      _app(
        api: api,
        configured: false,
        pay: (Map<String, String> _) async {
          paymentCalls++;
          return WechatPayOutcome.success;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('缴纳保证金'));
    await tester.pump();

    expect(api.depositInviteId, isNull);
    expect(paymentCalls, 0);
    expect(find.text('微信支付尚未配置，请稍后再试'), findsOneWidget);
  });

  testWidgets('后端少任一 App 支付签名字段时 fail closed，不调起微信', (
    WidgetTester tester,
  ) async {
    final params = <String, String>{..._validPayParams}..remove('sign');
    final api = _FakeCoopApi(params);
    var paymentCalls = 0;
    await tester.pumpWidget(
      _app(
        api: api,
        configured: true,
        pay: (Map<String, String> _) async {
          paymentCalls++;
          return WechatPayOutcome.success;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('缴纳保证金'));
    await tester.pump();

    expect(api.depositInviteId, 42);
    expect(paymentCalls, 0);
    expect(find.text('支付参数不完整，请稍后重试'), findsOneWidget);
  });

  // ─────────────────────── 保证金退款重试(push 接线 · 涉资兜底入口)
  // 真源 pages/coop/list/index.wxml:74/205 的 wx:if:
  //   depositRefundPending && !legacyReadonly —— 独立于「已接受」动作块。

  Map<String, dynamic> refundRow(
    int id, {
    int inviteType = 0,
    bool refundPending = true,
  }) => <String, dynamic>{
    'id': id,
    'inviteType': inviteType,
    'fromId': 7,
    'toType': 'merchant',
    'toId': 8,
    'topicId': 9,
    'status': 2,
    'depositRefundPending': refundPending,
    'partner': <String, dynamic>{'name': '静安咖啡'},
  };

  group('重试保证金退款', () {
    testWidgets('只有 depositRefundPending 且非 legacy 只读卡给重试入口', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
      authControllerProvider.overrideWith(_AccountAuth.new),
            coopApiProvider.overrideWithValue(
              _RefundFakeApi(<Map<String, dynamic>>[
                refundRow(42),
                refundRow(43, inviteType: 2),
                refundRow(44, refundPending: false),
              ]),
            ),
            merchantInvitesProvider.overrideWith(
              (ref) async => const <MerchantInvite>[],
            ),
          ],
          child: const MaterialApp(home: CoopListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('coop-retry-refund-42')), findsOneWidget);
      expect(find.text('重试保证金退款'), findsOneWidget);
      expect(find.byKey(const Key('coop-retry-refund-43')), findsNothing);
      expect(find.byKey(const Key('coop-retry-refund-44')), findsNothing);
    });

    testWidgets('点重试:发 inviteId、回执用服务端原话、并重拉列表刷新真值', (
      WidgetTester tester,
    ) async {
      final api = _RefundFakeApi(<Map<String, dynamic>>[refundRow(42)]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
      authControllerProvider.overrideWith(_AccountAuth.new),
            coopApiProvider.overrideWithValue(api),
            merchantInvitesProvider.overrideWith(
              (ref) async => const <MerchantInvite>[],
            ),
          ],
          child: const MaterialApp(home: CoopListPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('coop-retry-refund-42')));
      await tester.pumpAndSettle();

      expect(api.retriedInviteId, 42);
      expect(find.text('退款已重新发起，原路退回'), findsOneWidget);
      expect(api.listCalls, greaterThanOrEqualTo(2));
    });

    testWidgets('结果暂无法确认:催核对不催重发,失败后按钮仍可点', (WidgetTester tester) async {
      final api = _RefundFakeApi(<Map<String, dynamic>>[
        refundRow(42),
      ], error: Exception('退款结果暂无法确认，请先核对，勿重复提交'));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
      authControllerProvider.overrideWith(_AccountAuth.new),
            coopApiProvider.overrideWithValue(api),
            merchantInvitesProvider.overrideWith(
              (ref) async => const <MerchantInvite>[],
            ),
          ],
          child: const MaterialApp(home: CoopListPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('coop-retry-refund-42')));
      await tester.pumpAndSettle();

      expect(find.text('退款结果暂无法确认，请先核对，勿重复提交'), findsOneWidget);
      // 失败不重拉列表(回执≠观测:没确认的事不做下一步)。
      expect(api.listCalls, 1);
      final button = find.byKey(const Key('coop-retry-refund-42'));
      expect(
        tester.widget<CyNativeButton>(button).onPressed,
        isNotNull,
        reason: '失败后必须恢复可点 —— 兜底入口不能把自己锁死',
      );
    });
  });
}

class _RefundFakeApi implements CoopApi {
  _RefundFakeApi(this.rows, {this.error});

  final List<Map<String, dynamic>> rows;
  final Object? error;
  int listCalls = 0;
  int retryCalls = 0;
  int? retriedInviteId;

  @override
  Future<Map<String, dynamic>> inviteList() async {
    listCalls++;
    return <String, dynamic>{'received': rows, 'sent': <dynamic>[]};
  }

  @override
  Future<String> retryDepositRefund(int inviteId) async {
    retryCalls++;
    retriedInviteId = inviteId;
    if (error != null) throw error!;
    return '退款已重新发起，原路退回';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
