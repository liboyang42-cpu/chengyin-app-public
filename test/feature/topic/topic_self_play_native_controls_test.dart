import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('自玩通行证使用 Cupertino Sheet、系统输入与同意开关', () {
    final String source = File(
      'lib/feature/topic/topic_self_play_sheet.dart',
    ).readAsStringSync();

    expect(source, contains('showCupertinoSheet<void>'));
    expect(source, contains('CupertinoPageScaffold('));
    expect(RegExp(r'\bCupertinoTextField\(').allMatches(source).length, 2);
    expect(source, contains('CupertinoSwitch('));
    expect(source, contains('keyboardType: TextInputType.phone'));
    expect(source, isNot(contains('showModalBottomSheet')));
    expect(source, isNot(contains('TextFormField(')));
    expect(source, isNot(contains('CheckboxListTile(')));
    expect(source, isNot(contains('FilledButton(')));
  });
}
