import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/cy_tokens.dart';

/// 触感档位(只收本族实际用到的三档:轻=撞了一下,中=这一步成了,选中=点中一个选项)。
enum PlayKitHaptic { light, medium, selection }

/// 玩法触感:与小程序 `utils/motion.js` 的 `haptic()` **同一条规矩** ——
/// **减动效下不震**(触感也是动效,reduce-motion 用户一并关掉)。
///
/// 单独抽出来是因为五屏都要用:各写一份的话「减动效还震不震」迟早各说各话,
/// 而这条恰恰是只有真机会暴露、快照与单测都看不见的那类差异(见手册 §3.7 A2)。
void playKitHaptic(BuildContext context, PlayKitHaptic type) {
  if (MediaQuery.disableAnimationsOf(context)) return;
  unawaited(
    switch (type) {
      PlayKitHaptic.light => HapticFeedback.lightImpact(),
      PlayKitHaptic.medium => HapticFeedback.mediumImpact(),
      PlayKitHaptic.selection => HapticFeedback.selectionClick(),
    },
  );
}

/// 整屏族共用的三件小东西(两个以上玩法用到的才放这里;
/// 单处使用的留在各自文件里,免得长出一层谁都要读的中间层)。

/// 眉标:小程序那行小字(23–24rpx / 800 字重 / 6–7rpx 宽字距)。
/// iOS 侧按 T3 把字重收到 w600、字距收窄 —— §7.2 允许的「iOS 27 原生化」。
class PlayKitKicker extends StatelessWidget {
  const PlayKitKicker(this.text, {super.key, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(
      color: color,
      fontSize: CyType.caption1.fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 2,
    ),
  );
}

/// 摇一摇提示行:抖动的圆角方框 + 一行字(抛硬币 / 掷骰子两屏同款)。
class PlayKitShakeHintRow extends StatefulWidget {
  const PlayKitShakeHintRow({
    super.key,
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  State<PlayKitShakeHintRow> createState() => _PlayKitShakeHintRowState();
}

class _PlayKitShakeHintRowState extends State<PlayKitShakeHintRow>
    with SingleTickerProviderStateMixin {
  // 小程序 .9s ease-in-out infinite,±13deg。这是**提示动画**不是过渡,
  // 但档位里没有 900ms 这一格,所以由这里的编排常数给出(见 CyMotion 注释:
  // 逐帧编排留在各自模块里具名;字面量登记在 motion_ratchet 白名单)。
  static const Duration _shakeCycle = Duration(milliseconds: 900);
  late final AnimationController _shake;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: _shakeCycle,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _shake.stop();
      _shake.value = 0;
    } else if (!_shake.isAnimating) {
      _shake.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // ★ 必须走 AnimatedBuilder:_shake.value 只在 build 里读的话没人重建,
        //   方框会**冻在起始角度**上一个永不摆(快照与门禁都看不见这种死动画)。
        AnimatedBuilder(
          animation: _shake,
          builder: (BuildContext context, Widget? child) {
            final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
            final double angle = reduceMotion
                ? 0
                : (_shake.value * 2 - 1) * 0.2269;
            return Transform.rotate(angle: angle, child: child);
          },
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              border: Border.all(color: widget.color, width: 2),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
        const SizedBox(width: CyTokens.space2),
        Text(
          widget.text,
          style: TextStyle(
            color: widget.color,
            fontSize: CyType.footnote.fontSize,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

/// 玩法自己的主按钮(弹球 / 安静挑战):52pt 高、胶囊。
/// 小程序原型 .blb / .qtb 压在球场上、跟着内容流走,比通用按钮小一档。
/// 字重用 w700 收口(原型 800,T3 不许 w800)。
class PlayKitStageButton extends StatefulWidget {
  const PlayKitStageButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.background,
    required this.foreground,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color background;
  final Color foreground;

  /// 进行中:文案换成忙碌态、点不动(小程序 .55 透明度)。
  final bool busy;

  @override
  State<PlayKitStageButton> createState() => _PlayKitStageButtonState();
}

class _PlayKitStageButtonState extends State<PlayKitStageButton> {
  // 按下变暗是 iOS 原生按钮的基本反馈 —— 与同层 PlayKitSolidAction 同一档。
  static const double _pressedOpacity = 0.88;
  bool _pressed = false;

  bool get _tappable => !widget.busy && widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: _tappable,
      label: widget.label,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: !_tappable
              ? 0.55
              : _pressed
              ? _pressedOpacity
              : 1,
          child: GestureDetector(
            onTapDown: _tappable ? (_) => setState(() => _pressed = true) : null,
            onTapUp: _tappable ? (_) => setState(() => _pressed = false) : null,
            onTapCancel: _tappable ? () => setState(() => _pressed = false) : null,
            onTap: _tappable ? widget.onPressed : null,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: widget.background,
                borderRadius: BorderRadius.circular(CyTokens.radiusPill),
              ),
              child: Text(
                widget.label,
                style: TextStyle(
                  color: widget.foreground,
                  fontSize: CyType.callout.fontSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 传感器玩法开局前的校准层(弹球 / 安静挑战共用)。
///
/// 采样本身不在这里:谁在量谁最清楚怎么量(麦克风取每拍峰值 / 加速度记零点),
/// 这一层只管「进度与时长」—— 与小程序 `cy-play-calibrate` 同一分工。
class PlayKitCalibratePanel extends StatelessWidget {
  const PlayKitCalibratePanel({
    super.key,
    required this.label,
    required this.progress,
    required this.ink,
    required this.soft,
    this.sub = '别动，量一下这儿的底子',
  });

  final String label;

  /// 0–1,直接喂进度条。
  final double progress;
  final Color ink;
  final Color soft;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: '$label，$sub',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ink,
                fontSize: CyType.headline.fontSize,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: CyTokens.space4),
            SizedBox(
              width: 220,
              height: 6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(child: ColoredBox(color: soft)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: progress.clamp(0.0, 1.0),
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: ink,
                            borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            SizedBox(
              width: 260,
              child: Text(
                sub,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ink.withValues(alpha: 0.66),
                  fontSize: CyType.subhead.fontSize,
                  height: 1.6,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
