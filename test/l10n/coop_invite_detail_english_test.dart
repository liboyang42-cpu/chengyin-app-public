import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/coop_invite_row.dart';
import 'package:chengyin_app/feature/coop/coop_invite_detail_strings.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:chengyin_app/l10n/strings.dart';

void main() {
  final now = DateTime(2026, 9, 30, 12);
  final row = CoopInviteRow(id: 7, inviteType: 1, fromId: 8, toType: 'club', toId: 9,
    topicId: 12, gameId: 13, status: 0, shareMode: 2, fixedFee: 12.5,
    depositOwed: true, depositAmount: 12.5, partnerName: '原始合作方',
    message: '原始条款留言', handleReason: '原始理由', expireTime: now.add(const Duration(hours: 25)));
  final slots = <String, dynamic>{'byGame': <String, dynamic>{'13': <String, dynamic>{'pending': 2, 'cap': 7}},
    'byTopic': <String, dynamic>{'12': <String, dynamic>{'accepted': 1, 'cap': 9}}};
  for (final language in ['zh', 'en']) {
    testWidgets('Invite terms preserve exact financial values and raw text in $language', (tester) async {
      await tester.pumpWidget(MaterialApp(locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) => Column(children: [
          Text(coopDetailInviteType(context, row)), Text(coopDetailTerms(context, row)!),
          Text(coopDetailDeposit(context, row)), Text(coopDetailSlot(context, row, slots)),
          Text(coopDetailTopic(context, row)), Text(coopDetailCountdown(context, row, now)),
          Text(stringsOf(context).coopDetailSentPeer(row.partnerName!)),
          Text(row.message!), Text(row.handleReason!),
        ])),
      ));
      if (language == 'zh') {
        for (final expected in [row.typeText, row.termsText!, row.depositDueText, row.slotText(slots), row.topicText, row.countdownText(now)]) {
          expect(find.text(expected), findsOneWidget);
        }
      } else {
        expect(find.text('Merchant → Club'), findsOneWidget);
        expect(find.text('Fixed fee · ¥12.5 / redeemed participant'), findsOneWidget);
        expect(find.text('Deposit due after price locking: ¥12.50'), findsOneWidget);
        expect(find.text('Pending for this game: 2/7'), findsOneWidget);
        expect(find.text('Theme #12'), findsOneWidget);
        expect(find.text('Days left for recruitment: 1'), findsOneWidget);
        expect(find.text('To 原始合作方'), findsOneWidget);
      }
      expect(find.text('原始条款留言'), findsOneWidget);
      expect(find.text('原始理由'), findsOneWidget);
      expect(row.toType, 'club');
      expect(row.status, 0);
    });
  }
  testWidgets('Unknown deposits do not become zero and legacy invitations do not collect deposits', (tester) async {
    const missing = CoopInviteRow(id: 1, inviteType: 0, fromId: 2, toType: 'merchant', toId: 3, depositOwed: true);
    const zero = CoopInviteRow(id: 2, inviteType: 0, fromId: 2, toType: 'merchant', toId: 3, depositOwed: true, depositAmount: 0);
    const legacy = CoopInviteRow(id: 3, inviteType: 2, fromId: 2, toType: 'merchant', toId: 3, depositOwed: true, depositAmount: 50);
    await tester.pumpWidget(MaterialApp(locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        expect(coopDetailDeposit(context, legacy), isEmpty);
        expect(coopDetailTerms(context, missing), isNull);
        expect(coopDetailSlot(context, missing, null), isEmpty);
        return Column(children: [Text(coopDetailDeposit(context, missing)), Text(coopDetailDeposit(context, zero)),
          Text(stringsOf(context).coopDetailAcceptTerms), Text(stringsOf(context).coopDetailLockedError)]);
      }),
    ));
    expect(find.text('A deposit is required after price locking'), findsOneWidget);
    expect(find.text('Deposit due after price locking: ¥0'), findsOneWidget);
    expect(find.text('Accepting freezes the terms. Settlement will follow this order.'), findsOneWidget);
    expect(find.text('The theme price is locked. Cooperation cannot be canceled unilaterally. Contact support to discuss it.'), findsOneWidget);
    expect(find.textContaining('¥50'), findsNothing);
  });
}
