import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NPC 对话承载与输入操作使用 Cupertino 控件', () {
    final String source = File(
      'lib/feature/npc/widgets/npc_chat_sheet.dart',
    ).readAsStringSync();

    expect(source, contains('showCupertinoSheet<void>'));
    expect(source, contains('CupertinoPageScaffold('));
    expect(source, contains('CupertinoTextField('));
    expect(
      RegExp(r'\bCupertinoButton\(').allMatches(source).length,
      greaterThanOrEqualTo(2),
    );
    expect(source, isNot(contains('showModalBottomSheet')));
  });

  test('模板预览使用 Cupertino Sheet 和系统操作按钮', () {
    final String source = File(
      'lib/feature/template/template_list_page.dart',
    ).readAsStringSync();

    expect(source, contains('showCupertinoSheet<void>'));
    expect(source, contains('CupertinoPageScaffold('));
    expect(source, isNot(contains('showModalBottomSheet')));
    expect(
      source,
      isNot(contains("OutlinedButton(\n                  onPressed: onClose")),
    );
    expect(
      source,
      isNot(
        contains(
          "FilledButton(\n                  key: const Key('template-preview-open-detail')",
        ),
      ),
    );
  });
}
