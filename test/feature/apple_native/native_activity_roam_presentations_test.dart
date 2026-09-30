import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('报名与漫游玩法不再使用 Material bottom sheet', () {
    for (final String path in <String>[
      'lib/feature/activity/activity_detail_page.dart',
      'lib/feature/roam/roam_live_page.dart',
    ]) {
      final String source = File(path).readAsStringSync();
      expect(source, contains('showCupertinoSheet<void>'), reason: path);
      expect(source, isNot(contains('showModalBottomSheet')), reason: path);
    }
  });

  test('活动详情与取消入口使用 Apple 动作控件', () {
    final String source = <String>[
      'lib/feature/activity/activity_detail_page.dart',
      'lib/feature/activity/cancel_activity_sheet.dart',
    ].map((String path) => File(path).readAsStringSync()).join('\n');

    expect(source, contains('CyNativeButton('));
    expect(source, contains('CupertinoButton('));
    for (final String materialControl in <String>[
      'FilledButton(',
      'OutlinedButton(',
      'TextButton(',
      'IconButton(',
    ]) {
      expect(source, isNot(contains(materialControl)), reason: materialControl);
    }
  });
}
