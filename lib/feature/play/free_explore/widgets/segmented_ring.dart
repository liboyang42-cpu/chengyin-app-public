import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_colors.dart';

/// 一段圆弧。角度是弧度,0 在三点钟方向(与 Canvas.drawArc 一致)。
class RingSegment {
  const RingSegment({
    required this.startAngle,
    required this.sweepAngle,
    required this.filled,
  });

  final double startAngle;
  final double sweepAngle;
  final bool filled;
}

/// 把整圆等分成 [total] 段,前 [done] 段算已核销。
///
/// ★ 用分段圆弧而不是一整条进度条:自由探索**没有顺序**,
///   一条连续的进度条会暗示「要按顺序走」,那是定向模式的语义。
List<RingSegment> segmentedRing({
  required int total,
  required int done,
  double gapRadians = 0.12,
}) {
  if (total <= 0) return const <RingSegment>[];
  final int filledCount = done < 0 ? 0 : (done > total ? total : done);
  final double each = (2 * math.pi) / total - gapRadians;
  const double start = -math.pi / 2; // 十二点钟起画
  return List<RingSegment>.generate(total, (int i) {
    return RingSegment(
      startAngle: start + i * (each + gapRadians),
      sweepAngle: each,
      filled: i < filledCount,
    );
  });
}

class SegmentedRing extends StatelessWidget {
  const SegmentedRing({
    super.key,
    required this.total,
    required this.done,
    this.size = 72,
    this.strokeWidth = 4,
  });

  final int total;
  final int done;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _RingPainter(
        segments: segmentedRing(total: total, done: done),
        strokeWidth: strokeWidth,
      ),
    );
  }
}

/// 判断两组分段是否需要触发重绘。
///
/// ⚠️ 不能只比 `segments.length`:核销进度推进时(`total` 不变、
/// `done` 从 1 变 2)分段数量和每段角度都不变,只有 `filled` 变了——
/// 漏比这一项会导致环永远停在旧的填充状态上,而「显示核销进度」
/// 正是这个组件存在的理由。
bool ringNeedsRepaint(List<RingSegment> a, List<RingSegment> b) {
  if (a.length != b.length) return true;
  for (int i = 0; i < a.length; i++) {
    if (a[i].filled != b[i].filled) return true;
  }
  return false;
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.segments, required this.strokeWidth});

  final List<RingSegment> segments;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Rect arcRect = rect.deflate(strokeWidth / 2);
    for (final RingSegment s in segments) {
      final Paint p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth
        ..color = s.filled ? AppColors.success : AppColors.divider;
      canvas.drawArc(arcRect, s.startAngle, s.sweepAngle, false, p);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.strokeWidth != strokeWidth || ringNeedsRepaint(old.segments, segments);
}
