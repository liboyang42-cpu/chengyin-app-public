import 'dart:async';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/l10n/locale_preference.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _QueuedStorage extends FlutterSecureStorage {
  final firstStarted = Completer<void>();
  final releaseFirst = Completer<void>();
  String? persisted;
  int writes = 0;
  @override
  Future<void> write({required String key, required String? value,
    AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions,
    WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    if (++writes == 1) {
      firstStarted.complete();
      await releaseFirst.future;
      persisted = value;
    } else {
      throw StateError('second write failed');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  test('system preference follows language order, independently of country', () {
    const supported = [Locale('zh'), Locale('en')];
    expect(resolveAppLocale([const Locale('zh', 'US')], supported), const Locale('zh'));
    expect(resolveAppLocale([const Locale('en', 'CN')], supported), const Locale('en'));
    expect(resolveAppLocale([const Locale('fr'), const Locale('zh')], supported), const Locale('zh'));
    expect(resolveAppLocale(null, supported), const Locale('en'));
  });

  test('selection persists across restart and system selection removes override', () async {
    final first = ProviderContainer();
    addTearDown(first.dispose);
    await first.read(localePreferenceProvider.notifier).select('en');
    expect(first.read(localePreferenceProvider), const Locale('en'));
    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    await restored.read(localePreferenceProvider.notifier).restore();
    expect(restored.read(localePreferenceProvider), const Locale('en'));
    await restored.read(localePreferenceProvider.notifier).select(null);
    expect(restored.read(localePreferenceProvider), isNull);
    const storage = FlutterSecureStorage();
    expect(await storage.read(key: LocalePreference.storageKey), isNull);
  });

  test('later failed selection keeps UI aligned with earlier persisted selection', () async {
    final storage = _QueuedStorage();
    final container = ProviderContainer(overrides: [secureStorageProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    final controller = container.read(localePreferenceProvider.notifier);
    final first = controller.select('en');
    await storage.firstStarted.future;
    final second = controller.select('zh');
    final failed = expectLater(second, throwsStateError);
    storage.releaseFirst.complete();
    await first;
    await failed;
    expect(storage.persisted, 'en');
    expect(container.read(localePreferenceProvider), const Locale('en'));
  });

  test('unsupported language cannot replace stored preference', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(localePreferenceProvider.notifier).select('zh');
    await expectLater(container.read(localePreferenceProvider.notifier).select('fr'),
      throwsArgumentError);
    expect(container.read(localePreferenceProvider), const Locale('zh'));
  });
}
