import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/cy_tokens.dart';
import '../playkit_fullscreen.dart';
import 'playkit_timer_logic.dart';
import 'playkit_timer_parts.dart';

/// `cy-playkit-walk` · 低碳行动 · 计步。
///
/// 真源:`~/城瘾app/xcx-ref/pages/play/components/playkit-walk/`。
/// 一条线:设目标 → 倒着数步数 → 归零落章。没有 tab,没有第二条路。
///
/// ## 为什么它是本地 kind,不是 `steps`
/// 小程序原文:「计步单独一个 `walk`:已有的 `steps` 是 v5.1 那批半屏 sheet 的壳,
/// 与这一批整屏的不是一套东西。同名会让人以为换个 kit 就能切,实际两套壳。」
/// 所以这个组件**不吃 `kit` 段数据**,由本地流程直接点名([PlayKitKind.walk]
/// 在 `kLocalPlayKitKinds` 里,服务端段名表里没有它)。
///
/// ## 步数只能同步,不能填
/// 小程序走 `wx.getWeRunData` 拿**加密数据,解密在服务端** —— 客户端拿到的是密文,
/// 连自己都读不出来,更改不了。App 没有微信运动这条链路,所以:
/// **组件自己不造步数,也不假装同步成功**:`steps` 只从外面进来,`syncAvailable`
/// 为 false 时那颗 CTA 是禁用态 + 一行降级说明。等 App 有了步数来源(健康 / 计步权限),
/// 宿主把 `steps` 与 `syncAvailable` 接上即可,组件不用改。
///
/// ## 与真源的已知差异(§7.2 accepted)
/// * 琥珀点阵面板(原型 `#F5A200` 一族)保留:它是这一屏的道具语言。三个琥珀
///   逐值取自真源 wxss,并在小字上提到 `#C98A12` 一档(ADA:小字对比度)。
/// * 字重 900 → w700(T3);字号按原型保留。
class PlayKitWalkView extends StatefulWidget {
  const PlayKitWalkView({
    super.key,
    required this.data,
    this.steps = 0,
    this.syncing = false,
    this.syncAvailable = false,
    this.onGoalChanged,
    this.onSync,
    this.onClaim,
  });

  final PlayKitFullscreenContext data;

  /// 服务端解密回来的步数。**客户端拿不到明文**,所以这个值只会从外面进来。
  final int steps;

  final bool syncing;

  /// App 侧有没有步数来源。默认 false:没有微信运动,也不伪造一个。
  final bool syncAvailable;

  /// 目标改了(每格 500 步)。持久化是宿主的事 —— 真源只 `triggerEvent('goalchange')`。
  final ValueChanged<int>? onGoalChanged;

  /// 「同步」这个意图。拿数据与解密都在外面(客户端读不到明文)。
  final VoidCallback? onSync;

  /// 归零落章。真源 `triggerEvent('claim', { steps, goal })`。
  final VoidCallback? onClaim;

  @override
  State<PlayKitWalkView> createState() => _PlayKitWalkViewState();
}

/// 真源组件默认目标(`properties.goal.value = 6000`)。
const int kWalkDefaultGoal = 6000;

/// 原型道具色(小程序 `playkit-walk/index.wxss`,逐值,`ds-ok`)。
const Color _kWalkSurface = Color(0xFF0B0B0C);
const Color _kWalkInk = Color(0xFFF2F2F2);
const Color _kWalkAmber = Color(0xFFF5A200);
const Color _kWalkAmberDim = Color(0xFFC98A12);
const Color _kWalkPanelTop = Color(0xFF171106);
const Color _kWalkPanelBottom = Color(0xFF0E0B04);
const Color _kWalkPanelBorder = Color(0x4DF59F00);
const Color _kWalkPanelDots = Color(0x29F59F00);

/// 原型 58pt(116rpx)。
const double _kWalkFigureSize = 58;

