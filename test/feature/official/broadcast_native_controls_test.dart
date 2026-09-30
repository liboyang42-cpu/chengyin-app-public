import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('官方通知使用 Cupertino Sheet、系统输入和操作控件', () {
    final String source = File(
      'lib/feature/official/official_broadcast_sheet.dart',
    ).readAsStringSync();

    // B1 native_flutter_sheet 已落地:半屏表单走 showCyNativeSheet
    // (iOS 15+ 原生 sheet,其余回退 showCupertinoSheet),不再直接 showCupertinoSheet。
    expect(source, contains('showCyNativeSheet<void>'));
    expect(source, contains('isCyNativeSheet(context)'));
    expect(source, contains('CupertinoPageScaffold('));
    expect(RegExp(r'\bCupertinoTextField\(').allMatches(source).length, 2);
    expect(
      RegExp(r'\bCupertinoButton\(').allMatches(source).length,
      greaterThanOrEqualTo(2),
    );
    expect(source, isNot(contains('showModalBottomSheet')));
    expect(source, isNot(contains('FilledButton(')));
    expect(source, isNot(contains('InkWell(')));
  });
}
