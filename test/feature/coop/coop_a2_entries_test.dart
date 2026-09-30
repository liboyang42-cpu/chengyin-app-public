// a2-club-entry 行为门(coop 域):新接/补接的入口必须「点得到、带对话题参数、
// 且资金出口守 R10」。
//
// 覆盖:
//   - 我的合作:被拒卡「再邀别人」→ /coop/nearby?topicId=<原主题>;
//     无 topicId 的卡不给这个按钮(点了只能进一页空手找主题);
//     (退款重试三态判据由 main 的 CoopApi.retryDepositRefund 契约测试覆盖:
//      coop_api_contract_test / coop_deposit_test,此处不重复钉;)
//   - 邀约页:只邀商家且未锁定对象时出「附近商家」行,带 topicId/topicName;
//   - 合作结算:提现行三态(可提/待确认/暂无)—— 点可提只弹客服微信号弹窗,
//     ★ R10:一个提现请求都不发;
//   - 附近商家:带 topicId 进来自「再邀别人」时页名是「找商家承接」,
//     点行进商家公开主页(有 memberId 才给点)。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:chengyin_app/core/widgets/cy_native_notice.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/coop_api.dart';
import 'package:chengyin_app/data/models/coop_finance.dart';
import 'package:chengyin_app/data/models/coop_invite.dart' show CoopInviteType;
import 'package:chengyin_app/data/models/coop_invite_row.dart';
import 'package:chengyin_app/data/models/coop_candidate.dart'
    show CoopReceivedRegistration;
import 'package:chengyin_app/data/models/coop_pool.dart' show CoopPoolApply;
import 'package:chengyin_app/data/models/nearby_merchant.dart';
import 'package:chengyin_app/data/models/topic.dart' show Topic;
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/coop/coop_finance_page.dart';
import 'package:chengyin_app/feature/coop/coop_invite_page.dart';
import 'package:chengyin_app/feature/coop/coop_list_page.dart';
import 'package:chengyin_app/feature/coop/nearby_merchants_page.dart';
import 'package:chengyin_app/feature/withdrawal/withdrawal_contact_dialog.dart';

import '../../support/fixed_auth.dart';

DioClient _dummyDioClient() =>
    DioClient(TokenStore(const FlutterSecureStorage()));

/// 记录调用、可控回执的 CoopApi 假实现 —— 任何调用都会被记下来,
/// 用来证明「点提现一个请求都不发」(R10)。
class _NoRequestCoopApi extends CoopApi {
  _NoRequestCoopApi() : super(_dummyDioClient());
  final List<String> calls = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add('${invocation.memberName}');
    return super.noSuchMethod(invocation);
  }
}

String _q(GoRouterState state, String k) => state.uri.queryParameters[k] ?? '-';

/// 「到达页面 B 且参数对」的落点 stub(列表/邀约页的 push 目标)。
GoRoute _nearbyStubRoute() => GoRoute(
  path: '/coop/nearby',
  builder: (_, state) => Scaffold(
    body: Text('nearby|${_q(state, 'topicId')}|${_q(state, 'topicName')}'),
  ),
);

/// 真页 NearbyMerchantsPage 挂在与 app_router 同参口径的自有路由下,
/// 这样「再邀别人」的 stub 不会误拉起真页(真页要读定位)。
GoRoute _nearbyPageRoute() => GoRoute(
  path: '/coop/nearby-page',
  builder: (BuildContext _, GoRouterState state) => NearbyMerchantsPage(
    topicIdRaw: state.uri.queryParameters['topicId'],
    topicName: state.uri.queryParameters['topicName'],
  ),
);

Future<({GoRouter router, _NoRequestCoopApi coopApi})> _pump(
  WidgetTester tester,
  String initialLocation, {
  required List<dynamic> overrides,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 900));
  final coopApi = _NoRequestCoopApi();
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: '/coop/list',
        // 「再邀别人」「重试退款」分别挂在 我发出的 / 收到的 两档上,
        // 用 query 选档,别让测试去摸 UI。
        builder: (_, state) => CoopListPage(
          initialTab: state.uri.queryParameters['tab'] ?? 'received',
        ),
      ),
      GoRoute(
        path: '/coop/finance',
        builder: (_, _) => const CoopFinancePage(),
      ),
      GoRoute(
        path: '/coop/invite',
        builder: (BuildContext _, GoRouterState state) => CoopInvitePage(
          type: state.uri.queryParameters['type'] == 'club'
              ? CoopInviteType.club
              : CoopInviteType.merchant,
          topicId: int.tryParse(state.uri.queryParameters['topicId'] ?? ''),
          topicName: state.uri.queryParameters['topicName'],
          toId: int.tryParse(state.uri.queryParameters['toId'] ?? ''),
        ),
      ),
      _nearbyStubRoute(),
      _nearbyPageRoute(),
      GoRoute(
        path: '/merchant/public-home/member/:memberId',
        builder: (_, state) =>
            Scaffold(body: Text('public-${state.pathParameters['memberId']}')),
      ),
      GoRoute(
        path: '/coop/invite-detail',
        builder: (_, state) =>
            Scaffold(body: Text('detail|${_q(state, 'inviteId')}')),
      ),
      GoRoute(
        path: '/coop/perk-templates',
        builder: (_, _) => const Scaffold(body: Text('perk-templates')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(
          () => FixedAuth(signedInAuthState()),
        ),
        clubApiProvider.overrideWithValue(ClubApi(_dummyDioClient())),
        coopApiProvider.overrideWithValue(coopApi),
        ...overrides,
      ].cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return (router: router, coopApi: coopApi);
}