class _PlayKitWalkViewState extends State<PlayKitWalkView> {
  int? _goalOverride;

  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  int get _goal => walkNormalizeGoal(
    _goalOverride ?? widget.data.card.maxLength ?? kWalkDefaultGoal,
  );

  int get _steps => widget.steps < 0 ? 0 : widget.steps;

  bool get _done => _steps > 0 && walkRemain(_steps, _goal) == 0;

  bool get _running => _steps > 0;

  void _step(int direction) {
    if (_running) return;
    final int next = walkNormalizeGoal(
      _goal + (direction > 0 ? kWalkStepUnit : -kWalkStepUnit),
    );
    // 减动效下不震(真源 motion.haptic 在 reducedMotion 时 return false)。
    if (!_reduced) {
      unawaited(HapticFeedback.lightImpact());
    }
    setState(() => _goalOverride = next);
    widget.onGoalChanged?.call(next);
  }

  void _cta() {
    if (widget.syncing) return;
    if (_done) {
      // 「做成了」= 归零落章那一刻,不是同步按钮按下去那一下。
      if (!_reduced) {
        unawaited(HapticFeedback.mediumImpact());
      }
      widget.onClaim?.call();
      return;
    }
    widget.onSync?.call();
  }

  @override
  Widget build(BuildContext context) {
    final int left = walkRemain(_steps, _goal);
    final int percent = walkPercent(_steps, _goal);
    final bool done = _done;
    final String ctaLabel = done ? '落章' : (widget.syncing ? '同步中…' : '同步微信运动');

    return PlayKitStageSurface(
      background: _kWalkSurface,
      padding: const EdgeInsets.fromLTRB(
        CyTokens.space5,
        CyTokens.space6,
        CyTokens.space5,
        CyTokens.space5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            _running ? (done ? '走到了' : '还差多少') : '今天想走多少',
            style: const TextStyle(
              color: _kWalkInk,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CyTokens.space4),
          _LcdPanel(
            label: _running ? '还差' : '今日目标',
            figure: walkGroup(_running ? left : _goal),
            hint: _running ? (done ? '到了' : '步') : '每格 $kWalkStepUnit 步',
            showStepper: !_running,
            onStep: _step,
            progress: _running ? percent / 100 : null,
            progressLabel: _running
                ? '${walkGroup(_steps)} / ${walkGroup(_goal)} · $percent%'
                : null,
          ),
          const SizedBox(height: CyTokens.space4),
          Row(
            children: <Widget>[
              _Stat(label: '目标', value: walkGroup(_goal)),
              _Stat(label: '已走', value: walkGroup(_steps)),
              _Stat(label: '少排', value: '${walkCo2(_steps)} kg'),
            ],
          ),
          const SizedBox(height: CyTokens.space4),
          Text(
            _running ? '步数只能同步，不能填 —— 能填的话这个玩法就没意义了。' : '先设目标，再同步微信运动。',
            style: const TextStyle(
              color: CyTokens.textSecondary,
              fontSize: CyTokens.typeCaption,
              height: CyTokens.leadingNormal,
            ),
          ),
          if (!widget.syncAvailable) ...<Widget>[
            const SizedBox(height: CyTokens.space1),
            const Text(
              'App 端没有微信运动这条链路:读不到这台设备的步数,组件不伪造步数。',
              style: TextStyle(
                color: CyTokens.textTertiary,
                fontSize: CyTokens.typeCaption,
                height: CyTokens.leadingNormal,
              ),
            ),
          ],
          const Spacer(),
          PlayKitSolidAction(
            label: ctaLabel,
            width: double.infinity,
            background: _kWalkAmber,
            foreground: _kWalkSurface,
            busy: widget.syncing || !widget.syncAvailable,
            onPressed: widget.syncAvailable || done ? _cta : null,
          ),
        ],
      ),
    );
  }
}

/// 琥珀点阵 LCD:面板上的字全是中文,不发光。
class _LcdPanel extends StatelessWidget {
  const _LcdPanel({
    required this.label,
    required this.figure,
    required this.hint,
    required this.showStepper,
    required this.onStep,
    this.progress,
    this.progressLabel,
  });

