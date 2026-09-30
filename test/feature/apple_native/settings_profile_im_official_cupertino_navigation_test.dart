import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('设置、他人主页、聊天、官方邀约和真实商城页面使用 iOS 导航壳', () {
    const List<String> paths = <String>[
      'lib/feature/settings/settings_page.dart',
      'lib/feature/profile/user_profile_page.dart',
      'lib/feature/im/im_chat_page.dart',
      'lib/feature/official/official_inbox_page.dart',
      'lib/feature/mall/product_list_page.dart',
      'lib/feature/mall/product_detail_page.dart',
      'lib/feature/mall/cart_page.dart',
    ];

    for (final String path in paths) {
      final String source = File(path).readAsStringSync();
      expect(source, contains('CupertinoPageScaffold('), reason: path);
      expect(source, contains('CupertinoNavigationBar('), reason: path);
      expect(source, isNot(contains('return Scaffold(')), reason: path);
      expect(source, isNot(contains('appBar: AppBar(')), reason: path);
    }
  });

  test('聊天页保留 VoiceOver 拉黑动作和系统键盘自适应', () {
    final String source = File(
      'lib/feature/im/im_chat_page.dart',
    ).readAsStringSync();

    expect(source, contains("label: '拉黑此人'"));
    expect(source, contains('resizeToAvoidBottomInset: true'));
    expect(source, contains('CupertinoTextField('));
  });
}
