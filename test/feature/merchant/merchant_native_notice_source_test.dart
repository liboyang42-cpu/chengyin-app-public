import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _materialNotice = RegExp(r'\b(ScaffoldMessenger|SnackBar)\b');

List<String> _violations(String source) => _materialNotice
    .allMatches(source)
    .map((Match match) => match.group(1)!)
    .toList(growable: false);

void main() {
  test('负控：商家页 Material 通知门禁会抓到违规用法', () {
    expect(
      _violations(
        "ScaffoldMessenger.of(context).showSnackBar("
        "const SnackBar(content: Text('已保存')));",
      ),
      <String>['ScaffoldMessenger', 'SnackBar'],
    );
    expect(_violations("CyNativeNotice.show(context, '已保存');"), isEmpty);
  });

  test('商家功能页用 Apple 风格原生通知反馈', () {
    final Directory merchant = Directory('lib/feature/merchant');
    final List<String> failures = <String>[];
    int scanned = 0;

    for (final FileSystemEntity entity in merchant.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      scanned++;
      final List<String> found = _violations(entity.readAsStringSync());
      if (found.isNotEmpty) failures.add('${entity.path}: ${found.join(', ')}');
    }

    expect(scanned, greaterThanOrEqualTo(30));
    expect(
      failures,
      isEmpty,
      reason:
          '轻量反馈统一使用 CyNativeNotice.show；失败路径必须传 '
          'isError: true。\n${failures.join('\n')}',
    );
  });
}
