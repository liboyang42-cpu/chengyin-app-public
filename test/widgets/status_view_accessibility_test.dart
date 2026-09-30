import 'package:chengyin_app/core/widgets/status_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('错误与空态消息以唯一 live region 播报', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();

    await tester.pumpWidget(
      const CupertinoApp(
        home: CupertinoPageScaffold(
          child: StatusView(message: '网络开小差了', sub: '请稍后重试'),
        ),
      ),
    );

    final Iterable<Semantics> liveRegions = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((Semantics widget) => widget.properties.liveRegion == true);
    expect(liveRegions, hasLength(1));
    expect(liveRegions.single.properties.label, '网络开小差了。请稍后重试');
    handle.dispose();
  });

  testWidgets('LoadingView 以唯一 live region 播报正在加载', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();

    await tester.pumpWidget(
      const CupertinoApp(home: CupertinoPageScaffold(child: LoadingView())),
    );

    expect(find.bySemanticsLabel('正在加载'), findsOneWidget);
    final Iterable<Semantics> liveRegions = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((Semantics widget) => widget.properties.liveRegion == true);
    expect(liveRegions, hasLength(1));
    expect(liveRegions.single.properties.label, '正在加载');
    handle.dispose();
  });

  testWidgets('减弱动态效果时骨架屏停止持续调度帧', (WidgetTester tester) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: CupertinoPageScaffold(child: CySkeleton(count: 1)),
        ),
      ),
    );

    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 1),
    );

    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('正常模式下骨架屏仍持续呼吸', (WidgetTester tester) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: CupertinoPageScaffold(child: CySkeleton(count: 1)),
      ),
    );

    final Finder opacityFinder = find.descendant(
      of: find.byType(CySkeleton),
      matching: find.byType(Opacity),
    );
    final double initialOpacity = tester.widget<Opacity>(opacityFinder).opacity;
    await tester.pump(const Duration(milliseconds: 350));
    final double advancedOpacity = tester
        .widget<Opacity>(opacityFinder)
        .opacity;

    expect(advancedOpacity, greaterThan(initialOpacity));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
