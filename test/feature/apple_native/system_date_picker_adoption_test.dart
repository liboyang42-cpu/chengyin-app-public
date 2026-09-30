import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

int directCupertinoPickers(String source) =>
    RegExp(r'\bCupertinoDatePicker\s*\(').allMatches(source).length;

int systemPickerCalls(String source) =>
    RegExp(r'\bshowCySystemDatePicker\s*\(').allMatches(source).length;

void main() {
  const Map<String, int> expectedCalls = <String, int>{
    'lib/feature/merchant/merchant_recruit_sheets.dart': 2,
    'lib/feature/search/search_filter_sheet.dart': 2,
  };

  test('负控：直接 CupertinoDatePicker 会被统一门禁抓到', () {
    expect(
      directCupertinoPickers(
        'const CupertinoDatePicker(onDateTimeChanged: f);',
      ),
      1,
    );
    expect(
      directCupertinoPickers('showCySystemDatePicker(context: context);'),
      0,
    );
  });

  test('各处日期时间选择统一走 UIKit 优先入口', () {
    for (final MapEntry<String, int> entry in expectedCalls.entries) {
      final String source = File(entry.key).readAsStringSync();
      expect(
        directCupertinoPickers(source),
        0,
        reason: '${entry.key} 仍在页面内直接创建 CupertinoDatePicker',
      );
      expect(
        systemPickerCalls(source),
        entry.value,
        reason: '${entry.key} 没有按原顺序调用系统 picker',
      );
      expect(
        source.contains(
          "import '../../core/widgets/cy_system_date_picker.dart';",
        ),
        isTrue,
        reason: entry.key,
      );
    }
  });
}
