import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('优惠券发布使用 Cupertino Sheet、输入与操作控件', () {
    final String source = File(
      'lib/feature/coupon/coupon_publish_sheet.dart',
    ).readAsStringSync();

    // B1:改走原生玻璃 sheet —— `showCyNativeSheet` 是它上面的一层
    // (iOS 15+/26+ 原生 UISheetPresentationController,其余回退
    // showCupertinoSheet)。意图不变:**不许 Material bottom sheet**。
    expect(
      source.contains('showCyNativeSheet<bool>') ||
          source.contains('showCupertinoSheet<bool>'),
      isTrue,
      reason: '优惠券浮层必须走 iOS 原生 sheet 路径',
    );
    expect(source, contains('CupertinoPageScaffold('));
    expect(source, contains('CupertinoTextField('));
    expect(source, contains('showCySystemDatePicker('));
    expect(source, isNot(contains('showModalBottomSheet')));
    expect(source, isNot(contains('FilledButton(')));
    expect(source, isNot(contains('OutlinedButton(')));
    expect(source, isNot(contains('InputDecorator(')));
  });

  test('票务开关统一使用 Apple CupertinoSwitch', () {
    final String source = File(
      'lib/feature/publish/publish_pro_ticket_tab.dart',
    ).readAsStringSync();

    expect(RegExp(r'\bCupertinoSwitch\(').allMatches(source).length, 4);
    expect(RegExp(r'(?<!Cupertino)\bSwitch\(').hasMatch(source), isFalse);
  });
}
