import 'dart:io';

import 'package:chengyin_app/core/widgets/cy_system_text_input_alert.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      onPressed: () => showCySystemTextInputAlert(
        context: context,
        title: '手动输入核销码',
        placeholder: '玩家出示的那串字符',
        confirmText: '核销',
        keyboardKind: CySystemKeyboardKind.ascii,
      ),
      child: const Text('打开'),
    );
  }
}

void main() {
  testWidgets('核销码回退弹层是 Cupertino 输入 Alert', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Host()));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.byType(CupertinoTextField), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    final CupertinoTextField field = tester.widget(
      find.byType(CupertinoTextField),
    );
    expect(field.keyboardType, TextInputType.visiblePassword);
    expect(field.textInputAction, TextInputAction.done);
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
  });

  test('两个核销页共用系统输入 Alert，不再自建 Material Dialog', () {
    for (final String path in <String>[
      'lib/feature/merchant/merchant_scan_page.dart',
      'lib/feature/merchant/city_node_redeem_page.dart',
    ]) {
      final String source = File(path).readAsStringSync();
      expect(source, contains('showCySystemTextInputAlert('));
      expect(source, isNot(contains('AlertDialog(')));
    }
  });
}
