import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('积分任务和聊天路线选择使用 Cupertino rich sheet', () {
    for (final String path in <String>[
      'lib/feature/points/points_tasks_sheet.dart',
      'lib/feature/im/route_picker_sheet.dart',
    ]) {
      final String source = File(path).readAsStringSync();
      expect(source, contains('showCupertinoSheet'));
      expect(source, contains('CupertinoPageScaffold'));
      expect(source, isNot(contains('showModalBottomSheet')));
    }
  });
}
