import 'package:chengyin_app/data/models/coop_invite.dart';
import 'package:chengyin_app/data/models/merchant_coop.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/coop/coop_guard.dart';
import 'package:chengyin_app/feature/coop/coop_pool_page.dart';
import 'package:chengyin_app/feature/coop/coop_strings.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixed_auth.dart';

Widget _english(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

void main() {
  testWidgets('English guest gate stays readable and performs no collaboration fetch', (tester) async {
    bool requested = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => FixedAuth(guestAuthState)),
        coopPoolProvider.overrideWith((ref) async {
          requested = true;
          throw StateError('Guest must not fetch collaboration data');
        }),
      ],
      child: _english(const CoopPoolPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to view the collaboration pool'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(requested, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English action labels do not alter protocol values or party names', (tester) async {
    await tester.pumpWidget(_english(Builder(builder: (context) => Column(children: [
      Text(coopActionLabel(context, CoopHandleAction.accept)),
      Text(coopInviteTypeLabel(context, CoopInviteType.club)),
      Text(AppLocalizations.of(context).coopSelectedName('夜行俱乐部')),
      Text(AppLocalizations.of(context).coopSentCount(1)),
      Text(AppLocalizations.of(context).coopSentCount(2)),
    ]))));
    await tester.pumpAndSettle();
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('clubs'), findsOneWidget);
    expect(find.text('Selected: 夜行俱乐部'), findsOneWidget);
    expect(find.text('1 invitation sent. Awaiting confirmation.'), findsOneWidget);
    expect(find.text('2 invitations sent. Awaiting confirmation.'), findsOneWidget);
    expect(CoopHandleAction.accept.wire, 1);
    expect(CoopInviteType.club.toType, 'club');
  });

  testWidgets('status and complaint category display remain separate from wire codes', (tester) async {
    await tester.pumpWidget(_english(Builder(builder: (context) => Column(children: [
      Text(coopInvitationStatus(context, 1)),
      Text(coopInvitationStatus(context, 2)),
      Text(coopApplicationStatus(context, 99)),
      Text(coopAuditStatus(context, 2)),
      Text(coopComplaintCategory(context, 0)),
      Text(coopComplaintCategory(context, 1)),
    ]))));
    await tester.pumpAndSettle();
    expect(find.text('Accepted'), findsOneWidget);
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Unknown status'), findsOneWidget);
    expect(find.text('Not selected'), findsOneWidget);
    expect(find.text('Service and delivery'), findsOneWidget);
    expect(find.text('Fees and refunds'), findsOneWidget);
  });

  testWidgets('English error summary preserves original business error detail', (tester) async {
    await tester.pumpWidget(_english(Builder(builder: (context) => Text(
      coopErrorSub(Exception('仅主题发布者可查看候选池'), context: context),
    ))));
    await tester.pumpAndSettle();
    final Text text = tester.widget<Text>(find.byType(Text).first);
    expect(text.data, contains('仅主题发布者可查看候选池'));
    expect(text.data, contains('Original'));
    expect(text.data, isNot(startsWith('Exception:')));
  });
}
