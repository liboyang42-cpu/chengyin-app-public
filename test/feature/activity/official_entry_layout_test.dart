// 「官方活动」入口(nav bar trailing)必须完整可见 —— B1 §3.7 P2 回归锁。
//
// ★ 模拟器实拍(b1-sim-play-4 截图 03/18/19/20,四轮仍存):右上角「官方活动」
//   被裁半截,只有下半截字露出来。
// ★ 根因:裸 Text 吃导航栏默认样式(17pt、行高由字体度量给),按钮又带默认
//   6pt 内衬 —— 文字墨迹会不会被导航栏内容裁剪削掉,取决于真机字体行高的
//   巧合,widget 层没有任何保证。
// ★ 修法:文字盒占满导航栏 44pt 整带、按钮内衬归零、行高显式 ≥1em。
//   本测试锁这三条几何不变量。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/feature/activity/activity_controller.dart';
import 'package:chengyin_app/feature/activity/activity_list_page.dart';

import '../../golden/golden_theme.dart';

void main() {
  testWidgets('§3.7 官方活动入口不被顶边裁:整带居中、行盒装得下字号', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          activityListProvider.overrideWith((ref) async => const <Activity>[]),
        ].cast(),
        child: MaterialApp(
          theme: goldenTheme(),
          debugShowCheckedModeBanner: false,
          home: const ActivityListPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final entry = find.byKey(const Key('activities-official-entry'));
    expect(entry, findsOneWidget);
    final text = find.descendant(of: entry, matching: find.text('官方活动'));

    // ① 入口整体(含 44pt 触控高度)必须落在导航栏矩形内 —— 越界即被裁。
    final Rect barRect = tester.getRect(find.byType(CupertinoNavigationBar));
    final Rect entryRect = tester.getRect(entry);
    expect(
      entryRect.top,
      greaterThanOrEqualTo(barRect.top),
      reason: '入口顶边越出导航栏,会被裁',
    );
    expect(entryRect.bottom, lessThanOrEqualTo(barRect.bottom));

    // ② 按钮不许有默认内衬:文字盒必须占满 44pt 整带。
    final CupertinoButton button = tester.widget(entry);
    expect(
      button.padding,
      EdgeInsets.zero,
      reason: '默认 6pt 内衬会把文字盒压到 32pt,墨迹溢出后吃裁剪',
    );

    // ③ 行高显式 ≥1em:行盒才装得下 CJK 墨迹(墨迹 ≈ 1em = 字号)。
    final TextStyle textStyle = DefaultTextStyle.of(
      tester.element(text),
    ).style.merge(tester.widget<Text>(text).style);
    expect(
      textStyle.height ?? 0,
      greaterThanOrEqualTo(1.0),
      reason: '行高不设 ≥1em 时,行盒由字体度量给,真机(CJK)装不下墨迹',
    );

    // ④ 文字在整带里居中:文字盒中心 = 导航栏带中心(±1pt)。
    final Rect textBox = tester.getRect(text);
    expect(
      (textBox.center.dy - barRect.center.dy).abs(),
      lessThan(1.0),
      reason: '文字没在导航栏整带里居中,顶/底留白不对称',
    );
  });
}
