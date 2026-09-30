import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

void main() {
  testWidgets('内容区主 CTA 默认使用实色且不渲染 prominent glass', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: CyNativeButton(
            label: '继续',
            liquidGlassSupported: true,
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(find.byType(LiquidGlassButton), findsNothing);
    final CupertinoButton button = tester.widget<CupertinoButton>(
      find.byType(CupertinoButton),
    );
    expect(button.color, isNotNull);
  });

  testWidgets('浮动功能层仍可显式使用系统 Liquid Glass', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: CyNativeButton(
            label: '继续',
            presentation: CyNativeButtonPresentation.floatingGlass,
            liquidGlassSupported: true,
            onPressed: () {},
          ),
        ),
      ),
    );

    final LiquidGlassButton button = tester.widget<LiquidGlassButton>(
      find.byType(LiquidGlassButton),
    );
    expect(button.style, LiquidGlassButtonStyle.prominentGlass);
  });
}
