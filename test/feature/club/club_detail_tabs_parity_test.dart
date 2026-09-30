import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/coop_invite_row.dart';
import 'package:chengyin_app/data/models/my_project.dart';
import 'package:chengyin_app/feature/coop/coop_list_page.dart' show coopInviteListProvider;
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_manage.dart';
import 'package:chengyin_app/data/models/club_post.dart';
import 'package:chengyin_app/data/models/club_settlement.dart';
import 'package:chengyin_app/data/models/club_stats.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_detail_page.dart';
import 'package:chengyin_app/feature/club/club_posts_section.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Club club,
  List<ClubTopic> topics = const <ClubTopic>[],
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1100));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        clubDetailProvider(club.id).overrideWith((ref) async => club),
        clubPostsProvider(club.id).overrideWith((ref) async => <ClubPost>[]),
        clubMembersProvider(
          club.id,
        ).overrideWith((ref) async => <ClubMember>[]),
        clubTopicsProvider(club.id).overrideWith((ref) async => topics),
        clubLeaderboardProvider((
          clubId: club.id,
          sort: ClubRankSort.composite,
        )).overrideWith((ref) async => <ClubRankRow>[]),
        clubCoopMerchantsProvider(
          club.id,
        ).overrideWith((ref) async => <Map<String, dynamic>>[]),
        clubOwnerProjectsProvider(
          club.id,
        ).overrideWith((ref) async => <MyProject>[]),
        // 阶段机还要读一次发出邀约(/api/coop/list);不 override 同样会打真网络。
        coopInviteListProvider.overrideWith((ref) async => const CoopInviteList()),
        // 管理 tab 里那三格(客户数 / 分润 / 看板)会各取一次数;
        // 不 override 就会去打真网络,pumpAndSettle 直接超时。
        clubCustomerCountProvider(club.id).overrideWith((ref) async => 0),
        clubSettlementSummaryProvider(club.id).overrideWith(
          (ref) async => const ClubSettlementSummary(
            settledAmountText: '¥0.00',
            settledAmountStatus: 'verified',
            unverifiedSettledCount: 0,
            pendingAdjustment: null,
            topics: <ClubSettlementTopic>[],
          ),
        ),
        clubStatsProvider(club.id).overrideWith(
          (ref) async => ClubStats(
            clubId: club.id,
            topicCount: 0,
            participants: 0,
            completed: 0,
            overallRate: 0,
            topics: const <ClubTopicStats>[],
          ),
        ),
      ].cast(),
      child: MaterialApp(home: ClubDetailPage(clubId: club.id)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('审批中是独立状态，不能退化成可重复提交的加入按钮', () {
    final club = Club.fromJson(<String, dynamic>{
      'id': 7,
      'name': '夜行社',
      'joinPolicy': 1,
      'myJoinStatus': 0,
    });
    expect(club.myJoinStatus, 0);
    expect(club.joinPending, isTrue);
  });

  testWidgets('访客默认概览，固定帖子/活动/概览三视图', (tester) async {
    await _pump(
      tester,
      club: Club(
        id: 7,
        name: '夜行社',
        description: '每周一起走一条城市路线',
        city: '上海',
        leaderName: '阿岚',
        memberCount: 18,
      ),
    );

    expect(find.text('帖子'), findsOneWidget);
    expect(find.text('活动'), findsOneWidget);
    expect(find.text('概览'), findsOneWidget);
    expect(find.text('管理'), findsNothing);
    expect(find.text('俱乐部简介'), findsOneWidget);
    expect(find.text('每周一起走一条城市路线'), findsOneWidget);
    expect(find.text('加入俱乐部后可查看成员'), findsOneWidget);
  });

  testWidgets('主理人有第四个管理视图，且活动/管理保留真实入口', (tester) async {
    await _pump(
      tester,
      club: Club(
        id: 7,
        name: '夜行社',
        isOwner: true,
        isJoined: true,
        pendingJoinRequestCount: 2,
      ),
      topics: <ClubTopic>[
        ClubTopic(
          id: 91,
          name: '静安夜行',
          signupCount: 6,
          startDate: '2026-09-01 19:00:00',
        ),
      ],
    );

    expect(find.text('管理'), findsOneWidget);
    await tester.tap(find.text('活动'));
    await tester.pumpAndSettle();
    expect(find.text('静安夜行'), findsOneWidget);
    expect(find.textContaining('6 人已报名'), findsOneWidget);

    await tester.tap(find.text('管理'));
    await tester.pumpAndSettle();
    expect(find.text('现在要做'), findsOneWidget);
    expect(find.text('本俱乐部项目'), findsOneWidget);
    expect(find.text('可对接商家'), findsOneWidget);
    expect(find.text('项目工具'), findsOneWidget);
    expect(find.textContaining('入会申请 2'), findsOneWidget);
  });
}
