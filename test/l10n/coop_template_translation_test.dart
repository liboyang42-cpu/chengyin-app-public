import 'package:chengyin_app/data/models/coop_perk_template.dart';
import 'package:chengyin_app/feature/coop/coop_perk_template_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fixed_auth.dart';

void main() {
  testWidgets('English reusable benefits preserve Chinese item names, CNY, dates and zero quota', (tester) async {
    final rows = [CoopPerkTemplate.fromJson({
      'id': 1, 'perkType': 0, 'name': '礼品', 'retailValue': 28,
      'unitCost': 0, 'quota': 0, 'validEnd': '2026-12-31 17:00:00',
    })];
    await tester.pumpWidget(ProviderScope(
      overrides: <dynamic>[
        signedInAuthOverride(role: 'merchant'),
        coopPerkTemplatesProvider.overrideWith((ref) async => rows),
      ].cast(),
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CoopPerkTemplatePage(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Reusable benefits'), findsOneWidget);
    expect(find.text('礼品'), findsOneWidget);
    expect(find.textContaining('Retail ¥28.00'), findsOneWidget);
    expect(find.textContaining('Cost ¥0.00'), findsOneWidget);
    expect(find.textContaining('Capacity: 0 items'), findsOneWidget);
    expect(find.textContaining('Until 2026-12-31'), findsOneWidget);
    expect(rows.single.usable, isFalse);
    final strings = AppLocalizations.of(tester.element(find.byType(CoopPerkTemplatePage)));
    expect(strings.coopTemplateQuota(1), 'Capacity: 1 item');
    expect(strings.coopTemplateQuota(2), 'Capacity: 2 items');
    expect(strings.coopTemplateRetailError, contains('99999999.99'));
    expect(strings.coopTemplateCostError, contains('0 to 99999999.99'));
    expect(tester.takeException(), isNull);
  });
}
