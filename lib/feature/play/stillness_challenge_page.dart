import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/cy_native_button.dart';

import '../../core/theme/cy_tokens.dart';
import '../../data/api/play_api.dart';
import '../../data/models/checkin_models.dart';
import 'stillness_challenge_controller.dart';
import 'stillness_platform.dart';

typedef StillnessSubmit = Future<CheckinReward> Function(int heldSec);

class StillnessChallengePage extends StatefulWidget {
  const StillnessChallengePage({
    super.key,
    required this.title,
    required this.config,
    required this.source,
    required this.wakeLock,
    required this.onSubmit,
  });

  final String title;
  final StillnessConfig config;
  final StillnessSampleSource source;
  final ScreenWakeLock wakeLock;
  final StillnessSubmit onSubmit;

  @override
  State<StillnessChallengePage> createState() => _StillnessChallengePageState();
}

class _StillnessChallengePageState extends State<StillnessChallengePage>
    with WidgetsBindingObserver {
  late final StillnessChallengeController _controller;
  bool _purposeAccepted = false;
  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = StillnessChallengeController(
      source: widget.source,
      target: widget.config.duration,
      tolerance: widget.config.tolerance,
    )..addListener(_onProgressChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_purposeAccepted) return;
    if (state == AppLifecycleState.resumed) {
      _controller.resume();
      unawaited(_setWakeLock(true));
      return;
    }
    _controller.pause();
    unawaited(_setWakeLock(false));
  }

  void _acceptPurpose() {
    if (_purposeAccepted) return;
    setState(() => _purposeAccepted = true);
    _controller.start();
    unawaited(_setWakeLock(true));
  }

  Future<void> _setWakeLock(bool enabled) async {
    try {
      if (enabled) {
        await widget.wakeLock.enable();
      } else {
        await widget.wakeLock.disable();
      }
    } catch (_) {
      // 亮屏是体验增强；系统拒绝时挑战仍按传感器事实继续。
    }
  }

  void _onProgressChanged() {
    if (!mounted) return;
    setState(() {});
    if (_controller.state.phase == StillnessPhase.completed) {
      unawaited(_submit());
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final CheckinReward reward = await widget.onSubmit(
        widget.config.duration.inSeconds,
      );
      if (mounted) Navigator.of(context).pop(reward);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = error is PlayException ? error.message : '提交失败，请重试';
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onProgressChanged);
    _controller.dispose();
    if (_purposeAccepted) unawaited(_setWakeLock(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_purposeAccepted) {
      return _StillnessPurposeNotice(
        title: widget.title,
        onAccept: _acceptPurpose,
        onCancel: () => Navigator.of(context).pop(),
      );
    }
    final StillnessState state = _controller.state;
    final _StillnessSkin skin = _StillnessSkin.forTitle(widget.title);
    final double progress = widget.config.duration.inMilliseconds == 0
        ? 0
        : (state.stableFor.inMilliseconds /
                  widget.config.duration.inMilliseconds)
              .clamp(0.0, 1.0);
    final int heldSeconds = state.stableFor.inMilliseconds ~/ 1000;
    final int targetSeconds = widget.config.duration.inSeconds;

    return Scaffold(
      backgroundColor: CyTokens.bgPage,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double ringSize = math.min(
              CyTokens.stillnessRingSize,
              constraints.maxWidth - CyTokens.space6 * 2,
            );
            return Stack(
              children: <Widget>[
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    CyTokens.space5,
                    CyTokens.space7,
                    CyTokens.space5,
                    CyTokens.space5,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: math.max(
                        0,
                        constraints.maxHeight - CyTokens.space6 * 2,
                      ),
                    ),
                    child: Column(
                      children: <Widget>[
                        Text(
                          widget.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: CyTokens.textPrimary,
                            fontSize: CyTokens.typeButton,
                            fontWeight: FontWeight.w700,
                            letterSpacing: CyTokens.stillnessTitleTracking,
                          ),
                        ),
                        const SizedBox(height: CyTokens.space2),
                        const Text(
                          'APP 传感器挑战 · XP / 徽章',
                          style: TextStyle(
                            color: CyTokens.textTertiary,
                            fontSize: CyTokens.typeCaption,
                            letterSpacing: CyTokens.stillnessCaptionTracking,
                          ),
                        ),
                        const SizedBox(
                          height: CyTokens.space8 + CyTokens.space5,
                        ),
                        SizedBox(
                          width: ringSize,
                          height: ringSize,
                          child: TweenAnimationBuilder<double>(
                            duration: CyMotion.fast,
                            tween: Tween<double>(end: progress),
                            builder:
                                (
                                  BuildContext context,
                                  double value,
                                  Widget? child,
                                ) => Stack(
                                  fit: StackFit.expand,
                                  children: <Widget>[
                                    CustomPaint(
                                      painter: _StillnessRingPainter(
                                        value: value,
                                        stroke: CyTokens.stillnessRingStroke,
                                        trackColor: CyTokens.borderStrong,
                                        progressColor: CyTokens.statusInfo,
                                      ),
                                    ),
                                    child!,
                                  ],
                                ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Text(
                                  '$heldSeconds',
                                  style: const TextStyle(
                                    color: CyTokens.textPrimary,
                                    fontSize: CyTokens.stillnessTimerType,
                                    height: 1,
                                    fontWeight: FontWeight.w700,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                                const SizedBox(height: CyTokens.space2),
                                Text(
                                  '/ $targetSeconds 秒',
                                  style: const TextStyle(
                                    color: CyTokens.textSecondary,
                                    fontSize: CyTokens.typeBody,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: CyTokens.space6),
                        Text(
                          _statusText(state, skin),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: CyTokens.textSecondary,
                            fontSize: CyTokens.typeLabel,
                          ),
                        ),
                        const SizedBox(height: CyTokens.space3),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            CyTokens.radiusSm,
                          ),
                          child: SizedBox(
                            width: CyTokens.stillnessStabilityWidth,
                            height: CyTokens.stillnessStabilityHeight,
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                const ColoredBox(color: CyTokens.borderStrong),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor: state.stability,
                                    child: const ColoredBox(
                                      color: CyTokens.statusSuccess,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: CyTokens.space8),
                        const _CatGuide(),
                        const SizedBox(height: CyTokens.space4),
                        Text(
                          _submitting ? '正在向猫汇报…' : skin.guideLabel,
                          style: const TextStyle(
                            color: CyTokens.textTertiary,
                            fontSize: CyTokens.typeLabel,
                          ),
                        ),
                        if (_submitError != null) ...<Widget>[
                          const SizedBox(height: CyTokens.space3),
                          Text(
                            _submitError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: CyTokens.statusDanger,
                              fontSize: CyTokens.typeCaption,
                            ),
                          ),
                          CupertinoButton(
                            minimumSize: const Size(44, 44),
                            onPressed: _submit,
                            child: const Text('重新提交'),
                          ),
                        ],
                        const SizedBox(height: CyTokens.space5),
                        CupertinoButton(
                          minimumSize: const Size(44, 44),
                          onPressed: _submitting
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: const Text(
                            '放弃(会被猫嘲笑)',
                            style: TextStyle(
                              color: CyTokens.textTertiary,
                              fontSize: CyTokens.typeLabel,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: CyTokens.space2,
                  top: 0,
                  child: CupertinoButton(
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Icon(
                      CupertinoIcons.xmark,
                      semanticLabel: '退出挑战',
                      color: CyTokens.textSecondary,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _statusText(StillnessState state, _StillnessSkin skin) {
    if (state.phase == StillnessPhase.paused) return '已暂停 · 回到前台继续';
    if (state.phase == StillnessPhase.failed) {
      return state.errorMessage ?? '传感器暂不可用';
    }
    if (state.phase == StillnessPhase.completed) return '挑战完成 · 正在提交';
    if (state.resetCount > 0 && state.stableFor == Duration.zero) {
      return '检测到晃动 · 已重新计时';
    }
    if (state.phase == StillnessPhase.holding) return skin.holdingLabel;
    return skin.idleLabel;
  }
}

class _StillnessPurposeNotice extends StatelessWidget {
  const _StillnessPurposeNotice({
    required this.title,
    required this.onAccept,
    required this.onCancel,
  });

  final String title;
  final VoidCallback onAccept;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CyTokens.bgPage,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(CyTokens.space5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Spacer(),
              const Icon(
                Icons.sensors_outlined,
                size: CyTokens.stillnessGuideSize,
                color: CyTokens.statusInfo,
              ),
              const SizedBox(height: CyTokens.space5),
              Text(
                '开始$title',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: CyTokens.textPrimary,
                  fontSize: CyTokens.typeSectionTitle,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: CyTokens.space3),
              const Text(
                '将读取本机加速度计，仅用于判断设备是否保持静止。离开本页即暂停，不后台采集；结果只结算 XP / 徽章，不发真金券。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: CyTokens.textSecondary,
                  fontSize: CyTokens.typeBody,
                  height: CyTokens.leadingLoose,
                ),
              ),
              const SizedBox(height: CyTokens.space6),
              CyNativeButton(label: '同意并开始', onPressed: onAccept),
              CupertinoButton(
                minimumSize: const Size(44, 44),
                onPressed: onCancel,
                child: const Text('暂不开始'),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _StillnessSkin {
  const _StillnessSkin({
    required this.idleLabel,
    required this.holdingLabel,
    required this.guideLabel,
  });

  final String idleLabel;
  final String holdingLabel;
  final String guideLabel;

  static _StillnessSkin forTitle(String title) {
    if (title.contains('摆烂')) {
      return const _StillnessSkin(
        idleLabel: '把手机放稳 · 开始充电',
        holdingLabel: '摆烂充电中 · 晃动会重置',
        guideLabel: '猫向导陪你摆烂充电中…',
      );
    }
    return const _StillnessSkin(
      idleLabel: '先稳住手机 · 检测中',
      holdingLabel: '稳如老狗 · 晃动会重置',
      guideLabel: '猫向导陪你入定中…',
    );
  }
}

class _CatGuide extends StatelessWidget {
  const _CatGuide();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: CyTokens.stillnessGuideSize,
      height: CyTokens.stillnessGuideSize,
      decoration: const BoxDecoration(
        color: CyTokens.textPrimary,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.pets,
        size: CyTokens.stillnessGuideIconSize,
        color: CyTokens.textInverse,
      ),
    );
  }
}

/// 静止挑战的环形进度。用 CustomPaint 自绘,不用 Material 的环形加载件
/// —— play/roam 域的门禁禁用 Material 动作与加载控件。
class _StillnessRingPainter extends CustomPainter {
  const _StillnessRingPainter({
    required this.value,
    required this.stroke,
    required this.trackColor,
    required this.progressColor,
  });

  final double value;
  final double stroke;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Rect arcRect = rect.deflate(stroke / 2);
    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = trackColor;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, track);
    if (value <= 0) return;
    final Paint progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = progressColor;
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      math.pi * 2 * value.clamp(0.0, 1.0),
      false,
      progress,
    );
  }

  @override
  bool shouldRepaint(_StillnessRingPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.stroke != stroke ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.progressColor != progressColor;
}
