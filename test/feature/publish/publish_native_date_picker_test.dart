import 'dart:io';

import 'package:chengyin_app/feature/publish/publish_pro_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PickerHost extends StatelessWidget {
  const _PickerHost();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          CupertinoButton(
            key: const Key('open-date'),
            onPressed: () => pickDate(context),
            child: const Text('选日期'),
          ),
          CupertinoButton(
            key: const Key('open-date-time'),
            onPressed: () => pickDateTime(context),
            child: const Text('选日期时间'),
          ),
        ],
      ),
    );
  }
}

void main() {
  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: _PickerHost()));
  }

  testWidgets('发布日期用 Cupertino 系统样式 picker', (WidgetTester tester) async {
    await pumpHost(tester);
    await tester.tap(find.byKey(const Key('open-date')));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    final CupertinoDatePicker picker = tester.widget(
      find.byType(CupertinoDatePicker),
    );
    expect(picker.mode, CupertinoDatePickerMode.date);
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.byKey(const Key('cy-native-picker-cancel')), findsOneWidget);
    expect(find.byKey(const Key('cy-native-picker-done')), findsOneWidget);
  });

  testWidgets('发布日期时间一次用 dateAndTime picker 完成', (WidgetTester tester) async {
    await pumpHost(tester);
    await tester.tap(find.byKey(const Key('open-date-time')));
    await tester.pumpAndSettle();

    final CupertinoDatePicker picker = tester.widget(
      find.byType(CupertinoDatePicker),
    );
    expect(picker.mode, CupertinoDatePickerMode.dateAndTime);
    expect(find.byType(TimePickerDialog), findsNothing);
  });

  test('优惠券与活动发布不再调 Material 日期、时间和下拉选择器', () {
    final String coupon = File(
      'lib/feature/coupon/coupon_publish_sheet.dart',
    ).readAsStringSync();
    final String activity = File(
      'lib/feature/publish/publish_activity_page.dart',
    ).readAsStringSync();
    final String utils = File(
      'lib/feature/publish/publish_pro_utils.dart',
    ).readAsStringSync();

    for (final String source in <String>[coupon, activity, utils]) {
      expect(source, isNot(contains('showDatePicker(')));
      expect(source, isNot(contains('showTimePicker(')));
    }
    expect(coupon, isNot(contains('DropdownButtonFormField')));
  });
}
