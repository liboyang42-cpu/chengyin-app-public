import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/settings/about_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:chengyin_app/l10n/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _LoggedOut extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

void main() {
  testWidgets('English contact actions keep the original telephone target', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final called = <Uri>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [authControllerProvider.overrideWith(_LoggedOut.new)],
      child: MaterialApp(locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AboutPage(launchContactUri: (uri) async { called.add(uri); return true; })),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to view'), findsOneWidget);
    await tester.ensureVisible(find.text('Contact us'));
    await tester.tap(find.text('Contact us'));
    await tester.pumpAndSettle();
    expect(find.text('Customer service: 15229020419'), findsWidgets);
    await tester.tap(find.text('Call 15229020419'));
    await tester.pumpAndSettle();
    expect(called, [Uri(scheme: 'tel', path: '15229020419')]);
    expect(tester.takeException(), isNull);
  });

  test('settings messages preserve identifiers and original error detail', () {
    final strings = AppLocalizationsEn();
    expect(strings.settingsResidualVersion('1.0.0'), 'Version 1.0.0');
    expect(strings.settingsResidualMarketingError('原始消息 #17'),
      'Could not load marketing settings. Original message: 原始消息 #17');
    expect(strings.settingsResidualOptedOut, 'Unsubscribed');
  });
}
