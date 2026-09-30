import 'package:chengyin_app/core/widgets/cy_scratch.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// `cy-scratch` 的门禁。判据来自真源 `pages/play/components/scratch/` 与
/// `utils/scratch-progress.js` —— 那里把「算得对不对」抽成了纯函数,
/// 理由写得明白:「它在组件里被 canvas 与触摸事件包着,放在那儿等于永远测不到」。
///
/// ★ 无障碍那三条是**硬边界**,不是加分项:内容是运动能力不可达内容的风险,
///   比刮不动的风险大得多。
void main() {
  group('纯逻辑', () {
    test('擦除占比 = 已擦点数 / 总点数', () {
      expect(cyScratchProgress(0), 0);
      expect(cyScratchProgress(64), closeTo(0.25, 1e-9));
      expect(cyScratchProgress(256), 1);
      // 网格退化时不返回 NaN
      expect(cyScratchProgress(10, grid: 0), 0);
    });

    test('阈值缺失/非法退回 0.45,而不是 0', () {
      // 真源原文:「退回 0 会让『碰一下就揭示』,正是稿要避免的纯点击领奖」
      expect(cyScratchShouldReveal(0.44, 0), isFalse);
      expect(cyScratchShouldReveal(0.45, 0), isTrue);
      expect(cyScratchShouldReveal(0.44, double.nan), isFalse);
      expect(cyScratchShouldReveal(0.44, 1.5), isFalse);
      expect(cyScratchShouldReveal(0.45, 1.5), isTrue);
      // 正常阈值
      expect(cyScratchShouldReveal(0.54, 0.55), isFalse);
      expect(cyScratchShouldReveal(0.55, 0.55), isTrue);
      // 负进度当 0
      expect(cyScratchShouldReveal(-1, 0.4), isFalse);
    });

    test('笔刷盖住了哪些采样点', () {
      const Size box = Size(160, 160);
      // 笔刷在盒子外 → 一个点都没擦到
      expect(
        cyScratchCellsUnderBrush(
          center: const Offset(-50, -50),
          size: box,
          brush: 16,
        ),
        isEmpty,
      );
      // 盒子中点一下 → 擦到了一些、但不是全部
      final Set<int> single = cyScratchCellsUnderBrush(
        center: const Offset(80, 80),
        size: box,
        brush: 16,
      );
      expect(single, isNotEmpty);
      expect(single.length, lessThan(256));
      // 笔刷大到盖住整块 → 每个采样点都被擦到
      expect(
        cyScratchCellsUnderBrush(
          center: const Offset(80, 80),
          size: box,
          brush: 400,
        ).length,
        256,
      );
    });
  });

  group('无障碍边界', () {
    testWidgets('内容始终在树里 —— 遮罩不是渲染开关', (WidgetTester tester) async {
      await tester.pumpWidget(
        const _Host(
          child: CyScratch(child: Text('留给你的一句')),
        ),
      );
      // 读屏器任何时候都读得到下面那段字(真源:不「擦完才渲染」)
      expect(find.text('留给你的一句'), findsOneWidget);
      expect(find.text('直接揭示'), findsOneWidget);
    });

    testWidgets('减少动态效果 → 整层不挂,不要求擦', (WidgetTester tester) async {
      await tester.pumpWidget(
        const CupertinoApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: CyScratch(child: Text('留给你的一句')),
          ),
        ),
      );
      expect(find.text('留给你的一句'), findsOneWidget);
      // 不是「擦得快一点」,是**不要求擦** —— 直接揭示那颗也不出现
      expect(find.text('直接揭示'), findsNothing);
    });

    testWidgets('已经揭示过的内容不再盖一层雾', (WidgetTester tester) async {
      await tester.pumpWidget(
        const _Host(
          child: CyScratch(revealed: true, child: Text('昨天擦过的')),
        ),
      );
      expect(find.text('昨天擦过的'), findsOneWidget);
      expect(find.text('直接揭示'), findsNothing);
    });

    testWidgets('点「直接揭示」= 读屏用户的双击出口,揭示只报一次', (WidgetTester tester) async {
      int reveals = 0;
      await tester.pumpWidget(
        _Host(child: CyScratch(onReveal: () => reveals++, child: const Text('签文'))),
      );
      await tester.tap(find.text('直接揭示'));
      await tester.pump();
      expect(reveals, 1);
      expect(find.text('直接揭示'), findsNothing);
      // 再点一次不会重复上报(遮罩已经没了)
      expect(find.text('签文'), findsOneWidget);
    });
  });

  group('擦除判定接线', () {
    testWidgets('擦过阈值 → onReveal 一次,遮罩消失', (WidgetTester tester) async {
      int reveals = 0;
      await tester.pumpWidget(
        _Host(
          child: CyScratch(
            threshold: 0.01,
            onReveal: () => reveals++,
            child: const SizedBox(width: 200, height: 200),
          ),
        ),
      );
      expect(find.text('直接揭示'), findsOneWidget);
      final Offset center = tester.getCenter(find.byType(CyScratch));
      await tester.dragFrom(center, const Offset(60, 60));
      await tester.pump();
      expect(reveals, 1);
      expect(find.text('直接揭示'), findsNothing);
    });

    testWidgets('负控:没擦到阈值就一路盖着', (WidgetTester tester) async {
      int reveals = 0;
      await tester.pumpWidget(
        _Host(
          child: CyScratch(
            threshold: 0.99,
            brush: 4,
            onReveal: () => reveals++,
            child: const SizedBox(width: 200, height: 200),
          ),
        ),
      );
      final Offset center = tester.getCenter(find.byType(CyScratch));
      await tester.dragFrom(center, const Offset(10, 10));
      await tester.pump();
      expect(reveals, 0);
      expect(find.text('直接揭示'), findsOneWidget);
    });
  });
}

/// 不挂 reduceMotion 的宿主:遮罩在的时候那颗出口必须在。
class _Host extends StatelessWidget {
  const _Host({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => CupertinoApp(
    home: MediaQuery(
      data: const MediaQueryData(disableAnimations: false),
      child: Center(child: child),
    ),
  );
}
