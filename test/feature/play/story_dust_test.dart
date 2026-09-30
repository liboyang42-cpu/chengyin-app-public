import 'package:chengyin_app/feature/play/free_explore/widgets/story_dust.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester t, {
  required List<StoryDustLayer> layers,
  double scrollOffset = 0,
  bool reduceMotion = false,
}) {
  return t.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Center(
          child: SizedBox(
            width: 375,
            height: 800,
            child: StoryDust(layers: layers, scrollOffset: scrollOffset),
          ),
        ),
      ),
    ),
  );
}

StoryDustPainter _painter(WidgetTester t) =>
    t.widget<CustomPaint>(
          find.descendant(
            of: find.byType(StoryDust),
            matching: find.byType(CustomPaint),
          ),
        ).painter!
        as StoryDustPainter;

void main() {
  group('分层配置', () {
    test('★前后两张画布的分法照样机 `(p.z > 1.2) !== near`', () {
      expect(kStoryDustBack.map((StoryDustLayer l) => l.k).toList(), <double>[
        0.7,
      ]);
      expect(kStoryDustFront.map((StoryDustLayer l) => l.k).toList(), <double>[
        1.5,
        2.2,
      ]);
      final int total =
          <StoryDustLayer>[
            ...kStoryDustBack,
            ...kStoryDustFront,
          ].fold<int>(0, (int a, StoryDustLayer l) => a + l.count);
      expect(total, 222, reason: '样机侧本轮调到 222 颗:190 / 20 / 12');
      expect(kStoryDustBack.single.count, 190, reason: '远景不够密就不是星场,是几粒灰');
    });

    test('★近景层的 k 必须 > 1 —— 跟手跑得比手快,近的才「近」', () {
      for (final StoryDustLayer l in kStoryDustFront) {
        expect(l.k, greaterThan(1));
      }
      expect(kStoryDustBack.single.k, lessThan(1));
    });

    test('★种子按层定种:同配置两次铺出来完全一样(golden 要能复现)', () {
      final List<StoryDustParticle> a = seedStoryDust(kStoryDustFront);
      final List<StoryDustParticle> b = seedStoryDust(kStoryDustFront);
      expect(a.length, 32);
      expect(a.first.x, b.first.x);
      expect(a.last.size, b.last.size);
    });

    test('★后景与近景不是同一把种子(否则前 32 颗完全重叠)', () {
      expect(
        seedStoryDust(kStoryDustBack).first.x,
        isNot(seedStoryDust(kStoryDustFront).first.x),
      );
    });

    test('★自漂速度的量纲是像素每帧,不是「每帧 0.01px」那种看不见的量', () {
      final List<StoryDustParticle> ps = seedStoryDust(kStoryDustBack);
      final double maxV = ps
          .map((StoryDustParticle p) => p.vx.abs())
          .reduce((double a, double b) => a > b ? a : b);
      expect(maxV, greaterThan(0.1));
      expect(maxV, lessThanOrEqualTo(0.3));
    });
  });

  group('视差', () {
    test('★k>1 的层跟手跑得比手快:手指挪 100,k=2.2 的挪 220', () {
      const double h = 800;
      final double still = storyDustY(
        baseY: 0.5,
        scrollOffset: 0,
        k: 2.2,
        height: h,
      );
      final double near = storyDustY(
        baseY: 0.5,
        scrollOffset: 100,
        k: 2.2,
        height: h,
      );
      final double far = storyDustY(
        baseY: 0.5,
        scrollOffset: 100,
        k: 0.7,
        height: h,
      );
      expect(still - near, closeTo(220, 0.001));
      expect(still - far, closeTo(70, 0.001));
    });

    test('★滚多远都续得上:纵向按 2×height 循环,下半屏也落得到星星', () {
      const double h = 800;
      double at(double off) =>
          storyDustY(baseY: 0.5, scrollOffset: off, k: 1, height: h);

      expect(at(0), closeTo(at(h * 2), 0.001), reason: '周期是 2×height');
      // ⚠️ 周期若退成 1×height,值域只剩 [-0.5h, 0.5h) —— 下半屏一颗星都没有。
      //   只比「滚 2h 回到原位」是抓不到的:2h 同时也是 h 的整数倍,恒真。
      expect(at(0), isNot(closeTo(at(h), 0.001)), reason: '1×height 的周期在这里必须被判红');

      final List<double> ys = List<double>.generate(40, (int i) => at(i * 40.0));
      expect(ys.any((double y) => y > h * 0.6), isTrue, reason: '下半屏必须落得到点');
      expect(
        ys.every((double y) => y >= -h * 0.5 - 0.001 && y < h * 1.5 + 0.001),
        isTrue,
      );
    });

    test('★横向左出右回,区间 [-0.05, 1.05)', () {
      expect(storyDustX(0.5), closeTo(0.5, 1e-9));
      expect(storyDustX(1.06), closeTo(-0.04, 1e-9));
      expect(storyDustX(-0.06), closeTo(1.04, 1e-9));
    });
  });

  group('降低动态', () {
    testWidgets('★不起 ticker、不排帧,画一屏静止星点', (WidgetTester t) async {
      await _pump(t, layers: kStoryDustFront, reduceMotion: true);
      await t.pump(const Duration(milliseconds: 300));
      expect(
        t.binding.hasScheduledFrame,
        isFalse,
        reason: '样机 reducedMotion 时 _startStoryDust 第一行就 return,不跑 rAF',
      );
      expect(_painter(t).frames.value, 0);
      // 还是要画出来 —— 「不跑动画」不等于「星星消失」
      expect(_painter(t).particles.length, 32);
    });

    testWidgets('★常态下确实在漂(负控:上面那条不是恒真)', (WidgetTester t) async {
      await _pump(t, layers: kStoryDustFront);
      await t.pump(const Duration(milliseconds: 300));
      expect(_painter(t).frames.value, greaterThan(0));
      expect(t.binding.hasScheduledFrame, isTrue);
      // 收尾:ticker 是无限的,不停掉会让 tester 抱怨有 pending timer
      await _pump(t, layers: kStoryDustFront, reduceMotion: true);
    });
  });

  group('重绘守卫', () {
    test('★滚动位移变了必须重画 —— 视差全靠它', () {
      final List<StoryDustParticle> ps = seedStoryDust(kStoryDustBack);
      final ValueNotifier<double> f = ValueNotifier<double>(0);
      final StoryDustPainter a = StoryDustPainter(
        particles: ps,
        scrollOffset: 0,
        frames: f,
      );
      final StoryDustPainter b = StoryDustPainter(
        particles: ps,
        scrollOffset: 12,
        frames: f,
      );
      expect(b.shouldRepaint(a), isTrue);
      f.dispose();
    });

    test('★位移没变、种子没换就别重画(防恒真实现)', () {
      final List<StoryDustParticle> ps = seedStoryDust(kStoryDustBack);
      final ValueNotifier<double> f = ValueNotifier<double>(0);
      final StoryDustPainter a = StoryDustPainter(
        particles: ps,
        scrollOffset: 8,
        frames: f,
      );
      final StoryDustPainter b = StoryDustPainter(
        particles: ps,
        scrollOffset: 8,
        frames: f,
      );
      expect(b.shouldRepaint(a), isFalse);
      f.dispose();
    });
  });
}
