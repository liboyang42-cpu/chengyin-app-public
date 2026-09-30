import 'dart:io';
import 'dart:ui' show SemanticsAction, SemanticsActionEvent, Tristate;

import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

void main() {
  test('Liquid Glass 原生图标按钮把 tooltip 传给 iOS VoiceOver', () {
    final String source = File(
      'third_party/native_liquid_glass/lib/src/liquid_glass_button.dart',
    ).readAsStringSync();
    expect(
      source,
      contains("'title': isIconOnly ? widget.tooltip : widget.label"),
    );
    expect(source, contains('widget.tooltip,'));
  });

  testWidgets('iOS 26 纯图标动作使用原生 Liquid Glass 且保留名称', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CyNativeIconButton(
          label: '关闭',
          icon: const CyNativeButtonIcon(
            sfSymbol: 'xmark',
            fallback: CupertinoIcons.xmark,
          ),
          liquidGlassSupported: true,
          onPressed: () {},
        ),
      ),
    );

    final LiquidGlassButton native = tester.widget<LiquidGlassButton>(
      find.byType(LiquidGlassButton),
    );
    expect(native.tooltip, '关闭');
    expect(native.size, 44);
    expect(native.icon, const NativeLiquidGlassIcon.sfSymbol('xmark'));
  });

  testWidgets('旧系统纯图标动作保持 44pt 与 VoiceOver 动作', (WidgetTester tester) async {
    int presses = 0;
    await tester.pumpWidget(
      _host(
        CyNativeIconButton(
          label: '关闭',
          icon: const CyNativeButtonIcon(
            sfSymbol: 'xmark',
            fallback: CupertinoIcons.xmark,
          ),
          liquidGlassSupported: false,
          onPressed: () => presses++,
        ),
      ),
    );

    expect(tester.getSize(find.byType(CyNativeIconButton)), const Size(44, 44));
    final node = tester.getSemantics(find.bySemanticsLabel('关闭'));
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.tap,
        nodeId: node.id,
        viewId: tester.view.viewId,
      ),
    );
    await tester.pump();
    expect(presses, 1);
  });

  testWidgets('iOS 26 primary button uses the native glass control', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CyNativeButton(
          label: '继续',
          presentation: CyNativeButtonPresentation.floatingGlass,
          icon: const CyNativeButtonIcon(
            sfSymbol: 'arrow.right',
            fallback: CupertinoIcons.arrow_right,
          ),
          width: 220,
          height: 52,
          liquidGlassSupported: true,
          onPressed: () {},
        ),
      ),
    );

    final LiquidGlassButton native = tester.widget<LiquidGlassButton>(
      find.byType(LiquidGlassButton),
    );
    expect(native.label, '继续');
    expect(native.width, 220);
    expect(native.height, 52);
    expect(native.style, LiquidGlassButtonStyle.prominentGlass);
    expect(native.icon, const NativeLiquidGlassIcon.sfSymbol('arrow.right'));
    expect(find.byType(CupertinoButton), findsNothing);
  });

  testWidgets('secondary and destructive roles map to system glass styles', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Column(
          children: <Widget>[
            CyNativeButton(
              label: '稍后',
              presentation: CyNativeButtonPresentation.floatingGlass,
              role: CyNativeButtonRole.secondary,
              liquidGlassSupported: true,
              onPressed: () {},
            ),
            CyNativeButton(
              label: '删除',
              presentation: CyNativeButtonPresentation.floatingGlass,
              role: CyNativeButtonRole.destructive,
              liquidGlassSupported: true,
              onPressed: () {},
            ),
          ],
        ),
      ),
    );

    final List<LiquidGlassButton> buttons = tester
        .widgetList<LiquidGlassButton>(find.byType(LiquidGlassButton))
        .toList();
    expect(buttons, hasLength(2));
    expect(buttons[0].style, LiquidGlassButtonStyle.glass);
    expect(buttons[1].style, LiquidGlassButtonStyle.glass);
    expect(buttons[0].tint, isNot(buttons[1].tint));
  });

  testWidgets('浅色页危险操作使用达 AA 的浅色 token', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.merchantLight(),
        home: Scaffold(
          body: CyNativeButton(
            label: '删除',
            role: CyNativeButtonRole.destructive,
            liquidGlassSupported: false,
            onPressed: () {},
          ),
        ),
      ),
    );

    final CupertinoButton button = tester.widget<CupertinoButton>(
      find.byType(CupertinoButton),
    );
    expect(button.foregroundColor, const Color(0xFFD0323B));
  });

  testWidgets('unsupported systems get a complete Cupertino fallback', (
    WidgetTester tester,
  ) async {
    int presses = 0;
    await tester.pumpWidget(
      _host(
        CyNativeButton(
          label: '继续',
          icon: const CyNativeButtonIcon(
            sfSymbol: 'arrow.right',
            fallback: CupertinoIcons.arrow_right,
          ),
          width: 196,
          liquidGlassSupported: false,
          onPressed: () => presses++,
        ),
      ),
    );

    expect(find.byType(LiquidGlassButton), findsNothing);
    expect(find.byType(CupertinoButton), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.arrow_right), findsOneWidget);
    expect(tester.getSize(find.byType(CyNativeButton)), const Size(196, 44));

    final node = tester.getSemantics(find.bySemanticsLabel('继续'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.tap,
        nodeId: node.id,
        viewId: tester.view.viewId,
      ),
    );
    await tester.pump();
    expect(presses, 1);
  });

  testWidgets('disabled state is announced and cannot invoke the action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const CyNativeButton(
          label: '暂不可用',
          liquidGlassSupported: false,
          onPressed: null,
        ),
      ),
    );

    final node = tester.getSemantics(find.bySemanticsLabel('暂不可用'));
    expect(node.label, '暂不可用');
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.flagsCollection.isEnabled, Tristate.isFalse);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    expect(
      tester.widget<CupertinoButton>(find.byType(CupertinoButton)).onPressed,
      isNull,
    );
  });

  testWidgets('loading is a stable disabled Cupertino progress state', (
    WidgetTester tester,
  ) async {
    int presses = 0;
    await tester.pumpWidget(
      _host(
        CyNativeButton(
          label: '提交',
          loading: true,
          liquidGlassSupported: true,
          onPressed: () => presses++,
        ),
      ),
    );

    expect(find.byType(LiquidGlassButton), findsNothing);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(tester.getSize(find.byType(CyNativeButton)).height, 44);
    final node = tester.getSemantics(find.bySemanticsLabel('提交'));
    expect(node.label, '提交');
    expect(node.value, '正在处理');
    expect(node.flagsCollection.isEnabled, Tristate.isFalse);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);

    await tester.tap(find.byType(CupertinoButton));
    await tester.pump();
    expect(presses, 0);
  });

  testWidgets(
    'Dynamic Type grows the viewport without changing normal geometry',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          CyNativeButton(
            label: '继续',
            liquidGlassSupported: false,
            onPressed: () {},
          ),
          textScaler: const TextScaler.linear(2),
        ),
      );

      expect(
        tester.getSize(find.byType(CyNativeButton)).height,
        greaterThan(44),
      );
      expect(find.text('继续'), findsOneWidget);
    },
  );

  test('button height cannot violate the 44pt touch target', () {
    expect(
      () => CyNativeButton(label: '继续', height: 43, onPressed: () {}),
      throwsAssertionError,
    );
  });
}

Widget _host(Widget child, {TextScaler textScaler = TextScaler.noScaling}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}
