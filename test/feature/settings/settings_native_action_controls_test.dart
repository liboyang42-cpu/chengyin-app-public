import 'package:flutter_test/flutter_test.dart';

import '../../support/source_text.dart';

void main() {
  test('设置页的动作热区使用原生按钮或原生开关', () {
    final String source = codeOf('lib/feature/settings/settings_page.dart');
    final String about = codeOf('lib/feature/settings/about_page.dart');

    expect(RegExp(r'\bOutlinedButton\b').hasMatch(source), isFalse);
    expect(RegExp(r'\bIconButton\b').hasMatch(source), isFalse);
    expect(RegExp(r'\bInkWell\b').hasMatch(source), isFalse);
    expect(source, contains('CyNativeButton('));
    expect(source, contains('CupertinoButton('));
    expect(source, contains('AppleLiquidSwitch('));
    expect(source, contains('CupertinoSwitch('));
    expect(RegExp(r'\bInkWell\b').hasMatch(about), isFalse);
    expect(about, contains('CupertinoButton('));
  });
}
