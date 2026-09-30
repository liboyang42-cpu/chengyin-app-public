import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _rawMaterialControl = RegExp(
  r'(?<!Cupertino)\b(TextField|TextFormField|DropdownButtonFormField|'
  r'CalendarDatePicker|showDatePicker|showTimePicker|Slider|Switch)\(',
);

List<String> _violations(String source) => _rawMaterialControl
    .allMatches(source)
    .map((Match match) => match.group(1)!)
    .toList(growable: false);

void main() {
  test('负控：Material 输入或日期控件会被门禁抓到', () {
    expect(
      _violations(
        'TextField(); TextFormField(); showDatePicker(); Switch(); Slider();',
      ),
      <String>[
        'TextField',
        'TextFormField',
        'showDatePicker',
        'Switch',
        'Slider',
      ],
    );
    expect(
      _violations(
        'CupertinoTextField(); CupertinoSwitch(); CupertinoSlider();',
      ),
      isEmpty,
    );
  });

  test('功能页不再直接使用 Material 输入、日期、滑块或开关', () {
    final List<String> failures = <String>[];
    for (final FileSystemEntity entity in Directory(
      'lib/feature',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final List<String> found = _violations(entity.readAsStringSync());
      if (found.isNotEmpty) failures.add('${entity.path}: ${found.join(', ')}');
    }

    expect(
      failures,
      isEmpty,
      reason:
          '请使用 Cupertino/系统键盘与选择器；'
          '若业务需要 Form 校验，用 FormField 包 CupertinoTextField。',
    );
  });
}
