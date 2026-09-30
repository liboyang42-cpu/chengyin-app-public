import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _rawMaterialMerchantAction = RegExp(
  r'\b(FilledButton|OutlinedButton|TextButton|IconButton|ElevatedButton|'
  r'FloatingActionButton|CircularProgressIndicator|InkWell)\s*(?:\.|<|\()',
);

List<String> _violations(String source) => _rawMaterialMerchantAction
    .allMatches(source)
    .map((Match match) => match.group(1)!)
    .toList(growable: false);

void main() {
  test('负控：商家页 Material 动作门禁会抓到违规控件', () {
    expect(
      _violations(
        'FilledButton(); OutlinedButton.icon(); TextButton(); IconButton(); '
        'ElevatedButton(); FloatingActionButton(); '
        'CircularProgressIndicator(); InkWell();',
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
      ],
    );
    expect(
      _violations(
        'CyNativeButton(); CupertinoButton(); CupertinoActivityIndicator(); '
        'GestureDetector();',
      ),
      isEmpty,
    );
  });

  test('商家功能页只使用 Apple 原生动作、加载与点击反馈', () {
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
          '主 CTA 用 CyNativeButton，常规/图标动作用 CupertinoButton，'
          '加载用 CupertinoActivityIndicator；卡片点击保留语义与至少 44pt 热区。\n'
          '${failures.join('\n')}',
    );
  });
}
