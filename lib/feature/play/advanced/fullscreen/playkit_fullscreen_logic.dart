import 'dart:math' as math;

/// 整屏决定类五件套(coinFlip / diceRoll / reaction / ballShake / quietHold)的纯逻辑。
///
/// 与小程序逐条同源:`pages/play/components/playkit-*` 的「纯算法出口」一节
/// (`_normalizeFace` / `_spinDeg` / `_pipsOf` / `_pickWait` / `_bestOf` /
/// `_bounce` / `_tiltAccel` / `_baseline` / `_thresholds` / `_bandOf` / `_peakOf`)。
/// 这一层零副作用、可单测 —— 组件里只留「演出来」和「把动作抛给宿主」。
///
/// 三条本批铁律落在这里:
/// 1. **结果一律由服务端定**:下面没有任何「算出结果」的函数,只有把服务端
///    给的结果演出来所需的换算(哪一面、转多少度、点数怎么摆);
/// 2. **挑战类先 START_CHALLENGE**:由组件在开局那一刻抛给宿主,不在这一层;
/// 3. **单位在宿主换算**:这里只出现玩家读得懂的单位(秒 / 毫秒 / 次数)。

// ═══════════════════════════════ coinflip ═══════════════════════════════

const String kCoinHeads = 'HEADS';
const String kCoinTails = 'TAILS';

/// 服务端可能给 'HEADS'/'heads'/'H'/'正面'。归一到两个值,**认不出给空 —— 不猜**。
String normalizeCoinFace(Object? raw) {
  final String value = '${raw ?? ''}'.trim().toUpperCase();
  if (value == 'HEADS' || value == 'H' || value == '正面') return kCoinHeads;
  if (value == 'TAILS' || value == 'T' || value == '反面') return kCoinTails;
  return '';
}

/// 转多少圈:每次不同,不然第二次看就知道要转几圈了(纯装饰,不是结果)。
int nextCoinTurns(int previousTurns, int zeroToTwo) =>
    previousTurns + 6 + zeroToTwo.clamp(0, 2);

/// 落面角(度):**绕横轴**转(抛硬币本来就上下翻,绕竖轴那是转陀螺)。
/// TAILS 多转半圈。转动时长必须与动画时长完全一致,两个数由同一个
/// [kCoinSpinMs] 驱动,不会像小程序那样散在 JS/WXSS 两处。
int coinSpinDegrees(int turns, String face) =>
    turns * 360 + (face == kCoinTails ? 180 : 0);

// ═══════════════════════════════ diceroll ═══════════════════════════════

/// 骰面点位:九宫格里哪几格有点。**1 在中心、2 走对角,与真骰子一致** ——
/// 随便摆的话玩家一眼看得出不对劲,虽然说不上哪儿不对。
const Map<int, List<bool>> kDicePips = <int, List<bool>>{
  1: <bool>[false, false, false, false, true, false, false, false, false],
  2: <bool>[true, false, false, false, false, false, false, false, true],
  3: <bool>[true, false, false, false, true, false, false, false, true],
  4: <bool>[true, false, true, false, false, false, true, false, true],
  5: <bool>[true, false, true, false, true, false, true, false, true],
  6: <bool>[true, false, true, true, false, true, true, false, true],
};

/// 点数 → 九格布尔。越界给一颗空骰子,不抛错:一次显示异常好过整屏白。
List<bool> dicePipsOf(int value) =>
    kDicePips[value] ??
    const <bool>[false, false, false, false, false, false, false, false, false];

/// 一颗时任务 = 第 N 面;两颗时没有任务,只有点数和(拿两颗的和去索引六个面会越界)。
String diceTaskFor(List<int> values, List<String> faces) {
  if (values.length != 1) return '';
  final int index = values.first - 1;
  if (index < 0 || index >= faces.length) return '';
  return faces[index];
}

int diceSumOf(List<int> values) => values.fold<int>(0, (int a, int b) => a + b);

/// 服务端点数 → 合法骰值列表(1–6)。越界值丢弃,与服务端字段口径一致。
List<int> parseDiceValues(Object? raw) {
  if (raw is! List) return const <int>[];
  return <int>[
    for (final Object? value in raw)
      if (value is num && value >= 1 && value <= 6) value.toInt(),
  ];
}

// ═══════════════════════════════ reaction ═══════════════════════════════

/// 低于这个毫秒数后端会判抢跑(与后端 AdvancedGameRuntimeServiceImpl 同值)。
const int kReactionMinHumanMs = 120;
const int kReactionWaitMinMs = 1400;
const int kReactionWaitMaxMs = 4200;

/// 随机等待时长。**固定间隔的话第二轮就能背下来,测的就不是反应了。**
int pickReactionWaitMs(double unit) {
  final double clamped = unit.clamp(0.0, 1.0);
  return (kReactionWaitMinMs +
          clamped * (kReactionWaitMaxMs - kReactionWaitMinMs))
      .round();
}

/// 三轮取最快:一轮的偶然性太大。空数组给 0,由调用方判「还没有成绩」。
int reactionBestOf(List<int> timesMs) {
  final List<int> valid = <int>[
    for (final int value in timesMs)
      if (value > 0) value,
  ];
  if (valid.isEmpty) return 0;
  return valid.reduce(math.min);
}

// ═══════════════════════ shake(coinflip / diceroll 共用)═══════════════════════

/// 三轴绝对值之和的阈值,**数值照抄小程序 `utils/play-shake.js`**:
/// 低于它走路都会触发,而这两个玩法一触发就出结果,误触的代价是
/// 「还没准备好就抛了」。
///
/// ⚠️ 单位口径:小程序注释自称接入值以 g 计,但 26 这个数只有按 m/s² 读才
/// 自洽(静息合计约 9.8)。App 侧接的是 sensors_plus,原生口径就是 m/s²,
/// 所以**数值照抄、不再折算** —— 与小程序实际行为一致(26 m/s² ≈ 2.65g,
/// 走路约 12–15 m/s² 不会触发)。
const double kShakeMagnitude = 26;

