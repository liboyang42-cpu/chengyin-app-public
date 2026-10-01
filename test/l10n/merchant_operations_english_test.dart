import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/merchant_operator.dart';
import 'package:chengyin_app/data/models/merchant_ledger.dart';
import 'package:chengyin_app/feature/merchant/merchant_orders_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_operations_strings.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

Widget host(WidgetBuilder builder) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: Builder(builder: builder)),
);

void main() {
  testWidgets('English orders preserve receipt, date and CNY amount', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [merchantOrdersProvider.overrideWith((ref) async => [
        {'orderSn': '回执-001', 'status': 0, 'aftersaleStatus': 3,
         'payAmount': '1234.56', 'createTime': '2026-09-30 08:09:10'},
      ])],
      child: host((_) => const MerchantOrdersPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Awaiting payment'), findsOneWidget);
    expect(find.text('Refund in progress'), findsOneWidget);
    expect(find.text('回执-001'), findsOneWidget);
    expect(find.text('2026-09-30 08:09:10'), findsOneWidget);
    expect(find.text('¥1234.56'), findsOneWidget);
  });

  testWidgets('fallback roles and permissions localize without altering grants', (tester) async {
    final role = MerchantAssignableRole.fromJson({
      'roleCode': 'MERCHANT_FINANCE',
      'permissions': ['merchant:verify', 'merchant:finance:read'],
    });
    final supplied = MerchantAssignableRole.fromJson({
      'roleCode': 'MERCHANT_FINANCE', 'name': '财务', 'permissions': <String>[],
    });
    await tester.pumpWidget(host((context) => Column(children: [
      Text(localizedMerchantRoleName(context, role)),
      Text(localizedMerchantPermissions(context, role)),
      Text(localizedMerchantRoleName(context, supplied)),
    ])));
    expect(find.text('Finance'), findsOneWidget);
    expect(find.text('Redemptions, Finance'), findsOneWidget);
    expect(find.text('财务'), findsOneWidget);
    expect(role.permissions, {'merchant:verify', 'merchant:finance:read'});
    expect(role.role, MerchantOperatorRole.finance);
    expect(supplied.hasNameFallback, isFalse);
  });

  testWidgets('ledger backend reasons bypass local status translation', (tester) async {
    final supplied = MerchantRedemption.fromJson({
      'recordKey': '原始回执', 'displayState': 'NO_CASH_SETTLEMENT',
      'noCashReason': '待结算', 'settlementAmount': '0.00',
    });
    final missing = MerchantRedemption.fromJson({
      'recordKey': 'receipt', 'displayState': 'NO_CASH_SETTLEMENT',
    });
    await tester.pumpWidget(host((context) => Column(children: [
      Text(localizedMerchantLedgerState(context, supplied)),
      Text(localizedMerchantLedgerState(context, missing)),
    ])));
    expect(find.text('待结算'), findsOneWidget);
    expect(find.text('No cash settlement'), findsOneWidget);
    expect(supplied.recordKey, '原始回执');
    expect(supplied.amountDisplay, '—');
    expect(missing.settlementAmount, isNull);
  });
}
