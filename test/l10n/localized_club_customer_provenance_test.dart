import 'package:chengyin_app/data/models/club_crm.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_topic_ops.dart';
import 'package:chengyin_app/data/models/club_manage.dart';
import 'package:chengyin_app/feature/club/club_customer_labels.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('topic member fallback preserves source-name provenance', () {
    final missing = TopicCustomerRow.tryFromJson({'displayName': ''}, 'r1')!;
    final named = TopicCustomerRow.tryFromJson({'displayName': '这位成员'}, 'r2')!;
    expect(missing.nameMissing, isTrue);
    expect(named.nameMissing, isFalse);
    expect(named.displayName, '这位成员');
  });

  testWidgets('CRM local synthesis translates without matching authored fallback text', (tester) async {
    final missing = ClubCustomerItem.fromJson({
      'memberId': 7, 'displayName': '', 'verifiedCount': 0,
      'pendingCount': 2, 'lastTopicName': '未命名活动',
    });
    final authored = ClubCustomerItem.fromJson({
      'memberId': 8, 'displayName': '未留姓名', 'verifiedCount': 3,
      'pendingCount': 0, 'lastVisitDate': '2026-09-20',
    });
    final summary = ClubCustomerSummary.fromJson({
      'memberId': 7, 'arrivedCount': 0, 'pendingCount': 2,
      'refundedCount': 0, 'lastInteractionTime': '2026-09-20',
      'paidAmount': null,
    }, remark: '原始备注');
    final record = ClubCustomerRecord.fromJson({
      'key': 'r7', 'statusCode': 'PENDING', 'title': '',
      'occurredAt': '2026-09-20',
    });
    final edition = EditionOption.fromJson({'topicId': 41, 'startDate': '2026-09-20'});
    final manualEdition = EditionOption(id: 42, label: '期次 #42');
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) => Column(children: [
        Text(clubCustomerItemName(context, missing)),
        Text(clubMemberDisplayName(context, ClubMember(memberId: 99))),
        Text(clubCustomerItemName(context, authored)),
        Text(clubCustomerItemMeta(context, missing)),
        Text(clubCustomerItemMeta(context, authored)),
        Text(clubCustomerInteraction(context, summary)),
        Text(clubCustomerRecordTitle(context, record)),
        Text(clubEditionOptionLabel(context, edition)),
        Text(clubEditionOptionLabel(context, manualEdition)),
      ])),
    ));
    expect(find.text('Name not provided'), findsOneWidget);
    expect(find.text('User 99'), findsOneWidget);
    expect(find.text('未留姓名'), findsOneWidget);
    expect(find.text('2 tickets awaiting redemption · Most recently attended “未命名活动”'), findsOneWidget);
    expect(find.text('3 redemptions · Most recent 09-20'), findsOneWidget);
    expect(find.text('Latest interaction 9/20 · 原始备注'), findsOneWidget);
    expect(find.text('Untitled activity'), findsOneWidget);
    expect(find.text('期次 #42'), findsOneWidget);
    expect(find.textContaining('(2026-09-20)'), findsOneWidget);
    expect(summary.amountVisible, isFalse);
    expect(summary.paidAmountText, '无查看权限');
    expect(record.topicId, isNull);
    expect(edition.id, 41);
  });
}
