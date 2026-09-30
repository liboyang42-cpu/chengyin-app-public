import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';

enum StopwatchRevealMode { delay, never, always }

enum _StopwatchPhase { idle, running, done }

@immutable
class StopwatchVerdict {
  const StopwatchVerdict({
    required this.tierLabel,
    required this.stars,
    required this.diff,
    required this.late,
  });

  final String tierLabel;
  final int stars;
  final double diff;
  final bool late;
}

double normalizeStopwatchTarget(double value) {
  if (!value.isFinite) return 10;
  return (value.clamp(3, 60) * 100).round() / 100;
}

StopwatchVerdict judgeStopwatch(
  double elapsedSeconds,
  double targetSeconds, {
  double tolerance = 0.05,
}) {
  final double target = normalizeStopwatchTarget(targetSeconds);
  final double elapsed = elapsedSeconds.isFinite
      ? elapsedSeconds.clamp(0, double.infinity)
      : 0;
  final double diff = ((elapsed - target).abs() * 100).round() / 100;
  final double scale = tolerance > 0 ? tolerance / 0.05 : 1;
  if (diff <= 0.05 * scale) {
    return StopwatchVerdict(
      tierLabel: '完美',
      stars: 3,
      diff: diff,
      late: elapsed > target,
    );
  }
  if (diff <= 0.20 * scale) {
    return StopwatchVerdict(
      tierLabel: '优秀',
      stars: 2,
      diff: diff,
      late: elapsed > target,
    );
  }
  if (diff <= 0.50 * scale) {
    return StopwatchVerdict(
      tierLabel: '及格',
      stars: 1,
      diff: diff,
      late: elapsed > target,
    );
  }
  return StopwatchVerdict(
    tierLabel: '失手',
    stars: 0,
    diff: diff,
    late: elapsed > target,
  );
}

class StopwatchGamePage extends ConsumerStatefulWidget {
  const StopwatchGamePage({
    super.key,
    this.targetSeconds = 10,
    this.revealMode = StopwatchRevealMode.delay,
    this.tolerance = 0.05,
    this.templateId,
    this.now,
  });

  final double targetSeconds;
  final StopwatchRevealMode revealMode;
  final double tolerance;
  final String? templateId;
  final DateTime Function()? now;

  @override
  ConsumerState<StopwatchGamePage> createState() => _StopwatchGamePageState();
}

