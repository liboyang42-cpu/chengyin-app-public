// CySkeleton 在**小屏 + 多卡**下不许溢出。
//
// ★ 为什么补这条:`goldens/skeleton.png` 一直是张**孤儿基线** —— 没有任何测试引用它,
//   于是它停在 `2aeb960` 那一刻的样子(底部一条黄黑斜纹 = RenderFlex overflow),
//   而溢出早在 `ba0c3ce` 就按根因修掉了(骨架容器从 Column 换成 ListView)。
//   陈旧证据比没有证据更贵:复核时我正是被这张图误导,以为「标了 ✅ 的修复没生效」。
//   本文件把这张基线接管过来,让它随代码走。
//
// 取景刻意选**小屏**:骨架高度 = count × 卡片高,溢出只在高度不够时才现形;
// 用大屏拍这张图等于永远不会红。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/widgets/status_view.dart';

import 'golden_theme.dart';

void main() {
  testWidgets('骨架:小屏多卡不溢出', (WidgetTester tester) async {
    // 360×420 比任何在售机型都矮,专门把「装不下」这件事逼出来。
    setGoldenViewport(tester, const Size(360, 420));

    await tester.pumpWidget(
      MaterialApp(
        theme: goldenTheme(),
        debugShowCheckedModeBanner: false,
        home: const Scaffold(body: CySkeleton(count: 6)),
      ),
    );
    // 骨架的微光是**无限循环**动画,pumpAndSettle 会一直等不到静止而超时;
    // 固定推进一帧到动画中段即可,取景稳定也便于比对。
    await tester.pump(const Duration(milliseconds: 300));

    // ★ 先断言「没有溢出异常」,再拍图。图能看出黄黑条纹,但看图是人的事;
    //   这条断言让 CI 无人值守时也能红。
    expect(tester.takeException(), isNull);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/skeleton.png'),
    );
  });

  // list 档(真源 `type="list"` 缺省档):头像行鱼骨,首尾相接带分隔线。
  testWidgets('骨架:list 档行几何', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 480));

    await tester.pumpWidget(
      MaterialApp(
        theme: goldenTheme(),
        debugShowCheckedModeBanner: false,
        home: const Scaffold(
          body: CySkeleton(type: CySkeletonType.list, count: 4),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/skeleton_list.png'),
    );
  });
}
