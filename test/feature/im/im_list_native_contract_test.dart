import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('IM 会话菜单使用单个原生 action sheet，不在列表堆 platform view', () {
    final String source = File(
      'lib/feature/im/im_list_page.dart',
    ).readAsStringSync();

    expect(source, contains('LiquidGlassAlertStyle.actionSheet'));
    expect(source, contains('CupertinoActionSheet'));
    expect(source, contains('on MissingPluginException'));
    expect(source, contains('on PlatformException'));
    expect(source, isNot(contains('LiquidGlassMenu')));
    expect(source, isNot(contains('showModalBottomSheet')));
  });
}
