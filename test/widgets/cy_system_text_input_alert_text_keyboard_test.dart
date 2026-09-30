import 'dart:io';

import 'package:chengyin_app/core/widgets/cy_system_text_input_alert.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TextAlertHost extends StatelessWidget {
  const _TextAlertHost();

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      onPressed: () => showCySystemTextInputAlert(
        context: context,
        title: '输入答案',
        placeholder: '支持中文',
        confirmText: '确定',
        keyboardKind: CySystemKeyboardKind.text,
      ),
      child: const Text('打开'),
    );
  }
}

void main() {
  testWidgets('普通文本允许中文输入和系统纠错', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: _TextAlertHost()));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final CupertinoTextField field = tester.widget(
      find.byType(CupertinoTextField),
    );
    expect(field.keyboardType, TextInputType.text);
    expect(field.autocorrect, isTrue);
    expect(field.enableSuggestions, isTrue);
  });

  test('iOS bridge 将 text 映射到 UIKeyboardType.default', () {
    final String source = File(
      'ios/Runner/AppDelegate.swift',
    ).readAsStringSync();
    expect(source, contains('case "text": field.keyboardType = .default'));
  });

  test('iOS bridge 的 Done 键会提交当前输入且只回传一次', () {
    final String source = File(
      'ios/Runner/AppDelegate.swift',
    ).readAsStringSync();

    expect(source, contains('UITextFieldDelegate'));
    expect(source, contains('field.delegate ='));
    expect(source, contains('func textFieldShouldReturn'));
    expect(source, contains('guard !didComplete else { return }'));
  });
}
