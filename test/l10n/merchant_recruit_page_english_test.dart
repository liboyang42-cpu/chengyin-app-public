import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/merchant_recruit.dart';
import 'package:chengyin_app/feature/merchant/merchant_recruit_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_recruit_state.dart';
import 'package:chengyin_app/feature/merchant/merchant_recruit_strings.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);
void main() {
  testWidgets('English recruitment preserves category guidance supplied by server', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      merchantRecruitProvider.overrideWith((ref, id) async => const RecruitState(
        mode: RecruitMode.categoryMissing, topicName: '原始路线', blockedMessage: '原始品类修复指引')),
      merchantUpcomingRunsProvider.overrideWith((ref, id) async => []),
    ], child: _host(const MerchantRecruitPage(topicId: 3))));
    await tester.pumpAndSettle();
    expect(find.text('Complete your store category first'), findsOneWidget);
    expect(find.text('原始品类修复指引'), findsOneWidget);
    expect(find.byKey(const Key('recruit-station-entry')), findsNothing);
  });
  testWidgets('unknown node review keeps QR controls unavailable and raw rejection reason', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(overrides: [
      merchantRecruitProvider.overrideWith((ref, id) async => const RecruitState(
        mode: RecruitMode.chapterRecruit, topicName: '原始路线', nodes: [
          MyChapterNode(id: 1, name: '未命名点位'),
          MyChapterNode(id: 2, name: '被驳点位', nodeAuditStatus: 2, nodeAuditReason: '原始驳回理由'),
        ])),
      merchantUpcomingRunsProvider.overrideWith((ref, id) async => []),
    ], child: _host(const MerchantRecruitPage(topicId: 3))));
    await tester.pumpAndSettle();
    expect(find.text('Review status unknown'), findsOneWidget);
    expect(find.text('未命名点位'), findsOneWidget);
    expect(find.text('Rejection reason: 原始驳回理由'), findsOneWidget);
    expect(find.byKey(const Key('recruit-node-live-code-1')), findsNothing);
    expect(find.byKey(const Key('recruit-node-poster-code-2')), findsNothing);
    expect(find.byKey(const Key('recruit-node-npc-1')), findsOneWidget);
  });
  testWidgets('chapter preserves financial threshold and raw category alongside English limits', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      merchantRecruitProvider.overrideWith((ref, id) async => const RecruitState(
        mode: RecruitMode.chapterRecruit, topicName: '原始路线', chapters: [
          RecruitChapter(id: 1, name: '原始章节', category: '原始品类', termsMode: 'PERK',
            perkMinValue: 12.5, remainingMerchantCount: 0),
        ])),
      merchantUpcomingRunsProvider.overrideWith((ref, id) async => []),
    ], child: _host(const MerchantRecruitPage(topicId: 3))));
    await tester.pumpAndSettle();
    expect(find.text('原始品类 · Chapter type not specified · 权益承接'), findsOneWidget);
    expect(find.text('权益零售价不少于 ¥12.50'), findsOneWidget);
    expect(find.text('No openings left'), findsOneWidget);
  });
  testWidgets('presentation keeps time substrings and distinguishes missing names from server names', (tester) async {
    await tester.pumpWidget(_host(Builder(builder: (context) => Scaffold(body: Column(children: [
      Text(merchantRecruitChapterName(context, RecruitChapter.fromJson({'id': 1}))),
      Text(merchantRecruitChapterName(context, RecruitChapter.fromJson({'id': 2, 'name': '未命名章节'}))),
      Text(merchantRecruitNodeName(context, MyChapterNode.fromJson({'id': 3}))),
      Text(merchantRecruitNodeName(context, MyChapterNode.fromJson({'id': 4, 'name': '未命名点位'}))),
      Text(merchantRecruitStart(context, const UpcomingRun(startTime: '2026-10-02 23:59:12'))),
      Text(merchantRecruitMeta(context, const UpcomingRun(teamStatus: 'FORMED'))),
      Text(merchantRecruitArrival(context, const UpcomingRun(arrivalStart: '2026-10-02 23:50:00', arrivalEnd: '2026-10-03 00:20:00'))),
      Text(merchantRecruitSource(context, const UpcomingRun(clubName: '自由报名场'))),
    ])))));
    expect(find.text('Unnamed chapter'), findsOneWidget);
    expect(find.text('未命名章节'), findsOneWidget);
    expect(find.text('Unnamed stop'), findsOneWidget);
    expect(find.text('未命名点位'), findsOneWidget);
    expect(find.text('2026-10-02 23:59'), findsOneWidget);
    expect(find.text('Player count unknown · Group formed'), findsOneWidget);
    expect(find.text('Estimated arrival 23:50-00:20'), findsOneWidget);
    expect(find.text('自由报名场'), findsOneWidget);
  });
}
