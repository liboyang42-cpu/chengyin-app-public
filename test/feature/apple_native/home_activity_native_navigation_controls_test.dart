import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('首页主题流切换与重试使用 Cupertino 控件', () {
    final String source = File(
      'lib/feature/feed/feed_page.dart',
    ).readAsStringSync();
    // 分段自 a37cbb1f(#332)换共用件 CyTabs:页面不再自带 CupertinoSlidingSegmentedControl
    // (旧 `<bool>` 断言自该 commit 起必红),分段由共用层持有 —— iOS 26+ 原生玻璃分段、
    // 旧系统回退 CupertinoSlidingSegmentedControl,那两层归 cy_tabs.dart 的门禁
    // (test/no_material_segmented_test.dart · test/widgets/cy_tabs_test.dart)。
    expect(source, contains('CyTabs('));
    expect(source, isNot(contains('CupertinoSlidingSegmentedControl')));
    expect(source, contains('CupertinoActivityIndicator('));
    expect(source, contains('CupertinoButton('));
    expect(source, isNot(contains('TextButton(')));
  });

  test('活动目录的官方活动入口使用 Apple 按钮', () {
    final String source = File(
      'lib/feature/activity/activity_list_page.dart',
    ).readAsStringSync();
    expect(source, contains('CupertinoButton('));
    expect(source, isNot(contains('TextButton(')));
  });
}
