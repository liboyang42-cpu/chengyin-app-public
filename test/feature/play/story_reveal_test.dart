import 'package:chengyin_app/feature/play/free_explore/story_reveal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('速度是每帧位移,不随事件频率漂', () {
    // 同样挪 32px:一次 32ms 的事件 与 两次 16ms 的事件,算出的每帧速度必须一致
    expect(
      frameVelocity(top: 32, prevTop: 0, dt: const Duration(milliseconds: 32)),
      16,
    );
    expect(
      frameVelocity(top: 16, prevTop: 0, dt: const Duration(milliseconds: 16)),
      16,
    );
  });

  test('dt 下限 8ms —— 防止两次事件挨太近算出天文数字', () {
    expect(frameVelocity(top: 10, prevTop: 0, dt: Duration.zero), 20);
  });

  test('往回滚也算速度 —— 取绝对值', () {
    expect(
      frameVelocity(top: 0, prevTop: 32, dt: const Duration(milliseconds: 32)),
      16,
    );
  });

  test('inView 用行的中点,上边界 -20 下边界 boxHeight-40', () {
    expect(
      lineInView(lineTop: -30, lineHeight: 20, boxTop: 0, boxHeight: 800),
      isFalse,
    );
    expect(
      lineInView(lineTop: 0, lineHeight: 40, boxTop: 0, boxHeight: 800),
      isTrue,
    );
    expect(
      lineInView(lineTop: 780, lineHeight: 40, boxTop: 0, boxHeight: 800),
      isFalse,
    );
    // 两条边界各再钉一格,否则「-20」「-40」这两个余量被抹掉也照样绿
    expect(
      lineInView(lineTop: -29, lineHeight: 20, boxTop: 0, boxHeight: 800),
      isTrue,
    );
    expect(
      lineInView(lineTop: 760, lineHeight: 40, boxTop: 0, boxHeight: 800),
      isFalse,
    );
  });

  test('inView 是相对滚动框的,不是相对屏幕 —— boxTop 要减掉', () {
    // 滚动框从屏幕 y=300 起(上面是顶栏),行在 y=200:它在框**上方**,已经出屏。
    // 忘了减 boxTop 的话这行会被算成「在框内偏上」,顶栏底下的字就再也不复位了。
    expect(
      lineInView(lineTop: 200, lineHeight: 40, boxTop: 300, boxHeight: 800),
      isFalse,
    );
    expect(
      lineInView(lineTop: 400, lineHeight: 40, boxTop: 300, boxHeight: 800),
      isTrue,
    );
  });

  test('同批逐条错开 50ms', () {
    expect(staggerFor(0), Duration.zero);
    expect(staggerFor(3), const Duration(milliseconds: 150));
  });

  test('慢滑 30ms 就 settle,快滑等 70ms —— 滑得快时屏幕上没有字', () {
    expect(settleDelayFor(kStoryFastPx - 1), kSettleSlow);
    expect(settleDelayFor(kStoryFastPx), kSettleFast);
    expect(settleDelayFor(kStoryFastPx + 1), kSettleFast);
  });
}
