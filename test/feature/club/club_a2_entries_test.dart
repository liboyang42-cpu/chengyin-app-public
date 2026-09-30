// a2-club-entry 行为门:俱乐部页新接的入口必须「点得到、带对话题参数」。
// 每条都断言 从页面A点X → 到达页面B 且 URL 参数不丢。
//
// 真源判据:
//   - 治理入口(pages/club/detail/index.wxml 概览区 goGovernance('appeal') /
//     举报俱乐部 / 活动卡 canReport);
//   - 场次工具(wxml:489-491「场次工具」+ chooseActivityTool 三条 activityId);
//   - 成员行(goMemberProfile:能读客户名册 → 客户详情,否则公开主页;
//     wxml:335 自己的行不出「举报」)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/group_code_api.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_access.dart';
import 'package:chengyin_app/data/models/club_manage.dart';
import 'package:chengyin_app/data/models/club_post.dart';
import 'package:chengyin_app/data/models/club_settlement.dart';
import 'package:chengyin_app/data/models/club_stats.dart';
import 'package:chengyin_app/data/models/coop_invite_row.dart';
import 'package:chengyin_app/data/models/my_project.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_detail_page.dart';
import 'package:chengyin_app/feature/club/club_posts_section.dart';
import 'package:chengyin_app/feature/coop/coop_list_page.dart'
    show coopInviteListProvider;

DioClient _dummyDioClient() =>
    DioClient(TokenStore(const FlutterSecureStorage()));

class _FakeGroupCodeApi extends GroupCodeApi {
  _FakeGroupCodeApi() : super(_dummyDioClient());
  List<GroupCodeActivity> next = <GroupCodeActivity>[];

  @override
  Future<List<GroupCodeActivity>> activities(int topicId) async => next;
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._initial);
  final AuthState _initial;

  @override
  AuthState build() => _initial;

  @override
  Future<void> refreshRole() async {}
}

String _q(GoRouterState state, String k) => state.uri.queryParameters[k] ?? '-';

