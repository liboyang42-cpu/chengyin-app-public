import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// 计时/传感器族五件(countdown / stopwatch / walk / gameTimer / stickerBook)的
/// **纯逻辑**。
///
/// 真源=小程序 `pages/play/components/playkit-{countdown,stopwatch,walk}`、
/// `game-timer`、`playkit-stickerbook` 各自的「纯算法出口」一节 ——
/// `_oilPercent` / `_remainSeconds` / `secs` / `clockText` / `diffSeconds` /
/// `tierLabel` / `_group` / `_remain` / `_percent` / `_co2Of` / `_formatClock` /
/// `_remainPercent` / `_buildCells`。这些函数**有对错**(差一步就是另一个结果),
/// 而它们又不需要一帧渲染 —— 所以单独放这一层,组件里只留「把它演出来」。
///
/// ⚠️ 这一层里**没有任何**「算出结果」的入口:倒计时到点与否、秒表准不准,
/// 判定在服务端(设备时钟玩家改得动,见各组件头部)。这里只有把服务端/本地读数
/// 换算成玩家看得懂的那一步。

// ══════════════════════════ 具名时间轴(非动效档位)══════════════════════
//
// 下面这些是**节拍**:计时器多久对一次时、数字什么时候藏、开跑前数几拍。
// 它们不是 UI 过渡,不走 CyMotion 的五档 —— 与仓内既有登记同口径
// (`feature/play/stopwatch_game_page.dart|50ms` 等同表),在
// `test/theme/motion_ratchet_test.dart` 的 kAllowedLiterals 里逐条写明理由。

/// 倒计时每拍一次对时(小程序 `playkit-countdown` 的 `setInterval(..., 1000)`)。
/// ⚠️ 每拍**重新取 Date.now()**,不做 `seconds--` 累加:小程序切后台时定时器会被
/// 限频甚至停掉,累加法回来会少算 —— 那等于白送时间。
const Duration kCountdownTickInterval = Duration(milliseconds: 1000);

/// 油面每拍退一格,与拍同档(`transition: transform 1s linear`)。
/// 用 1s 而不是某个动效档:油面的位置就是「还剩多少」的读数,走快了读数会跳。
const Duration kCountdownOilStep = Duration(seconds: 1);

/// 油面波形循环两条(小程序 4.6s / 7.4s,反向)。同速的话整块像一个刚体在晃,
/// 不像液体。属于具名时间轴(与 `status_view.dart|1400ms` 同类的循环),
/// **不是**态切换,所以不套 CyMotion 档位。
const Duration kCountdownWaveA = Duration(milliseconds: 4600);
const Duration kCountdownWaveB = Duration(milliseconds: 7400);

/// 秒表读数刷新节拍(20Hz,与 `stopwatch_game_page.dart` 同档)。
const Duration kStopwatchTickInterval = Duration(milliseconds: 50);

/// 开跑 1 秒后把走动的数字藏起来(盲停:不藏就是「读秒」,不是「估时」)。
const Duration kStopwatchHideAfter = Duration(milliseconds: 1000);

/// 3-2-1 每一拍(小程序 `cy-play-countin` 的 `TICK_MS = 620`)。
const Duration kCountInTickInterval = Duration(milliseconds: 620);

// ══════════════════════════════════ countdown ══════════════════════════════════

/// 已过 / 总时长 → 油面退到哪儿。**0 = 满,1 = 空**。总时长缺失时不退。
///
/// 小程序 `_oilPercent` 返回 0–100 的整数;App 侧直接收成 0–1 的比例,
/// 布局里只乘高度一次,少一次除。
double countdownOilFraction(int elapsedMs, int totalSeconds) {
  if (totalSeconds <= 0) return 0;
  final double k = elapsedMs / (totalSeconds * 1000);
  if (k.isNaN) return 0;
  return k.clamp(0, 1).toDouble();
}

/// 剩余秒数,**向上取整**:还剩 0.4 秒时显示 0 会让人以为已经到点了。
int countdownRemainSeconds(int elapsedMs, int totalSeconds) {
  if (totalSeconds <= 0) return 0;
  final double remain = totalSeconds - elapsedMs / 1000;
  if (remain <= 0) return 0;
  return remain.ceil();
}

// ══════════════════════════════════ stopwatch ══════════════════════════════════

