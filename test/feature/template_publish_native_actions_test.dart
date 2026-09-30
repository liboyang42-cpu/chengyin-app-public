import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _materialAction = RegExp(
  r'\b(FilledButton|OutlinedButton|TextButton|IconButton|ElevatedButton|'
  r'FloatingActionButton|CircularProgressIndicator|InkWell)\s*(?:\.|<|\()',
);

List<String> _findMaterialActions(String source) => _materialAction
    .allMatches(source)
    .map((Match match) => match.group(1)!)
    .toList(growable: false);

void main() {
  test('负控：模板与发布的 Material 动作门禁能变红', () {
    expect(
      _findMaterialActions(
        'FilledButton(); OutlinedButton.icon(); TextButton(); IconButton(); '
        'ElevatedButton(); FloatingActionButton(); '
        'CircularProgressIndicator(); InkWell();',
      ),
      hasLength(8),
    );
    expect(
      _findMaterialActions(
        'CyNativeButton(); CupertinoButton(); CupertinoActivityIndicator();',
      ),
      isEmpty,
    );
  });

  test('模板与发布页使用原生动作、加载和点击控件', () {
    final List<String> failures = <String>[];
    for (final String folder in <String>[
      'lib/feature/template',
      'lib/feature/publish',
    ]) {
      for (final FileSystemEntity entity in Directory(
        folder,
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final List<String> found = _findMaterialActions(
          entity.readAsStringSync(),
        );
        if (found.isNotEmpty) {
          failures.add('${entity.path}: ${found.join(', ')}');
        }
      }
    }

    expect(
      failures,
      isEmpty,
      reason:
          '主要提交使用 CyNativeButton，图标/次要动作用 CupertinoButton，'
          '加载使用 CupertinoActivityIndicator，可点内容需要无墨水点击层。\n'
          '${failures.join('\n')}',
    );
  });
}
