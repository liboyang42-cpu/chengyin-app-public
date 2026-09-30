import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _rawMaterialAction = RegExp(
  r'\b(FilledButton|OutlinedButton|TextButton|IconButton|ElevatedButton|'
  r'FloatingActionButton|CircularProgressIndicator|InkWell|ActionChip|'
  r'InputChip|RawChip|Chip|Checkbox|Radio|PopupMenuButton|RangeSlider|'
  r'LinearProgressIndicator)\s*(?:\.|<|\()',
);

List<String> _violations(String source) => _rawMaterialAction
    .allMatches(source)
    .map((Match match) => match.group(1)!)
    .toList(growable: false);

void main() {
  test('负控：Material 按钮、加载件或墨水点击层会被抓到', () {
    expect(
      _violations(
        'FilledButton(); OutlinedButton.icon(); TextButton(); IconButton(); '
        'ElevatedButton(); FloatingActionButton(); '
        'CircularProgressIndicator(); InkWell(); Chip(); Checkbox(); Radio(); '
        'PopupMenuButton<String>(); RangeSlider(); LinearProgressIndicator();',
      ),
      <String>[
        'FilledButton',
        'OutlinedButton',
        'TextButton',
        'IconButton',
        'ElevatedButton',
        'FloatingActionButton',
        'CircularProgressIndicator',
        'InkWell',
        'Chip',
        'Checkbox',
        'Radio',
        'PopupMenuButton',
        'RangeSlider',
        'LinearProgressIndicator',
      ],
    );
    expect(
      _violations(
        'CyNativeButton(); CupertinoButton(); CupertinoActivityIndicator();',
      ),
      isEmpty,
    );
  });

  test('功能页和共享控件不再直接使用 Material 动作与加载控件', () {
    final List<String> failures = <String>[];
    int scanned = 0;
    for (final String root in <String>['lib/feature', 'lib/core/widgets']) {
      for (final FileSystemEntity entity in Directory(
        root,
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        scanned++;
        final List<String> found = _violations(entity.readAsStringSync());
        if (found.isNotEmpty) {
          failures.add('${entity.path}: ${found.join(', ')}');
        }
      }
    }

    expect(scanned, greaterThanOrEqualTo(70));
    expect(
      failures,
      isEmpty,
      reason:
          '主 CTA 使用 CyNativeButton，普通动作/图标使用 CupertinoButton，'
          '加载使用 CupertinoActivityIndicator；保持 44pt 热区和语义。\n'
          '${failures.join('\n')}',
    );
  });
}
