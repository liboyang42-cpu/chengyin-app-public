// CyBadge 的计数文字必须走 token,不许硬编码白色。
//
// ★ 为什么单独立一条:`test/theme/contrast_test.dart` 已经断言「状态色上深字优于
//   白字」,但那条只管**token 之间的关系**,管不到某个组件有没有真的用那个 token。
//   CyBadge 此前就是硬编码 `Colors.white` —— 通用对比度守卫全绿,组件照样是错的。
//   闸放在错的层 = 恒绿。这条把闸放到组件本身。
//
// 对齐依据:小程序 `components/cy/badge/index.wxss:16`
//   `.bd__count { color: var(--cy-comp-oncover-fg) }`
// 实测依据:danger 底 #E5484D 上,白字 3.91(低于 AA 正文 4.5)、深字 5.06;
//   badge 是 micro 字号,小字比正文更吃亏。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/core/widgets/cy_widgets.dart';

void main() {
  testWidgets('CyBadge 计数文字用 onCoverFg,不是白色', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: CyBadge(count: 3))),
      ),
    );

    final Text text = tester.widget<Text>(find.text('3'));
    expect(
      text.style?.color,
      CyTokens.onCoverFg,
      reason: '若这条红了,先看 contrast_test 的「深字优于白字」是否也红 —— '
          '那条还绿就说明是组件改错了,不是 token 该改',
    );
    expect(text.style?.color, isNot(const Color(0xFFFFFFFF)));
  });
}
