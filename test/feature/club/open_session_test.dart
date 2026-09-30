// 「开一场」入口 —— 对齐小程序 `pages/club/detail`(@github/master):
//
// ★★★ 四条硬契约(真源 `tests/unit/club-session-open.test.js` 逐条对):
//   ① 入口只对 **club.isOwner** 可见(管理员不行:后端 requireOwner 会拒);
//   ② 点击**只跳运营页** `/pages/club/event-ops/index?clubId=<id>&recurrence=ONCE`,
//      **不发任何建场请求**;
//   ③ 旧弹层 + `/api/club/open-session(-topics)` + `submitClubSession` /
//      `sessionSheetShow` 整条链路退役,不许回流;
//   ④ 非主理人从该入口进不去运营页。
//
// ★ 建场本身由运营页 `/club/:id/event-ops` 承接(单次 = `recurrenceType: ONCE`)。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_detail_page.dart';
import 'package:chengyin_app/feature/club/club_posts_section.dart';

/// 开一场入口**只跳转** —— 任何落在这个假 API 上的调用都说明有人又发了请求
/// (真源 `club-session-open.test.js` 的 `assert.equal(sent, null)`)。
class _NoRequestClub implements ClubApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('开一场入口不该发请求:${invocation.memberName}');
}

Future<GoRouter> _pump(
  WidgetTester tester, {
  required bool isOwner,
  required bool isJoined,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 2400));
  final GoRouter router = GoRouter(
    initialLocation: '/club/3',
    routes: <RouteBase>[
      GoRoute(
        path: '/club/:id',
        builder: (_, _) => const ClubDetailPage(clubId: 3),
      ),
      // 承接方:活动运营页。真跳转必须带 clubId + recurrence=ONCE。
      GoRoute(
        path: '/club/:id/event-ops',
        builder: (_, GoRouterState state) => Scaffold(
          body: Text(
            'event-ops-${state.pathParameters['id']}'
            '-${state.uri.queryParameters['recurrence']}',
          ),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        clubDetailProvider(3).overrideWith(
          (ref) async => Club.fromJson(<String, dynamic>{
            'id': 3,
            'name': '城市夜骑俱乐部',
            'memberCount': 1,
            'isJoined': isJoined,
            'isOwner': isOwner,
          }),
        ),
        clubApiProvider.overrideWithValue(_NoRequestClub()),
        clubMembersProvider(3).overrideWith((ref) async => <ClubMember>[]),
        clubTopicsProvider(3).overrideWith((ref) async => <ClubTopic>[]),
        clubPostsProvider(3).overrideWith((ref) async => <ClubPost>[]),
        clubOwnerProjectsProvider(3).overrideWith((ref) async => <MyProject>[]),
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
        clubAccessProvider(3).overrideWith(
          (ref) async => ClubAccess(
            active: true,
            clubId: 3,
            permissions: const <String>{},
            roleCodes: isOwner
                ? const <String>['CLUB_OWNER']
                : const <String>[],
          ),
        ),
      ].cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _tapOpenSession(WidgetTester tester) async {
  await tester.tap(find.text('管理'));
  await tester.pumpAndSettle();
  final Finder target = find.byKey(const Key('club-open-event-ops'));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('★★★ 开一场入口只给创建者 —— 普通成员没有', (WidgetTester tester) async {
    final GoRouter router = await _pump(tester, isOwner: false, isJoined: true);
    expect(
      find.byKey(const Key('club-open-event-ops')),
      findsNothing,
      reason: '小程序 wxml 的入口判据是 club.isOwner,admin 不获得开一场权限',
    );
    // 群聊判据不同:已加入就有。
    expect(find.byKey(const Key('club-group-chat')), findsOneWidget);
    router.dispose();
  });

  testWidgets('★★★ 非成员连入口和群聊都没有', (WidgetTester tester) async {
    final GoRouter router = await _pump(
      tester,
      isOwner: false,
      isJoined: false,
    );
    expect(find.byKey(const Key('club-open-event-ops')), findsNothing);
    expect(
      find.byKey(const Key('club-group-chat')),
      findsNothing,
      reason: '非成员调群聊恒失败(「加入俱乐部后才能进群聊」)',
    );
    router.dispose();
  });

  testWidgets('★★★ 点开一场 → 直达活动运营并预选单次', (WidgetTester tester) async {
    final GoRouter router = await _pump(tester, isOwner: true, isJoined: true);
    // 创建者:开一场与群聊都在。
    expect(find.byKey(const Key('club-group-chat')), findsOneWidget);
    await _tapOpenSession(tester);

    expect(
      find.text('event-ops-3-ONCE'),
      findsOneWidget,
      reason:
          '真源 onOpenClubSession 只做这一跳:'
          '/pages/club/event-ops/index?clubId=<id>&recurrence=ONCE',
    );
    router.dispose();
  });

  test('★★★ 旧建场链路退役 —— lib 里不许再出现端点与旧弹层符号', () {
    final RegExp forbidden = RegExp(
      r'open-session|open_session|openSession|openableTopics|'
      r'submitClubSession|sessionSheetShow',
    );
    final List<String> hits = <String>[];
    for (final FileSystemEntity entity in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (forbidden.hasMatch(entity.readAsStringSync())) hits.add(entity.path);
    }
    expect(
      hits,
      isEmpty,
      reason:
          '旧弹层与 /api/club/open-session(-topics) 已退役,'
          '建场统一走 /api/club/event-ops/series/create',
    );
  });
}