/// 两次之间至少隔这么久,否则一次晃动会被读成好几次。
const int kShakeGapMs = 900;

double shakeMagnitudeOf(double x, double y, double z) =>
    x.abs() + y.abs() + z.abs();

/// 摇一摇识别器:够力度且过了防抖才 `true`。抛硬币和掷骰子共用同一个 ——
/// 各写一份的话阈值迟早不一样,同一个动作在两屏里会一个认一个不认。
class PlayKitShakeDetector {
  PlayKitShakeDetector({
    this.threshold = kShakeMagnitude,
    this.gapMs = kShakeGapMs,
  });

  final double threshold;
  final int gapMs;

  /// null = 从没摇过。**第一次摇必须永远算数**(小程序用 -Infinity 表达同一件事)。
  int? _lastMs;

  bool feed({required double x, required double y, required double z, required int atMs}) {
    if (shakeMagnitudeOf(x, y, z) <= threshold) return false;
    final int? last = _lastMs;
    if (last != null && atMs - last <= gapMs) return false;
    _lastMs = atMs;
    return true;
  }
}

// ═══════════════════════════════ ballshake ═══════════════════════════════

/// 倾斜 → 加速度。普通重力的三分之一 —— 沉的球会滚到底边来回蹭,弹不起来就没得玩。
///
/// ⚠️ 与小程序同源同一处口径问题(见 [kShakeMagnitude]):0.05 这个系数只有
/// 按 m/s² 口径读才等于「普通重力的三分之一」,App 侧 sensors_plus 原生 m/s²,
/// 因此**照抄数值、不做 g 折算**。
const double kBallTiltGravity = 0.05;

/// 阻尼几乎不给:球要一直有劲。
const double kBallDamp = 0.999;

/// 相对零点的倾斜 → 这一帧的加速度。零点没量过时不给力,球不动。
///
/// x 取反照抄原型:手机左倾(x 负)球往右加速。
class BallShakeTilt {
  const BallShakeTilt(this.gx, this.gy);

  final double gx;
  final double gy;
}

BallShakeTilt ballShakeTiltOf({
  required double x,
  required double y,
  double? zeroX,
  double? zeroY,
}) {
  if (zeroX == null || zeroY == null) return const BallShakeTilt(0, 0);
  return BallShakeTilt(
    -(x - zeroX) * kBallTiltGravity,
    (y - zeroY) * kBallTiltGravity,
  );
}

/// 反弹:反向 + 一点随机。不加随机的话球会卡进一条来回直线,
/// 分照涨但人已经不用操作了 —— 那是动画不是游戏。
double ballShakeBounce(double velocity, double unit) =>
    -velocity * 0.98 + (unit.clamp(0.0, 1.0) - 0.5) * 0.5;

// ═══════════════════════════════ quiethold ═══════════════════════════════

/// 黄线 = 底噪 + 这个;红线 = 黄线 + 这个。**判峰值不判均值** ——
/// 一声咳嗽在均值里会被摊平,而人的直觉对得上峰值。
const double kQuietMidOverBase = 0.06;
const double kQuietHotOverMid = 0.09;

/// 采样序列 → 底噪。取 80 分位,别被一次咳嗽带偏;没采到给一个保守的低值。
double quietBaselineOf(List<double> samples) {
  if (samples.isEmpty) return 0.06;
  final List<double> sorted = List<double>.of(samples)..sort();
  final int index = (sorted.length * 0.8).floor();
  return sorted[index.clamp(0, sorted.length - 1)];
}

class QuietThresholds {
  const QuietThresholds(this.mid, this.hot);

  final double mid;
  final double hot;
}

/// 底噪 → 黄线 / 红线。都夹在合理区间里:校准到极端值时不能让阈值跑飞。
QuietThresholds quietThresholdsOf(double base) {
  final double mid = math.min(0.5, math.max(0.12, base + kQuietMidOverBase));
  return QuietThresholds(mid, math.min(0.72, mid + kQuietHotOverMid));
}

/// 当前音量落在哪一档。hot = 过线,判输。
String quietBandOf(double level, double mid, double hot) {
  if (level > hot) return 'hot';
  if (level > mid) return 'mid';
  return 'ok';
}

/// 一帧若干采样 → 0–1 峰值。拿不到数据时给 0,不猜。
double quietPeakOf(Iterable<double> frame) {
  double peak = 0;
  for (final double value in frame) {
    final double magnitude = value.abs();
    if (magnitude > peak) peak = magnitude;
  }
  return peak;
}

/// 录音插件给的 dBFS → 0–1 线性振幅。
///
/// 小程序那侧拿到的是 PCM 帧里的线性峰值(0–1),App 侧 `record` 给的是
/// dBFS(-160–0)。阈值是**相对校准**出来的(底噪 + 固定偏移),所以只要
/// 全程同一把尺子就行;折成线性是为了与小程序同一套「峰值」直觉。
double decibelsToLinear(double decibels) {
  if (decibels.isNaN || decibels <= -160) return 0;
  if (decibels >= 0) return 1;
  return math.pow(10, decibels / 20).toDouble();
}

// ═══════════════════════════ 单位换算(宿主用)════════════════════════════
// 组件按玩家读得懂的单位报,服务端按判定要用的单位收 —— 换算落在宿主层,
// 见 playkit_fullscreen_payload.dart。

/// 秒 → 毫秒(quiethold 的 heldSeconds → heldMs)。
int heldSecondsToMs(num heldSeconds) => (heldSeconds * 1000).round();
