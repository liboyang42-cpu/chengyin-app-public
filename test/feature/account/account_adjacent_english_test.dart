// NOT_RUN locally: Flutter SDK unavailable.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/data/models/balance_detail.dart';
import 'package:chengyin_app/data/models/infomation.dart';
import 'package:chengyin_app/feature/account/income_detail_page.dart';
import 'package:chengyin_app/feature/account/infomation_detail_page.dart';
import 'package:chengyin_app/feature/account/participants_page.dart';
import 'package:chengyin_app/feature/account/play_guide_page.dart';
import 'package:chengyin_app/feature/activity/participant_picker.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import '../../support/fixed_auth.dart';

Widget _app(Widget page) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)), child: child!),
  home: page,
);

void main() {
  testWidgets('English participants empty state at large text', (t) async {
    await t.pumpWidget(ProviderScope(overrides: [
      signedInAuthOverride(),
      participantsProvider.overrideWith((ref) async => []),
    ], child: _app(const ParticipantsPage(liquidGlassSupported: false))));
    await t.pumpAndSettle();
    expect(find.text('Participants'), findsOneWidget);
    expect(find.text('No participants yet'), findsOneWidget);
    expect(find.text('Add participant'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('English income keeps exact CNY decimals and server reason', (t) async {
    await t.pumpWidget(ProviderScope(overrides: [
      incomeDetailProvider(IncomeEventFilter.all).overrideWith((ref) async => [
        const BalanceDetail(id: 1, changeType: 2, eventType: 3,
          changeBalance: '128.0010', changeReason: '收益记录', createTime: '2026-01-01'),
      ]),
    ], child: _app(const IncomeDetailPage())));
    await t.pumpAndSettle();
    expect(find.text('−¥128.0010'), findsOneWidget);
    expect(find.text('收益记录'), findsOneWidget);
    expect(find.textContaining('Withdrawal request'), findsOneWidget);
    expect(find.textContaining('Expense'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('English article state preserves server title and body', (t) async {
    await t.pumpWidget(ProviderScope(overrides: [
      infomationDetailProvider(7).overrideWith((ref) async =>
        const Infomation(id: 7, title: '这篇还没有内容', contents: '服务器原文')),
    ], child: _app(const InfomationDetailPage(id: 7))));
    await t.pumpAndSettle();
    expect(find.text('这篇还没有内容'), findsOneWidget);
    expect(find.text('服务器原文'), findsOneWidget);
    expect(find.text('This guide has no content yet'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('English play mode CTA still navigates to the real home tab', (t) async {
    final router = GoRouter(initialLocation: '/play-guide', routes: [
      GoRoute(path: '/play-guide', builder: (_, _) => const PlayGuidePage()),
      GoRoute(path: '/feed', builder: (_, _) => const Scaffold(body: Text('feed destination'))),
    ]);
    addTearDown(router.dispose);
    await t.pumpWidget(ProviderScope(overrides: [
      infomationsProvider.overrideWith((ref) async => []),
    ], child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    )));
    await t.pumpAndSettle();
    await t.tap(find.text('Go to City orienteering'));
    await t.pumpAndSettle();
    expect(find.text('feed destination'), findsOneWidget);
  });
}
