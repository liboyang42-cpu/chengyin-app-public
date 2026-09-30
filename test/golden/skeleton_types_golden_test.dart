// CySkeleton 真源补档的「加载中」态渲染台取景。
//
// 每张图 = 一档骨架在 390×844(iPhone 主流档)视口下的加载态实拍。
// 数据源没有任何 Mock:骨架屏本身就是「还没有数据」的形态。
// 与 skeleton_golden_test(小屏溢出回归)分工不同,这里只核几何观感。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/widgets/status_view.dart';

import 'golden_theme.dart';

// ★ 文件名必须整串字面量出现(`no_orphan_goldens_test` 按字面量反查引用):
//   写成 'goldens/$name.png' 拼接会让这 7 张图被那道闸判成孤儿基线。
const List<(CySkeletonType, String, int)> kShots =
    <(CySkeletonType, String, int)>[
      (CySkeletonType.amount, 'skeleton_amount.png', 1),
      (CySkeletonType.formSection, 'skeleton_form_section.png', 4),
      (CySkeletonType.ticket, 'skeleton_ticket.png', 1),
      (CySkeletonType.merchantMetric, 'skeleton_merchant_metric.png', 3),
      (CySkeletonType.routeTimeline, 'skeleton_route_timeline.png', 4),
      (CySkeletonType.mapCard, 'skeleton_map_card.png', 2),
      (CySkeletonType.postCard, 'skeleton_post_card.png', 2),
    ];

void main() {
  for (final (CySkeletonType type, String name, int count) in kShots) {
    testWidgets('渲染台:${name.replaceAll('.png', '')} 加载中取景', (
      WidgetTester tester,
    ) async {
      setGoldenViewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          theme: goldenTheme(),
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: CySkeleton(type: type, count: count),
          ),
        ),
      );
      // 无限循环微光不能 pumpAndSettle;固定推进到中段。
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$name'),
      );
    });
  }
}
