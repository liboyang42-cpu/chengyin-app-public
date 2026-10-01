import 'package:chengyin_app/feature/club/club_director_controller.dart';
import 'package:chengyin_app/feature/club/club_director_messages.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('English local message does not translate identical raw server copy', (tester) async {
    const local = ClubDirectorState(activityId: 41,
      writeState: ClubDirectorWriteState.unknownWrite,
      writeMessage: '结果仍待核对，写操作继续锁定',
      localWriteMessage: ClubDirectorLocalMessage.stillPending);
    final raw = local.copyWith(writeMessage: local.writeMessage);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) => Column(children: [
        Text(clubDirectorWriteMessage(context, local)),
        Text(clubDirectorWriteMessage(context, raw)),
      ])),
    ));
    expect(find.text('The result still needs verification. Write actions remain locked'), findsOneWidget);
    expect(find.text('结果仍待核对，写操作继续锁定'), findsOneWidget);
    expect(local.writeLocked, isTrue);
    expect(raw.writeLocked, isTrue);
  });
}
