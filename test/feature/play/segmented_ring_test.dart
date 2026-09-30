import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/feature/play/free_explore/widgets/segmented_ring.dart';

void main() {
  test('n 段等分整圆,段间留缝', () {
    final segs = segmentedRing(total: 4, done: 1);
    expect(segs.length, 4);
    final double sum = segs.fold<double>(0, (a, s) => a + s.sweepAngle);
    // 四段 + 四条缝 = 整圆
    expect(sum + 4 * 0.12, closeTo(2 * math.pi, 0.001));
  });

  test('已核销数决定填充哪几段', () {
    final segs = segmentedRing(total: 4, done: 1);
    expect(segs.map((s) => s.filled).toList(), <bool>[true, false, false, false]);
  });

  test('★负控:done 超过 total 不越界,total 为 0 不炸', () {
    expect(segmentedRing(total: 4, done: 9).where((s) => s.filled).length, 4);
    expect(segmentedRing(total: 0, done: 0), isEmpty);
  });

  test('★shouldRepaint 守卫:total 不变、done 推进必须要求重绘', () {
    final before = segmentedRing(total: 4, done: 1);
    final after = segmentedRing(total: 4, done: 2);
    expect(ringNeedsRepaint(before, after), isTrue);
  });

  test('★shouldRepaint 守卫:填充状态没变不应重绘(防恒真实现)', () {
    final a = segmentedRing(total: 4, done: 1);
    final b = segmentedRing(total: 4, done: 1);
    expect(ringNeedsRepaint(a, b), isFalse);
  });

  test('★startAngle 排布:相邻两段的间隙恰为 gapRadians', () {
    const gap = 0.12;
    final segs = segmentedRing(total: 4, done: 1, gapRadians: gap);
    for (int i = 0; i < segs.length - 1; i++) {
      final double actualGap =
          segs[i + 1].startAngle - (segs[i].startAngle + segs[i].sweepAngle);
      expect(actualGap, closeTo(gap, 0.001));
    }
  });
}
