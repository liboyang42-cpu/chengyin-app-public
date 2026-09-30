import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/play/app_sensor_challenge_placeholder.dart';

void main() {
  testWidgets('vm=7 未开放玩法保持零提交入口', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppSensorChallengePlaceholder())),
    );

    expect(find.text('App 专属挑战'), findsOneWidget);
    expect(find.text('该传感器玩法暂未开放'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('B1 静止玩法显示可开始状态', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppSensorChallengePlaceholder(stillnessReady: true),
        ),
      ),
    );

    expect(find.text('点击开始静止挑战'), findsOneWidget);
    expect(find.byIcon(Icons.sensors_outlined), findsOneWidget);
  });
}
