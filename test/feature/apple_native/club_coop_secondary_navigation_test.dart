import 'dart:async';

import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_manage.dart';
import 'package:chengyin_app/data/models/coop_candidate.dart';
import 'package:chengyin_app/data/models/coop_finance.dart';
import 'package:chengyin_app/data/models/coop_invite_row.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_dissolution_blockers_page.dart';
import 'package:chengyin_app/feature/club/club_edition_report_page.dart';
import 'package:chengyin_app/feature/club/club_leaderboard_page.dart';
import 'package:chengyin_app/feature/club/club_workbench_page.dart';
import 'package:chengyin_app/feature/coop/coop_candidates_page.dart';
import 'package:chengyin_app/feature/coop/coop_finance_page.dart';
import 'package:chengyin_app/feature/coop/coop_invite_page.dart';
import 'package:chengyin_app/feature/coop/coop_list_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Widget page,
  List<dynamic> overrides = const <dynamic>[],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(home: page),
    ),
  );
  await tester.pump();
}

void _expectNativeRoot() {
  expect(find.byType(CupertinoPageScaffold), findsOneWidget);
  expect(find.byType(CupertinoNavigationBar), findsOneWidget);
  expect(find.byType(Scaffold), findsNothing);
  expect(find.byType(AppBar), findsNothing);
}

void main() {
  testWidgets('俱乐部工作台深链等待态使用 Cupertino 根导航', (WidgetTester tester) async {
    await _pump(
      tester,
      page: const ClubWorkbenchPage(),
      overrides: <dynamic>[
        clubMyProvider.overrideWith(
          (Ref ref) => Completer<List<Club>>().future,
        ),
      ],
    );

    _expectNativeRoot();
  });

  testWidgets('工作台带 clubId 深链:不在 build 期同步跳转,能落到详情', (WidgetTester tester) async {
    final GoRouter router = GoRouter(
      initialLocation: '/club/workbench?id=7',
      routes: <RouteBase>[
        GoRoute(
          path: '/club/workbench',
          builder: (_, GoRouterState state) => ClubWorkbenchPage(
            clubId: int.tryParse(state.uri.queryParameters['id'] ?? ''),
          ),
        ),
        GoRoute(
          path: '/club/:id',
          builder: (_, GoRouterState state) =>
              Text('详情 ${state.pathParameters['id']}'),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(find.text('详情 7'), findsOneWidget);
  });

  testWidgets('俱乐部贡献榜使用 Cupertino 根导航且保留标题', (WidgetTester tester) async {
    await _pump(
      tester,
      page: const ClubLeaderboardPage(clubId: 1),
      overrides: <dynamic>[
        clubLeaderboardProvider((
          clubId: 1,
          sort: ClubRankSort.composite,
        )).overrideWith((Ref ref) => Completer<List<ClubRankRow>>().future),
      ],
    );

    _expectNativeRoot();
    expect(find.text('贡献榜'), findsOneWidget);
  });

  testWidgets('解散阻断页使用 Cupertino 根导航且保留页内标题', (WidgetTester tester) async {
    await _pump(
      tester,
      page: const ClubDissolutionBlockersPage(clubId: 1),
      overrides: <dynamic>[
        clubDissolutionBlockersProvider(
          1,
        ).overrideWith((Ref ref) => Completer<DissolutionBlockers>().future),
      ],
    );

    _expectNativeRoot();
    expect(find.text('解散前待处理'), findsOneWidget);
  });

  testWidgets('期次工时证据页使用 Cupertino 根导航且保留缺参态', (WidgetTester tester) async {
    await _pump(tester, page: const ClubEditionReportPage());

    _expectNativeRoot();
    expect(find.text('探店日工时与证据'), findsOneWidget);
    expect(find.text('缺少俱乐部信息'), findsOneWidget);
  });

  testWidgets('我的合作使用 Cupertino 根导航且保留双分段', (WidgetTester tester) async {
    await _pump(
      tester,
      page: const CoopListPage(),
      overrides: <dynamic>[
        coopInviteListProvider.overrideWith(
          (Ref ref) => Completer<CoopInviteList>().future,
        ),
      ],
    );

    _expectNativeRoot();
    expect(find.text('我的合作'), findsOneWidget);
    expect(find.text('收到的'), findsOneWidget);
    expect(find.text('我发出的'), findsOneWidget);
  });

  testWidgets('承接候选使用 Cupertino 根导航且保留标题', (WidgetTester tester) async {
    await _pump(
      tester,
      page: const CoopCandidatesPage(topicId: 1),
      overrides: <dynamic>[
        coopCandidatesProvider(
          1,
        ).overrideWith((Ref ref) => Completer<CoopCandidates>().future),
      ],
    );

    _expectNativeRoot();
    expect(find.text('承接候选'), findsOneWidget);
  });

  testWidgets('合作结算使用 Cupertino 根导航且保留标题', (WidgetTester tester) async {
    await _pump(
      tester,
      page: const CoopFinancePage(),
      overrides: <dynamic>[
        coopFinanceProvider.overrideWith(
          (Ref ref) => Completer<List<CoopFinanceRow>>().future,
        ),
      ],
    );

    _expectNativeRoot();
    expect(find.text('合作结算'), findsOneWidget);
  });

  testWidgets('发起协作邀请使用 Cupertino 根导航且保留三段表单', (WidgetTester tester) async {
    await _pump(
      tester,
      page: const CoopInvitePage(topicId: 1, topicName: '夜行路线'),
    );

    _expectNativeRoot();
    expect(find.text('发起协作邀请'), findsOneWidget);
    expect(find.text('① 关联主题'), findsOneWidget);
    expect(find.text('② 合作条款'), findsOneWidget);
    expect(find.text('③ 邀请对象'), findsOneWidget);
  });
}
