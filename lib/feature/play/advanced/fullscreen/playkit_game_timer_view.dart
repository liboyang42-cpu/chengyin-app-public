import 'package:flutter/cupertino.dart';

import '../../../../core/theme/cy_palette.dart';
import '../../../../core/theme/cy_tokens.dart';
import '../../free_explore/widgets/segmented_ring.dart';
import '../playkit_fullscreen.dart';
import '../playkit_projection.dart';
import 'playkit_timer_logic.dart';
import 'playkit_timer_parts.dart';

/// `cy-game-timer` · 计时快答(限时题)。
///
/// 真源:`~/城瘾app/xcx-ref/pages/play/components/game-timer/`。
///
/// ## 组件不自己跑秒
/// 限时题的权威计时在**服务端**(否则改手机时间就能拿满连击奖励)。页面按服务端下发的
/// deadline 推 `seconds`,组件只把它画成环与数字。`state` 同理由宿主给 ——
/// 什么时候算 `critical` 是玩法规则,不是渲染规则。
///
/// ## 这一件在小程序里是「半屏 sheet」
/// 它的 `usingComponents` 是 `cy-sheet`(带 grabber 的半屏),不是 `cy-play-stage`。
/// 所以 App 侧这一件渲染的是**sheet 内容**(圆角顶部 + 可选 grabber),
/// **没有**登记进 `kFullscreenPlayKinds` —— 那个集合的语义是「必须占满屏」。
/// 宿主若用原生 sheet 呈现,把 `showGrabber` 关掉即可(系统自带那条)。
///
/// ## 与真源的已知差异(§7.2 accepted)
/// * `cy-ring-meter` 的 40 段环 → 复用仓内 `segmentedRing` 的**几何**,
///   颜色走语义色(info/danger/success),因为小程序那支环的 tone 也是这三个。
/// * 字重 900 → w700(T3)。
class PlayKitGameTimerView extends StatelessWidget {
  const PlayKitGameTimerView({
    super.key,
    required this.data,
    this.state,
    this.remainingSeconds,
    this.statusLabel = '',
    this.chips = const <String>[],
    this.showGrabber = true,
    this.onCta,
  });

  final PlayKitFullscreenContext data;

  /// 玩法状态。留空时按卡片推:`complete` → result、`started` → running、否则 ready。
  /// `critical` **推不出来** —— 那是玩法规则,只能由宿主给。
  final PlayKitGameTimerState? state;

  /// 剩余秒数(服务端 deadline 推出来的)。留空时读 `card.durationSeconds`。
  final int? remainingSeconds;

  final String statusLabel;
  final List<String> chips;

  /// 宿主用原生 sheet 时关掉:系统自带那条 grabber。
  final bool showGrabber;

  /// 底部那颗按钮。真源 `triggerEvent('cta', { state })`。
  final ValueChanged<PlayKitGameTimerState>? onCta;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final PlayKitCard card = data.card;
    final int total = card.durationSeconds;
    final int left = remainingSeconds ?? total;
    final PlayKitGameTimerState resolved = state ?? _fromCard(card);
    final int percent = gameTimerRemainPercent(left, total);
    final Color tone = switch (resolved) {
      PlayKitGameTimerState.ready ||
      PlayKitGameTimerState.running => palette.statusInfo,
      PlayKitGameTimerState.critical => palette.statusDanger,
      PlayKitGameTimerState.result => palette.statusSuccess,
    };
    final String ctaLabel = card.primaryAction?.label ?? '';

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
          if (statusLabel.isNotEmpty || card.eyebrow.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  statusLabel,
                  style: TextStyle(
                    color: tone,
                    fontSize: CyTokens.typeCaption,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  card.eyebrow.isEmpty ? '限时挑战' : card.eyebrow,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: CyTokens.typeCaption,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          const SizedBox(height: CyTokens.space4),
          Center(
            child: SizedBox(
              width: 208,
              height: 208,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  CustomPaint(
                    painter: _RingMeterPainter(
                      percent: percent,
                      tone: tone,
                      track: palette.borderSubtle,
                    ),
                  ),
                  Center(
                    child: PlayKitBigFigure(
                      text: formatPlayClock(left),
                      size: 44,
                      color: palette.textPrimary,
                      semanticsLabel: '剩余 ${formatPlayClock(left)}',
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (card.title.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space4),
            Text(
              card.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: CyTokens.typeSectionTitle,
                fontWeight: FontWeight.w600,
                height: CyTokens.leadingNormal,
              ),
            ),
          ],
          if (card.detail.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Text(
              card.detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: CyTokens.typeBody,
                height: CyTokens.leadingNormal,
              ),
            ),
          ],
          if (card.hint.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            Text(
              card.hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textTertiary,
                fontSize: CyTokens.typeLabel,
              ),
            ),
          ],
          if (chips.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space4),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: CyTokens.space2,
              runSpacing: CyTokens.space2,
              children: <Widget>[
                for (final String chip in chips)
                  PlayKitPill(
                    chip,
                    foreground: palette.textSecondary,
                    background: palette.bgSurfaceSubtle,
                  ),
              ],
            ),
          ],
          if (ctaLabel.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space5),
            PlayKitSolidAction(
              label: ctaLabel,
              width: double.infinity,
              background: resolved == PlayKitGameTimerState.critical
                  ? palette.statusDanger
                  : palette.actionPrimaryBg,
              foreground: resolved == PlayKitGameTimerState.critical
                  ? palette.textInverse
                  : palette.actionPrimaryFg,
              busy: !data.enabled || data.acting,
              onPressed: () => _emitCta(resolved),
            ),
          ],
        ],
      ),
    );
  }

  void _emitCta(PlayKitGameTimerState resolved) {
    final ValueChanged<PlayKitGameTimerState>? callback = onCta;
    if (callback != null) {
      callback(resolved);
      return;
    }
    // 宿主没给回调时,把卡片自带的主动作原样转发 —— 组件不替它编一个动作名。
    final PlayKitAction? action = data.card.primaryAction;
    if (action != null) data.onAction?.call(action);
  }

  static PlayKitGameTimerState _fromCard(PlayKitCard card) {
    if (card.complete) return PlayKitGameTimerState.result;
    if (card.started) return PlayKitGameTimerState.running;
    return PlayKitGameTimerState.ready;
  }
}

enum PlayKitGameTimerState { ready, running, critical, result }

/// 40 段环。几何复用自由探索那支 `segmentedRing`(同一套分段口径),
/// 颜色按 tone 走语义色 —— 小程序 `cy-ring-meter` 的 tone 正是 info/danger/success。
class _RingMeterPainter extends CustomPainter {
  const _RingMeterPainter({
    required this.percent,
    required this.tone,
    required this.track,
  });

  final int percent;
  final Color tone;
  final Color track;

  static const int _segments = 40;
  static const double _stroke = 12;

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
  bool shouldRepaint(_RingMeterPainter oldDelegate) =>
      oldDelegate.percent != percent ||
      oldDelegate.tone != tone ||
      oldDelegate.track != track;
}
