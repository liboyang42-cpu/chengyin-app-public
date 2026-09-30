// 时间线里的「展开全文」要真的展开,而且不许被卡片本身的点击吃掉。
//
// ★ 卡片正文整块是「点进详情」的按钮,展开钮长在它里面 ——
//   这是嵌套点击区最容易出错的地方:点展开却跳进了详情页。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/theme/cy_palette.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/feature/square/square_list_page.dart';

void main() {
  testWidgets('点「展开全文」只展开,不触发卡片进详情', (WidgetTester tester) async {
    int replies = 0;
    final String long = List<String>.generate(
      9,
      (int i) => '第 $i 段:沿苏州河走到昌平路,风比昨天轻。',
    ).join('\n');
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: <ThemeExtension<dynamic>>[CyPalette.dark]),
        home: Scaffold(
          body: SquareThreadItem(
            post: SquarePost(id: 5, memberId: 11, contents: long),
            busy: false,
            onReply: () => replies++,
            onLike: () {},
            onShare: (_) {},
            onMore: () {},
          ),
        ),
      ),
    );

    expect(find.text('展开全文'), findsOneWidget);
    await tester.tap(find.byKey(const Key('square-content-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('收起'), findsOneWidget);
    expect(find.text('第 8 段:沿苏州河走到昌平路,风比昨天轻。'), findsOneWidget);
    expect(replies, 0, reason: '展开钮的点击不该冒泡到卡片上');
  });
}
