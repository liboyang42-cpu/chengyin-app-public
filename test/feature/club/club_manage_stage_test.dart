// 俱乐部详情「管理」tab 顶部那张阶段卡(小程序的「现在要做」)的门。
//
// 判据对齐小程序 `pages/club/detail/index.js`(@90e66d70):
//   `loadOwnerProjects()` → `POST /api/project/my` `{ownerType:'club', state:'all',
//   type:'all', pageNum:1, pageSize:200}` → 只留 `bizType !== 'activity'` 且
//   `clubId` 是本次俱乐部的行;`acceptStatus === 'merchantAccepted'` 才把阶段推到
//   `accepted`(「管理项目」)。`pending` 由 `/api/coop/list` 的**发出**邀约
//   (`status === 0` 且 topicId 在本俱乐部项目里)决定。
//   任一路读失败 = error(「重试管理进度」),不许把读不到说成「先发布一个项目」。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/my_project_api.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_manage.dart';
import 'package:chengyin_app/data/models/club_post.dart';
import 'package:chengyin_app/data/models/club_settlement.dart';
import 'package:chengyin_app/data/models/club_stats.dart';
import 'package:chengyin_app/data/models/coop_invite_row.dart';
import 'package:chengyin_app/data/models/my_project.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_detail_page.dart';
import 'package:chengyin_app/feature/club/club_manage_stage.dart';
import 'package:chengyin_app/feature/club/club_posts_section.dart';
import 'package:chengyin_app/feature/coop/coop_list_page.dart'
    show coopInviteListProvider;

const Key _cardKey = Key('club-manage-stage');
const Key _primaryKey = Key('club-manage-primary');

DioClient _dummyDioClient() =>
    DioClient(TokenStore(const FlutterSecureStorage()));

MyProject _project(
  int id, {
  String bizType = 'topic',
  int? clubId,
  String? acceptStatus,
}) => MyProject.fromJson(<String, dynamic>{
  'id': id,
  'bizType': bizType,
  'title': '项目 $id',
  'clubId': clubId,
  'acceptStatus': acceptStatus,
});

CoopInviteRow _invite(int topicId, int status) => CoopInviteRow.fromJson(
  <String, dynamic>{'topicId': topicId, 'status': status},
);

CoopInviteList _invites(int topicId, int status) =>
    CoopInviteList(sent: <CoopInviteRow>[_invite(topicId, status)]);

final ClubTopic _topic77 = ClubTopic(id: 77, name: '静安夜行项目');

AsyncValue<List<ClubTopic>> _topics(List<ClubTopic> rows) =>
    AsyncValue<List<ClubTopic>>.data(rows);

AsyncValue<List<MyProject>> _projects(List<MyProject> rows) =>
    AsyncValue<List<MyProject>>.data(rows);

AsyncValue<CoopInviteList> _inviteRows(CoopInviteList list) =>
    AsyncValue<CoopInviteList>.data(list);

AsyncValue<T> _failed<T>() =>
    AsyncValue<T>.error(Exception('网络连接失败'), StackTrace.empty);

/// 小程序那条查询的报文必须逐字对上 —— 只 override 掉 provider 就测不出来了。
class _FakeMyProjectApi extends MyProjectApi {
  _FakeMyProjectApi() : super(_dummyDioClient());

  final List<({String type, String state, String ownerType, int pageSize})>
  calls = <({String type, String state, String ownerType, int pageSize})>[];
  Object? error;
  List<MyProject> rows = <MyProject>[];

  @override
  Future<MyProjectPage> page({
    String type = 'all',
    String state = 'all',
    String ownerType = 'all',
    String? scope,
    int pageSize = 200,
  }) async {
    calls.add((
      type: type,
      state: state,
      ownerType: ownerType,
      pageSize: pageSize,
    ));
    final Object? failure = error;
    if (failure != null) throw failure;
    return MyProjectPage(rows: rows, total: rows.length);
  }
}

