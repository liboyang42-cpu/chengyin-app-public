import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_manage.dart';
import 'package:chengyin_app/feature/club/club_dissolution_blockers_page.dart';
import 'package:chengyin_app/data/models/club_access.dart';
import 'package:chengyin_app/feature/club/club_access_gate.dart';
import 'package:chengyin_app/feature/club/club_group_code_page.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_join_requests_page.dart';
import 'package:chengyin_app/feature/club/club_leaderboard_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: child,
);

void main() {
  testWidgets('English group code missing parameters has a terminal exit', (tester) async {
    await tester.pumpWidget(ProviderScope(child: _app(const ClubGroupCodePage())));
    await tester.pumpAndSettle();
    expect(find.text('Route or session information is missing'), findsOneWidget);
    expect(find.text('Open club management'), findsOneWidget);
    expect(find.text('Please try again'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English membership empty state', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [clubJoinRequestsProvider(1).overrideWith((ref) async => [])],
      child: _app(const ClubJoinRequestsPage(clubId: 1)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Membership requests'), findsOneWidget);
    expect(find.text('No membership requests yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English ranking preserves names and missing timing', (tester) async {
    const rows = [
      ClubRankRow(memberId: 3, nickname: '原始昵称', score: 1.0,
        clearCount: 1, mileage: 0, durationMin: 0, hostedCount: 0,
        pace: null, completionDuration: null),
    ];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        for (final sort in ClubRankSort.values)
          clubLeaderboardProvider((clubId: 1, sort: sort))
              .overrideWith((ref) async => rows),
      ],
      child: _app(const ClubLeaderboardPage(clubId: 1)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('原始昵称'), findsOneWidget);
    expect(find.text('1.0 points'), findsOneWidget);
    await tester.tap(find.text('Pace'));
    await tester.pumpAndSettle();
    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining('0.0 min/km'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English dissolution keeps unknown amounts and fixed currency', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        clubDissolutionBlockersProvider(1).overrideWith((ref) async => DissolutionBlockers(
          deposits: [ClubDeposit(id: 9, depositStatus: 2, amount: 12.30)],
          settlements: [ClubSettlement(id: 10, direction: 'incoming')],
        )),
      ],
      child: _app(const ClubDissolutionBlockersPage(clubId: 1)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('¥12.30'), findsOneWidget);
    expect(find.text('Amount unconfirmed'), findsOneWidget);
    expect(find.text('¥0.00'), findsNothing);
    expect(find.text('Paid and frozen, awaiting refund or deduction'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local permission reason translates; identical server copy stays raw', (tester) async {
    final local = evaluateClubAccess(
      const AsyncData(ClubAccess(active: false, permissions: {}, roleCodes: [])),
      clubId: 1, permission: kClubMemberListRead,
    );
    final server = ClubAccessGateResult(ClubAccessDecision.deny, local.reason);
    await tester.pumpWidget(_app(Builder(builder: (context) => Column(
      children: [
        Text(localizedClubAccessReason(context, local)),
        Text(localizedClubAccessReason(context, server)),
      ],
    ))));
    expect(local.decision, ClubAccessDecision.deny);
    expect(find.text('This account cannot access this club'), findsOneWidget);
    expect(find.text('当前账号无权进入该俱乐部'), findsOneWidget);
  });
}
