import 'package:chengyin_app/l10n/locale_preference.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:chengyin_app/feature/settings/settings_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fixed_auth.dart';

void main() {
  testWidgets('Settings switches shared screen between Chinese, English and system', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.platformDispatcher.localesTestValue = [const Locale('en', 'US')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final container = ProviderContainer(overrides: [signedInAuthOverride()]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: Consumer(builder: (context, ref, child) => MaterialApp(
        locale: ref.watch(localePreferenceProvider),
        localeListResolutionCallback: resolveAppLocale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const SettingsPage(liquidGlassSupported: false),
      )),
    ));
    await tester.pumpAndSettle();
    final originalState = tester.state(find.byType(SettingsPage));
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('简体中文'));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    expect(container.read(localePreferenceProvider), const Locale('zh'));
    expect(tester.state(find.byType(SettingsPage)), same(originalState));
    await tester.tap(find.text('语言'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(container.read(localePreferenceProvider), const Locale('en'));
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Follow system'));
    await tester.pumpAndSettle();
    expect(container.read(localePreferenceProvider), isNull);
    expect(find.text('Settings'), findsOneWidget);
    const storage = FlutterSecureStorage();
    expect(await storage.read(key: LocalePreference.storageKey), isNull);
    expect(tester.takeException(), isNull);
  });

}
