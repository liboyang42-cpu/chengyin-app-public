import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('搜索入口、筛选与结果卡使用 Apple 动作控件', () {
    final String source = <String>[
      'lib/feature/search/search_page.dart',
      'lib/feature/search/city_node_search_page.dart',
      'lib/feature/search/search_result_page.dart',
    ].map((String path) => File(path).readAsStringSync()).join('\n');

    expect(source, contains('CupertinoButton('));
    expect(source, contains('CyNativeButton('));
    for (final String materialControl in <String>[
      'FilledButton(',
      'OutlinedButton(',
      'TextButton(',
      'IconButton(',
      'InkWell(',
    ]) {
      expect(source, isNot(contains(materialControl)), reason: materialControl);
    }
  });
}
