import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/page_parity_api.dart';
import 'package:chengyin_app/data/api/team_map_api.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/marketing_consent.dart';
import 'package:chengyin_app/feature/orders/merchant_consent_row.dart';
import 'package:chengyin_app/feature/orders/order_detail_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

RegistrationDetail _detail({
  required int id,
  Map<String, dynamic> ownerPatch = const <String, dynamic>{},
  Map<String, dynamic> patch = const <String, dynamic>{},
}) => RegistrationDetail.fromJson(<String, dynamic>{
  'id': id,
  'ownerType': 2,
  'ownerId': 9,
  'registrationNo': 'CY-99-$id',
  'registrationStatus': 2,
  'paymentStatus': 2,
  'verificationStatus': 0,
  'createTime': '2026-08-22 09:00:00',
  'paymentTime': '2026-08-22 09:05:00',
  'ticketPrice': 49.9,
  'payableAmount': 49.9,
  'cmsActivity': <String, dynamic>{
    'name': '城市夜游',
    'startDate': '2099-01-01 10:00:00',
    ...ownerPatch,
  },
  ...patch,
});

class _FakeConsentApi implements PageParityApi {
  _FakeConsentApi({this.rows = const <MarketingConsent>[], this.setError});

  final List<MarketingConsent> rows;
  final Object? setError;
  final List<String> requestIds = <String>[];

  @override
  Future<List<MarketingConsent>> marketingConsents() async => rows;

  @override
  Future<List<MarketingConsent>> setMarketingConsent({
    required int merchantRowId,
    required int merchantOwnerMemberId,
    required String channel,
    required bool optedIn,
    required String requestId,
  }) async {
    requestIds.add(requestId);
    if (setError != null) throw setError!;
    return rows;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeTeamApi implements TeamMapApi {
  _FakeTeamApi({this.teamId = 77, this.error});

  final int teamId;
  final Object? error;
  final List<Map<String, Object?>> calls = <Map<String, Object?>>[];

  @override
  Future<int> createActivityTeam({
    required int ownerId,
    required int maxMembers,
    bool inviteOnly = false,
  }) async {
    calls.add(<String, Object?>{
      'ownerId': ownerId,
      'maxMembers': maxMembers,
      'inviteOnly': inviteOnly,
    });
    if (error != null) throw error!;
    return teamId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Widget _app({
  required RegistrationDetail detail,
  PageParityApi? consentApi,
  TeamMapApi? teamApi,
}) {
  final int id = detail.id;
  final router = GoRouter(
    initialLocation: '/order/$id',
    routes: <RouteBase>[
      GoRoute(
        path: '/order/:id',
        builder: (_, _) => OrderDetailSheet(orderId: id),
      ),
      GoRoute(
        path: '/team/:teamId',
        builder: (_, GoRouterState state) =>
            Scaffold(body: Text('team-${state.pathParameters['teamId']}')),
      ),
      GoRoute(
        path: '/tickets',
        builder: (_, _) => const Scaffold(body: Text('tickets-page')),
      ),
      GoRoute(
        path: '/complaint',
        builder: (_, _) => const Scaffold(body: Text('complaint-page')),
      ),
    ],
  );
  return ProviderScope(
    overrides: <dynamic>[
      orderDetailProvider(id).overrideWith((_) async => detail),
      orderCompletionProvider(id).overrideWith((_) async => null),
      pageParityApiProvider.overrideWithValue(consentApi ?? _FakeConsentApi()),
      activityTeamApiProvider.overrideWithValue(teamApi ?? _FakeTeamApi()),
    ].cast(),
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 300);
  expect(finder, findsOneWidget);
}

void main() {
  testWidgets('teamMemberOptions 档位:2 起步,上限 clamp(2,min(4,max))', (
    WidgetTester tester,
  ) async {
    expect(teamMemberOptions(null), <int>[2, 3, 4]);
    expect(teamMemberOptions(1), <int>[2]);
    expect(teamMemberOptions(2), <int>[2]);
    expect(teamMemberOptions(3), <int>[2, 3]);
    expect(teamMemberOptions(9), <int>[2, 3, 4]);
  });

  testWidgets('订单进度时间线卡:已付未核销出现 创建/支付/核销 三行', (WidgetTester tester) async {
    await tester.pumpWidget(_app(detail: _detail(id: 81)));
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.text('订单进度'));
    expect(find.text('订单已创建'), findsOneWidget);
    expect(find.text('支付已完成'), findsOneWidget);
    expect(find.text('2026-08-22 09:00'), findsOneWidget);
    expect(find.text('等待到店核销'), findsOneWidget);
  });

  testWidgets('复制订单号:写入剪贴板并提示「已复制订单号」', (WidgetTester tester) async {
    final List<MethodCall> platformCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall call,
        ) async {
          platformCalls.add(call);
          return null;
        });

    await tester.pumpWidget(_app(detail: _detail(id: 82)));
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.byKey(const Key('order-detail-copy-no')));
    await tester.tap(find.byKey(const Key('order-detail-copy-no')));
    await tester.pumpAndSettle();

    final MethodCall copied = platformCalls.firstWhere(
      (MethodCall c) => c.method == 'Clipboard.setData',
    );
    expect(copied.arguments['text'], 'CY-99-82');
    expect(find.text('已复制订单号'), findsOneWidget);
  });

