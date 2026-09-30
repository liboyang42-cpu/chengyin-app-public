import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/auth/login_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixed_auth.dart';

void main() {
  testWidgets('English registration supports large text and a small viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [authControllerProvider.overrideWith(() => FixedAuth(guestAuthState))],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const LoginPage(intent: 'merchant'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Merchant registration'), findsOneWidget);
    expect(find.text('商家注册'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Choose again'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('generated English resources use singular and plural counts', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) => Column(children: [
        Text(AppLocalizations.of(context).itemCount(1)),
        Text(AppLocalizations.of(context).itemCount(2)),
      ])),
    ));
    await tester.pumpAndSettle();
    expect(find.text('1 item'), findsOneWidget);
    expect(find.text('2 items'), findsOneWidget);
  });
}
