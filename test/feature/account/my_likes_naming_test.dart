// 「收藏」这个词在整页里只能有一个说法。
//
// ★★ 原来标题叫「我的喜欢」,而同一页的空态写的是「还没有**收藏**」,
//   用户在主题详情页点的按钮也叫收藏 —— 一个面上两个名字。
//   这类不一致看不出报错、测试也不会红,但它让人怀疑自己点错了地方。

import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'dart:io';

import '../../support/source_text.dart';

void main() {
  test('★★ 同一页里不许「喜欢」和「收藏」混着叫', () {
    final resources = jsonDecode(File('lib/l10n/app_zh.arb').readAsStringSync()) as Map<String, dynamic>;
    final visible = resources.entries.where((entry) => entry.key.startsWith('likes') && entry.value is String)
        .map((entry) => entry.value as String).toList();
    expect(visible, isNotEmpty, reason: '一条中文字面量都没抽到 —— 断言写法失效了');
    final bool hasLike = visible.any((String s) => s.contains('喜欢'));
    expect(
      hasLike,
      isFalse,
      reason:
          '页面上还留着「喜欢」的说法,而空态与详情页按钮都叫「收藏」:\n'
          '${visible.where((String s) => s.contains('喜欢')).toList()}',
    );
  });

  test('★ 取消收藏必须先确认 —— 误触一下就没了', () {
    final String src = codeOf('lib/feature/account/my_likes_page.dart');
    expect(src.contains('cyConfirm'), isTrue);
    // ⚠️ 后端是切换语义,失败后自动重试会把状态翻回去。
    final int unlikeStart = src.indexOf('Future<void> _unlike(');
    final int unlikeEnd = src.indexOf('Future<void> _share(', unlikeStart);
    expect(unlikeStart, greaterThanOrEqualTo(0));
    expect(unlikeEnd, greaterThan(unlikeStart));
    final String unlikeBody = src.substring(unlikeStart, unlikeEnd);
    expect(
      unlikeBody.contains('retry') || unlikeBody.contains('重试'),
      isFalse,
      reason: '切换式接口不许自动重试 —— 重试会把刚取消的又收藏回来',
    );
  });
}