class _StopwatchGamePageState extends ConsumerState<StopwatchGamePage>
    with WidgetsBindingObserver {
  Timer? _ticker;
  DateTime? _startedAt;
  _StopwatchPhase _phase = _StopwatchPhase.idle;
  StopwatchVerdict? _result;
  String _digits = '';
  String _caption = '';
  int _roundCount = 0;
  double? _bestDiff;
  late double _targetSeconds;
  late StopwatchRevealMode _revealMode;
  late double _tolerance;
  String _templateId = '';
  bool _templateRestoreStarted = false;

  DateTime get _now => widget.now?.call() ?? DateTime.now();
  double get _target => normalizeStopwatchTarget(_targetSeconds);

  @override
  void initState() {
    super.initState();
    _targetSeconds = widget.targetSeconds;
    _revealMode = widget.revealMode;
    _tolerance = widget.tolerance;
    WidgetsBinding.instance.addObserver(this);
    _syncIdle();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_templateRestoreStarted) return;
    _templateRestoreStarted = true;
    final String explicit = widget.templateId?.trim() ?? '';
    final GoRouter? router = GoRouter.maybeOf(context);
    _templateId = explicit.isNotEmpty
        ? explicit
        : (router?.state.uri.queryParameters['id']?.trim() ?? '');
    if (_templateId.isNotEmpty) unawaited(_restoreTemplateResult());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_phase == _StopwatchPhase.running &&
        (state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached)) {
      _abort();
    }
  }

  void _syncIdle() {
    _phase = _StopwatchPhase.idle;
    _digits = _formatSeconds(_target);
    _caption = '在 ${_formatSeconds(_target)} 秒按停 · ${_revealText(_revealMode)}';
  }

  String get _templateStorageKey =>
      'stopwatch_template_v1_${Uri.encodeComponent(_templateId)}';

  Future<void> _restoreTemplateResult() async {
    try {
      final String? encoded = await ref
          .read(secureStorageProvider)
          .read(key: _templateStorageKey);
      if (!mounted || encoded == null) return;
      final Object? decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return;
      final int rounds = (decoded['rounds'] as num?)?.toInt() ?? 0;
      final double? best = (decoded['best'] as num?)?.toDouble();
      final double? target = (decoded['target'] as num?)?.toDouble();
      final double? tolerance = (decoded['tolerance'] as num?)?.toDouble();
      final StopwatchRevealMode reveal = switch (decoded['reveal']) {
        'never' => StopwatchRevealMode.never,
        'always' => StopwatchRevealMode.always,
        _ => StopwatchRevealMode.delay,
      };
      setState(() {
        _roundCount = rounds < 0 ? 0 : rounds;
        _bestDiff = best != null && best.isFinite && best >= 0 ? best : null;
        if (target != null && target.isFinite) _targetSeconds = target;
        if (tolerance != null && tolerance.isFinite && tolerance > 0) {
          _tolerance = tolerance;
        }
        _revealMode = reveal;
        _syncIdle();
      });
    } on Object {
      // 旧版或损坏记录不应阻断本局游玩。
    }
  }

  Future<void> _saveTemplateResult() async {
    if (_templateId.isEmpty) return;
    final String reveal = switch (_revealMode) {
      StopwatchRevealMode.delay => 'delay',
      StopwatchRevealMode.never => 'never',
      StopwatchRevealMode.always => 'always',
    };
    try {
      await ref
          .read(secureStorageProvider)
          .write(
            key: _templateStorageKey,
            value: jsonEncode(<String, Object?>{
              'target': _target,
              'reveal': reveal,
              'tolerance': _tolerance,
              'rounds': _roundCount,
              'best': _bestDiff,
            }),
          );
    } on Object {
      // 存档失败不影响本局结果展示，下次进入仍可重试。
    }
  }

  void _onTap() {
    if (_phase == _StopwatchPhase.running) {
      _stop();
    } else {
      _start();
    }
  }

  void _start() {
    _ticker?.cancel();
    _startedAt = _now;
    _phase = _StopwatchPhase.running;
    _result = null;
    _caption = '凭体感按停';
    _digits = _visibleAt(0) ? '00.00' : '––.––';
    if (_revealMode != StopwatchRevealMode.never) {
      _ticker = Timer.periodic(
        const Duration(milliseconds: 50),
        (_) => _tick(),
      );
    }
    HapticFeedback.selectionClick();
    setState(() {});
  }

  void _tick() {
    if (!mounted || _phase != _StopwatchPhase.running) return;
    final double elapsed = _elapsedSeconds();
    if (!_visibleAt(elapsed)) {
      _ticker?.cancel();
      _ticker = null;
      setState(() {
        _digits = '––.––';
        _caption = '数字已隐藏 · 凭体感按停';
      });
      return;
    }
    setState(() => _digits = _formatSeconds(elapsed));
  }

  void _stop() {
    _ticker?.cancel();
    _ticker = null;
    final double elapsed = _elapsedSeconds();
    final StopwatchVerdict verdict = judgeStopwatch(
      elapsed,
      _target,
      tolerance: _tolerance,
    );
    _roundCount += 1;
    _bestDiff = _bestDiff == null || verdict.diff < _bestDiff!
        ? verdict.diff
        : _bestDiff;
    setState(() {
      _phase = _StopwatchPhase.done;
      _digits = _formatSeconds(elapsed);
      _caption = '目标 ${_formatSeconds(_target)}s';
      _result = verdict;
    });
    HapticFeedback.mediumImpact();
    unawaited(_saveTemplateResult());
  }

  void _abort() {
    _ticker?.cancel();
    _ticker = null;
    if (!mounted) return;
    setState(() {
      _syncIdle();
      _caption = '这一局作废了，重新开始';
      _result = null;
    });
  }

  double _elapsedSeconds() {
    final DateTime? start = _startedAt;
    if (start == null) return 0;
    return _now.difference(start).inMilliseconds / 1000;
  }

  bool _visibleAt(double elapsed) => switch (_revealMode) {
    StopwatchRevealMode.delay => elapsed < 1,
    StopwatchRevealMode.never => false,
    StopwatchRevealMode.always => true,
  };

  @override
  Widget build(BuildContext context) {
    final StopwatchVerdict? result = _result;
    // 小程序初始态是浅色，结果态则把胜/负软色叠在玩家黑底上。
    final CyPalette palette = result == null
        ? CyPalette.light
        : CyPalette.dark;
    final Color pageColor = switch (result?.stars) {
      2 || 3 => Color.alphaBlend(
        const Color(0x240B7A57),
        const Color(0xFF000000),
      ),
      1 => Color.alphaBlend(
        const Color(0x29F59F00),
        const Color(0xFF000000),
      ),
      0 => Color.alphaBlend(
        const Color(0x1FD0323B),
        const Color(0xFF000000),
      ),
      _ => palette.bgPage,
    };
    final Color navigationColor = result == null
        ? pageColor
        : CyPalette.light.bgPage;
    final CupertinoThemeData inheritedTheme = CupertinoTheme.of(context);
    final CupertinoTextThemeData inheritedText = inheritedTheme.textTheme;
    return CupertinoTheme(
      data: inheritedTheme.copyWith(
        brightness: Brightness.light,
        scaffoldBackgroundColor: pageColor,
        textTheme: inheritedText.copyWith(
          textStyle: inheritedText.textStyle.copyWith(
            color: palette.textPrimary,
          ),
          navTitleTextStyle: inheritedText.navTitleTextStyle.copyWith(
            color: CyPalette.light.textPrimary,
          ),
        ),
      ),
      child: CupertinoPageScaffold(
        backgroundColor: pageColor,
        navigationBar: CupertinoNavigationBar(
          backgroundColor: navigationColor,
          automaticBackgroundVisibility: false,
          border: null,
          middle: const Text('精准停表'),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: SafeArea(
            top: false,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          return _dial(palette, constraints.maxHeight);
                        },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CyTokens.space4,
                    CyTokens.space3,
                    CyTokens.space4,
                    CyTokens.space7,
                  ),
                  child: Column(
                    children: <Widget>[
                      DefaultTextStyle.merge(
                        style: TextStyle(
                          color: palette.textTertiary,
                          fontSize: CyTokens.typeCaption,
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: CyTokens.space3,
                          children: <Widget>[
                            Text('第 $_roundCount 局'),
                            if (_bestDiff != null)
                              Text('最佳 ${_bestDiff!.toStringAsFixed(2)}s'),
                            Text(_revealText(_revealMode)),
                          ],
                        ),
                      ),
                      const SizedBox(height: CyTokens.space3),
                      CupertinoButton(
                        key: const Key('stopwatch-primary-action'),
                        onPressed: _onTap,
                        minimumSize: const Size(double.infinity, 100),
                        color: _phase == _StopwatchPhase.running
                            ? palette.textPrimary
                            : const Color(0xFFD0323B),
                        borderRadius: BorderRadius.circular(
                          _phase == _StopwatchPhase.running
                              ? CyTokens.radiusXl
                              : CyTokens.radiusPill,
                        ),
                        child: Text(
                          switch (_phase) {
                            _StopwatchPhase.running => '停',
                            _StopwatchPhase.done => '再来一次',
                            _StopwatchPhase.idle => '开始',
                          },
                          style: TextStyle(
                            color: _phase == _StopwatchPhase.running
                                ? palette.bgSurface
                                : CupertinoColors.white,
                            fontSize: CyTokens.typePageTitle,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dial(CyPalette palette, double height) {
    final int seconds = _target.floor();
    final int centiseconds = ((_target - seconds) * 100).round();
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: <Widget>[
        Positioned(
          top: height * 0.17,
          left: 0,
          right: 0,
          child: Center(
            child: Transform.rotate(
              angle: 0.785398,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59F00),
                  borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                ),
              ),
            ),
          ),
        ),
        for (int offset = -3; offset <= 3; offset++) ...<Widget>[
          _dialNumber(
            palette,
            value: (seconds + offset).clamp(0, 99),
            left: true,
            offset: offset,
            height: height,
          ),
          _dialNumber(
            palette,
            value: (centiseconds + offset * 25) % 100,
            left: false,
            offset: offset,
            height: height,
          ),
        ],
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _phase == _StopwatchPhase.running
                    ? '计时中'
                    : (_result?.tierLabel ?? '停表挑战'),
                style: TextStyle(
                  color: palette.textTertiary,
                  fontSize: CyTokens.typeLabel,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: CyTokens.space2),
              Text(
                _digits,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 64,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              const SizedBox(height: CyTokens.space3),
              Text(
                _caption,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: CyTokens.typeCaption,
                ),
              ),
            ],
          ),
        ),
        if (_result case final StopwatchVerdict result)
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Center(child: _verdict(result)),
          ),
      ],
    );
  }

  Widget _dialNumber(
    CyPalette palette, {
    required int value,
    required bool left,
    required int offset,
    required double height,
  }) {
    if (offset == 0) return const SizedBox.shrink();
    final double distance = offset.abs().toDouble();
    return Positioned(
      top: height * 0.5 + offset * 42 - 12,
      left: left ? 28 + distance * 4 : null,
      right: left ? null : 28 + distance * 4,
      child: Opacity(
        opacity: (0.72 - distance * 0.16).clamp(0.16, 0.56),
        child: Text(
          value.toString().padLeft(2, '0'),
          style: TextStyle(
            color: palette.textTertiary,
            fontSize: 30 - distance * 3,
            fontWeight: FontWeight.w600,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  Widget _verdict(StopwatchVerdict result) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space4,
        vertical: CyTokens.space2_5,
      ),
      decoration: BoxDecoration(
        color: CupertinoColors.black,
        borderRadius: BorderRadius.circular(CyTokens.radiusPill),
      ),
      child: Wrap(
        spacing: CyTokens.space2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(
            result.tierLabel,
            style: const TextStyle(
              color: CupertinoColors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '${result.late ? '晚' : '早'} ${result.diff.toStringAsFixed(2)}s',
            style: TextStyle(
              color: CupertinoColors.white.withValues(alpha: 0.72),
            ),
          ),
          Text(
            '★' * result.stars + '☆' * (3 - result.stars),
            style: const TextStyle(color: Color(0xFFF59F00)),
          ),
        ],
      ),
    );
  }
}

String _formatSeconds(double value) {
  final double safe = value.isFinite ? value.clamp(0, double.infinity) : 0;
  return safe.toStringAsFixed(2).padLeft(5, '0');
}

String _revealText(StopwatchRevealMode mode) => switch (mode) {
  StopwatchRevealMode.delay => '1 秒后隐藏',
  StopwatchRevealMode.never => '全程隐藏',
  StopwatchRevealMode.always => '全程显示',
};
