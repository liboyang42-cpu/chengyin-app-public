import 'package:chengyin_app/l10n/locale_preference.dart';
import 'package:chengyin_app/l10n/strings_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  testWidgets('retained controller strings follow system language changes',
      (tester) async {
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    final container = ProviderContainer();
    final subscription = container.listen(appStringsProvider, (_, _) {});
    try {
      expect(container.read(appStringsProvider).localeName, 'zh');

      tester.platformDispatcher.localesTestValue = <Locale>[const Locale('en')];
      await tester.pump(Duration.zero);
      expect(container.read(appStringsProvider).localeName, 'en');

      tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
      await tester.pump(Duration.zero);
      expect(container.read(appStringsProvider).localeName, 'zh');
      await tester.pump(Duration.zero);
    } finally {
      subscription.close();
      container.dispose();
      tester.platformDispatcher.clearLocalesTestValue();
      // Widget invariants run before addTearDown. Dispose providers and drain
      // their zero-duration scheduler task while still inside the test body.
      await tester.pump(Duration.zero);
    }
  });

  testWidgets('explicit language survives system changes until follow system',
      (tester) async {
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    final container = ProviderContainer();
    final subscription = container.listen(appStringsProvider, (_, _) {});
    try {
      final preferences = container.read(localePreferenceProvider.notifier);
      await preferences.select('en');
      expect(container.read(appStringsProvider).localeName, 'en');

      tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh', 'US')];
      await tester.pump(Duration.zero);
      expect(container.read(appStringsProvider).localeName, 'en');
      await preferences.select(null);
      expect(container.read(appStringsProvider).localeName, 'zh');
      await tester.pump(Duration.zero);
    } finally {
      subscription.close();
      container.dispose();
      tester.platformDispatcher.clearLocalesTestValue();
      // Widget invariants run before addTearDown. Dispose providers and drain
      // their zero-duration scheduler task while still inside the test body.
      await tester.pump(Duration.zero);
    }
  });
}
