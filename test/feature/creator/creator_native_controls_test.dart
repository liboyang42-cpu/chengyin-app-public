import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('创作者申请使用 Cupertino 输入与系统操作控件', () {
    final String source = File(
      'lib/feature/creator/creator_center_page.dart',
    ).readAsStringSync();

    expect(RegExp(r'\bCupertinoTextField\(').allMatches(source).length, 2);
    expect(source, contains('CupertinoButton('));
    expect(source, contains('textInputAction: TextInputAction.next'));
    expect(RegExp(r'(?<!Cupertino)\bTextField\(').hasMatch(source), isFalse);
    expect(source, isNot(contains('FilledButton(')));
  });
}
