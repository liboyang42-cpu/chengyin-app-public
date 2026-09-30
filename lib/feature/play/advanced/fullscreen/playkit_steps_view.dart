import 'package:flutter/cupertino.dart';

import '../../../../core/theme/cy_palette.dart';
import '../../../../core/theme/cy_tokens.dart';
import '../../free_explore/widgets/segmented_ring.dart';
import '../playkit_fullscreen.dart';
import '../playkit_projection.dart';
import 'playkit_step_row.dart';
import 'playkit_timer_logic.dart';
import 'playkit_timer_parts.dart';

/// 每步约 0.03g CO₂。真源 `utils/playkit-view.js#CO2_GRAM_PER_STEP` 同值
/// (稿 48:279 给的 4286 步 ≈ 128g 反推),只用于文案,**不参与判定**。
const double kPlayKitCo2GramPerStep = 0.03;

/// 已减排的克数(四舍五入到整数克)。
int playKitStepsCo2Gram(int steps) =>
    ((steps > 0 ? steps : 0) * kPlayKitCo2GramPerStep).round();

/// 已减排文案。真源 `buildSteps` 那句比较也照抄 ——
/// 它是一句固定比喻,不是按步数换算出来的。
String playKitStepsCo2Label(int steps) =>
    '已减排 ${playKitStepsCo2Gram(steps)}g CO₂ · 约等于一杯奶茶的吸管';

/// 还差多少 / 已达标。真源 `buildSteps#remainLabel` 同口径:
/// 拿到 XP 才在句尾报它的数(没配就不报,不写「+0 XP」)。
String playKitStepsRemainLabel({required int steps, required int goal, int xp = 0}) {
  final int remain = walkRemain(steps, goal);
  if (remain <= 0) return '已达标,爪印已落章';
  return '再走 ${walkGroup(remain)} 步,爪印落章${xp > 0 ? ' + $xp XP' : ''}';
}

/// `cy-playkit-steps` · 计步挑战(Figma v5.1 node 48:270)。
///
/// 真源:`~/城瘾app/xcx-ref/pages/play/components/playkit-steps/`。
///
/// ## 这一屏只画,不取数
/// 真源头注原文:「步数来源是微信运动(`wx.getWeRunData`),取数与解密归页面/服务端;
/// 组件只负责画」。App 侧没有微信运动这个来源(AGENTS.md:不伪造),
/// 所以**没有「刷新步数」那颗按钮** —— 真源那颗按钮发的是 `SUBMIT_STEPS`,
/// 契约要求 `encryptedData + iv` 两个只有小程序拿得到的字段;
/// 发一条空载荷出去会被服务端按 0 判,比不发更坏。
/// 位置留给一行说明,口径与半屏那条通用卡一致。
///
/// ## 这一件在小程序里是「半屏 sheet」
/// 壳是 `cy-sheet`,不是 `cy-play-stage` —— 所以**没有**进 [kFullscreenPlayKinds]。
///
/// ## 与真源的已知差异(§7.2 accepted)
/// * `cy-ring-meter segments="60"` → 复用仓内 `segmentedRing` 的几何,段数照真源取 60。
/// * CTA「刷新步数」→ 换成一行来源说明(理由见上)。
class PlayKitStepsView extends StatelessWidget {
  const PlayKitStepsView({
    super.key,
    required this.data,
    this.showGrabber = true,
  });

  final PlayKitFullscreenContext data;

  /// 宿主用原生 sheet 呈现时关掉。
  final bool showGrabber;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final PlayKitCard card = data.card;
    final Map<String, Object?> kit = card.kit;
    final int today = _int(kit['todaySteps'] ?? kit['steps']);
    final int goal = _int(kit['goal']);
    final int xp = _int(kit['xp']);
    final String eyebrow = _text(kit['eyebrow']).isEmpty
        ? '低碳行动 · 今日步数'
        : _text(kit['eyebrow']);
    final int percent = walkPercent(today, goal);
    final String a11y = playKitStepsA11y(card.kind, _text(kit['steps']));

    return Container(
      decoration: BoxDecoration(
        color: palette.bgSurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CyTokens.radiusXl),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        CyTokens.space5,
        CyTokens.space2,
        CyTokens.space5,
        CyTokens.space5,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (showGrabber)
            Center(
              child: Semantics(
                label: '下滑关闭',
                child: Container(
                  width: 36,
                  height: 5,
                  margin: const EdgeInsets.only(top: CyTokens.space1),
                  decoration: BoxDecoration(
                    color: palette.borderStrong,
                    borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                  ),
                ),
              ),
            ),
          const SizedBox(height: CyTokens.space3),
          PlayKitEyebrow(eyebrow, color: palette.textSecondary),
          const SizedBox(height: CyTokens.space3),
          PlayKitStepRow(
            kind: card.kind,
            a11yLabel: a11y,
            color: palette.textPrimary,
          ),
          const SizedBox(height: CyTokens.space4),
          Center(
            child: SizedBox(
              width: 216,
              height: 216,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  CustomPaint(
                    painter: _StepsRingPainter(
                      percent: percent,
                      tone: palette.statusSuccess,
                      track: palette.borderSubtle,
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        PlayKitBigFigure(
                          text: walkGroup(today),
                          size: 52,
                          color: palette.textPrimary,
                          semanticsLabel: '今日已走 ${walkGroup(today)} 步',
                        ),
                        const SizedBox(height: CyTokens.space1),
                        Text(
                          '/ ${walkGroup(goal)} 步',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: CyTokens.typeBody,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: CyTokens.space3),
          Text(
            playKitStepsCo2Label(today),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.statusSuccess,
              fontSize: CyTokens.typeCaption,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: CyTokens.space2),
          Text(
            playKitStepsRemainLabel(steps: today, goal: goal, xp: xp),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: CyTokens.typeBody,
            ),
          ),
          const SizedBox(height: CyTokens.space4),
          // 真源这颗是「刷新步数」。App 拿不到微信运动,发空载荷会被按 0 判 ——
          // 所以换成说明:这条契约在 App 上不可用,不装作可用。
          Text(
            '步数只认微信运动授权后的服务端解密结果，App 不会伪造步数提交',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textTertiary,
              fontSize: CyTokens.typeCaption,
              height: CyTokens.leadingNormal,
            ),
          ),
        ],
      ),
    );
  }
}

/// 60 段环(真源 `cy-ring-meter segments="60"`)。几何取自仓内 `segmentedRing`,
/// 与 `playkit_game_timer_view.dart` 的 40 段环同一支画笔,只有段数不同。
class _StepsRingPainter extends CustomPainter {
  const _StepsRingPainter({
    required this.percent,
    required this.tone,
    required this.track,
  });

  final int percent;
  final Color tone;
  final Color track;

  static const int _segments = 60;
  static const double _stroke = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final int filled = (percent.clamp(0, 100) / 100 * _segments).round();
    final List<RingSegment> segments = segmentedRing(
      total: _segments,
      done: filled,
    );
    final Rect arcRect = (Offset.zero & size).deflate(_stroke / 2);
    for (final RingSegment segment in segments) {
      canvas.drawArc(
        arcRect,
        segment.startAngle,
        segment.sweepAngle,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = _stroke
          ..color = segment.filled ? tone : track,
      );
    }
  }

  @override
  bool shouldRepaint(_StepsRingPainter oldDelegate) =>
      oldDelegate.percent != percent ||
      oldDelegate.tone != tone ||
      oldDelegate.track != track;
}

String _text(Object? value) => value?.toString().trim() ?? '';

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}
