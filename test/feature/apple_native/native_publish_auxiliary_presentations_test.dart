import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const files = <String>[
    'lib/feature/square/square_compose_page.dart',
    'lib/feature/publish/ai_draft_sheet.dart',
    'lib/feature/publish/publish_pro_story_editor.dart',
    'lib/feature/publish/collaborator_picker.dart',
  ];

  test('发布辅助层使用 Cupertino 系统呈现而非 Material bottom sheet', () {
    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('showModalBottomSheet')), reason: path);
      expect(source, contains('Cupertino'), reason: path);
    }
  });

  test('三个富内容弹层使用官方 showCupertinoSheet 和页级语义', () {
    for (final path in files.skip(1)) {
      final source = File(path).readAsStringSync();
      expect(source, contains('showCupertinoSheet'), reason: path);
      expect(source, contains('CupertinoPageScaffold'), reason: path);
    }
  });

  test('可编辑内容使用 CupertinoTextField 以接入 iOS 系统键盘', () {
    for (final path in <String>[files[0], files[1], files[2]]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('CupertinoTextField'), reason: path);
    }
  });
}
