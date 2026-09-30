import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _nonAdaptiveRefreshIndicator = RegExp(r'\bRefreshIndicator\s*\(');

List<String> _violations(String source) => _nonAdaptiveRefreshIndicator
    .allMatches(source)
    .map((Match match) => match.group(0)!)
    .toList(growable: false);

void main() {
  test('负控：普通 RefreshIndicator 会被门禁抓到', () {
    expect(_violations('RefreshIndicator(onRefresh: refresh, child: list);'), [
      'RefreshIndicator(',
    ]);
    expect(
      _violations(
        'RefreshIndicator.adaptive(onRefresh: refresh, child: list);',
      ),
      isEmpty,
    );
  });

  test('功能页刷新指示器使用平台自适应实现', () {
    final List<String> failures = <String>[];
    int scanned = 0;
    for (final FileSystemEntity entity in Directory(
      'lib/feature',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      scanned++;
      final List<String> found = _violations(entity.readAsStringSync());
      if (found.isNotEmpty) failures.add('${entity.path}: ${found.length}');
    }

    expect(scanned, greaterThanOrEqualTo(60));
    expect(
      failures,
      isEmpty,
      reason:
          'iOS/macOS 应使用 RefreshIndicator.adaptive 显示 '
          'CupertinoActivityIndicator，同时保持原有滚动结构与 onRefresh。\n'
          '${failures.join('\n')}',
    );
  });
}
