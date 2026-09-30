import 'dart:io';

import 'package:chengyin_app/core/widgets/cy_system_date_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const MethodChannel _channel = MethodChannel(
  'com.chengyin.app/native_date_picker',
);

void main() {
  testWidgets('Cupertino date/time/dateAndTime 原样映射到 UIKit 通道', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    late BuildContext context;
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (BuildContext value) {
            context = value;
            return const CupertinoPageScaffold(child: SizedBox.expand());
          },
        ),
      ),
    );

    final List<String> sentModes = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
      MethodCall call,
    ) async {
      sentModes.add(
        (call.arguments as Map<Object?, Object?>)['mode']! as String,
      );
      return DateTime(2026, 8, 23, 14, 30).millisecondsSinceEpoch;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        null,
      ),
    );

    for (final CupertinoDatePickerMode mode in <CupertinoDatePickerMode>[
      CupertinoDatePickerMode.date,
      CupertinoDatePickerMode.time,
      CupertinoDatePickerMode.dateAndTime,
    ]) {
      await showCySystemDatePicker(
        context: context,
        mode: mode,
        initialDateTime: DateTime(2026, 8, 23, 14, 30),
        minimumDate: DateTime(2026),
        maximumDate: DateTime(2027),
      );
    }

    debugDefaultTargetPlatformOverride = null;
    expect(sentModes, <String>['date', 'time', 'dateTime']);
  });

  test('iOS bridge 把 time/date/dateTime 分别交给正确 UIDatePickerMode', () {
    final String source = File(
      'ios/Runner/AppDelegate.swift',
    ).readAsStringSync();

    expect(source, contains('case "date": pickerMode = .date'));
    expect(source, contains('case "time": pickerMode = .time'));
    expect(source, contains('case "dateTime": pickerMode = .dateAndTime'));
    expect(source, contains('picker.datePickerMode = mode'));
    expect(source, contains('nativeDatePickerController == nil'));
    expect(source, contains('code: "already_presented"'));
  });
}
