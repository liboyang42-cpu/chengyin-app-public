import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('俱乐部详情主动作使用 Liquid Glass 能力按钮', () {
    final String source = File(
      'lib/feature/club/club_detail_page.dart',
    ).readAsStringSync();

    expect(
      RegExp(r'\bCyNativeButton\(').allMatches(source).length,
      greaterThanOrEqualTo(5),
    );
    expect(source, contains('CupertinoButton('));
    expect(source, isNot(contains('FilledButton(')));
    expect(source, isNot(contains('OutlinedButton(')));
    expect(source, isNot(contains('TextButton(')));
  });
}
