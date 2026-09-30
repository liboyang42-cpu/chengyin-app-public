import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/group_code_api.dart';
import 'package:chengyin_app/data/models/coop_invite_row.dart';
import 'package:chengyin_app/data/models/my_project.dart';
import 'package:chengyin_app/feature/coop/coop_list_page.dart'
    show coopInviteListProvider;
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_access.dart';
import 'package:chengyin_app/data/models/club_manage.dart';
import 'package:chengyin_app/data/models/club_post.dart';
import 'package:chengyin_app/data/models/club_settlement.dart';
import 'package:chengyin_app/data/models/club_stats.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_detail_page.dart';
import 'package:chengyin_app/feature/club/club_posts_section.dart';

/// 场次清单(/api/topic/info-to-user)的桩:场次工具与举报活动都读它。
class _FakeGroupCodeApi extends GroupCodeApi {
  _FakeGroupCodeApi()
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  List<GroupCodeActivity> activitiesValue = const <GroupCodeActivity>[];
  Object? error;
  List<int> requestedTopicIds = <int>[];

  @override
  Future<List<GroupCodeActivity>> activities(int topicId) async {
    requestedTopicIds.add(topicId);
    if (error != null) throw error!;
    return activitiesValue;
  }
}

/// 登录者固定成「我 = memberId [myId]」:成员行的举报自我抑制读它。
class _FixedAuth extends AuthController {
  _FixedAuth(this.myId);
  final int myId;

  @override
  AuthState build() => AuthState(
    user: User(id: myId, nickname: '我', avatar: '', role: 'player'),
    initialized: true,
  );
}