Future<GoRouter> _pump(
  WidgetTester tester, {
  required _FakeMyProjectApi projects,
  List<ClubTopic>? topics,
  CoopInviteList invites = const CoopInviteList(),
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 900));
  final GoRouter router = GoRouter(
    initialLocation: '/club/3',
    routes: <RouteBase>[
      GoRoute(
        path: '/club/:id',
        builder: (_, _) => const ClubDetailPage(clubId: 3),
      ),
      GoRoute(
        path: '/project/home/:topicId',
        builder: (_, GoRouterState state) =>
            Scaffold(body: Text('project-${state.pathParameters['topicId']}')),
      ),
      GoRoute(
        path: '/coop/list',
        builder: (_, GoRouterState state) => Scaffold(
          body: Text('coop-${state.uri.queryParameters['tab'] ?? 'received'}'),
        ),
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
            isOwner: true,
            isJoined: true,
            memberCount: 1,
          ),
        ),
        clubPostsProvider(3).overrideWith((ref) async => <ClubPost>[]),
        clubMembersProvider(3).overrideWith((ref) async => <ClubMember>[]),
        clubTopicsProvider(
          3,
        ).overrideWith((ref) async => topics ?? <ClubTopic>[_topic77]),
        clubLeaderboardProvider((
          clubId: 3,
          sort: ClubRankSort.composite,
        )).overrideWith((ref) async => <ClubRankRow>[]),
        clubCoopMerchantsProvider(
          3,
        ).overrideWith((ref) async => <Map<String, dynamic>>[]),
        clubCustomerCountProvider(3).overrideWith((ref) async => 0),
        clubSettlementSummaryProvider(3).overrideWith(
          (ref) async => const ClubSettlementSummary(
            settledAmountText: '¥0.00',
            settledAmountStatus: 'verified',
            unverifiedSettledCount: 0,
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
        myProjectApiProvider.overrideWithValue(projects),
        coopInviteListProvider.overrideWith((ref) async => invites),
      ].cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('管理'));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  group('阶段机', () {
    test('没有项目 → 先发布项目(与邀约状态无关)', () {
      expect(
        resolveClubManageStage(
          topics: _topics(const <ClubTopic>[]),
          ownerProjects: _failed<List<MyProject>>(),
          invites: _failed<CoopInviteList>(),
        ),
        ClubManageStage.publish,
      );
    });

    test('有项目但没有商家承接 → 邀请商家', () {
      expect(
        resolveClubManageStage(
          topics: _topics(<ClubTopic>[_topic77]),
          ownerProjects: _projects(<MyProject>[_project(77, clubId: 3)]),
          invites: _inviteRows(const CoopInviteList()),
        ),
        ClubManageStage.invite,
      );
    });

    test('发出邀约还没回应 → 查看邀请进度;别的主题的邀约不算', () {
      ClubManageStage stageFor(int topicId) => resolveClubManageStage(
        topics: _topics(<ClubTopic>[_topic77]),
        ownerProjects: _projects(<MyProject>[_project(77, clubId: 3)]),
        invites: _inviteRows(_invites(topicId, 0)),
      );

      expect(stageFor(77), ClubManageStage.pending);
      expect(stageFor(99), ClubManageStage.invite);
    });

    test('商家已承接 → 管理项目(优先于等回应的邀约)', () {
      expect(
        resolveClubManageStage(
          topics: _topics(<ClubTopic>[_topic77]),
          ownerProjects: _projects(<MyProject>[
            _project(77, clubId: 3, acceptStatus: 'merchantAccepted'),
          ]),
          invites: _inviteRows(_invites(77, 0)),
        ),
        ClubManageStage.accepted,
      );
    });

    test('任一路读失败 → error(不说成「先发布一个项目」)', () {
      expect(
        resolveClubManageStage(
          topics: _failed<List<ClubTopic>>(),
          ownerProjects: _projects(const <MyProject>[]),
          invites: _inviteRows(const CoopInviteList()),
        ),
        ClubManageStage.error,
      );
      expect(
        resolveClubManageStage(
          topics: _topics(<ClubTopic>[_topic77]),
          ownerProjects: _failed<List<MyProject>>(),
          invites: _inviteRows(const CoopInviteList()),
        ),
        ClubManageStage.error,
      );
      expect(
        resolveClubManageStage(
          topics: _topics(<ClubTopic>[_topic77]),
          ownerProjects: _projects(const <MyProject>[]),
          invites: _failed<CoopInviteList>(),
        ),
        ClubManageStage.error,
      );
    });

    test('还没读完 → loading,不抢跑成任何终态', () {
      expect(
        resolveClubManageStage(
          topics: const AsyncValue<List<ClubTopic>>.loading(),
          ownerProjects: _projects(const <MyProject>[]),
          invites: _inviteRows(const CoopInviteList()),
        ),
        ClubManageStage.loading,
      );
      expect(
        resolveClubManageStage(
          topics: _topics(<ClubTopic>[_topic77]),
          ownerProjects: const AsyncValue<List<MyProject>>.loading(),
          invites: _inviteRows(const CoopInviteList()),
        ),
        ClubManageStage.loading,
      );
    });
  });

  testWidgets('管理 tab 按小程序同参取 /api/project/my,只认本俱乐部的主题项目', (
    WidgetTester tester,
  ) async {
    final projects = _FakeMyProjectApi()
      ..rows = <MyProject>[
        // 本俱乐部的**活动**、别的俱乐部的主题:都不算「本俱乐部项目」。
        _project(
          501,
          bizType: 'activity',
          clubId: 3,
          acceptStatus: 'merchantAccepted',
        ),
        _project(502, clubId: 8, acceptStatus: 'merchantAccepted'),
        _project(503, clubId: 3),
      ];
    final router = await _pump(tester, projects: projects);

    expect(projects.calls, hasLength(1));
    expect(projects.calls.single.ownerType, 'club');
    expect(projects.calls.single.pageSize, 200);
    expect(projects.calls.single.type, 'all');
    expect(projects.calls.single.state, 'all');
    expect(
      find.descendant(of: find.byKey(_cardKey), matching: find.text('邀请商家')),
      findsWidgets,
      reason: '两行 merchantAccepted 都不是本俱乐部的主题项目,不该判成「商家已接受」',
    );
    router.dispose();
  });

  testWidgets('商家已承接 → 「管理项目」,按钮进该项目主办视图', (WidgetTester tester) async {
    final projects = _FakeMyProjectApi()
      ..rows = <MyProject>[
        _project(77, clubId: 3, acceptStatus: 'merchantAccepted'),
      ];
    final router = await _pump(tester, projects: projects);

    expect(
      find.descendant(of: find.byKey(_cardKey), matching: find.text('管理项目')),
      findsWidgets,
    );
    await tester.tap(find.byKey(_primaryKey));
    await tester.pumpAndSettle();
    expect(find.text('project-77'), findsOneWidget);
    router.dispose();
  });

  testWidgets('邀约等回应 → 「查看邀请进度」,按钮进我发出的合作', (WidgetTester tester) async {
    final projects = _FakeMyProjectApi()
      ..rows = <MyProject>[_project(77, clubId: 3)];
    final router = await _pump(
      tester,
      projects: projects,
      invites: _invites(77, 0),
    );

    expect(
      find.descendant(of: find.byKey(_cardKey), matching: find.text('查看邀请进度')),
      findsWidgets,
    );
    await tester.tap(find.byKey(_primaryKey));
    await tester.pumpAndSettle();
    expect(find.text('coop-sent'), findsOneWidget);
    router.dispose();
  });

  testWidgets('读不到进度 → 「重试管理进度」,点了重新取数', (WidgetTester tester) async {
    final projects = _FakeMyProjectApi()..error = Exception('网络连接失败');
    final router = await _pump(tester, projects: projects);

    expect(
      find.descendant(of: find.byKey(_cardKey), matching: find.text('重试管理进度')),
      findsWidgets,
    );
    expect(projects.calls, hasLength(1));

    projects.error = null;
    projects.rows = <MyProject>[_project(77, clubId: 3)];
    await tester.tap(find.byKey(_primaryKey));
    await tester.pumpAndSettle();
    expect(projects.calls, hasLength(2));
    expect(
      find.descendant(of: find.byKey(_cardKey), matching: find.text('邀请商家')),
      findsWidgets,
    );
    router.dispose();
  });
}
