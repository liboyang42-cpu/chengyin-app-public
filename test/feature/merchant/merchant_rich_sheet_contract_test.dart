import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const List<String> files = <String>[
    'lib/feature/merchant/topic_chapter_applications_page.dart',
    'lib/feature/merchant/ai_node_assist.dart',
    'lib/feature/merchant/merchant_recruit_sheets.dart',
  ];

  test('商家富内容弹层使用 Flutter 官方 Cupertino sheet', () {
    for (final String path in files) {
      final String source = File(path).readAsStringSync();
      expect(source, contains('showCupertinoSheet'), reason: path);
      expect(source, contains('CupertinoPageScaffold'), reason: path);
      expect(source, isNot(contains('showModalBottomSheet')), reason: path);
    }
  });

  test('表单使用 CupertinoTextField 接入 iOS 系统键盘', () {
    for (final String path in <String>[files.first, files.last]) {
      final String source = File(path).readAsStringSync();
      expect(source, contains('CupertinoTextField'), reason: path);
    }
  });

  test('所有弹层主操作显式保留 44pt 命中区', () {
    for (final String path in files) {
      final String source = File(path).readAsStringSync();
      expect(source, contains('Size.fromHeight(44)'), reason: path);
    }
  });
}
