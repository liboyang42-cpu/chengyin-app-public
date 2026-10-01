import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/merchant_crm_console.dart';
import 'package:chengyin_app/feature/merchant/merchant_crm_panels.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

void main() {
  testWidgets('English broadcast estimates preserve raw team names and counts', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const CrmBroadcastSheet(castCount: 12,
        rows: [CrmCustomerRow(memberId: 7, name: '原始姓名', teamName: '原始队伍')],
        query: CrmCustomerQuery(),
      ),
    )));
    expect(find.text('12 people · Reachability is checked before sending'), findsOneWidget);
    await tester.tap(find.text('Teams'));
    await tester.pump();
    expect(find.text('Nothing selected yet'), findsOneWidget);
    expect(find.text('原始队伍'), findsOneWidget);
    await tester.tap(find.text('原始队伍'));
    await tester.pump();
    expect(find.text('1 people · 1 teams · Checked before sending'), findsOneWidget);
    // Draft estimates do not send requests or manufacture delivery receipts.
    expect(find.textContaining('Delivered to'), findsNothing);
  });
}
