import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/feature/activity/activity_detail_page.dart';
import 'package:chengyin_app/feature/orders/orders_page.dart';
import 'package:chengyin_app/feature/orders/order_detail_sheet.dart';
import 'package:chengyin_app/feature/orders/registration_order_strings.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:chengyin_app/feature/orders/payment_result_sheet.dart';
import 'package:chengyin_app/feature/orders/payment_verifier.dart';

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

void main() {
  for (final serverMessage in <String?>[null, '支付未完成', 'Original payment reason']) {
    testWidgets('payment failure preserves message provenance: $serverMessage', (tester) async {
      final outcome = await RegistrationPaymentVerifier(
        requestStatus: (_) async => <String, dynamic>{
          'paymentStatus': 4,
          if (serverMessage != null) 'errMsg': serverMessage,
        },
      ).verify(77);
      expect(outcome.hasLocalFailureMessage, serverMessage == null);
      await tester.pumpWidget(_app(Builder(builder: (context) => CupertinoButton(
        onPressed: () => showPaymentResultSheet(context, reconcile: () async => outcome),
        child: const Text('Open'),
      ))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text(serverMessage ?? 'Payment not completed'), findsOneWidget);
      expect(find.text('Check your order for the final status. Do not pay again yet.'), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('English fees preserve amount and server error', (tester) async {
    await tester.pumpWidget(_app(Scaffold(body: FeeBreakdown(
      quote: const RegistrationQuote(payAmount: 49.25, quoteSign: 'receipt-signature'),
      loading: false,
      error: null,
      usePoints: false,
      onRetry: () {},
      onTogglePoints: null,
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Charge details'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('¥49.25'), findsOneWidget);
    await tester.pumpWidget(_app(Scaffold(body: FeeBreakdown(
      quote: null,
      loading: false,
      error: '服务端报价原话',
      usePoints: false,
      onRetry: () {},
      onTogglePoints: null,
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Could not load price: 服务端报价原话'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('English order detail keeps original receipt fields', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        orderDetailProvider(77).overrideWith((_) async => RegistrationDetail.fromJson({
          'id': 77, 'ownerType': 2, 'ownerId': 9,
          'registrationNo': 'RECEIPT-原号-77',
          'registrationStatus': 2, 'paymentStatus': 2,
          'payableAmount': 49.25,
          'paymentTime': '2026-09-30 12:34:56',
          'transactionId': 'WX-原交易号',
          'cmsActivity': {'name': '主办方原活动名'},
        })),
        orderCompletionProvider(77).overrideWith((_) async => null),
      ],
      child: _app(const OrderDetailSheet(orderId: 77)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Order details'), findsOneWidget);
    expect(find.text('RECEIPT-原号-77'), findsOneWidget);
    expect(find.text('主办方原活动名'), findsWidgets);
    expect(find.text('¥49.25'), findsOneWidget);
    expect(find.text('WX-原交易号'), findsOneWidget);
    expect(find.text('2026-09-30 12:34'), findsWidgets);
  });

  testWidgets('English order filters and empty state', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [myOrdersProvider.overrideWith((_) async => <MyRegistration>[])],
      child: _app(const OrdersPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('My orders'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Awaiting payment'), findsOneWidget);
    expect(find.text('No city route orders yet'), findsOneWidget);
  });

  testWidgets('entitlement fallback translates but matching server label does not', (tester) async {
    await tester.pumpWidget(_app(Builder(builder: (context) => Column(children: [
      Text(localizedEntitlementLabel(context, const Entitlement(id: 1, status: 0))),
      Text(localizedEntitlementLabel(context, const Entitlement(id: 2, status: 0, statusLabel: '待核销'))),
      Text(localizedEntitlementLabel(context, const Entitlement(id: 3, status: 0, statusLabel: 'Original server label'))),
    ]))));
    await tester.pumpAndSettle();
    expect(find.text('Awaiting redemption'), findsOneWidget);
    expect(find.text('待核销'), findsOneWidget);
    expect(find.text('Original server label'), findsOneWidget);
  });
}
