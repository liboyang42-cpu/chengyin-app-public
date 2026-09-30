import 'dart:math' as math;

/// 集邮册散落布局。**逐行移植**小程序
/// `subpackageP3/pages/stamp-album/index/layout.js`,
/// 目的是让两端算出**同样的位置**,而不只是"看起来都挺乱"。
///
/// ★ 必须是**确定性伪随机**:真随机会让每次进页面邮票乱跳,也没法测。
///   用 index 派生:看着乱,实际可复现。
class StampSlot {
  const StampSlot({
    required this.x,
    required this.y,
    required this.rotDeg,
    required this.z,
  });

  final double x;
  final double y;
  final double rotDeg;
  final int z;
}

/// 小程序原式:`sin(i*12.9898 + salt*78.233) * 43758.5453` 取小数部分。
///
/// ⚠️ 不要"改进"成 Random(seed) —— 那会算出另一套位置,
///   两端的册子就长得不一样了,而这正是这个文件存在的理由。
double _rnd(int i, int salt) {
  final double x = math.sin(i * 12.9898 + salt * 78.233) * 43758.5453;
  return x - x.floorToDouble();
}

/// 与小程序同参:cols=4,jitter=16,maxRot=12。
List<StampSlot> collageLayout(
  int count, {
  required int cols,
  required double cellW,
  required double cellH,
  double jitter = 16,
  double maxRot = 12,
}) {
  return List<StampSlot>.generate(count, (int i) {
    final int c = i % cols;
    final int r = i ~/ cols;
    return StampSlot(
      x: c * cellW + (_rnd(i, 1) - 0.5) * jitter,
      y: r * cellH + (_rnd(i, 2) - 0.5) * jitter,
      rotDeg: (_rnd(i, 3) - 0.5) * 2 * maxRot,
      z: i,
    );
  });
}
