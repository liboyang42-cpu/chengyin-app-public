// 故事流的分层漂浮粒子。逐条照搬小程序 `_startStoryDust`(pages/play/index.js:1128-1180)。
//
// ★ 两层夹住文字:近景那层画在文字**上方**、会遮住字 —— 这是刻意的景深,不是缺陷。
// ★ 视差幅度大于手指位移:k > 1 的层跟手跑得比手快,近的才「近」。

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 一层粒子。
///
/// 样机里三个量都由同一个 `z` 派生(`z` 越大越近:更大、更实、视差更强),
/// 所以 [k] 与 [radius] 数值相同 —— 这不是重复,是把「视差」和「尺寸」两件事各自命名,
/// 免得以后调其中一个时误伤另一个。
class StoryDustLayer {
  const StoryDustLayer({
    required this.count,
    required this.k,
    required this.radius,
    required this.opacity,
  });

  /// 这一层几颗。
  ///
  /// ★ 远景要足够密才是「星场」—— 样机注释记着:之前 86 颗是随手写的,稀得像几粒灰。
  final int count;

  /// 视差系数。`k > 1` 的层跟手跑得比手快。
  final double k;

  /// 尺寸基数(样机的 `z`)。单颗边长 = `radius × (0.9 ~ 2.3)`。
  final double radius;

  /// 不透明度基数(样机的 `z > 1 ? 1 : 0.8`)。单颗 alpha = `opacity × (0.18 ~ 0.48)`。
  final double opacity;
}

/// 后景那张「canvas」:样机 `(p.z > 1.2) !== near` 把 z ≤ 1.2 的都分到这里。
const List<StoryDustLayer> kStoryDustBack = <StoryDustLayer>[
  StoryDustLayer(count: 190, k: 0.7, radius: 0.7, opacity: 0.8),
];

/// 近景那张:z = 1.5 与 z = 2.2 两层,共 32 颗,**压在文字之上**。
const List<StoryDustLayer> kStoryDustFront = <StoryDustLayer>[
  StoryDustLayer(count: 20, k: 1.5, radius: 1.5, opacity: 1),
  StoryDustLayer(count: 12, k: 2.2, radius: 2.2, opacity: 1),
];

/// 一颗粒子的种子。位置是归一化的(0..1 横向 / 0..2 纵向),与画布尺寸无关 ——
/// 所以旋转屏幕不会把星场重新洗一遍。
class StoryDustParticle {
  const StoryDustParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.alpha,
    required this.shape,
    required this.vx,
    required this.vy,
    required this.k,
  });

  final double x;
  final double y;
  final double size;
  final double alpha;

  /// 0 方 / 1 圆 / 2 三角。只有这三种 —— 不画十字星、不加光晕。
  final int shape;

  /// 自漂速度,量纲是**像素每帧**,用时除以画布尺寸才归一化。
  ///
  /// ⚠️ 样机在这里栽过一次:早先给的是 ±0.01 再除以宽度 ⇒ 每帧 0.01px,
  ///   一秒挪不到一个像素,肉眼就是完全静止。
  final double vx;
  final double vy;

  final double k;
}

/// 一颗粒子在画布上的纵坐标。
///
/// ★ 这是「近景」成立的地方:滚动位移 [scrollOffset] 乘 [k] 再减掉 ——
///   k=2.2 的层,手指挪 100px 它挪 220px。
/// 纵向按 `2 × height` 取模循环,再上提 `0.5 × height`,滚多远都续得上。
double storyDustY({
  required double baseY,
  required double scrollOffset,
  required double k,
  required double height,
}) {
  final double span = height * 2;
  final double raw = baseY * height - scrollOffset * k;
  return (raw % span + span) % span - height * 0.5;
}

/// 横向循环:左出 `-0.05` 从 `1.05` 回来,区间长 1.1(样机同款)。
double storyDustX(double x) => ((x + 0.05) % 1.1 + 1.1) % 1.1 - 0.05;

