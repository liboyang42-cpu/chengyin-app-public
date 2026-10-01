import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/merchant_application.dart';
import 'package:chengyin_app/feature/merchant/merchant_apply_page.dart';
import 'package:chengyin_app/feature/publisher/publisher_identity.dart';
import 'package:chengyin_app/feature/publisher/publisher_identity_fields.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

Widget _app({MerchantApplication? application, Object? error}) => ProviderScope(
  overrides: [
    merchantApplicationProvider.overrideWith((ref) async {
      if (error != null) throw error;
      return application;
    }),
  ],
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const MerchantApplyPage(),
  ),
);

void main() {
  testWidgets('English form labels and blockers track existing validation', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('Merchant application · Basic details'), findsOneWidget);
    expect(find.text('Store name'), findsOneWidget);
    expect(find.text('Enter a brand name'), findsOneWidget);
    expect(
      tester.widget<CupertinoButton>(find.byKey(const Key('merchant-apply-next')))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const Key('merchant-apply-name')), '原店名');
    await tester.pump();
    expect(find.text('Enter a contact mobile number'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('merchant-apply-phone')), '13800138000');
    await tester.pump();
    await tester.tap(find.byKey(const Key('merchant-apply-next')));
    await tester.pumpAndSettle();
    expect(find.text('Merchant application · Business details'), findsOneWidget);
    expect(find.text('Enter the store address'), findsOneWidget);
    expect(find.text('Business hours'), findsOneWidget);
  });

  testWidgets('English rejected status preserves server reason and reapply', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        application: const MerchantApplication(
          id: 7,
          status: 2,
          accountStatus: 0,
          name: '原始店名',
          phone: '13800138000',
          rejectReason: '后端驳回原话',
          createTime: '2026-09-30 11:25',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Your application was not approved. 后端驳回原话'), findsOneWidget);
    expect(find.text('2026-09-30 11:25'), findsOneWidget);
    await tester.tap(find.text('Apply again'));
    await tester.pumpAndSettle();
    expect(find.text('Merchant application · Basic details'), findsOneWidget);
    expect(find.text('原始店名'), findsOneWidget);
  });

  testWidgets('English status failure offers localized recovery', (tester) async {
    await tester.pumpWidget(_app(error: Exception('offline')));
    await tester.pumpAndSettle();
    expect(find.text('Application status is currently unavailable'), findsOneWidget);
    expect(find.text('Check your connection and try again.'), findsOneWidget);
    expect(find.text('Check again'), findsOneWidget);
  });

  testWidgets('identity labels translate while consent stays verbatim', (
    tester,
  ) async {
    final controller = PublisherIdentityController(source: kIdentitySourceMerchantApply);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PublisherIdentityFields(
            controller: controller,
            title: 'Business operator identity',
            footHint: 'Original disclosure',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Real name'), findsOneWidget);
    expect(find.text('ID card number'), findsOneWidget);
    expect(find.text(kIdentityConsentText), findsOneWidget);
    controller.markRegistered();
    await tester.pump();
    expect(find.text('Registered. Contact platform support to update your identity details.'), findsOneWidget);
    expect(find.text('Real name'), findsNothing);
  });
}