/// 走动的读数:秒,两位小数(小程序 `secs()`)。
String stopwatchSecondsText(int elapsedMs) =>
    (math.max(0, elapsedMs) / 1000).toStringAsFixed(2);

/// 底部那颗表:mm:ss.xx(小程序 `clockText()`)。
String stopwatchClockText(int elapsedMs) {
  final double t = math.max(0, elapsedMs) / 1000;
  final int minutes = t ~/ 60;
  final double rest = t - minutes * 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${rest.toStringAsFixed(2).padLeft(5, '0')}';
}

/// 差多少秒。早停与晚停一视同仁,取绝对值(小程序 `diffSeconds`)。
double stopwatchDiffSeconds(int elapsedMs, double targetSeconds) =>
    ((math.max(0, elapsedMs) / 1000) - targetSeconds).abs();

/// 三档措辞。「优秀」那一档**不能比容差还宽** —— 容差配得极小时它得跟着收。
String stopwatchTierLabel(double diffSeconds, double toleranceSeconds) {
  final double fine = math.min(0.05, toleranceSeconds / 2);
  if (diffSeconds <= fine) return '优秀';
  return diffSeconds <= toleranceSeconds ? '达标' : '差一点';
}

/// 停在哪儿了那句话。`diff < 0.005` 读作「正好命中」,否则「早/晚 N.NN 秒」。
String stopwatchStopDetail({
  required int elapsedMs,
  required double targetSeconds,
  required double toleranceSeconds,
}) {
  final double diff = stopwatchDiffSeconds(elapsedMs, targetSeconds);
  if (diff < 0.005) return '正好命中';
  final bool late = elapsedMs / 1000 > targetSeconds;
  return '${late ? '晚 ' : '早 '}${diff.toStringAsFixed(2)} 秒';
}

/// 超出「目标 + 30 秒」还没停 → 这一局作废(忘了停不能永远走下去)。
bool stopwatchAborted(int elapsedMs, double targetSeconds) =>
    elapsedMs > (targetSeconds + 30) * 1000;

// ══════════════════════════════════ walk ══════════════════════════════════

/// 每格 500 步,与原型同值。
const int kWalkStepUnit = 500;

/// 一步约少排这么多 kg,与原型同值。再多位是假精度,这个数本来就是估的。
const double kWalkCo2PerStep = 0.00008;

