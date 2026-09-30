// 系统 Cupertino 确认弹窗的快照：锁定原生布局、深浅色与
// destructive 动作语义，防止旧 iOS 回退为自绘 Material 框。
//
// 更新基准图:flutter test --update-goldens test/golden/cy_confirm_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/widgets/cy_confirm.dart';
import 'golden_theme.dart';

Future<void> _shot(
  WidgetTester tester,
  ThemeData theme,
  String goldenPath, {
  required bool danger,
}) async {
  setGoldenViewport(tester, const Size(390, 500));
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => cyConfirm(
                context,
                title: '删除「静安夜跑 · 第一期」?',
                content: '删除后无法恢复。已售出的票不受影响,但页面会立即下线。',
                confirmText: '删除',
                danger: danger,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

void main() {
  testWidgets('危险动作:Cupertino destructive 确认键', (WidgetTester tester) async {
    await _shot(
      tester,
      goldenTheme(),
      'goldens/confirm_danger.png',
      danger: true,
    );
  });

  testWidgets('普通动作:Cupertino default 确认键', (WidgetTester tester) async {
    await _shot(
      tester,
      goldenTheme(),
      'goldens/confirm_normal.png',
      danger: false,
    );
  });

  testWidgets('浅色主题(商家域)', (WidgetTester tester) async {
    await _shot(
      tester,
      merchantGoldenTheme(),
      'goldens/confirm_light.png',
      danger: true,
    );
  });
}
