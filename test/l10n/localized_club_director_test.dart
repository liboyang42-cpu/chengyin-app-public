import 'package:chengyin_app/feature/club/club_director_controller.dart';
import 'package:chengyin_app/feature/club/club_director_sheets.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('English reconciliation controls wrap at larger text size', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.5)),
        child: child!,
      ),
      home: Scaffold(body: ClubDirectorUnknownBar(
        state: const ClubDirectorState(activityId: 1,
          writeState: ClubDirectorWriteState.unknownWrite,
          writeMessage: 'Please verify the pending result before taking further action.',
          canRetryUnknownWrite: true),
        onReconcile: () {}, onRetry: () {},
      )),
    ));
    expect(find.text('Verify result'), findsOneWidget);
    expect(find.text('Retry original action'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English unknown-write controls preserve the pending message and retry gate', (tester) async {
    var reconciled = 0;
    var retried = 0;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: ClubDirectorUnknownBar(
        state: const ClubDirectorState(
          activityId: 1,
          writeState: ClubDirectorWriteState.unknownWrite,
          writeMessage: '原始待核对说明',
          canRetryUnknownWrite: false,
        ),
        onReconcile: () => reconciled++,
        onRetry: () => retried++,
      )),
    ));
    expect(find.text('Result needs verification'), findsOneWidget);
    expect(find.text('原始待核对说明'), findsOneWidget);
    await tester.tap(find.text('Verify result'));
    await tester.pump();
    expect(reconciled, 1);
    expect(retried, 0);
    expect(find.byKey(const Key('director-unknown-retry')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
