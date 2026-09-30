// 增值服务(订阅 + 商业化能力)。
//
// ★ endDate 缺席在后端语义里是"永久有效"(merchant_subscription 表注释),
//   不是"没读到"——这条极容易被误写成显示破折号或空白。
// ★ 自助开通默认关闭时，不展示必败的下单 CTA，
//   也不引导到 App 外购买或人工开通数字权益。

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/feature/merchant/merchant_subscription_page.dart';
import '../../golden/golden_theme.dart' show merchantGoldenTheme;

class _FakeMerchantApi implements MerchantApi {
  _FakeMerchantApi({
    required this.subs,
    required this.caps,
    this.orderFailuresRemaining = 0,
    this.orderCompleter,
    this.orderReply = const <String, dynamic>{'orderSn': 'TPLTM_x'},
    this.orderStatus = 'pending',
  });
  final List<Map<String, dynamic>> subs;
  final Map<String, dynamic> caps;
  int orderFailuresRemaining;
  final Completer<Map<String, dynamic>>? orderCompleter;
  final Map<String, dynamic> orderReply;
  final String orderStatus;
  Map<String, dynamic>? lastOrderBody;
  final List<Map<String, dynamic>> orderBodies = <Map<String, dynamic>>[];
  int orderCallCount = 0;
  final List<String> statusQueries = <String>[];
  int subsCalls = 0;
  int capsCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> mySubscriptions() async {
    subsCalls++;
    return subs;
  }

  @override
  Future<Map<String, dynamic>> commerceCapabilities() async {
    capsCalls++;
    return caps;
  }

  @override
  Future<Map<String, dynamic>> createCommerceOrder(
    Map<String, dynamic> body,
  ) async {
    orderCallCount++;
    lastOrderBody = body;
    orderBodies.add(Map<String, dynamic>.of(body));
    if (orderFailuresRemaining > 0) {
      orderFailuresRemaining--;
      throw MerchantApiException('临时下单失败');
    }
    if (orderCompleter != null) return orderCompleter!.future;
    return orderReply;
  }

