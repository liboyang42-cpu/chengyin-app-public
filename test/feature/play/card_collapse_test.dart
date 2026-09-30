import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/feature/play/free_explore/card_box_geometry.dart';

void main() {
  test('0→220px 映射到 0→1,卡片缩到 0.12', () {
    expect(cardCollapse(0).scale, closeTo(1.0, 0.001));
    expect(cardCollapse(220).scale, closeTo(0.12, 0.001));
    expect(
      cardCollapse(400).scale,
      closeTo(0.12, 0.001),
      reason: '越过 220 就夹住,不许继续缩',
    );
  });

  test('★越过 0.85 顶栏接管', () {
    expect(cardCollapse(220 * 0.84).barTakesOver, isFalse);
    expect(cardCollapse(220 * 0.86).barTakesOver, isTrue);
  });

  test('★淡出是 0.92 那一下的布尔切换,不是一路半透明', () {
    expect(cardCollapse(0).faded, isFalse);
    expect(cardCollapse(220 * 0.91).faded, isFalse, reason: '0.85 接管之后卡片还在');
    expect(cardCollapse(220 * 0.93).faded, isTrue);
  });

  test('★负控:负的 scrollTop 不许把卡片放大,也不许提前淡出', () {
    expect(cardCollapse(-50).scale, closeTo(1.0, 0.001));
    expect(cardCollapse(-50).faded, isFalse);
  });
}
