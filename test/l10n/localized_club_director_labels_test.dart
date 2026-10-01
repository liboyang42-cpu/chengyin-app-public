import 'package:chengyin_app/data/models/club_director.dart';
import 'package:chengyin_app/feature/club/club_director_labels.dart';
import 'package:chengyin_app/feature/club/club_director_sheets.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ClubDirectorProjection _projection() => ClubDirectorProjection.fromJson({
  'perspective': 'CLUB', 'activityId': 41, 'status': 'RUNNING', 'revision': 3,
  'availableActions': ['BROADCAST'],
  'club': {
    'teams': [
      {'teamId': 1, 'name': '未命名队伍', 'memberCount': 2},
      {'teamId': 2, 'memberCount': 3, 'status': 'BLOCKED'},
    ],
    'stations': [
      {'nodeId': 7, 'status': 'PAUSED', 'pauseReason': '原始暂停原因',
        'resumeEta': '2026-09-30 18:00', 'fallbackPlanCode': 'PLAN-A'},
    ],
    'broadcasts': [
      {'content': '广播内容待同步', 'targetName': '原始范围', 'receiptStatus': 'CONFIRMED'},
    ],
  },
});

void main() {
  testWidgets('English generated labels preserve identical authored fallback text', (tester) async {
    final projection = _projection();
    final target = projection.broadcastTargets('ALL').single;
    final originalCount = projection.broadcastRecipientCount(target);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) {
        final labels = ClubDirectorLabels(context);
        final rows = clubDirectorTeamRows(projection.teams, context: context);
        final incident = labels.incidentDetails(projection, projection.incidents.single);
        return Scaffold(body: Column(children: [
          for (final row in rows) ...[Text(row.title), Text(row.subtitle)],
          Text(labels.targetLabel(projection, 'ALL', target)),
          Text(labels.broadcastContent(projection.broadcasts.single)),
          Text(labels.broadcastTarget(projection.broadcasts.single)),
          Text(labels.broadcastReceipt(projection.broadcasts.single)),
          Text(incident.text), Text(incident.sub),
        ]));
      }),
    ));
    expect(find.text('未命名队伍'), findsOneWidget);
    expect(find.text('Unnamed team'), findsOneWidget);
    expect(find.text('Progress unconfirmed'), findsNWidgets(2));
    expect(find.text('0/0 nodes'), findsNothing);
    expect(find.text('All players present'), findsOneWidget);
    expect(find.text('广播内容待同步'), findsOneWidget);
    expect(find.text('原始范围'), findsOneWidget);
    expect(find.text('Delivery confirmed'), findsOneWidget);
    expect(find.textContaining('原始暂停原因'), findsOneWidget);
    expect(find.text('Fallback plan PLAN-A linked'), findsOneWidget);
    expect(target.label, '全部在场玩家');
    expect(originalCount, 5);
    expect(projection.broadcastRecipientCount(target), originalCount);
    expect(tester.takeException(), isNull);
  });
}
