import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('取消活动和邀请人是 Cupertino 表单 Sheet', () {
    for (final String path in <String>[
      'lib/feature/activity/cancel_activity_sheet.dart',
      'lib/feature/account/inviter_sheet.dart',
    ]) {
      final String source = File(path).readAsStringSync();
      expect(source, contains('showCupertinoSheet'));
      expect(source, contains('CupertinoPageScaffold'));
      expect(source, contains('CupertinoTextField'));
      expect(source, isNot(contains('showModalBottomSheet')));
    }
  });

  test('取消活动保留小程序文案和 100 字上限', () {
    final String source = File(
      'lib/feature/activity/cancel_activity_sheet.dart',
    ).readAsStringSync();
    expect(source, contains('maxLength: 100'));
    expect(source, contains('将为所有未核销报名全额退款，并同步下架活动，操作不可撤销。'));
    expect(source, contains('填写取消原因（会展示给已报名用户）'));
    expect(source, contains('确认取消并退款'));
  });
}
