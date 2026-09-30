// 设置页的「营销消息与优惠券」(真源 `pages/shezhi/components/marketing-consent`)。
//
// ★★ 两个开关的当前值必须来自**服务端回读**,不能乐观翻转那一格:
//   写没写进去、写的是不是这一格,只有回读能证明。
// ★ 写失败要回读真值 —— 半开着的开关比报错更坏。

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/page_parity_api.dart';
import 'package:chengyin_app/data/models/marketing_consent.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/settings/marketing_consent_sheet.dart';

DioException _http(int status) => DioException(
  requestOptions: RequestOptions(path: '/api/crm/marketing-consent'),
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: '/api/crm/marketing-consent'),
    statusCode: status,
  ),
);

class _LoggedOutAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

class _FakePageParityApi implements PageParityApi {
  _FakePageParityApi({
    this.rows = const <MarketingConsent>[],
    this.failLoad = false,
    this.failWrite = false,
    this.loadError,
  });

  final List<MarketingConsent> rows;
  final bool failLoad;
  final bool failWrite;
  final Object? loadError;

  int loadCalls = 0;
  final List<Map<String, dynamic>> writes = <Map<String, dynamic>>[];

  @override
  Future<List<MarketingConsent>> marketingConsents() async {
    loadCalls++;
    if (loadError != null) throw loadError!;
    if (failLoad) throw const PageParityApiException('营销设置加载失败');
    return rows;
  }

