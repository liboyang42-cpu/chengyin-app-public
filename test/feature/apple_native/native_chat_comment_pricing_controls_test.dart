import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/feature/topic/topic_pricing_page.dart';

void main() {
  test('主题定价页仍保留公开 topicId 入口', () {
    expect(const TopicPricingPage(topicId: 17).topicId, 17);
  });

  test('私信与评论输入使用 CupertinoTextField 和系统发送按钮', () {
    for (final String path in <String>[
      'lib/feature/im/im_chat_page.dart',
      'lib/feature/square/square_detail_page.dart',
    ]) {
      final String source = File(path).readAsStringSync();
      expect(source, contains('CupertinoTextField('), reason: path);
      expect(source, contains('CupertinoButton('), reason: path);
      expect(
        RegExp(r'(?<!Cupertino)\bTextField\(').hasMatch(source),
        isFalse,
        reason: path,
      );
    }
  });

  test('主题定价使用 Apple 分段、输入、滑杆和操作控件', () {
    final String source = File(
      'lib/feature/topic/topic_pricing_page.dart',
    ).readAsStringSync();

    // 分段走共用层 CyTabs(26+ 原生玻璃分段、旧系统回退
    // CupertinoSlidingSegmentedControl),那两层归 cy_tabs.dart 的门禁
    // (test/no_material_segmented_test.dart · test/widgets/cy_tabs_test.dart),
    // 页面侧只核「用了共用件、没自带裸控件」。
    expect(source, contains('CyTabs('));
    expect(source, contains('CyTabsVariant.segmented'));
    expect(source, isNot(contains('CupertinoSlidingSegmentedControl')));
    expect(RegExp(r'\bCupertinoTextField\(').allMatches(source).length, 2);
    expect(source, contains('CupertinoSlider('));
    expect(
      RegExp(r'\bCupertinoButton\(').allMatches(source).length,
      greaterThanOrEqualTo(2),
    );
    expect(source, isNot(contains('FilledButton(')));
    expect(source, isNot(contains('OutlinedButton(')));
  });
}