  testWidgets('组队卡:仅邀请开关 + N人队伍档位 + 建队成功进队伍页', (WidgetTester tester) async {
    final teamApi = _FakeTeamApi(teamId: 77);
    await tester.pumpWidget(
      _app(
        detail: _detail(
          id: 83,
          ownerPatch: <String, dynamic>{
            'memberId': 5,
            'teamMode': 2,
            'teamMaxMembers': 3,
          },
        ),
        teamApi: teamApi,
      ),
    );
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.text('和队友一起出发'));
    expect(find.textContaining('按主理人设置的人数上限建队'), findsOneWidget);
    await tester.tap(find.byKey(const Key('order-detail-team-invite-only')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('order-detail-team-create')));
    await tester.pumpAndSettle();

    expect(find.text('队伍人数'), findsOneWidget);
    expect(find.text('2 人队伍'), findsOneWidget);
    expect(find.text('3 人队伍'), findsOneWidget);
    expect(find.text('4 人队伍'), findsNothing);

    await tester.tap(find.byKey(const Key('order-detail-team-size-3')));
    await tester.pumpAndSettle();

    expect(teamApi.calls.single, <String, Object?>{
      'ownerId': 9,
      'maxMembers': 3,
      'inviteOnly': true,
    });
    expect(find.text('team-77'), findsOneWidget);
  });

  testWidgets('建队失败:后端 msg 原样提示,不离开订单页', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(
        detail: _detail(id: 84, ownerPatch: <String, dynamic>{'teamMode': 2}),
        teamApi: _FakeTeamApi(error: const TeamMapApiException('活动已开始，队伍锁定')),
      ),
    );
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.byKey(const Key('order-detail-team-create')));
    await tester.tap(find.byKey(const Key('order-detail-team-create')));
    await tester.pumpAndSettle();
    // maxMembers 缺省 → 档位给满 2/3/4。
    await tester.tap(find.byKey(const Key('order-detail-team-size-2')));
    await tester.pumpAndSettle();

    expect(find.text('活动已开始，队伍锁定'), findsOneWidget);
    expect(find.text('team-77'), findsNothing);
  });

  testWidgets('商家消息 consent 行:勾选保存成功进入已同意态', (WidgetTester tester) async {
    final consentApi = _FakeConsentApi(
      rows: <MarketingConsent>[
        const MarketingConsent(
          merchantRowId: 7,
          merchantOwnerMemberId: 5,
          merchantName: '测试商家',
          inAppOptedIn: false,
          couponOptedIn: false,
        ),
      ],
    );
    await tester.pumpWidget(
      _app(
        detail: _detail(id: 85, ownerPatch: <String, dynamic>{'memberId': 5}),
        consentApi: consentApi,
      ),
    );
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.text('商家消息'));
    expect(find.textContaining('接收「测试商家」的活动消息'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(CyMerchantConsentRow),
        matching: find.byType(CupertinoCheckbox),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已同意，可在设置里随时退订'), findsOneWidget);
    expect(consentApi.requestIds.single, startsWith('consent-order-'));
  });

  testWidgets('consent 保存失败:显示原因 + 重试复用同一 requestId', (
    WidgetTester tester,
  ) async {
    final consentApi = _FakeConsentApi(
      rows: <MarketingConsent>[
        const MarketingConsent(
          merchantRowId: 7,
          merchantOwnerMemberId: 5,
          merchantName: '测试商家',
          inAppOptedIn: false,
          couponOptedIn: false,
        ),
      ],
      setError: const PageParityApiException('营销同意状态未确认，请重试'),
    );
    await tester.pumpWidget(
      _app(
        detail: _detail(id: 86, ownerPatch: <String, dynamic>{'memberId': 5}),
        consentApi: consentApi,
      ),
    );
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.text('商家消息'));
    await tester.tap(
      find.descendant(
        of: find.byType(CyMerchantConsentRow),
        matching: find.byType(CupertinoCheckbox),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('营销同意状态未确认，请重试'), findsOneWidget);
    await tester.tap(find.byKey(const Key('order-merchant-consent-retry')));
    await tester.pumpAndSettle();

    expect(consentApi.requestIds, hasLength(2));
    expect(consentApi.requestIds.first, consentApi.requestIds.last);
  });

  testWidgets('ownerType=1(路线单)不出现组队卡', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(
        detail: RegistrationDetail.fromJson(<String, dynamic>{
          'id': 87,
          'ownerType': 1,
          'ownerId': 7,
          'registrationStatus': 2,
          'paymentStatus': 2,
          'cmsTopic': <String, dynamic>{
            'name': '城市路线',
            'teamMode': 2,
            'memberId': 5,
          },
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('和队友一起出发'), findsNothing);
    // 时间线对所有订单都在。
    await _scrollTo(tester, find.text('订单进度'));
  });
}
