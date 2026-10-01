import 'package:chengyin_app/data/models/account_local_failure.dart';
import 'package:chengyin_app/l10n/account_local_failure.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('local validation failures translate; identical server copy stays raw', (tester) async {
    const original = '门店授权状态未确认，核销码未打开';
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) => Column(children: [
        Text(accountFailureMessage(context,
            const AccountLocalFailure(AccountLocalFailureKind.merchantConsent, original),
            fallback: 'Fallback')),
        Text(accountFailureMessage(context, Exception(original), fallback: 'Fallback')),
        Text(accountFailureMessage(context,
            const AccountLocalFailure(AccountLocalFailureKind.roamRevocation, '原文'),
            fallback: 'Fallback')),
        Text(accountFailureMessage(context,
            const AccountLocalFailure(AccountLocalFailureKind.playerCode, '原文'),
            fallback: 'Fallback')),
        Text(accountFailureMessage(context, Exception('Server detail 42'), fallback: 'Fallback')),
      ])),
    ));
    expect(find.text('Shop consent is unconfirmed. The code was not opened.'), findsOneWidget);
    expect(find.text(original), findsOneWidget);
    expect(find.text('Roam location consent withdrawal is unconfirmed. Please try again'), findsOneWidget);
    expect(find.text('Your player code is unavailable. Try again later.'), findsOneWidget);
    expect(find.text('Server detail 42'), findsOneWidget);
  });
}
