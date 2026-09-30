import 'dart:convert';
import 'dart:typed_data';
import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../support/fixed_auth.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:chengyin_app/l10n/app_localizations_en.dart';
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
    this.statusCompleter,
  });
  final List<Map<String, dynamic>> subs;
  final Map<String, dynamic> caps;
  int orderFailuresRemaining;
  final Completer<Map<String, dynamic>>? orderCompleter;
  final Map<String, dynamic> orderReply;
  final String orderStatus;
  final Completer<String>? statusCompleter;
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
    if (statusCompleter != null) return statusCompleter!.future;
    return orderStatus;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpPage(WidgetTester tester, _FakeMerchantApi api) async {
  await tester.binding.setSurfaceSize(const Size(390, 900));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[signedInAuthOverride(role: 'merchant'), merchantApiProvider.overrideWithValue(api)].cast(),
      child: MaterialApp(
        theme: merchantGoldenTheme(),
        home: const MerchantSubscriptionPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {

  for (final waitForStatus in [false, true]) {
    testWidgets('account switch drops late subscription ${waitForStatus ? "status" : "order"}', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final order = Completer<Map<String, dynamic>>();
      final status = Completer<String>();
      final api = _FakeMerchantApi(subs: [], caps: {'selfCheckoutEnabled': true},
        orderCompleter: waitForStatus ? null : order,
        statusCompleter: waitForStatus ? status : null);
      final container = ProviderContainer(overrides: [
        authControllerProvider.overrideWith(_SwitchingAuth.new),
        merchantApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container,
        child: const MaterialApp(home: MerchantSubscriptionPage())));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('开通高级模板权益'));
      await tester.tap(find.text('开通高级模板权益'));
      await tester.pump();
      expect(api.orderCallCount, 1);
      expect(api.statusQueries.length, waitForStatus ? 1 : 0);
      (container.read(authControllerProvider.notifier) as _SwitchingAuth).switchTo(2);
      await tester.pumpAndSettle();
      final countsAfterSwitch = (api.subsCalls, api.capsCalls);
      if (waitForStatus) { status.complete('success'); }
      else { order.complete({'paymentStatus': 'success', 'orderSn': 'A-order'}); }
      await tester.pumpAndSettle();
      expect((api.subsCalls, api.capsCalls), countsAfterSwitch);
      expect(api.statusQueries.length, waitForStatus ? 1 : 0);
      expect(find.text('权益已到账'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('switch during order token read prevents dispatch with B credential', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _OrderTokenStore();
    final client = DioClient(store);
    final adapter = _OrderAdapter();
    client.dio.httpClientAdapter = adapter;
    addTearDown(() => client.dio.close());
    final container = ProviderContainer(retry: (_, _) => null, overrides: [
      authControllerProvider.overrideWith(_SwitchingAuth.new),
      dioClientProvider.overrideWithValue(client),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: const MaterialApp(home: MerchantSubscriptionPage())));
    await tester.pumpAndSettle();
    store.pauseNext = true;
    await tester.ensureVisible(find.text('开通高级模板权益'));
    await tester.tap(find.text('开通高级模板权益'));
    await tester.pump();
    await store.started.future;
    store.token = 'B-token';
    (container.read(authControllerProvider.notifier) as _SwitchingAuth).switchTo(2);
    await tester.pump();
    store.release.complete('B-token');
    await tester.pumpAndSettle();
    expect(adapter.paths.where((path) => path == '/api/merchant/commerce/order'), isEmpty);
    expect(adapter.paths.where((path) => path == '/api/merchant/commerce/order/status'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late subscription status after disposal does not refresh or notify', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final status = Completer<String>();
    final api = _FakeMerchantApi(subs: [], caps: {'selfCheckoutEnabled': true}, statusCompleter: status);
    await _pumpPage(tester, api);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.ensureVisible(find.text('开通高级模板权益'));
    await tester.tap(find.text('开通高级模板权益'));
    await tester.pump();
    expect(api.statusQueries, ['TPLTM_x']);
    final before = (api.subsCalls, api.capsCalls);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    status.complete('success');
    await tester.pumpAndSettle();
    expect((api.subsCalls, api.capsCalls), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English access labels preserve iOS purchase restriction and raw expiry', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final api = _FakeMerchantApi(subs: [
      {'subscriptionType': 'premium_template', 'endDate': '2030-07-01 13:45', 'usedCount': 1, 'maxUsage': 3},
    ], caps: {'selfCheckoutEnabled': true});
    await tester.pumpWidget(ProviderScope(
      overrides: [signedInAuthOverride(role: 'merchant'), merchantApiProvider.overrideWithValue(api)],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: merchantGoldenTheme(),
        home: const MerchantSubscriptionPage(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Premium template access'), findsOneWidget);
    expect(find.text('Valid until 2030-07-01 13:45'), findsOneWidget);
    expect(find.text('Used 1 / 3'), findsOneWidget);
    await tester.ensureVisible(find.text('Purchases are unavailable in this app'));
    await tester.tap(find.text('Purchases are unavailable in this app'));
    await tester.pumpAndSettle();
    expect(find.text('This version does not offer premium template purchases.'), findsOneWidget);
    expect(api.orderCallCount, 0);
    expect(tester.takeException(), isNull);
  });
  test('English access type keeps unknown server value unchanged', () {
    final strings = AppLocalizationsEn();
    expect(subscriptionTypeLabel('premium_template', strings: strings), 'Premium template access');
    expect(subscriptionTypeLabel('自定义类型', strings: strings), '自定义类型');
  });

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
        overrides: <dynamic>[signedInAuthOverride(role: 'merchant'), merchantApiProvider.overrideWithValue(api)].cast(),
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
        overrides: <dynamic>[signedInAuthOverride(role: 'merchant'), merchantApiProvider.overrideWithValue(api)].cast(),
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
        overrides: <dynamic>[signedInAuthOverride(role: 'merchant'), merchantApiProvider.overrideWithValue(api)].cast(),
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

class _SwitchingAuth extends AuthController {
  @override
  AuthState build() => _state(1);
  static AuthState _state(int id) => AuthState(initialized: true,
    user: User(id: id, nickname: 'Merchant', avatar: '', role: 'merchant'));
  void switchTo(int id) => state = _state(id);
}

class _OrderTokenStore extends TokenStore {
  _OrderTokenStore() : super(const FlutterSecureStorage());
  bool pauseNext = false;
  String token = 'A-token';
  final started = Completer<void>();
  final release = Completer<String?>();
  @override
  Future<String?> read() {
    if (pauseNext) {
      pauseNext = false;
      started.complete();
      return release.future;
    }
    return Future.value(token);
  }
}

class _OrderAdapter implements HttpClientAdapter {
  final paths = <String>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    paths.add(options.path);
    final Object data = options.path == '/api/merchant/subscription'
        ? <Object>[] : <String, dynamic>{'selfCheckoutEnabled': true};
    return ResponseBody.fromString(jsonEncode({'code': 200, 'data': data}), 200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }
  @override
  void close({bool force = false}) {}
}
