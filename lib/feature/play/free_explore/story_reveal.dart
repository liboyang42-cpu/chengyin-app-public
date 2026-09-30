// 故事流「停下来那一刻才逐行浮起」的判据。**纯逻辑,不碰 widget** ——
// 判据逐条照搬小程序 `onStoryScroll` / `_settleStory`(pages/play/index.js:1079-1126)。

import 'dart:math' as math;

/// 快滑门槛(每帧位移 px)。样机 `STORY_FAST_PX`(index.js:82)。
const double kStoryFastPx = 18;

/// 慢滑:30ms 后就地显形,手感上「跟着滑就浮出来」。
const Duration kSettleSlow = Duration(milliseconds: 30);

/// 快滑:等 70ms —— 滑得快时屏幕上没有字,这就是 tesseract 的手感。
const Duration kSettleFast = Duration(milliseconds: 70);

/// 每帧位移(px):`|Δtop| / Δt × 16`。
///
/// ⚠️ **判据是每帧位移,不是「每次事件挪了多少」**:滚动事件不保证一帧一次,
///   直接拿事件差值当速度会随机器快慢漂(样机注释原文)。
/// ⚠️ `dt` 下限 **8ms**:两次事件挨太近会算出天文数字,一路判成「快滑」,
///   结果就是永远不显形。
double frameVelocity({
  required double top,
  required double prevTop,
  required Duration dt,
}) {
  final int ms = math.max(8, dt.inMilliseconds);
  return (top - prevTop).abs() / ms * 16;
}

/// 停下来后多久开始量位置显形。
Duration settleDelayFor(double velocity) =>
    velocity < kStoryFastPx ? kSettleSlow : kSettleFast;

/// 这一行在不在滚动框的可视区里。
///
/// 判据是**行的中点**相对滚动框顶的位置:`cy = lineTop + lineHeight/2 - boxTop`,
/// `cy > -20 && cy < boxHeight - 40`。上下各留一档余量,让行在真正贴边时才算出屏 ——
/// 出屏要复位,滚回来能重演一次。
bool lineInView({
  required double lineTop,
  required double lineHeight,
  required double boxTop,
  required double boxHeight,
}) {
  final double cy = lineTop + lineHeight / 2 - boxTop;
  return cy > -20 && cy < boxHeight - 40;
}

/// 同一批补显形的行逐条错开 50ms。
///
/// ★ 一起亮就是整块淡入,不是样机那种一行一行浮起来。
Duration staggerFor(int orderInBatch) =>
    Duration(milliseconds: orderInBatch * 50);