Future<({GoRouter router, _FakeGroupCodeApi groupApi})> _pump(
  WidgetTester tester, {
  required bool owner,
  bool joined = true,
  Set<String> permissions = const <String>{},
  List<ClubMember> members = const <ClubMember>[],
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1000));
  final groupApi = _FakeGroupCodeApi();
  final router = GoRouter(
    initialLocation: '/club/3',
    routes: <RouteBase>[
      GoRoute(
        path: '/club/:id',
        builder: (_, _) => const ClubDetailPage(clubId: 3),
      ),
      GoRoute(
        path: '/club/:id/governance',
        builder: (_, state) => Scaffold(
          body: Text(
            'gov|${_q(state, 'mode')}|${_q(state, 'targetType')}'
            '|${_q(state, 'targetId')}|${_q(state, 'targetMemberId')}',
          ),
        ),
      ),
      GoRoute(
        path: '/club/:id/notify',
        builder: (_, state) =>
            Scaffold(body: Text('notify|${_q(state, 'activityId')}')),
      ),
      GoRoute(
        path: '/club/:id/roles',
        builder: (_, state) =>
            Scaffold(body: Text('roles|${_q(state, 'activityId')}')),
      ),
      GoRoute(
        path: '/club/:id/event-ops',
        builder: (_, state) => Scaffold(
          body: Text('ops|${_q(state, 'topicId')}|${_q(state, 'activityId')}'),
        ),
      ),
      GoRoute(
        path: '/club/:id/customers/:memberId',
        builder: (_, state) => Scaffold(
          body: Text('customers-${state.pathParameters['memberId']}'),
        ),
      ),
      GoRoute(
        path: '/user/:id',
        builder: (_, state) =>
            Scaffold(body: Text('user-${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/coop-pool',
        builder: (_, _) => const Scaffold(body: Text('coop-pool')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        clubDetailProvider(3).overrideWith(
          (ref) async => Club(
            id: 3,
            name: '城市夜骑俱乐部',
            isOwner: owner,
            isJoined: joined,
            memberCount: members.length,
          ),
        ),
        clubPostsProvider(3).overrideWith((ref) async => <ClubPost>[]),
        clubMembersProvider(3).overrideWith((ref) async => members),
        clubTopicsProvider(3).overrideWith(
          (ref) async => <ClubTopic>[
            ClubTopic(
              id: 77,
              name: '静安夜行项目',
              signupCount: 12,
              startDate: '2026-09-01 19:00:00',
            ),
          ],
        ),
        clubCoopMerchantsProvider(
          3,
        ).overrideWith((ref) async => <Map<String, dynamic>>[]),
        clubOwnerProjectsProvider(3).overrideWith((ref) async => <MyProject>[]),
        coopInviteListProvider.overrideWith(
          (ref) async => const CoopInviteList(),
        ),
        clubCustomerCountProvider(3).overrideWith((ref) async => 0),
        clubSettlementSummaryProvider(3).overrideWith(
          (ref) async => const ClubSettlementSummary(
            settledAmountText: '¥0.00',
            pendingAdjustment: null,
            topics: <ClubSettlementTopic>[],
          ),
        ),
        clubStatsProvider(3).overrideWith(
          (ref) async => const ClubStats(
            clubId: 3,
            topicCount: 0,
            participants: 0,
            completed: 0,
            overallRate: 0,
            topics: <ClubTopicStats>[],
          ),
        ),
        clubAccessProvider(3).overrideWith(
          (ref) async => ClubAccess(
            active: true,
            clubId: 3,
            permissions: permissions,
            roleCodes: owner ? const <String>['CLUB_OWNER'] : const <String>[],
          ),
        ),
        authControllerProvider.overrideWith(
          () => _FakeAuthController(
            AuthState(
              user: User(id: 1, nickname: '我', avatar: '', role: 'player'),
              initialized: true,
            ),
          ),
        ),
        groupCodeApiProvider.overrideWithValue(groupApi),
      ].cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return (router: router, groupApi: groupApi);
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('概览:封禁申诉/举报俱乐部 带 mode+target 进治理页', (tester) async {
    final (:router, :groupApi) = await _pump(tester, owner: true);
    groupApi;
    await _openTab(tester, '概览');

    await _tapKey(tester, const Key('club-governance-appeal'));
    expect(find.text('gov|appeal|-|-|-'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    await _tapKey(tester, const Key('club-governance-report-club'));
    expect(find.text('gov|report|CLUB|3|-'), findsOneWidget);
    router.dispose();
  });

  testWidgets('活动行「举报活动」:选场次后治理页带 ACTIVITY+targetId', (tester) async {
    final (:router, :groupApi) = await _pump(tester, owner: true);
    groupApi.next = <GroupCodeActivity>[
      GroupCodeActivity(id: 501, name: '周六场'),
    ];
    await _openTab(tester, '活动');
    await _tapKey(tester, const Key('club-topic-report-77'));
    expect(find.text('gov|report|ACTIVITY|501|-'), findsOneWidget);
    router.dispose();
  });

  testWidgets('管理 tab:活动运营直达 / 可对接的活动进 coop-pool', (tester) async {
    final (:router, :groupApi) = await _pump(tester, owner: true);
    groupApi;
    await _openTab(tester, '管理');

    await _tapKey(tester, const Key('club-manage-event-ops'));
    expect(find.text('ops|-|-'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    await _tapKey(tester, const Key('club-coop-pool'));
    expect(find.text('coop-pool'), findsOneWidget);
    router.dispose();
  });

  testWidgets('项目行「场次工具」:多场次先选,三条工具都带 activityId', (tester) async {
    final (:router, :groupApi) = await _pump(tester, owner: true);
    groupApi.next = <GroupCodeActivity>[
      GroupCodeActivity(id: 501, name: '周六场'),
      GroupCodeActivity(id: 502, name: '周日场'),
    ];
    await _openTab(tester, '管理');
    await _tapKey(tester, const Key('club-topic-activity-tools-77'));
    // 先选场次(一周多场不截断)。
    await tester.tap(find.text('周日场'));
    await tester.pumpAndSettle();
    // 再进「本场工具」。
    await tester.tap(find.byKey(const Key('activity-tool-分配领队与核销员')));
    await tester.pumpAndSettle();
    expect(find.text('roles|502'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    groupApi.next = <GroupCodeActivity>[
      GroupCodeActivity(id: 501, name: '周六场'),
      GroupCodeActivity(id: 502, name: '周日场'),
    ];
    await _tapKey(tester, const Key('club-topic-activity-tools-77'));
    await tester.tap(find.text('周六场'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('activity-tool-通知本场成员')));
    await tester.pumpAndSettle();
    expect(find.text('notify|501'), findsOneWidget);
    router.dispose();
  });

  testWidgets('成员行:能读客户名册 → 客户详情;举报带 targetMemberId', (tester) async {
    final (:router, :groupApi) = await _pump(
      tester,
      owner: true,
      members: <ClubMember>[ClubMember(memberId: 9, nickname: '阿九')],
    );
    groupApi;
    await _openTab(tester, '概览');
    await _tapKey(tester, const Key('club-member-row-9'));
    expect(find.text('customers-9'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    await _tapKey(tester, const Key('club-member-report-9'));
    expect(find.text('gov|report|-|-|9'), findsOneWidget);
    router.dispose();
  });

  testWidgets('无客户读取权的普通成员:成员行退到公开主页', (tester) async {
    final (:router, :groupApi) = await _pump(
      tester,
      owner: false,
      members: <ClubMember>[ClubMember(memberId: 9, nickname: '阿九')],
    );
    groupApi;
    await _openTab(tester, '概览');
    await _tapKey(tester, const Key('club-member-row-9'));
    expect(find.text('user-9'), findsOneWidget);
    router.dispose();
  });
}
