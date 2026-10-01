import 'package:chengyin_app/data/models/club_access.dart';
import 'package:chengyin_app/data/models/club_settlement.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_settlement_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('English settlement chrome preserves supplied amount text', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clubAccessProvider(41).overrideWith(
            (ref) async => const ClubAccess(
              active: true,
              clubId: 41,
              permissions: {'club:finance:read'},
              roleCodes: ['OWNER'],
            ),
          ),
          clubSettlementSummaryProvider(41).overrideWith(
            (ref) async => const ClubSettlementSummary(
              settledAmountText: '¥12,480.01',
              topics: [],
            ),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: ClubSettlementPage(clubId: 41),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Club revenue share'), findsWidgets);
    expect(find.text('No topic settlement records yet'), findsOneWidget);
    expect(find.text('Contact platform support to withdraw'), findsOneWidget);
    expect(find.text('¥12,480.01'), findsOneWidget);
    // Display labels translate; the supplied amount remains unchanged.
    expect(find.text('Credited revenue share'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
