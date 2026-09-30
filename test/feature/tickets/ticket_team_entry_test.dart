import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/feature/tickets/tickets_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fixed_auth.dart';

/// 票夹里那行「我的队伍 ›」:真源 `subpackageMember/signup/index.wxml:112`。
/// ★ 队伍挂在**具体某张票**上(按 ownerType:ownerId 对齐);没有队伍整行不出。
/// rebase 注(#130→#256/#307 实现):走 walletMyTeamsProvider/WalletTeam 口径,
/// 静默失败在主实现内(indexWalletTeams)。「路线/场次」分页 tab 已由用户
/// 2026-09-09 裁决删除,两种票合并同屏,挂票判据改用几何位置。
void main() {
  final tickets = <MyRegistration>[
    MyRegistration(
      id: 11,
      ownerType: 1,
      ownerId: 101,
      title: '外滩路线',
      registrationStatus: 2,
    ),
    MyRegistration(
      id: 22,
      ownerType: 2,
      ownerId: 202,
      title: '周末场次',
      registrationStatus: 2,
    ),
  ];

  Future<GoRouter> pump(
    WidgetTester tester, {
    required List<Map<String, dynamic>> teams,
  }) async {
    final router = GoRouter(
      initialLocation: '/tickets',
      routes: <RouteBase>[
        GoRoute(path: '/tickets', builder: (_, _) => const TicketsPage()),
        GoRoute(
          path: '/team/:teamId',
          builder: (_, GoRouterState state) =>
              Text('team:${state.pathParameters['teamId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          signedInAuthOverride(),
          myTicketsProvider.overrideWith(
            (ref) async => WalletSnapshot(tickets: tickets),
          ),
          walletMyTeamsProvider.overrideWith(
            (ref) async => indexWalletTeams(teams),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('票上挂着队伍时出「我的队伍 ›」并点了进队伍详情', (WidgetTester tester) async {
    await pump(
      tester,
      teams: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 7,
          'title': '外滩夜行',
          'joinedCount': 3,
          'maxMembers': 4,
          'status': 0,
          'ownerType': 1,
          'ownerId': 101,
        },
      ],
    );

    expect(find.text('我的队伍'), findsOneWidget);
    expect(find.text('外滩夜行'), findsOneWidget);
    expect(find.text('3/4'), findsOneWidget);

    await tester.tap(find.text('我的队伍'));
    await tester.pumpAndSettle();
    expect(find.text('team:7'), findsOneWidget);
  });

  testWidgets('没有队伍 / 队伍已解散(3、4)时整行不出', (WidgetTester tester) async {
    await pump(
      tester,
      teams: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 8,
          'title': '散了的队',
          'status': 3,
          'ownerType': 1,
          'ownerId': 101,
        },
      ],
    );

    expect(find.text('我的队伍'), findsNothing);
    expect(find.text('散了的队'), findsNothing);
  });

  testWidgets('队伍人数缺口不补 0/0;队伍只跟自己对的那张票', (WidgetTester tester) async {
    await pump(
      tester,
      teams: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 9,
          'title': '场次队',
          'status': 0,
          'ownerType': 2,
          'ownerId': 202,
        },
      ],
    );

    // 合并列表:两种票同屏(分页 tab 已裁决删除),队伍行只有一处。
    expect(find.text('外滩路线'), findsOneWidget);
    expect(find.text('周末场次'), findsOneWidget);
    expect(find.text('场次队'), findsOneWidget);
    expect(find.text('0/0'), findsNothing);
    expect(find.text('我的队伍'), findsOneWidget);
    // 挂错票的判据:票序 = 外滩路线 → 周末场次;队伍行挂在**自己那张场次票**
    // 票卡外面往下,几何上必须落在周末场次票卡的下面。
    final double teamY = tester.getTopLeft(find.text('场次队')).dy;
    final double ownTicketY = tester.getBottomLeft(find.text('周末场次')).dy;
    expect(teamY, greaterThan(ownTicketY));
  });

  testWidgets('队伍拉不到时票夹照常可用,只是不出那一行', (WidgetTester tester) async {
    await pump(tester, teams: const <Map<String, dynamic>>[]);

    expect(tester.takeException(), isNull);
    expect(find.text('外滩路线'), findsOneWidget);
    expect(find.text('周末场次'), findsOneWidget);
    expect(find.text('我的队伍'), findsNothing);
  });
}
