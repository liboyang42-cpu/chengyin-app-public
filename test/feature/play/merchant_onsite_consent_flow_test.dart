import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/account_api.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/data/models/consent_record.dart';
import 'package:chengyin_app/feature/play/play_session_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('探店日仅在用户明确同意且写后回读成功后打开核销码', (WidgetTester tester) async {
    final consentApi = _ConsentApi();
    final router = _router();
    addTearDown(router.dispose);
    await _pump(tester, router, consentApi);

    await _skipIntro(tester);
    await tester.ensureVisible(find.text('梧桐小店'));
    await tester.pump();
    await tester.tap(find.text('梧桐小店')); // 现在这一下会打开卡片详情
    await tester.pumpAndSettle();

    final SemanticsHandle semantics = tester.ensureSemantics();
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Semantics &&
            widget.properties.button == true &&
            widget.properties.label == '梧桐小店，开始互动 获得奖励！',
      ),
      findsOneWidget,
    );
    semantics.dispose();
    final Finder ctaTapTarget = find
        .ancestor(of: find.text('开始互动 获得奖励！'), matching: find.byType(CupertinoButton))
        .first;
    expect(tester.getSize(ctaTapTarget).height, greaterThanOrEqualTo(44));

    await tester.tap(find.text('开始互动 获得奖励！')); // 详情页的主 CTA 才触发 _onNodeTap
    await tester.pumpAndSettle();

    expect(consentApi.agreeCalls, 0, reason: '弹窗出现不等于用户已接受');
    expect(find.text('仅授权当前门店'), findsOneWidget);
    expect(find.textContaining('不会授权其他门店，可随时撤回'), findsOneWidget);

    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();

    expect(consentApi.agreeCalls, 1);
    expect(consentApi.lastMerchantId, 71);
    expect(find.text('入场码 91'), findsOneWidget);
  });

  testWidgets('AGREE 写成功但 latest 回读失败时核销码保持关闭', (WidgetTester tester) async {
    final consentApi = _ConsentApi(failAgreementReadback: true);
    final router = _router();
    addTearDown(router.dispose);
    await _pump(tester, router, consentApi);

    await _skipIntro(tester);
    await tester.ensureVisible(find.text('梧桐小店'));
    await tester.pump();
    await tester.tap(find.text('梧桐小店'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始互动 获得奖励！'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();

    expect(consentApi.agreeCalls, 1);
    expect(find.text('入场码 91'), findsNothing);
    expect(find.textContaining('状态未确认'), findsOneWidget);
  });

  testWidgets('已有门店授权提供撤回入口；撤回后留在当前游玩页', (WidgetTester tester) async {
    final consentApi = _ConsentApi(initialEvent: 'AGREE');
    final router = _router();
    addTearDown(router.dispose);
    await _pump(tester, router, consentApi);

    await _skipIntro(tester);
    await tester.ensureVisible(find.text('梧桐小店'));
    await tester.pump();
    await tester.tap(find.text('梧桐小店'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始互动 获得奖励！'));
    await tester.pumpAndSettle();

    expect(find.text('当前门店授权'), findsOneWidget);
    expect(find.text('撤回授权'), findsOneWidget);
    await tester.tap(find.text('撤回授权'));
    await tester.pumpAndSettle();

    expect(consentApi.revokeCalls, 1);
    // 屏① 迁移前:「留在当前游玩页」= 节点列表页标题「游玩打卡」仍在。
    // 屏① 迁移后:撤回不弹走、不报错——停在卡片详情原地,主 CTA 仍在就是同一件事。
    // 详情页还在最上层(没被弹掉)
    expect(find.text('开始互动 获得奖励！'), findsOneWidget);
    // ★ 游玩页仍在栈里 —— 用例名说的「留在当前游玩页」指的是这个。
    //   detail 页 push 在它之上,所以必须 skipOffstage: false 才看得到;
    //   默认的 find.text 会把它当不可见跳过,那样就等于把这条断言悄悄删了。
    expect(find.text('游玩打卡', skipOffstage: false), findsOneWidget);
    expect(find.text('入场码 91'), findsNothing);
    expect(find.textContaining('已撤回当前门店授权'), findsOneWidget);
  });

  for (final Object error in <Object>[
    MissingPluginException('alert unavailable'),
    PlatformException(code: 'presentation_failed'),
  ]) {
    testWidgets('${error.runtimeType} 保留完整 Cupertino 门店授权动作', (
      WidgetTester tester,
    ) async {
      final consentApi = _ConsentApi(initialEvent: 'AGREE');
      final router = _router(
        liquidGlassSupported: true,
        consentNativeDriver: _FailingConsentNativeDriver(error),
      );
      addTearDown(router.dispose);
      await _pump(tester, router, consentApi);

      await _skipIntro(tester);
      await tester.ensureVisible(find.text('梧桐小店'));
      await tester.pump();
      await tester.tap(find.text('梧桐小店'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始互动 获得奖励！'));
      await tester.pumpAndSettle();

      final Finder sheet = find.byType(CupertinoActionSheet);
      expect(sheet, findsOneWidget);
      for (final String label in <String>['当前门店授权', '出示核销码', '撤回授权', '取消']) {
        expect(
          find.descendant(of: sheet, matching: find.text(label)),
          findsOneWidget,
        );
      }
    });
  }

  testWidgets('缺少真实 merchantId 时不读写授权、不打开核销码', (WidgetTester tester) async {
    final consentApi = _ConsentApi();
    final router = _router();
    addTearDown(router.dispose);
    await _pump(tester, router, consentApi, withMerchantId: false);

    await _skipIntro(tester);
    await tester.ensureVisible(find.text('梧桐小店'));
    await tester.pump();
    await tester.tap(find.text('梧桐小店'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始互动 获得奖励！'));
    await tester.pumpAndSettle();

    expect(consentApi.latestCalls, 0);
    expect(consentApi.agreeCalls, 0);
    expect(find.textContaining('门店身份未确认'), findsOneWidget);
    expect(find.text('入场码 91'), findsNothing);
  });

  testWidgets('缺少 registrationId 时不读写授权、不猜票号', (WidgetTester tester) async {
    final consentApi = _ConsentApi();
    final router = _router(registrationId: null);
    addTearDown(router.dispose);
    await _pump(tester, router, consentApi);

    await _skipIntro(tester);
    await tester.ensureVisible(find.text('梧桐小店'));
    await tester.pump();
    await tester.tap(find.text('梧桐小店'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始互动 获得奖励！'));
    await tester.pumpAndSettle();

    expect(consentApi.latestCalls, 0);
    expect(consentApi.agreeCalls, 0);
    expect(find.textContaining('从票夹进入后才能出示核销码'), findsOneWidget);
  });
}

GoRouter _router({
  int? registrationId = 91,
  bool liquidGlassSupported = false,
  PlayMerchantConsentNativeDriver? consentNativeDriver,
}) => GoRouter(
  initialLocation: '/play/77',
  routes: <RouteBase>[
    GoRoute(
      path: '/play/:id',
      builder: (_, _) => PlaySessionPage(
        activityId: 77,
        registrationId: registrationId,
        liquidGlassSupported: liquidGlassSupported,
        consentNativeDriver: consentNativeDriver,
      ),
    ),
    GoRoute(
      path: '/ticket/:id/pass',
      builder: (_, GoRouterState state) =>
          Scaffold(body: Text('入场码 ${state.pathParameters['id']}')),
    ),
  ],
);

class _FailingConsentNativeDriver implements PlayMerchantConsentNativeDriver {
  const _FailingConsentNativeDriver(this.error);

  final Object error;

  @override
  Future<String?> show({
    required BuildContext context,
    required String merchantName,
  }) => Future<String?>.error(error);
}

Future<void> _pump(
  WidgetTester tester,
  GoRouter router,
  _ConsentApi consentApi, {
  bool withMerchantId = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        playApiProvider.overrideWithValue(
          _MerchantPlayApi(withMerchantId: withMerchantId),
        ),
        accountApiProvider.overrideWithValue(consentApi),
      ].cast(),
      child: MaterialApp.router(
        routerConfig: router,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _skipIntro(WidgetTester tester) async {
  if (find.text('跳过').evaluate().isNotEmpty) {
    await tester.tap(find.text('跳过'));
  }
  await tester.pumpAndSettle();
}

class _MerchantPlayApi implements PlayApi {
  _MerchantPlayApi({required this.withMerchantId});
  final bool withMerchantId;

  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async => PlayNodesResult(
    topicId: 23,
    mode: 2,
    playable: true,
    total: 1,
    doneCount: 0,
    nodes: <PlayNode>[
      PlayNode(
        nodeId: 7,
        name: '梧桐小店',
        address: '衡山路 7 号',
        sortId: 1,
        done: false,
        merchantId: withMerchantId ? 71 : null,
        arrived: true,
        selfReported: true,
        // 旧实现走到「不支持」而不是等待定位插件；新实现应由 mode=2 状态优先分流。
        validationMethod: 99,
      ),
    ],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ConsentApi extends AccountApi {
  _ConsentApi({this.initialEvent, this.failAgreementReadback = false})
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  final String? initialEvent;
  final bool failAgreementReadback;
  int latestCalls = 0;
  int agreeCalls = 0;
  int revokeCalls = 0;
  int? lastMerchantId;

  ConsentRecord _record(String eventType, int merchantId) => ConsentRecord(
    docType: AccountApi.merchantOnsiteDocType,
    scene: AccountApi.merchantOnsiteScene,
    scopeType: AccountApi.merchantScopeType,
    scopeId: merchantId,
    eventType: eventType,
  );

  @override
  Future<ConsentRecord?> latestMerchantOnsiteConsent(int merchantId) async {
    latestCalls += 1;
    lastMerchantId = merchantId;
    return initialEvent == null ? null : _record(initialEvent!, merchantId);
  }

  @override
  Future<ConsentRecord> agreeMerchantOnsiteDataSharing({
    required int merchantId,
    required String requestId,
  }) async {
    agreeCalls += 1;
    lastMerchantId = merchantId;
    if (failAgreementReadback) {
      throw Exception('门店授权状态未确认，核销码未打开');
    }
    return _record('AGREE', merchantId);
  }

  @override
  Future<ConsentRecord> revokeMerchantOnsiteDataSharing({
    required int merchantId,
    required String requestId,
  }) async {
    revokeCalls += 1;
    lastMerchantId = merchantId;
    return _record('REVOKE', merchantId);
  }
}
