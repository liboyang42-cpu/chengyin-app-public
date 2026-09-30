import 'package:chengyin_app/core/widgets/cy_native_notice.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(CyNativeNotice.hide);

  testWidgets('通知使用 Cupertino 表面并向 VoiceOver 实时播报', (
    WidgetTester tester,
  ) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (BuildContext context) {
            pageContext = context;
            return const CupertinoPageScaffold(child: SizedBox.expand());
          },
        ),
      ),
    );

    CyNativeNotice.show(pageContext, '已保存');
    await tester.pump();

    expect(find.byType(CupertinoPopupSurface), findsOneWidget);
    final Semantics semantics = tester.widget(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Semantics && widget.properties.liveRegion == true,
      ),
    );
    expect(semantics.properties.label, '已保存');
    CyNativeNotice.hide();
    await tester.pump();
  });

  testWidgets('减弱动态效果时通知入场时长为零', (WidgetTester tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: CupertinoApp(
          home: Builder(
            builder: (BuildContext context) {
              pageContext = context;
              return const CupertinoPageScaffold(child: SizedBox.expand());
            },
          ),
        ),
      ),
    );

    CyNativeNotice.show(pageContext, '已完成');
    await tester.pump();

    final TweenAnimationBuilder<double> animation = tester.widget(
      find.byType(TweenAnimationBuilder<double>),
    );
    expect(animation.duration, Duration.zero);
    CyNativeNotice.hide();
    await tester.pump();
  });

  testWidgets('可操作通知保留撤销等原有业务入口', (WidgetTester tester) async {
    late BuildContext pageContext;
    bool invoked = false;
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (BuildContext context) {
            pageContext = context;
            return const CupertinoPageScaffold(child: SizedBox.expand());
          },
        ),
      ),
    );

    CyNativeNotice.show(
      pageContext,
      '已删除',
      actionLabel: '撤销',
      onAction: () => invoked = true,
    );
    await tester.pump();
    await tester.tap(find.text('撤销'));
    await tester.pump();

    expect(invoked, isTrue);
    expect(find.text('已删除'), findsNothing);
  });

  testWidgets('可操作通知不会在默认 2.4 秒内消失', (WidgetTester tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (BuildContext context) {
            pageContext = context;
            return const CupertinoPageScaffold(child: SizedBox.expand());
          },
        ),
      ),
    );

    CyNativeNotice.show(pageContext, '已删除', actionLabel: '撤销', onAction: () {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2500));

    expect(find.text('已删除'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 3500));
    expect(find.text('已删除'), findsNothing);
  });

  testWidgets('VoiceOver 可访问模式为可操作通知保留更长时间', (WidgetTester tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(accessibleNavigation: true),
        child: CupertinoApp(
          home: Builder(
            builder: (BuildContext context) {
              pageContext = context;
              return const CupertinoPageScaffold(child: SizedBox.expand());
            },
          ),
        ),
      ),
    );

    CyNativeNotice.show(pageContext, '已删除', actionLabel: '撤销', onAction: () {});
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));

    expect(find.text('已删除'), findsOneWidget);
    await tester.pump(const Duration(seconds: 24));
    expect(find.text('已删除'), findsNothing);
  });
}