Future<GoRouter> _pump(
  WidgetTester tester, {
  required bool owner,
  bool? joined,
  Set<String> permissions = const <String>{},
  List<ClubMember> members = const <ClubMember>[],
  int myId = 1,
  GroupCodeApi? sessionApi,
  List<EditionOption> editions = const <EditionOption>[],
  bool eventScope = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 900));
  final router = GoRouter(
    initialLocation: '/club/3',
    routes: <RouteBase>[
      GoRoute(
        path: '/club/:id',
        builder: (_, _) => const ClubDetailPage(clubId: 3),
      ),
      GoRoute(
        path: '/project/home/:topicId',
        builder: (_, state) =>
            Scaffold(body: Text('project-${state.pathParameters['topicId']}')),
      ),
      GoRoute(
        path: '/publish/pro',
        builder: (_, state) => Scaffold(
          body: Text(
            'publish-${state.uri.queryParameters['clubId']}-${state.uri.queryParameters['mode']}',
          ),
        ),
      ),
      GoRoute(
        path: '/coop/list',
        builder: (_, state) => Scaffold(
          body: Text('coop-${state.uri.queryParameters['tab'] ?? 'received'}'),
        ),
      ),
      // 运营三页:入口在管理 tab,页面本身由各自的分支实现。
      // governance 桩把 query 原样回显,钉「入口带了哪几个参数」。
      GoRoute(
        path: '/club/:id/roles',
        builder: (_, state) => Scaffold(
          body: Text(
            'roles-3|${state.uri.queryParameters['activityId'] ?? ''}',
          ),
        ),
      ),
      GoRoute(
        path: '/club/:id/event-ops',
        builder: (_, state) {
          final q = state.uri.queryParameters;
          return Scaffold(
            body: Text(
              'event-ops-3|${q['activityId'] ?? ''}|${q['topicId'] ?? ''}',
            ),
          );
        },
      ),
      GoRoute(
        path: '/coop-pool',
        builder: (_, _) => const Scaffold(body: Text('coop-pool')),
      ),
      GoRoute(
        path: '/club/:id/governance',
        builder: (_, state) {
          final q = state.uri.queryParameters;
          return Scaffold(
            body: Text(
              'governance-3|${q['mode'] ?? ''}|'
              '${q['memberId'] ?? q['targetMemberId'] ?? ''}|'
              '${q['targetType'] ?? ''}|${q['targetId'] ?? ''}',
            ),
          );
        },
      ),
      GoRoute(
        path: '/club/:id/notify',
        builder: (_, state) => Scaffold(
          body: Text(
            'notify-3|${state.uri.queryParameters['activityId'] ?? ''}',
          ),
        ),
      ),
      GoRoute(
        path: '/club/:id/customers/:memberId',
        builder: (_, state) => Scaffold(
          body: Text('customer-${state.pathParameters['memberId']}'),
        ),
      ),
      GoRoute(
        path: '/user/:memberId',
        builder: (_, state) =>
            Scaffold(body: Text('user-${state.pathParameters['memberId']}')),
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
            isJoined: joined ?? owner,
            memberCount: 1,
          ),
        ),
        clubPostsProvider(3).overrideWith((ref) async => <ClubPost>[]),
        clubMembersProvider(3).overrideWith((ref) async => members),
        authControllerProvider.overrideWith(() => _FixedAuth(myId)),
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
        // 管理 tab 的「探店日期次」折叠区读它;不 override 同样会打真网络。
        clubEditionsProvider(3).overrideWith((ref) async => editions),
        // 阶段机还要读一次发出邀约(/api/coop/list);不 override 同样会打真网络。
        coopInviteListProvider.overrideWith(
          (ref) async => const CoopInviteList(),
        ),
        // 管理 tab 里那三格(客户数 / 分润 / 看板)会各取一次数;
        // 不 override 就会去打真网络,pumpAndSettle 直接超时。
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
        // 管理 tab 里那三行(角色与权限 / 成员治理 / 通知成员)读它判可见性;
        // 不 override 同样会打真网络。
        if (sessionApi != null)
          groupCodeApiProvider.overrideWithValue(sessionApi),
        clubAccessProvider(3).overrideWith(
          (ref) async => ClubAccess(
            active: true,
            clubId: 3,
            permissions: permissions,
            roleCodes: owner ? const <String>['CLUB_OWNER'] : const <String>[],
            eventAccesses: eventScope
                ? const <ClubEventAccess>[
                    ClubEventAccess(
                      activityId: 501,
                      topicId: 77,
                      roleCodes: <String>['EVENT_LEAD'],
                      permissions: <String>{'club:read'},
                    ),
                  ]
                : const <ClubEventAccess>[],
          ),
        ),
      ].cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _showOwnerProjects(WidgetTester tester) async {
  await tester.tap(find.text('管理'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('本俱乐部项目'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
}

/// 把目标滚到视口中段再点:固定像素的拖拽会随上方内容增删而失效
/// (2026-09-17:项目行加了「运营」入口后,原来 -420 的拖拽就把目标顶到了
/// 视口外,点了个空)。
Future<void> _tapInList(WidgetTester tester, String label) =>
    _tapIn(tester, find.text(label));

Future<void> _tapIn(WidgetTester tester, Finder target) async {
  final Finder scrollable = find.byType(Scrollable).first;
  final ScrollPosition position = tester
      .state<ScrollableState>(scrollable)
      .position;

  for (int step = 0; step < 40; step += 1) {
    if (target.evaluate().isNotEmpty) {
      final Rect viewport = tester.getRect(scrollable);
      final Rect rect = tester.getRect(target);
      final double delta = rect.center.dy - viewport.center.dy;
      if (delta.abs() < 1) break;
      position.jumpTo(
        (position.pixels + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      await tester.pumpAndSettle();
      continue;
    }
    final double before = position.pixels;
    position.jumpTo(
      (position.pixels + 300).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    await tester.pumpAndSettle();
    if (position.pixels == before) break;
  }
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('主理人才能看见项目与合作入口', (WidgetTester tester) async {
    final ownerRouter = await _pump(tester, owner: true);
    await _showOwnerProjects(tester);
    expect(find.text('本俱乐部项目'), findsOneWidget);
    expect(find.text('我的合作'), findsOneWidget);
    expect(find.text('我发出的合作'), findsOneWidget);
    ownerRouter.dispose();

    final memberRouter = await _pump(tester, owner: false);
    expect(find.text('本俱乐部项目'), findsNothing);
    expect(find.text('我的合作'), findsNothing);
    memberRouter.dispose();
  });

  testWidgets('主理人点项目 → 进该主题主办视图', (WidgetTester tester) async {
    final router = await _pump(tester, owner: true);
    await _showOwnerProjects(tester);
    // 管理 tab 现在多了「成员与活动概况」在上面,项目行会落在折叠线以下;
    // 不先滚到它,tap 的命中点在屏幕外,等于没点(只打一条 warning)。
    await tester.ensureVisible(find.text('静安夜行项目'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('静安夜行项目'));
    await tester.pumpAndSettle();
    expect(find.text('project-77'), findsOneWidget);
    router.dispose();
  });

  testWidgets('发布主题选模式 → 带 clubId+mode 进编辑器', (WidgetTester tester) async {
    final router = await _pump(tester, owner: true);
    await _showOwnerProjects(tester);
    await tester.ensureVisible(find.byKey(const Key('club-create-topic')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('club-create-topic')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自由探索 · 全点开放'));
    await tester.pumpAndSettle();
    expect(find.text('publish-3-2'), findsOneWidget);
    router.dispose();
  });

  testWidgets('我发出的合作 → 合作列表 sent 分页', (WidgetTester tester) async {
    final router = await _pump(tester, owner: true);
    await _showOwnerProjects(tester);
    await _tapInList(tester, '我发出的合作');
    expect(find.text('coop-sent'), findsOneWidget);
    router.dispose();
  });

  testWidgets('主理人管理 tab 点得到角色与权限 / 成员治理 / 通知成员', (WidgetTester tester) async {
    final router = await _pump(tester, owner: true);
    await tester.tap(find.text('管理'));
    await tester.pumpAndSettle();

    await _tapInList(tester, '角色与权限');
    expect(find.text('roles-3|'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    await _tapInList(tester, '成员治理');
    expect(find.textContaining('governance-3|'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    await _tapInList(tester, '通知成员');
    expect(find.text('notify-3|'), findsOneWidget);
    router.dispose();
  });

  testWidgets('普通成员不摆这三行(看不见但点得到,反过来也不行)', (WidgetTester tester) async {
    final router = await _pump(tester, owner: false);

    expect(find.text('管理'), findsNothing);
    expect(find.byKey(const Key('club-manage-roles')), findsNothing);
    expect(find.byKey(const Key('club-manage-governance')), findsNothing);
    expect(find.byKey(const Key('club-manage-notify')), findsNothing);
    router.dispose();
  });

  // 受委派的非主理人：拿到任一管理权限即出「管理」tab，但只看得见自己有权限的那几行，
  // 主理人专属动作(发布主题/设置与解散/分润)仍挡住 —— 对齐小程序 canUseManageTab。
  testWidgets('受委派持有 role:manage 的非主理人可进管理 tab,只看得到角色与权限', (
    WidgetTester tester,
  ) async {
    final router = await _pump(
      tester,
      owner: false,
      permissions: const <String>{'club:role:manage'},
    );

    // tab 出现了,点进去。
    expect(find.text('管理'), findsOneWidget);
    await tester.tap(find.text('管理'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('club-manage-roles')), findsOneWidget);
    // 主理人专属:阶段卡(现在要做)/发布主题/设置与解散/分润 都不给。
    expect(find.text('现在要做'), findsNothing);
    expect(find.text('发布主题'), findsNothing);
    expect(find.text('设置与解散'), findsNothing);
    expect(find.text('俱乐部分润'), findsNothing);
    router.dispose();
  });

  testWidgets('只有场次授权(领队/核销员)也能进管理 tab', (WidgetTester tester) async {
    final router = await _pump(tester, owner: false, eventScope: true);
    expect(find.text('管理'), findsOneWidget);
    await tester.tap(find.text('管理'));
    await tester.pumpAndSettle();
    // toolsPanel 命中 hasEventScope → 项目工具/AI 策划入口给出;主理人专属仍挡。
    expect(find.text('AI 策划'), findsOneWidget);
    expect(find.text('俱乐部分润'), findsNothing);
    router.dispose();
  });

  group('detail:治理与安全 + 成员行接线', () {
    // 游客/成员各占一个 testWidgets:同一 tester 里连着两次 _pump 且第一棵
    // 树还 push 过页面时,第二棵树会留着第一棵的 Navigator 栈与 provider 状态
    // (2026-09-19 实测:成员树上读到的是游客那份 isJoined=false 的 Club)。
    testWidgets('治理与安全:封禁申诉不设闸', (WidgetTester tester) async {
      // 未加入的游客:只剩申诉这一条路,不给举报入口。
      final guest = await _pump(tester, owner: false);
      final ScrollPosition pos = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      pos.jumpTo(pos.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('治理与安全'), findsOneWidget);
      expect(
        find.byKey(const Key('club-governance-report-club')),
        findsNothing,
        reason: 'canSeeMembers 没过的游客看不见成员,也不给举报入口',
      );
      pos.jumpTo(0);
      await tester.pumpAndSettle();
      await _tapInList(tester, '封禁申诉');
      expect(find.text('governance-3|appeal|||'), findsOneWidget);
      guest.dispose();
    });

    testWidgets('治理与安全:举报俱乐部要能看见成员', (WidgetTester tester) async {
      final member = await _pump(tester, owner: false, joined: true);
      await tester.tap(find.text('概览'));
      await tester.pumpAndSettle();
      await _tapInList(tester, '举报俱乐部');
      expect(find.text('governance-3|report||CLUB|3'), findsOneWidget);
      member.dispose();
    });

    testWidgets('受委派成员:行整块进客户档案;自我行不给自己举报;临时封禁带 memberId', (
      WidgetTester tester,
    ) async {
      final router = await _pump(
        tester,
        owner: false,
        joined: true,
        permissions: const <String>{'club:member:manage'},
        myId: 42,
        members: <ClubMember>[
          ClubMember(memberId: 9, nickname: '主理人', isOwner: true),
          ClubMember(memberId: 42, nickname: '我'),
          ClubMember(memberId: 77, nickname: '组员甲', role: 1),
        ],
      );
      await tester.tap(find.text('概览'));
      await tester.pumpAndSettle();

      // 行整块可点(小程序头像+info 同一 handler):有成员读权限 → 客户档案。
      await tester.scrollUntilVisible(
        find.byKey(const Key('club-member-row-77')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('club-member-row-77')));
      await tester.pumpAndSettle();
      expect(find.text('customer-77'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();

      // 举报:自己的行没有,别人都有(js:2089 myMemberId 比对)。
      expect(find.byKey(const Key('club-member-report-42')), findsNothing);
      expect(find.byKey(const Key('club-member-report-77')), findsOneWidget);
      expect(find.byKey(const Key('club-member-report-9')), findsOneWidget);
      await tester.tap(find.byKey(const Key('club-member-report-77')));
      await tester.pumpAndSettle();
      expect(find.text('governance-3|report|77||'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();

      // 临时封禁:持 club:member:manage 可见;创建者本人那行不给(js:2080)。
      expect(find.byKey(const Key('member-governance-77')), findsOneWidget);
      expect(find.byKey(const Key('member-governance-9')), findsNothing);
      // 受委派的非创建者不越权设角色/移除 —— 那是创建者专属。
      expect(find.byKey(const Key('member-role-77')), findsNothing);
      await tester.tap(find.byKey(const Key('member-governance-77')));
      await tester.pumpAndSettle();
      expect(find.text('governance-3||77||'), findsOneWidget);
      router.dispose();
    });

    testWidgets('无读成员权限的成员:行点击退到公开主页,不给封禁入口', (WidgetTester tester) async {
      final router = await _pump(
        tester,
        owner: false,
        joined: true,
        myId: 42,
        members: <ClubMember>[ClubMember(memberId: 77, nickname: '组员甲')],
      );
      await tester.tap(find.text('概览'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('club-member-row-77')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('club-member-row-77')));
      await tester.pumpAndSettle();
      expect(find.text('user-77'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('member-governance-77')), findsNothing);
      // 举报不靠管理权限 —— 能看见成员就能向平台反映别人。
      expect(find.byKey(const Key('club-member-report-77')), findsOneWidget);
      router.dispose();
    });
  });

  group('detail:场次工具与活动运营直达', () {
    testWidgets('管理 tab 有「活动运营」直达', (WidgetTester tester) async {
      final router = await _pump(tester, owner: true);
      await tester.tap(find.text('管理'));
      await tester.pumpAndSettle();
      await _tapInList(tester, '活动运营');
      expect(find.text('event-ops-3||'), findsOneWidget);
      router.dispose();
    });

    testWidgets('场次工具:单场直进工具行,三个工具各按各的闸(主理人三件齐)', (WidgetTester tester) async {
      final sessions = _FakeGroupCodeApi()
        ..activitiesValue = <GroupCodeActivity>[
          GroupCodeActivity(id: 501, name: '周六场'),
        ];
      final router = await _pump(tester, owner: true, sessionApi: sessions);
      await _showOwnerProjects(tester);
      final toolsKey = find.byKey(const Key('club-topic-activity-tools-77'));

      // 只有一场:不再问「选哪场」,直接到「本场工具」。
      await _tapIn(tester, toolsKey);
      expect(sessions.requestedTopicIds, <int>[77]);
      expect(find.text('选择场次'), findsNothing);
      expect(find.text('本场工具'), findsOneWidget);

      await tester.tap(find.text('现场名册与核销'));
      await tester.pumpAndSettle();
      expect(find.text('event-ops-3|501|'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();

      await _tapIn(tester, toolsKey);
      await tester.tap(find.text('分配领队与核销员'));
      await tester.pumpAndSettle();
      expect(find.text('roles-3|501'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();

      await _tapIn(tester, toolsKey);
      await tester.tap(find.text('通知本场成员'));
      await tester.pumpAndSettle();
      expect(find.text('notify-3|501'), findsOneWidget);
      router.dispose();
    });

    testWidgets('多场先选场,选中的场次带进工具链', (WidgetTester tester) async {
      final sessions = _FakeGroupCodeApi()
        ..activitiesValue = <GroupCodeActivity>[
          GroupCodeActivity(id: 501, name: '周六场'),
          GroupCodeActivity(id: 502, name: '周日场'),
        ];
      final router = await _pump(tester, owner: true, sessionApi: sessions);
      await _showOwnerProjects(tester);
      await _tapIn(
        tester,
        find.byKey(const Key('club-topic-activity-tools-77')),
      );
      expect(find.text('选择场次'), findsOneWidget);
      expect(find.text('一周多场时在这里选，不会被系统菜单截断'), findsOneWidget);
      await tester.tap(find.byKey(const Key('topic-activity-pick-502')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('现场名册与核销'));
      await tester.pumpAndSettle();
      expect(find.text('event-ops-3|502|'), findsOneWidget);
      router.dispose();
    });

    // E-15f(真源 js:851-857):加载失败 ≠ 没有场次 —— 两句话必须是两句。
    // 单独一个 testWidgets:同一 tester 里第二棵树会留着第一棵的栈与缓存态。
    testWidgets('场次读取失败:说「加载失败」,不冒充「没有场次」', (WidgetTester tester) async {
      final broken = _FakeGroupCodeApi()..error = Exception('offline');
      final router = await _pump(tester, owner: true, sessionApi: broken);
      await _showOwnerProjects(tester);
      await _tapIn(
        tester,
        find.byKey(const Key('club-topic-activity-tools-77')),
      );
      expect(find.text('场次加载失败，请稍后重试'), findsOneWidget);
      expect(find.text('这个项目还没有可管理的具体场次'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      router.dispose();
    });

    testWidgets('举报活动:一场直落 ACTIVITY 工单', (WidgetTester tester) async {
      final sessions = _FakeGroupCodeApi()
        ..activitiesValue = <GroupCodeActivity>[
          GroupCodeActivity(id: 501, name: '周六场'),
        ];
      final router = await _pump(tester, owner: true, sessionApi: sessions);
      await tester.tap(find.text('活动'));
      await tester.pumpAndSettle();
      await _tapIn(tester, find.byKey(const Key('club-topic-report-77')));
      expect(find.text('governance-3|report||ACTIVITY|501'), findsOneWidget);
      router.dispose();
    });

    testWidgets('举报活动:canSeeMembers 没过的人卡上没有这个入口', (WidgetTester tester) async {
      final guest = await _pump(tester, owner: false);
      await tester.tap(find.text('活动'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('club-topic-report-77')), findsNothing);
      guest.dispose();
    });

    testWidgets('可对接的活动:管理 tab 有路进 /coop-pool', (WidgetTester tester) async {
      final router = await _pump(tester, owner: true);
      await _showOwnerProjects(tester);
      await _tapInList(tester, '可对接的活动');
      expect(find.text('coop-pool'), findsOneWidget);
      router.dispose();
    });

    // 探店日期次(真源 manage-fold wxml:504-528):票源归因的唯一产出口。
    // 只认冻结条款里执行俱乐部=本团的期次,别团的照列不显。
    testWidgets('带票分享:只列执行俱乐部是本团的期次', (WidgetTester tester) async {
      final router = await _pump(
        tester,
        owner: true,
        editions: <EditionOption>[
          EditionOption(
            id: 900,
            label: '',
            topicName: '城西咖啡一期',
            startDate: '2026-09-25 10:00:00',
            executingClubId: 3,
          ),
          EditionOption(
            id: 901,
            label: '',
            topicName: '别团期次',
            startDate: '2026-09-26 10:00:00',
            executingClubId: 4,
          ),
        ],
      );
      await _showOwnerProjects(tester);
      await tester.scrollUntilVisible(
        find.text('城西咖啡一期'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('城西咖啡一期'), findsOneWidget);
      expect(find.text('别团期次'), findsNothing);
      expect(find.byKey(const Key('club-edition-share-900')), findsOneWidget);
      expect(find.text('2026-09-25 · 执行俱乐部期次'), findsOneWidget);
      router.dispose();
    });
  });
}