/// 按层配置铺一把种子。
///
/// ⚠️ 随机数**按层定种**(`k × 100`),不用系统随机:
///   ① golden 基线要能复现;② 后景与近景两个实例各自成场,不会前 32 颗完全重叠。
List<StoryDustParticle> seedStoryDust(List<StoryDustLayer> layers) {
  final List<StoryDustParticle> out = <StoryDustParticle>[];
  for (final StoryDustLayer layer in layers) {
    final math.Random rnd = math.Random((layer.k * 100).round());
    for (int i = 0; i < layer.count; i++) {
      out.add(
        StoryDustParticle(
          x: rnd.nextDouble(),
          y: rnd.nextDouble() * 2,
          size: (0.9 + rnd.nextDouble() * 1.4) * layer.radius,
          alpha: (0.18 + rnd.nextDouble() * 0.3) * layer.opacity,
          shape: i % 3,
          vx: (rnd.nextDouble() - 0.5) * 0.6,
          vy: (rnd.nextDouble() - 0.5) * 0.4,
          k: layer.k,
        ),
      );
    }
  }
  return out;
}

/// 一层(或几层)粒子。放在文字之前是后景,放在文字之后就是遮字的近景。
class StoryDust extends StatefulWidget {
  const StoryDust({
    super.key,
    required this.layers,
    required this.scrollOffset,
  });

  final List<StoryDustLayer> layers;

  /// 滚动区当前的偏移(px)。视差就是拿它乘各层的 k。
  final double scrollOffset;

  @override
  State<StoryDust> createState() => _StoryDustState();
}

class _StoryDustState extends State<StoryDust>
    with SingleTickerProviderStateMixin {
  late List<StoryDustParticle> _particles = seedStoryDust(widget.layers);

  /// 已经过了多少「帧」(按 60fps 折算)。用 notifier 直接驱动重绘 ——
  /// 每帧 setState 会把整棵子树重建一遍,而这里变的只有画布。
  final ValueNotifier<double> _frames = ValueNotifier<double>(0);
  Ticker? _ticker;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 降低动态:样机 `_startStoryDust` 第一行就 return,不跑 rAF。
    // 这里同样**不起 ticker**,画一屏静止星点即可。
    if (MediaQuery.disableAnimationsOf(context)) {
      _ticker?.stop();
      _frames.value = 0;
      return;
    }
    final Ticker ticker = _ticker ??= createTicker(_onTick);
    if (!ticker.isActive) ticker.start();
  }

  @override
  void didUpdateWidget(StoryDust oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.layers, widget.layers)) {
      _particles = seedStoryDust(widget.layers);
    }
  }

  void _onTick(Duration elapsed) {
    // ponytail: 按 60fps 折算而不是真数帧 —— 掉帧时漂移速度不跟着变慢,更稳。
    _frames.value = elapsed.inMicroseconds / 16666.67;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _frames.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
        painter: StoryDustPainter(
          particles: _particles,
          scrollOffset: widget.scrollOffset,
          frames: _frames,
        ),
      ),
    );
  }
}

class StoryDustPainter extends CustomPainter {
  StoryDustPainter({
    required this.particles,
    required this.scrollOffset,
    required this.frames,
  }) : super(repaint: frames);

  final List<StoryDustParticle> particles;
  final double scrollOffset;
  final ValueListenable<double> frames;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    if (w <= 0 || h <= 0) return;
    final double f = frames.value;
    // 星点恒白:玩家端整页单色。
    final Paint paint = Paint()..style = PaintingStyle.fill;

    for (final StoryDustParticle p in particles) {
      final double x = storyDustX(p.x + p.vx / w * f) * w;
      final double y = storyDustY(
        baseY: p.y + p.vy / h * f,
        scrollOffset: scrollOffset,
        k: p.k,
        height: h,
      );
      paint.color = const Color(0xFFFFFFFF).withValues(alpha: p.alpha);
      final double s = p.size;
      switch (p.shape) {
        case 0:
          canvas.drawRect(Rect.fromLTWH(x, y, s, s), paint);
        case 1:
          canvas.drawCircle(Offset(x, y), s / 2, paint);
        default:
          canvas.drawPath(
            Path()
              ..moveTo(x, y - s / 2)
              ..lineTo(x + s / 2, y + s / 2)
              ..lineTo(x - s / 2, y + s / 2)
              ..close(),
            paint,
          );
      }
    }
  }

  /// ⚠️ `frames` 已经是 `repaint` 监听源,漂移不走这里;
  /// 这里只管**重建时**该不该重画 —— 滚动位移变了必须重画(视差就靠它),
  /// 种子没换就别重画,否则每次父级 rebuild 都全量重绘一遍星场。
  @override
  bool shouldRepaint(StoryDustPainter oldDelegate) =>
      oldDelegate.scrollOffset != scrollOffset ||
      !identical(oldDelegate.particles, particles);
}
