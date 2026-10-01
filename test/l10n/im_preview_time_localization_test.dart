import 'package:chengyin_app/data/models/im.dart';
import 'package:chengyin_app/feature/im/im_list_page.dart';
import 'package:chengyin_app/feature/im/im_time.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('English local placeholders preserve verbatim server previews', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) => Column(children: [
        for (final text in <String?>[null, '[图片]', '晚点到'])
          Text(conversationPreview(context, Conversation(
            conversationId: 9,
            type: kImTypeSingle,
            counterparty: ImCounterparty(id: 2, nickname: '朋友', avatar: ''),
            lastMsgType: kMsgImage,
            lastMsgText: text,
          ))),
        Text(fmtConversationTime('2026-09-29 11:30:00',
            now: DateTime(2026, 9, 30), context: context)),
        Text(fmtMessageTime('2026-09-29 11:30:00',
            now: DateTime(2026, 9, 30), context: context)),
        Text(fmtMessageTime('2026-01-15 11:30:00',
            now: DateTime(2026, 9, 30), context: context)),
      ])),
    ));
    await tester.pumpAndSettle();
    expect(find.text('[Photo]'), findsOneWidget);
    expect(find.text('[图片]'), findsOneWidget,
        reason: 'Server literal must not be mistaken for an app placeholder');
    expect(find.text('晚点到'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Yesterday 11:30'), findsOneWidget);
    expect(find.text('Jan 15 11:30'), findsOneWidget);
  });

  test('invalid dates stay empty and time values are not timezone-converted', () {
    expect(fmtMessageTime('not a timestamp'), '');
    expect(fmtConversationTime(null), '');
    expect(fmtMessageTime('2026-09-30 23:45:00', now: DateTime(2026, 9, 30)), '23:45');
  });
}
