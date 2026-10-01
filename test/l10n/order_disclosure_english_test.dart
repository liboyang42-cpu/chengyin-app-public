import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/page_parity_api.dart';
import 'package:chengyin_app/data/models/marketing_consent.dart';
import 'package:chengyin_app/feature/orders/merchant_consent_row.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api implements PageParityApi {
  _Api(this.name);
  final String? name;
  int submissions = 0;
  @override
  Future<List<MarketingConsent>> marketingConsents() async => [MarketingConsent.fromJson({
    'merchantRowId': 7, 'merchantOwnerMemberId': 8, 'merchantName': name,
    'inAppOptedIn': false, 'couponOptedIn': false,
  })];
  @override
  Future<List<MarketingConsent>> setMarketingConsent({required int merchantRowId, required int merchantOwnerMemberId, required String channel, required bool optedIn, required String requestId}) async {
    expect(merchantRowId, 7); expect(merchantOwnerMemberId, 8);
    expect(channel, 'IN_APP'); expect(optedIn, isTrue);
    submissions++;
    return [];
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final entry in <(int, String?, String)>[(8001, '商家', '商家'), (8002, null, 'Merchant')]) {
    testWidgets('English consent preserves merchant provenance ${entry.$1}', (tester) async {
      final api = _Api(entry.$2);
      await tester.pumpWidget(ProviderScope(overrides: [pageParityApiProvider.overrideWithValue(api)],
        child: MaterialApp(locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: CyMerchantConsentRow(orderId: entry.$1, ownerMemberId: 8)),
        ),
      ));
      await tester.pumpAndSettle();
      final label = 'Receive activity messages from “${entry.$3}”';
      expect(tester.getSemantics(find.byKey(const Key('order-merchant-consent'))).getSemanticsData().label, contains(label));
      expect(find.text('$label (in-app messages; you can unsubscribe in Settings at any time)'), findsOneWidget);
      expect(tester.widget<CupertinoCheckbox>(find.byType(CupertinoCheckbox)).value, isFalse);
      await tester.tap(find.byType(CupertinoCheckbox));
      await tester.pumpAndSettle();
      expect(api.submissions, 1);
      expect(find.text('Agreed. You can unsubscribe in Settings at any time'), findsOneWidget);
    });
  }
}