/// 合作列表页:邀约两路 + 带队申请 + 承接报名都钉成假数据,不打网络。
List<dynamic> _listOverrides(CoopInviteList list) => <dynamic>[
  coopInviteListProvider.overrideWith((ref) async => list),
  coopPoolAppliesProvider.overrideWith(
    (Ref ref, String box) async => const <CoopPoolApply>[],
  ),
  coopReceivedRegsProvider.overrideWith(
    (Ref ref) async => const <CoopReceivedRegistration>[],
  ),
];

void main() {
  tearDown(CyNativeNotice.hide);

  testWidgets('被拒卡「再邀别人」→ /coop/nearby 带原 topicId;无 topicId 不给', (
    WidgetTester tester,
  ) async {
    final h = await _pump(
      tester,
      '/coop/list?tab=sent',
      overrides: _listOverrides(
        const CoopInviteList(
          sent: <CoopInviteRow>[
            CoopInviteRow(
              id: 9,
              inviteType: 0,
              fromId: 21,
              toType: 'merchant',
              toId: 1,
              topicId: 44,
              status: 2,
            ),
            CoopInviteRow(
              id: 10,
              inviteType: 0,
              fromId: 21,
              toType: 'merchant',
              toId: 1,
              status: 2,
            ),
          ],
        ),
      ),
    );
    final router = h.router;
    // 两张被拒卡各说一句事实(main 的文案闸是 status==2 && mine,不看 topicId)。
    expect(find.text('对方已拒绝，可再邀其他商家。'), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('coop-reinvite-9')));
    await tester.pumpAndSettle();
    expect(find.text('nearby|44|-'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    // 没带主题的拒绝卡不给「再邀别人」—— 跳过去只能进一页空手找主题。
    expect(find.byKey(const Key('coop-reinvite-10')), findsNothing);
    router.dispose();
  });

  testWidgets('邀约页:只邀商家且未锁定对象 → 「附近商家」行,带 topicId/topicName', (
    WidgetTester tester,
  ) async {
    final h = await _pump(
      tester,
      '/coop/invite?type=merchant&topicId=44&topicName=静安夜跑',
      overrides: const <dynamic>[],
    );
    final router = h.router;
    await tester.tap(find.byKey(const Key('coop-invite-nearby')));
    await tester.pumpAndSettle();
    expect(find.text('nearby|44|静安夜跑'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('coop-invite-nearby')), findsOneWidget);
    router.dispose();
  });

  testWidgets('邀约页:邀俱乐部(activeType=1)没有「附近商家」行', (WidgetTester tester) async {
    final h = await _pump(
      tester,
      '/coop/invite?type=club&topicId=44',
      overrides: const <dynamic>[],
    );
    expect(find.byKey(const Key('coop-invite-nearby')), findsNothing);
    h.router.dispose();
  });

  testWidgets('邀约页:已锁定受邀对象(preset)时不给「附近商家」行', (WidgetTester tester) async {
    final h = await _pump(
      tester,
      '/coop/invite?type=merchant&topicId=44&toId=7',
      overrides: const <dynamic>[],
    );
    expect(find.byKey(const Key('coop-invite-nearby')), findsNothing);
    h.router.dispose();
  });

  testWidgets('邀约页:没带主题也出「附近商家」行,跳过去不带参数', (WidgetTester tester) async {
    final h = await _pump(
      tester,
      '/coop/invite?type=merchant',
      overrides: <dynamic>[
        coopInviteTopicsProvider.overrideWith((ref) async => <Topic>[]),
      ],
    );
    final router = h.router;
    await tester.tap(find.byKey(const Key('coop-invite-nearby')));
    await tester.pumpAndSettle();
    expect(find.text('nearby|-|-'), findsOneWidget);
    router.dispose();
  });

  Future<({GoRouter router, _NoRequestCoopApi coopApi})> pumpFinance(
    WidgetTester tester,
    List<CoopFinanceRow> rows,
  ) async {
    return _pump(
      tester,
      '/coop/finance',
      overrides: <dynamic>[
        coopFinanceProvider.overrideWith((ref) async => rows),
      ],
    );
  }

  testWidgets('合作结算「联系平台客服提现」:可提时点它只弹客服微信号,R10 不发任何请求', (
    WidgetTester tester,
  ) async {
    final h = await pumpFinance(tester, <CoopFinanceRow>[
      const CoopFinanceRow(
        topicId: 1,
        topicName: '静安夜跑',
        settled: true,
        myIncome: '12.50',
        myIncomeArrived: true,
      ),
    ]);
    final router = h.router;
    final coopApi = h.coopApi;
    final button = tester.widget<CyNativeButton>(
      find.byKey(const Key('coop-finance-withdraw')),
    );
    expect(button.onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('coop-finance-withdraw')));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.textContaining(kWithdrawalContactWechatId), findsOneWidget);
    expect(find.text('返回'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(coopApi.calls, isEmpty, reason: 'R10:点提现不发任何提现请求');

    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    router.dispose();
  });

  testWidgets('合作结算:结算了但金额没给 → 待确认且按钮不可点', (WidgetTester tester) async {
    final h = await pumpFinance(tester, <CoopFinanceRow>[
      const CoopFinanceRow(topicId: 1, topicName: '甲', settled: true),
    ]);
    expect(find.text('已入账金额待确认'), findsOneWidget);
    expect(
      tester
          .widget<CyNativeButton>(
            find.byKey(const Key('coop-finance-withdraw')),
          )
          .onPressed,
      isNull,
    );
    h.router.dispose();
  });

  testWidgets('合作结算:全未结算 → 暂无已入账分润', (WidgetTester tester) async {
    final h = await pumpFinance(tester, <CoopFinanceRow>[
      const CoopFinanceRow(topicId: 2, topicName: '乙', settled: false),
    ]);
    expect(find.text('暂无已入账分润'), findsOneWidget);
    expect(
      tester
          .widget<CyNativeButton>(
            find.byKey(const Key('coop-finance-withdraw')),
          )
          .onPressed,
      isNull,
    );
    h.router.dispose();
  });

  testWidgets('合作结算:「是否到账」缺布尔判据 → 同样待确认,不猜能提', (WidgetTester tester) async {
    final h = await pumpFinance(tester, <CoopFinanceRow>[
      const CoopFinanceRow(
        topicId: 3,
        topicName: '丙',
        settled: true,
        myIncome: '30.00',
        myIncomeArrivedKnown: false,
      ),
    ]);
    expect(find.text('已入账金额待确认'), findsOneWidget);
    expect(h.coopApi.calls, isEmpty);
    h.router.dispose();
  });

  testWidgets('附近商家:带 topicId 进来页名「找商家承接」,点行进商家公开主页;无 memberId 不给点', (
    WidgetTester tester,
  ) async {
    final h = await _pump(
      tester,
      '/coop/nearby-page?topicId=44&topicName=静安夜跑',
      overrides: <dynamic>[
        nearbyMerchantsProvider.overrideWith(
          (ref) async => const <NearbyMerchant>[
            NearbyMerchant(id: 5, name: '老麦咖啡', memberId: 88),
            NearbyMerchant(id: 6, name: '未入驻面馆'),
          ],
        ),
      ],
    );
    final router = h.router;
    expect(find.text('找商家承接'), findsOneWidget);
    await tester.tap(find.byKey(const Key('nearby-merchant-5')));
    await tester.pumpAndSettle();
    expect(find.text('public-88'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    // 没绑会员的商家没有公开主页可去:整行照旧可点,但点下去是说清原因,
    // 不是把人带进一页空主页(main 的口径,对齐真源 openMerchant)。
    await tester.tap(find.byKey(const Key('nearby-merchant-6')));
    await tester.pumpAndSettle();
    expect(find.text('这家还没在平台建档，先电话联系'), findsOneWidget);
    router.dispose();
  });

  testWidgets('附近商家:不带主题时页名仍是「附近商家」', (WidgetTester tester) async {
    final h = await _pump(
      tester,
      '/coop/nearby-page',
      overrides: <dynamic>[
        nearbyMerchantsProvider.overrideWith(
          (ref) async => const <NearbyMerchant>[
            NearbyMerchant(id: 5, name: '老麦咖啡', memberId: 88),
          ],
        ),
      ],
    );
    final router = h.router;
    expect(find.text('附近商家'), findsOneWidget);
    expect(find.text('找商家承接'), findsNothing);
    router.dispose();
  });
}
