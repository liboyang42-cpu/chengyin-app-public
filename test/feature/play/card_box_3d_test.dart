import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/feature/play/free_explore/widgets/card_box_3d.dart';

Future<void> _pump(WidgetTester t, {bool dimmed = false}) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: CardBox3d(
          width: 200, height: 276, dimmed: dimmed,
          front: const Text('FRONT'),
          back: const Text('BACK'),
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('初始朝正面:只画正面,背面不在树里', (t) async {
    await _pump(t);
    expect(find.text('FRONT'), findsOneWidget);
    expect(find.text('BACK'), findsNothing,
        reason: 'Flutter 没有 backface-visibility,背面同时在树里会镜像透出来');
  });

  testWidgets('★横向拖过半圈换成背面', (t) async {
    await _pump(t);
    // ry += dx*0.8,要越过 90° 需 dx > 112.5
    await t.drag(find.byType(CardBox3d), const Offset(160, 0));
    await t.pumpAndSettle();
    expect(find.text('BACK'), findsOneWidget);
    expect(find.text('FRONT'), findsNothing);
  });

  testWidgets('★松手吸附:小角度拖动会弹回正面', (t) async {
    await _pump(t);
    await t.drag(find.byType(CardBox3d), const Offset(40, 0)); // 32° < 90°
    await t.pumpAndSettle();
    expect(find.text('FRONT'), findsOneWidget, reason: '吸附回正面,不许停在斜着的角度');
  });

  testWidgets('已核销整张灰掉', (t) async {
    await _pump(t, dimmed: true);
    expect(find.byKey(const ValueKey<String>('card-box-dimmed')), findsOneWidget);
  });
}
