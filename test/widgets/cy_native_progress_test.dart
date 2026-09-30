import 'dart:io';

import 'package:chengyin_app/core/widgets/cy_native_progress.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

void main() {
  testWidgets('进度使用 UIKit 插件封装并提供 VoiceOver 值', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const CupertinoApp(
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: CupertinoPageScaffold(
            child: CyNativeProgress(
              progress: .625,
              height: 8,
              semanticLabel: '任务进度',
            ),
          ),
        ),
      ),
    );

    expect(find.byType(LiquidGlassProgressView), findsOneWidget);
    expect(tester.getSize(find.byType(CyNativeProgress)).height, 8);
    final node = tester.getSemantics(find.bySemanticsLabel('任务进度'));
    expect(node.value, '63%');
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    handle.dispose();
  });

  test('三处业务进度统一走 CyNativeProgress', () {
    for (final String path in <String>[
      'lib/feature/merchant/merchant_apply_page.dart',
      'lib/feature/merchant/merchant_marketing_page.dart',
      'lib/feature/play/play_session_page.dart',
    ]) {
      final String source = File(path).readAsStringSync();
      expect(source, contains('CyNativeProgress('), reason: path);
      expect(source, isNot(contains('LinearProgressIndicator(')), reason: path);
    }
  });
}
