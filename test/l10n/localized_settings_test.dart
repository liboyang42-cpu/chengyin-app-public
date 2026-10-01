import 'package:chengyin_app/l10n/locale_preference.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/account_api.dart';
import 'package:chengyin_app/data/models/consent_record.dart';
import 'package:chengyin_app/feature/settings/settings_page.dart';
import 'package:chengyin_app/feature/settings/sound_haptics_settings.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixed_auth.dart';

class _SoundStore implements SoundHapticsSettingsStore {
  @override
  Future<SoundHapticsSettings> read() async => SoundHapticsSettings.defaults;

  @override
  Future<void> write(SoundHapticsSettings value) async {
    throw Exception('storage unavailable');
  }
}

class _FailingPrivacyApi extends Fake implements AccountApi {
  int calls = 0;

  @override
  Future<ConsentRecord> revokeRoamLocationConsent({
    required String requestId,
  }) async {
    calls++;
    throw Exception('network unavailable');
  }
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  _FailingPrivacyApi? privacyApi,
}) async {
  tester.view.physicalSize = const Size(430, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        signedInAuthOverride(),
        soundHapticsSettingsStoreProvider.overrideWithValue(_SoundStore()),
        if (privacyApi != null)
          accountApiProvider.overrideWithValue(privacyApi),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: SettingsPage(liquidGlassSupported: false),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

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

  testWidgets('English settings preserves language and legal-source entries', (
    tester,
  ) async {
    await _pumpSettings(tester);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Participants'), findsOneWidget);
    expect(find.text('Chengyin player'), findsOneWidget);
    expect(find.text('用户服务协议'), findsOneWidget);
    expect(find.text('个人资料'), findsNothing);
    await tester.ensureVisible(find.text('Sign out'));
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(
      find.text('You will need to sign in again to view orders and tickets.'),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English sound controls expose state and storage failure', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    await _pumpSettings(tester);
    await tester.ensureVisible(find.text('Sound and haptics').first);
    await tester.tap(find.text('Sound and haptics').first);
    await tester.pumpAndSettle();
    expect(find.text('Ambient sound'), findsOneWidget);
    expect(find.text('Airplane engine'), findsOneWidget);
    final row = find.byKey(const Key('sound-haptics-row-sound'));
    expect(tester.getSemantics(row).value, 'On');
    await tester.tap(find.text('Sound'));
    await tester.pumpAndSettle();
    expect(find.text('Settings were not saved. Try again.'), findsOneWidget);
    expect(tester.getSemantics(row).value, 'On');
    expect(find.byType(CupertinoSwitch), findsNWidgets(6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('English privacy failure uses a localized document action', (
    tester,
  ) async {
    final api = _FailingPrivacyApi();
    await _pumpSettings(tester, privacyApi: api);
    await tester.ensureVisible(find.text('Privacy and location'));
    await tester.tap(find.text('Privacy and location'));
    await tester.pumpAndSettle();
    expect(find.text('View privacy document'), findsOneWidget);
    await tester.tap(find.byKey(const Key('privacy-revoke-button')));
    await tester.pumpAndSettle();
    expect(api.calls, 1);
    expect(
      find.text('Could not record your withdrawal. Check your connection and try again.'),
      findsOneWidget,
    );
    expect(find.text('Withdraw roaming location consent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
