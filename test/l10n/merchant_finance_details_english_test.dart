import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/merchant_finance.dart';
import 'package:chengyin_app/feature/merchant/batch_detail_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_redemption_detail_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

Widget _host(Widget child) => MaterialApp(locale: const Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales, home: child);
void main() {
  testWidgets('English batch retains amount date voucher and truthful payment progress', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(overrides: [batchDetailProvider.overrideWith((ref, id) async => const PublicTransferBatchDetail(
      batch: PublicTransferBatch(batchId: '7', periodYm: '2026-09', amountTotal: '0012.50', netDirection: 'PLATFORM_PAYS_MERCHANT',
        paymentState: 'PAID', invoiceState: 'ISSUED', paidAt: '2026-09-30 12:34:56', payVoucherNo: '凭证-001'), earningEntries: [], adjustments: [],
    ))], child: _host(const BatchDetailPage(batchId: 7))));
    await tester.pumpAndSettle();
    expect(find.text('¥0012.50'), findsOneWidget);
    expect(find.text('2026-09-30 12:34:56'), findsOneWidget);
    expect(find.text('凭证-001 · Copy'), findsOneWidget);
    expect(find.text('2026-09-30 12:34 · Voucher 凭证-001'), findsOneWidget);
    expect(find.text('Batch created'), findsOneWidget);
    expect(find.text('Reconciliation confirmed'), findsOneWidget);
  });
  testWidgets('opposite-direction paid batch does not claim merchant payment or show voucher', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [batchDetailProvider.overrideWith((ref, id) async => const PublicTransferBatchDetail(
      batch: PublicTransferBatch(batchId: '7', amountTotal: '12.50', netDirection: 'MERCHANT_OWES_PLATFORM',
        paymentState: 'PAID', payVoucherNo: '不得展示凭证'), earningEntries: [], adjustments: [],
    ))], child: _host(const BatchDetailPage(batchId: 7))));
    await tester.pumpAndSettle();
    expect(find.text('Adjustment pending'), findsOneWidget);
    expect(find.textContaining('不得展示凭证'), findsNothing);
    expect(find.text('Payment progress'), findsNothing);
  });
  testWidgets('redemption raw no-cash reason bypasses identical local-label translation', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [merchantRedemptionDetailProvider.overrideWith((ref, id) async => const MerchantRedemptionView(
      recordKey: '7', recordType: 'CHAPTER', recordId: '7', topicName: '核销记录', displayState: 'NO_CASH_SETTLEMENT',
      noCashReason: '平台已打款', settlementAmount: '0.00', storeName: '原始门店',
    ))], child: _host(const MerchantRedemptionDetailPage(recordType: 'CHAPTER', recordId: '7'))));
    await tester.pumpAndSettle();
    expect(find.text('平台已打款'), findsOneWidget);
    expect(find.text('核销记录 · My income'), findsOneWidget);
    expect(find.text('¥0.00'), findsOneWidget);
    expect(find.text('原始门店'), findsOneWidget);
  });
}