  final String label;
  final String figure;
  final String hint;
  final bool showStepper;
  final ValueChanged<int> onStep;
  final double? progress;
  final String? progressLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.space3_5,
        CyTokens.space4,
        CyTokens.space3_5,
        CyTokens.space3_5,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        border: Border.all(color: _kWalkPanelBorder),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[_kWalkPanelTop, _kWalkPanelBottom],
        ),
      ),
      child: Stack(
        children: <Widget>[
          const Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _DotMatrixPainter()),
            ),
          ),
          Column(
            children: <Widget>[
              Text(
                label,
                style: const TextStyle(
                  color: _kWalkAmberDim,
                  fontSize: CyTokens.typeCaption,
                ),
              ),
              const SizedBox(height: CyTokens.space2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  _StepperButton(
                    direction: -1,
                    visible: showStepper,
                    onPressed: () => onStep(-1),
                  ),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: PlayKitBigFigure(
                        text: figure,
                        size: _kWalkFigureSize,
                        color: _kWalkAmber,
                      ),
                    ),
                  ),
                  _StepperButton(
                    direction: 1,
                    visible: showStepper,
                    onPressed: () => onStep(1),
                  ),
                ],
              ),
              const SizedBox(height: CyTokens.space2),
              Text(
                hint,
                style: const TextStyle(
                  color: _kWalkAmberDim,
                  fontSize: CyTokens.typeCaption,
                ),
              ),
              if (progress != null) ...<Widget>[
                const SizedBox(height: CyTokens.space3),
                _ProgressBar(progress: progress!),
                const SizedBox(height: CyTokens.space2),
                Text(
                  progressLabel ?? '',
                  style: const TextStyle(
                    color: _kWalkAmberDim,
                    fontSize: CyTokens.typeCaption,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 加减号**画出来**,不用「−」「＋」这两个字符:字符在不同机型上粗细和居中都不一样,
/// 而且读屏器会把它念成「减号」这种没用的词(真正的意思在 aria-label 上)。
class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.direction,
    required this.visible,
    required this.onPressed,
  });

  final int direction;
  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      // 藏起来也占住位:布局不跳(且这就是 44pt 命中区下限本身)
      return const SizedBox.square(dimension: kPlayKitMinTapTarget);
    }
    return Semantics(
      button: true,
      label: direction > 0 ? '增加 $kWalkStepUnit 步' : '减少 $kWalkStepUnit 步',
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(kPlayKitMinTapTarget),
        onPressed: onPressed,
        child: Icon(
          direction > 0 ? CupertinoIcons.plus : CupertinoIcons.minus,
          size: 22,
          color: _kWalkInk,
        ),
      ),
    );
  }
}

/// 进度条。真源用 `transform: scaleX(...)`,App 同义:整条不动、里面那截按比例拉长。
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 6,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: progress.clamp(0, 1).toDouble(),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _kWalkAmber,
              borderRadius: BorderRadius.circular(CyTokens.radiusPill),
            ),
            child: const SizedBox(height: 6),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              color: CyTokens.textTertiary,
              fontSize: CyTokens.typeCaption,
            ),
          ),
          const SizedBox(height: CyTokens.space1),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                color: _kWalkInk,
                fontSize: CyTokens.typeCardTitle,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 点阵是真的点:6pt 一格的小圆点铺满(`radial-gradient(...) 0 0 / 12rpx 12rpx`)。
/// 画成纯色块的话它就只是个深色卡片,读不出「这是一块屏」。
class _DotMatrixPainter extends CustomPainter {
  const _DotMatrixPainter();

  static const double _cell = 6;
  static const double _dot = 1;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = _kWalkPanelDots;
    for (double y = 0; y < size.height; y += _cell) {
      for (double x = 0; x < size.width; x += _cell) {
        canvas.drawCircle(Offset(x + _cell / 2, y + _cell / 2), _dot, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotMatrixPainter oldDelegate) => false;
}
