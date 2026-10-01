import 'package:chengyin_app/data/models/club_ops.dart';
import 'package:chengyin_app/feature/club/club_occurrence_labels.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('English occurrence labels preserve raw locks and unknown counts', (tester) async {
    final row = SeriesOccurrence.fromJson({
      'occurrenceId': 8,
      'activityId': 41,
      'occurrenceAt': '2026-09-20 14:00:00',
      'signupCount': null,
      'editable': false,
      // Same text as the local fallback, but explicitly supplied by backend.
      'lockReason': '已锁定',
    });
    final cancelled = SeriesOccurrence.fromJson({
      'status': 'CANCELLED',
      'refundedCount': 3,
    });
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) => Column(children: [
        Text(clubOccurrenceMeta(context, row)),
        Text(clubOccurrenceBadge(context, row)),
        Text(clubOccurrenceDate(context, row)),
        Text(clubOccurrenceMeta(context, cancelled)),
        Text(clubOccurrenceDate(context, cancelled)),
      ])),
    ));
    expect(find.text('Registration count pending confirmation'), findsOneWidget);
    expect(find.text('已锁定'), findsOneWidget);
    expect(find.textContaining('14:00'), findsOneWidget);
    expect(find.text('3 orders refunded'), findsOneWidget);
    expect(find.text('Date pending confirmation'), findsOneWidget);
    expect(row.activityId, 41);
    expect(row.badgeKind, 'locked');
    expect(row.displaySource!.signupCount, isNull);
  });
}