  @override
  Future<String> commerceOrderStatus(String orderSn) async {
    statusQueries.add(orderSn);
    return orderStatus;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpPage(WidgetTester tester, _FakeMerchantApi api) async {
  await tester.binding.setSurfaceSize(const Size(390, 900));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[merchantApiProvider.overrideWithValue(api)].cast(),
      child: MaterialApp(
        theme: merchantGoldenTheme(),
        home: const MerchantSubscriptionPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('权益类型字典:已知四种 + 未知原样返回', () {
    expect(subscriptionTypeLabel('premium_template'), '高级模板权益');
    expect(subscriptionTypeLabel('promotion_slot'), '推广位权益');
    expect(subscriptionTypeLabel('brand_home'), '品牌主页权益');
    expect(subscriptionTypeLabel('custom_event'), '活动定制权益');
    expect(subscriptionTypeLabel('whatever'), 'whatever');
    expect(subscriptionTypeLabel(null), '权益');
  });

  testWidgets('★ endDate 缺席 = 永久有效,不是空白/破折号', (WidgetTester tester) async {
    final api = _FakeMerchantApi(
      subs: <Map<String, dynamic>>[
        <String, dynamic>{
          'subscriptionType': 'premium_template',
          'maxUsage': 3,
          'usedCount': 1,
          // endDate 故意缺席
        },
      ],
      caps: <String, dynamic>{
        'selfCheckoutEnabled': false,
        'premiumTemplate': <String, dynamic>{
          'limit': 2,
          'used': 1,
          'remaining': 1,
        },
        'cityNode': <String, dynamic>{'limit': 3, 'used': 0, 'remaining': 3},
      },
    );
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[merchantApiProvider.overrideWithValue(api)].cast(),
        child: MaterialApp(
          theme: merchantGoldenTheme(),
          home: const MerchantSubscriptionPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('永久有效'), findsOneWidget);
    expect(find.text('已用 1 / 3'), findsOneWidget);
    expect(find.text('已用 1 / 2(剩 1)'), findsOneWidget);
  });

  testWidgets('★★ 自助开通关闭时只说明 App 内不提供购买，不引导外部开通', (WidgetTester tester) async {
    final api = _FakeMerchantApi(
      subs: <Map<String, dynamic>>[],
      caps: <String, dynamic>{
        'selfCheckoutEnabled': false,
        'premiumTemplate': <String, dynamic>{
          'limit': 0,
          'used': 0,
          'remaining': 0,
        },
      },
    );
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[merchantApiProvider.overrideWithValue(api)].cast(),
        child: MaterialApp(
          theme: merchantGoldenTheme(),
          home: const MerchantSubscriptionPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('开通高级模板权益'), findsNothing);
    expect(find.text('App 内暂不提供购买'), findsOneWidget);
    expect(find.textContaining('人工开通'), findsNothing);
    expect(find.textContaining('15229020419'), findsNothing);

    await tester.tap(find.text('App 内暂不提供购买'));
    await tester.pump();

    expect(api.orderCallCount, 0);
    expect(api.lastOrderBody, isNull);
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.textContaining('当前版本暂不提供高级模板权益购买'), findsOneWidget);
    expect(find.text('知道了'), findsOneWidget);
    expect(find.textContaining('人工开通'), findsNothing);
    expect(find.textContaining('15229020419'), findsNothing);
    expect(api.orderCallCount, 0);
  });

  testWidgets('★★ 自助开通开启时带合法 requestId 下单', (WidgetTester tester) async {
    final api = _FakeMerchantApi(
      subs: <Map<String, dynamic>>[],
      caps: <String, dynamic>{
        'selfCheckoutEnabled': true,
        'premiumTemplate': <String, dynamic>{
          'limit': 0,
          'used': 0,
          'remaining': 0,
        },
      },
    );
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[merchantApiProvider.overrideWithValue(api)].cast(),
        child: MaterialApp(
          theme: merchantGoldenTheme(),
          home: const MerchantSubscriptionPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('开通高级模板权益'), findsOneWidget);
    expect(find.text('App 内暂不提供购买'), findsNothing);

    await tester.tap(find.text('开通高级模板权益'));
    await tester.pump();

    expect(api.orderCallCount, 1);
    expect(api.lastOrderBody?['bizType'], 'premium_template');
    expect(
      api.lastOrderBody?['requestId'],
      isA<String>().having(
        (String value) => RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(value),
        'wire format',
        isTrue,
      ),
    );
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('★★ iOS 即使服务端开启自助下单也不绕开 Apple IAP', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final api = _FakeMerchantApi(
        subs: <Map<String, dynamic>>[],
        caps: <String, dynamic>{'selfCheckoutEnabled': true},
      );
      await _pumpPage(tester, api);

      expect(find.text('开通高级模板权益'), findsNothing);
      expect(find.text('App 内暂不提供购买'), findsOneWidget);
      await tester.tap(find.text('App 内暂不提供购买'));
      await tester.pump();

      expect(api.orderCallCount, 0);
      expect(find.text('当前版本暂不提供高级模板权益购买。'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('★★ 下单请求未完成时连点只发一次', (WidgetTester tester) async {
    final orderCompleter = Completer<Map<String, dynamic>>();
    final api = _FakeMerchantApi(
      subs: <Map<String, dynamic>>[],
      caps: <String, dynamic>{'selfCheckoutEnabled': true},
      orderCompleter: orderCompleter,
    );
    await _pumpPage(tester, api);

    final Finder button = find.text('开通高级模板权益');
    await tester.tap(button);
    await tester.tap(button);
    await tester.pump();

    expect(api.orderCallCount, 1, reason: '同一业务意图不能并发建两张单');

    orderCompleter.complete(<String, dynamic>{'orderSn': 'TPLTM_x'});
    await tester.pumpAndSettle();
  });

  testWidgets('★★ 下单失败后重试复用同一业务意图的 requestId', (WidgetTester tester) async {
    final api = _FakeMerchantApi(
      subs: <Map<String, dynamic>>[],
      caps: <String, dynamic>{'selfCheckoutEnabled': true},
      orderFailuresRemaining: 1,
    );
    await _pumpPage(tester, api);

    final Finder button = find.text('开通高级模板权益');
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(api.orderBodies, hasLength(2));
    final Object? firstRequestId = api.orderBodies.first['requestId'];
    expect(
      firstRequestId,
      isA<String>().having(
        (String value) => RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(value),
        'wire format',
        isTrue,
      ),
    );
    expect(api.orderBodies.last['requestId'], firstRequestId);
  });

  group('★ 下单之后的真值来自服务端,不是「已创建订单」', () {
    testWidgets('★★ 建单后回读 `commerce/order/status`,并照它说话', (WidgetTester tester) async {
      final api = _FakeMerchantApi(
        subs: <Map<String, dynamic>>[],
        caps: <String, dynamic>{'selfCheckoutEnabled': true},
        orderStatus: 'pending',
      );
      await _pumpPage(tester, api);

      await tester.tap(find.text('开通高级模板权益'));
      await tester.pumpAndSettle();

      expect(api.statusQueries, <String>['TPLTM_x']);
      expect(find.text('订单已创建,尚未完成支付'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('★★ 终态 success = 权益已到账,并重新拉配额', (WidgetTester tester) async {
      final api = _FakeMerchantApi(
        subs: <Map<String, dynamic>>[],
        caps: <String, dynamic>{'selfCheckoutEnabled': true},
        orderStatus: 'success',
      );
      await _pumpPage(tester, api);
      final int capsBefore = api.capsCalls;
      final int subsBefore = api.subsCalls;

      await tester.tap(find.text('开通高级模板权益'));
      await tester.pumpAndSettle();

      expect(find.text('权益已到账'), findsOneWidget);
      expect(
        api.capsCalls,
        greaterThan(capsBefore),
        reason: '到账之后配额得过期重拉,否则界面还停在旧数字上',
      );
      expect(api.subsCalls, greaterThan(subsBefore));
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('★ 订单已关闭 → 说清要重新选,不冒充成功', (WidgetTester tester) async {
      final api = _FakeMerchantApi(
        subs: <Map<String, dynamic>>[],
        caps: <String, dynamic>{'selfCheckoutEnabled': true},
        orderStatus: 'failed',
      );
      await _pumpPage(tester, api);

      await tester.tap(find.text('开通高级模板权益'));
      await tester.pumpAndSettle();

      expect(find.text('订单已关闭,请重新选择权益'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('★★ 建单回执里就有终态时不再多问一次', (WidgetTester tester) async {
      final api = _FakeMerchantApi(
        subs: <Map<String, dynamic>>[],
        caps: <String, dynamic>{'selfCheckoutEnabled': true},
        orderReply: <String, dynamic>{
          'orderSn': 'TPLTM_x',
          'paymentStatus': 'success',
        },
      );
      await _pumpPage(tester, api);

      await tester.tap(find.text('开通高级模板权益'));
      await tester.pumpAndSettle();

      expect(find.text('权益已到账'), findsOneWidget);
      expect(api.statusQueries, isEmpty);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('★★ 没有订单号就查不了 —— 说不知道,不编「已创建」', (WidgetTester tester) async {
      final api = _FakeMerchantApi(
        subs: <Map<String, dynamic>>[],
        caps: <String, dynamic>{'selfCheckoutEnabled': true},
        orderReply: <String, dynamic>{},
      );
      await _pumpPage(tester, api);

      await tester.tap(find.text('开通高级模板权益'));
      await tester.pumpAndSettle();

      expect(find.textContaining('没有订单号'), findsOneWidget);
      expect(api.statusQueries, isEmpty);
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