/// 千分位。LCD 上的数字不加逗号会读成一长串,而这一屏就这一个数。
String walkGroup(int steps) {
  final int v = math.max(0, steps);
  final String digits = v.toString();
  if (digits.length <= 3) return digits;
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// 还差多少。走超了给 0,不给负数 —— 负数会让人以为倒扣。
int walkRemain(int steps, int goal) => math.max(0, goal - steps);

/// 走到几成。目标为 0 时给 0,不给 NaN 或 100。
int walkPercent(int steps, int goal) {
  if (goal <= 0) return 0;
  final int pct = (steps / goal * 100).round();
  return pct.clamp(0, 100);
}

/// 少排多少碳,两位小数。
String walkCo2(int steps) =>
    (math.max(0, steps) * kWalkCo2PerStep).toStringAsFixed(2);

/// 目标对齐到 500 步的整格,下限一格(目标 0 步不是一个目标)。
int walkNormalizeGoal(int goal) =>
    math.max(kWalkStepUnit, (goal / kWalkStepUnit).round() * kWalkStepUnit);

// ══════════════════════════════════ gameTimer ══════════════════════════════════

/// 秒 → MM:SS。真源 `utils/play-ui-contract.formatElapsed`(倒计时/限时快答同源):
/// **向下取整**、补零、负数当 0。
String formatPlayClock(int seconds) {
  final int safe = math.max(0, seconds);
  final int minutes = safe ~/ 60;
  final int remain = safe % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${remain.toString().padLeft(2, '0')}';
}

/// 剩余 / 总时长 → 环上还剩多少(0–100)。总时长缺失时**画满** ——
/// 画成 0 会被读成「已超时」。
int gameTimerRemainPercent(int seconds, int totalSeconds) {
  if (totalSeconds <= 0) return 100;
  final int left = seconds > 0 ? seconds : 0;
  final int pct = (left / totalSeconds * 100).round();
  return pct.clamp(0, 100);
}

// ══════════════════════════════════ stickerBook ══════════════════════════════════

/// 稿 53:308–326 给了五个角度;第六个 -2 是补的 —— 五个循环会让第 6 格和第 1 格
/// 同为 4°,正好落在同一列上下相邻,歪斜就读不出「手贴上去」的随手感了。
const List<int> kStickerTilts = <int>[4, -3, 2, -5, 3, -2];

/// 一张贴纸的输入(服务端/本地流程给什么就是什么,这里不补齐、不猜)。
@immutable
class PlayKitSticker {
  const PlayKitSticker({
    this.id,
    this.label = '',
    this.color,
    this.imgUrl,
    this.isNew = false,
  });

  final int? id;
  final String label;
  final String? color;
  final String? imgUrl;
  final bool isNew;
}

/// 网格里的一格:已收集的贴纸,或一个未解锁空槽。
@immutable
class PlayKitStickerCell {
  const PlayKitStickerCell({
    required this.key,
    required this.locked,
    required this.tilt,
    this.id,
    this.label = '',
    this.color,
    this.imgUrl,
    this.isNew = false,
  });

  /// 稳定 key。**不能用数组下标**:已收集与空槽混在一列里,下标一变整格会闪。
  final String key;
  final bool locked;
  final int tilt;
  final int? id;
  final String label;
  final String? color;
  final String? imgUrl;
  final bool isNew;
}

/// 已收集 + 未解锁数 → 渲染网格(小程序 `buildCells`)。
///
/// `lockedCount` 由调用方给(它知道本城总共几张),组件不猜 —— 空槽不是占位符,
/// 是稿里明确要的「还差几张」。
List<PlayKitStickerCell> buildStickerCells(
  List<PlayKitSticker> stickers,
  int lockedCount,
) {
  final List<PlayKitStickerCell> cells = <PlayKitStickerCell>[];
  for (int i = 0; i < stickers.length; i++) {
    final PlayKitSticker sticker = stickers[i];
    cells.add(
      PlayKitStickerCell(
        key: 's-${sticker.id ?? i}',
        locked: false,
        tilt: kStickerTilts[i % kStickerTilts.length],
        id: sticker.id,
        label: sticker.label,
        color: sticker.color,
        imgUrl: sticker.imgUrl,
        isNew: sticker.isNew,
      ),
    );
  }
  final int locked = lockedCount > 0 ? lockedCount : 0;
  for (int i = 0; i < locked; i++) {
    cells.add(
      PlayKitStickerCell(
        key: 'lock-$i',
        locked: true,
        tilt: kStickerTilts[(stickers.length + i) % kStickerTilts.length],
      ),
    );
  }
  return cells;
}

// ══════════════════════════════════ timeWindow ══════════════════════════════════

/// "HH:mm" → 当天第几分钟;格式不对返回 -1(真源 `minuteOfDay`)。
int playKitMinuteOfDay(String clockText) {
  if (clockText.length != 5 || clockText[2] != ':') return -1;
  final int? hour = int.tryParse(clockText.substring(0, 2));
  final int? minute = int.tryParse(clockText.substring(3));
  if (hour == null || minute == null) return -1;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return -1;
  return hour * 60 + minute;
}

/// 距离**下一个**开放时刻还有多少秒(真源 `secondsUntilOpen`)。
///
/// 今天的开点已过就等明天这个点 —— 跨夜窗口(23:00–01:00)靠这一条兜住,
/// 否则 23:30 会算出一个负数或者一整天。`openFrom` 不是 "HH:mm" 时给 0:
/// 这一屏宁可不倒计时,也不能拿坏数据算出个假读数。
int playKitSecondsUntilOpen(String openFrom, DateTime now) {
  final int from = playKitMinuteOfDay(openFrom);
  if (from < 0) return 0;
  final int nowMinute = now.hour * 60 + now.minute;
  int diff = from - nowMinute;
  if (diff <= 0) diff += 24 * 60;
  return diff * 60 - now.second;
}

/// 剩余秒 → HH:MM:SS;负数与非数字一律归零(不显示 "-1:59:59")。
String playKitClockText(int seconds) {
  final int total = seconds > 0 ? seconds : 0;
  String pad(int value) => value < 10 ? '0$value' : '$value';
  return '${pad(total ~/ 3600)}:${pad((total % 3600) ~/ 60)}:${pad(total % 60)}';
}