  @override
  Future<List<MarketingConsent>> setMarketingConsent({
    required int merchantRowId,
    required int merchantOwnerMemberId,
    required String channel,
    required bool optedIn,
    required String requestId,
  }) async {
    writes.add(<String, dynamic>{
      'merchantRowId': merchantRowId,
      'merchantOwnerMemberId': merchantOwnerMemberId,
      'channel': channel,
      'optedIn': optedIn,
      'requestId': requestId,
    });
    if (failWrite) throw const PageParityApiException('营销同意状态未确认，请重试');
    return rows;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MarketingConsent _row({
  int merchantRowId = 71,
  String merchantName = '夜航书店',
  bool inApp = false,
  bool coupon = false,
}) => MarketingConsent(
  merchantRowId: merchantRowId,
  merchantOwnerMemberId: 9,
  merchantName: merchantName,
  inAppOptedIn: inApp,
  couponOptedIn: coupon,
);

Widget _app(PageParityApi api, {bool loggedIn = true}) => ProviderScope(
  overrides: <dynamic>[
    pageParityApiProvider.overrideWithValue(api),
    if (!loggedIn) authControllerProvider.overrideWith(_LoggedOutAuth.new),
  ].cast(),
  child: MaterialApp(
    home: Builder(
      builder: (BuildContext context) => CupertinoPageScaffold(
        child: Center(
          child: CupertinoButton(
            onPressed: () => showMarketingConsentSheet(context),
            child: const Text('打开营销设置'),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _open(
  WidgetTester tester,
  PageParityApi api, {
  bool loggedIn = true,
}) async {
  await tester.pumpWidget(_app(api, loggedIn: loggedIn));
  await tester.tap(find.text('打开营销设置'));
  await tester.pumpAndSettle();
}

Finder _switchOf(int merchantRowId, String channel) => find.descendant(
  of: find.byKey(Key('marketing-consent-$merchantRowId-$channel')),
  matching: find.byType(CupertinoSwitch),
);

void main() {
  test('★ 幂等标识的形状对齐真源(crm-consent-<动作>-…)', () {
    expect(
      newMarketingConsentRequestId(true),
      matches(RegExp(r'^crm-consent-opt-in-[0-9a-z]+-[0-9a-z]+$')),
    );
    expect(
      newMarketingConsentRequestId(false),
      matches(RegExp(r'^crm-consent-opt-out-[0-9a-z]+-[0-9a-z]+$')),
    );
  });

  testWidgets('按商家渲染两个渠道开关,值来自服务端', (WidgetTester tester) async {
    final api = _FakePageParityApi(
      rows: <MarketingConsent>[
        _row(inApp: true, coupon: false),
        _row(merchantRowId: 72, merchantName: '拐角咖啡', coupon: true),
      ],
    );
    await _open(tester, api);

    expect(api.loadCalls, 1);
    expect(find.text('夜航书店'), findsOneWidget);
    expect(find.text('站内活动消息'), findsNWidgets(2));
    expect(find.text('商家优惠券'), findsNWidgets(2));
    expect(
      tester.widget<CupertinoSwitch>(_switchOf(71, 'IN_APP')).value,
      isTrue,
    );
    expect(
      tester.widget<CupertinoSwitch>(_switchOf(71, 'COUPON')).value,
      isFalse,
    );
    expect(
      tester.widget<CupertinoSwitch>(_switchOf(72, 'COUPON')).value,
      isTrue,
    );
  });

  testWidgets('★★ 打开某渠道 = 写这一格(带幂等 requestId),并贴回回读结果', (
    WidgetTester tester,
  ) async {
    final api = _FakePageParityApi(
      rows: <MarketingConsent>[_row()],
    );
    await _open(tester, api);

    await tester.tap(_switchOf(71, 'IN_APP'));
    await tester.pumpAndSettle();

    final Map<String, dynamic> write = api.writes.single;
    expect(write['merchantRowId'], 71);
    expect(write['merchantOwnerMemberId'], 9);
    expect(write['channel'], 'IN_APP');
    expect(write['optedIn'], isTrue);
    expect(
      write['requestId'],
      isA<String>().having(
        (String v) => RegExp(r'^crm-consent-opt-in-[0-9a-z]+-[0-9a-z]+$').hasMatch(v),
        'wire format',
        isTrue,
      ),
    );
    expect(find.text('已同意'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('★★ 退订写 optedIn=false,并用 opt-out 的 requestId', (WidgetTester tester) async {
    final api = _FakePageParityApi(
      rows: <MarketingConsent>[_row(inApp: true)],
    );
    await _open(tester, api);

    await tester.tap(_switchOf(71, 'IN_APP'));
    await tester.pumpAndSettle();

    expect(api.writes.single['optedIn'], isFalse);
    expect(
      api.writes.single['requestId'],
      startsWith('crm-consent-opt-out-'),
    );
    expect(find.text('已退订'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('★★ 写失败 → 说清没写成 + 回读真值,开关不许半开着', (
    WidgetTester tester,
  ) async {
    final api = _FakePageParityApi(
      rows: <MarketingConsent>[_row()],
      failWrite: true,
    );
    await _open(tester, api);
    expect(api.loadCalls, 1);

    await tester.tap(_switchOf(71, 'IN_APP'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('marketing-consent-action-error')), findsOneWidget);
    expect(find.textContaining('状态未确认'), findsOneWidget);
    expect(api.loadCalls, 2, reason: '写失败必须把服务端真值读回来');
    expect(
      tester.widget<CupertinoSwitch>(_switchOf(71, 'IN_APP')).value,
      isFalse,
    );
  });

  testWidgets('空名单说清什么时候才会有', (WidgetTester tester) async {
    await _open(tester, _FakePageParityApi());
    expect(find.byKey(const Key('marketing-consent-empty')), findsOneWidget);
    expect(find.textContaining('完成一次真实报名'), findsOneWidget);
  });

  testWidgets('★ 读失败给重试,不渲染成「没有商家」', (WidgetTester tester) async {
    await _open(tester, _FakePageParityApi(failLoad: true));
    expect(find.byKey(const Key('marketing-consent-load-error')), findsOneWidget);
    expect(find.byKey(const Key('marketing-consent-empty')), findsNothing);
    expect(find.byKey(const Key('marketing-consent-retry')), findsOneWidget);
  });

  testWidgets('★ 游客撞 401:说「登录后查看」,不吐 DioException 原文', (
    WidgetTester tester,
  ) async {
    await _open(
      tester,
      _FakePageParityApi(loadError: _http(401)),
      loggedIn: false,
    );

    expect(find.text('登录后查看营销设置'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.textContaining('developer.mozilla.org'), findsNothing);
    expect(find.byKey(const Key('marketing-consent-empty')), findsNothing);

    // 「去登录」要真能把登录弹窗叫出来 —— 光有一句话不算出口。
    await tester.tap(find.text('去登录'));
    await tester.pumpAndSettle();
    expect(find.text('登录城瘾'), findsOneWidget);
  });

  testWidgets('★ 断网不算「要登录」:仍是重试,不推去登录页', (WidgetTester tester) async {
    await _open(
      tester,
      _FakePageParityApi(
        loadError: DioException(
          requestOptions: RequestOptions(path: '/api/crm/marketing-consent'),
          type: DioExceptionType.connectionError,
        ),
      ),
    );

    expect(find.byKey(const Key('marketing-consent-retry')), findsOneWidget);
    expect(find.text('登录后查看营销设置'), findsNothing);
  });
}
