import 'package:chengyin_app/core/widgets/cy_system_date_picker.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('com.chengyin.app/native_date_picker');

void main() {
  for (final language in ['en', 'zh']) {
    testWidgets('native picker uses $language text and device region', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        tester.platformDispatcher.localeTestValue = const Locale('zh', 'US');
        late BuildContext context;
        await tester.pumpWidget(CupertinoApp(
          locale: Locale(language),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(builder: (value) {
            context = value;
            return const SizedBox.shrink();
          }),
        ));
        Map<Object?, Object?>? sent;
        final instant = DateTime(2026, 9, 30, 14, 15);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
          sent = call.arguments as Map<Object?, Object?>;
          return instant.millisecondsSinceEpoch;
        });
        final result = await showCySystemDatePicker(
          context: context,
          mode: CupertinoDatePickerMode.dateAndTime,
          initialDateTime: instant,
          minimumDate: DateTime(2026),
          maximumDate: DateTime(2027),
        );
        final strings = AppLocalizations.of(context);
        expect(sent!['localeIdentifier'], '$language-US');
        expect(sent!['title'], strings.selectDate);
        expect(sent!['cancelText'], strings.cancel);
        expect(sent!['doneText'], strings.done);
        expect(sent!['mode'], 'dateTime');
        expect(sent!['initialMilliseconds'], instant.millisecondsSinceEpoch);
        expect(result!.millisecondsSinceEpoch, instant.millisecondsSinceEpoch);
      } finally {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
        tester.platformDispatcher.clearLocaleTestValue();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
