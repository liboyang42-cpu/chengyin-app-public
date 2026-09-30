import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';

/// Language preference only: never a currency, residency or payment-region choice.
class LocalePreference extends Notifier<Locale?> {
  static const String storageKey = 'app_language_v1';
  int _revision = 0;
  Future<void> _writes = Future<void>.value();

  @override
  Locale? build() => null;

  Future<void> restore() async {
    final revision = _revision;
    try {
      final language = await ref.read(secureStorageProvider)
          .read(key: storageKey).timeout(const Duration(seconds: 2));
      if (!ref.mounted || revision != _revision) return;
      state = switch (language) {
        'en' => const Locale('en'),
        'zh' => const Locale('zh'),
        _ => null,
      };
    } catch (_) {
      // Storage failure falls back to the current system language.
    }
  }

  Future<void> select(String? language) {
    if (language != null && language != 'en' && language != 'zh') {
      return Future<void>.error(ArgumentError.value(language, 'language'));
    }
    _revision++;
    final storage = ref.read(secureStorageProvider);
    final operation = _writes.then((_) async {
      if (language == null) {
        await storage.delete(key: storageKey);
      } else {
        await storage.write(key: storageKey, value: language);
      }
      if (ref.mounted) {
        state = language == null ? null : Locale(language);
      }
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

}

final localePreferenceProvider = NotifierProvider<LocalePreference, Locale?>(
  LocalePreference.new,
);

/// Respect the ordered system language list, independently of country/currency.
Locale resolveAppLocale(List<Locale>? preferred, Iterable<Locale> supported) {
  for (final locale in preferred ?? <Locale>[]) {
    for (final candidate in supported) {
      if (candidate.languageCode == locale.languageCode) return candidate;
    }
  }
  return const Locale('en');
}
