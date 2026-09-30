import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_localizations.dart';
import 'locale_preference.dart';

class _SystemLocaleObserver extends WidgetsBindingObserver {
  _SystemLocaleObserver(this.onChanged);

  final VoidCallback onChanged;

  @override
  void didChangeLocales(List<Locale>? locales) => onChanged();
}

/// Keep controller resources in sync even while another provider retains them.
/// Observe the binding rather than replacing the engine's locale callback.
final systemLocalesProvider = Provider.autoDispose<List<Locale>>((ref) {
  final binding = WidgetsBinding.instance;
  final observer = _SystemLocaleObserver(ref.invalidateSelf);
  binding.addObserver(observer);
  ref.onDispose(() => binding.removeObserver(observer));
  return List<Locale>.unmodifiable(binding.platformDispatcher.locales);
});

/// Resource access for controllers without a BuildContext. Read at action time,
/// so system language changes are observed without caching a stale locale.
final appStringsProvider = Provider.autoDispose<AppLocalizations>((ref) {
  final selected = ref.watch(localePreferenceProvider);
  final locale = selected ?? resolveAppLocale(
    ref.watch(systemLocalesProvider),
    AppLocalizations.supportedLocales,
  );
  return lookupAppLocalizations(locale);
});
