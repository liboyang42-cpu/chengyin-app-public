// CySkeleton `list` 档门禁:几何 1:1 对齐真源
// `chengyinhub-xcx/components/cy/skeleton`(`type="list"` 缺省档):
//   .sk-row   = 上下内衬 12pt(space3) + 底部 0.5pt 分隔线,行与行首尾相接无间隙
//   .sk-avatar= 88rpx = 44pt 圆
//   两行文字条 = 高 14pt(space3-5),宽 50% / 80%,行间隔 8pt(space2)
// count 生效;切回 card 不残留 list 几何。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/widgets/status_view.dart';

Finder _findSkAvatar() {
  return find.byWidgetPredicate(
    (Widget w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration! as BoxDecoration).shape == BoxShape.circle,
  );
}

double _rowPitch(WidgetTester tester, int index) {
  // 相邻两行头像圆心的垂直距离 = 行高(68 + 0.5 边框)。
  final Rect a = tester.getRect(_findSkAvatar().at(index));
  final Rect b = tester.getRect(_findSkAvatar().at(index + 1));
  return b.center.dy - a.center.dy;
}

void main() {
  Future<void> pumpSkeleton(
    WidgetTester tester,
    CySkeletonType type,
    int count,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: CySkeleton(type: type, count: count),
          ),
        ),
      ),
    );
    // 骨架微光是无限循环动画,pumpAndSettle 会超时;推进固定一帧即可。
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('list 档:count 决定行数,不溢出', (WidgetTester tester) async {
    await pumpSkeleton(tester, CySkeletonType.list, 4);
    expect(tester.takeException(), isNull);
    expect(_findSkAvatar(), findsNWidgets(4));
  });

  testWidgets('list 档:行几何 44pt 圆 + 50%/80% 两行 + 首尾相接', (
    WidgetTester tester,
  ) async {
    await pumpSkeleton(tester, CySkeletonType.list, 3);

    final Rect avatar = tester.getRect(_findSkAvatar().first);
    expect(avatar.width, 44);
    expect(avatar.height, 44);

    // 两条文字条:宽 50% / 80%,高 14pt。行可用宽 = 390 - 2*16(pageX) - 44 - 12(space3)。
    final double mainW = 390 - 2 * 16 - 44 - 12;
    final List<FractionallySizedBox> bars = tester
        .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .where((FractionallySizedBox b) => b.widthFactor != 1.0)
        .toList();
    // 每行 2 条非整宽 bar。
    expect(bars.length, 3 * 2);
    expect(bars[0].widthFactor, 0.5);
    expect(bars[1].widthFactor, 0.8);
    final Rect line1 = tester.getRect(find.byWidget(bars[0]));
    final Rect line2 = tester.getRect(find.byWidget(bars[1]));
    expect(line1.width, moreOrLessEquals(mainW * 0.5, epsilon: 0.5));
    expect(line2.width, moreOrLessEquals(mainW * 0.8, epsilon: 0.5));
    expect(line1.height, 14);
    expect(line2.height, 14);
    // 两行文字条间隔 8pt。
    expect(line2.top - line1.bottom, 8);

    // 行pitch = 12 + 44 + 12 + 0.5(分隔线) = 68.5。
    expect(_rowPitch(tester, 0), moreOrLessEquals(68.5, epsilon: 0.01));
    expect(_rowPitch(tester, 1), moreOrLessEquals(68.5, epsilon: 0.01));
  });

  testWidgets('档切换:list→card 几何随档变化,无残留', (WidgetTester tester) async {
    await pumpSkeleton(tester, CySkeletonType.list, 4);
    expect(_findSkAvatar(), findsNWidgets(4));

    await pumpSkeleton(tester, CySkeletonType.card, 4);
    expect(tester.takeException(), isNull);
    // card 档没有圆头像,而是 96pt 封面块。
    expect(_findSkAvatar(), findsNothing);
    final Iterable<FractionallySizedBox> fullBars = tester
        .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .where((FractionallySizedBox b) => b.widthFactor == 1.0);
    expect(fullBars, isNotEmpty);
  });
}
