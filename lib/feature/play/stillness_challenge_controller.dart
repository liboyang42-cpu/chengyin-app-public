import 'dart:async';

import 'package:flutter/foundation.dart';

const double defaultStillnessTolerance = 0.02;

class StillnessConfig {
  const StillnessConfig({required this.duration, required this.tolerance});

  final Duration duration;
  final double tolerance;

  static StillnessConfig? tryParse(Map<String, dynamic>? json) {
    if (json == null) return null;
    final Object? rawDuration = json['durationSec'];
    final int? durationSec = rawDuration is num
        ? rawDuration.toInt()
        : int.tryParse('$rawDuration');
    if (durationSec == null || durationSec < 1 || durationSec > 3600) {
      return null;
    }

    final Object? rawTolerance = json['tolerance'];
    final double? tolerance = rawTolerance == null
        ? defaultStillnessTolerance
        : rawTolerance is num
        ? rawTolerance.toDouble()
        : double.tryParse('$rawTolerance');
    if (tolerance == null || tolerance <= 0 || tolerance > 10) return null;
    return StillnessConfig(
      duration: Duration(seconds: durationSec),
      tolerance: tolerance,
    );
  }
}

class StillnessSample {
  const StillnessSample({
    required this.x,
    required this.y,
    required this.z,
    required this.timestamp,
  });

  final double x;
  final double y;
  final double z;
  final Duration timestamp;
}

abstract interface class StillnessSampleSource {
  Stream<StillnessSample> watch();
}

enum StillnessPhase { stabilizing, holding, paused, completed, failed }

class StillnessState {
  const StillnessState({
    this.phase = StillnessPhase.stabilizing,
    this.stableFor = Duration.zero,
    this.stability = 0,
    this.resetCount = 0,
    this.completionCount = 0,
    this.errorMessage,
  });

  final StillnessPhase phase;
  final Duration stableFor;
  final double stability;
  final int resetCount;
  final int completionCount;
  final String? errorMessage;

  StillnessState copyWith({
    StillnessPhase? phase,
    Duration? stableFor,
    double? stability,
    int? resetCount,
    int? completionCount,
    String? errorMessage,
  }) {
    return StillnessState(
      phase: phase ?? this.phase,
      stableFor: stableFor ?? this.stableFor,
      stability: stability ?? this.stability,
      resetCount: resetCount ?? this.resetCount,
      completionCount: completionCount ?? this.completionCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// 通过固定大小滑动窗口判断三轴加速度方差，并只累计连续前台静止时长。
///
/// 插件事件经 [StillnessSampleSource] 注入，因此核心状态机可脱离 MethodChannel
/// 做行为测试。切后台时 [pause] 会断开时间锚；回前台不会把后台时间补进进度。
class StillnessChallengeController extends ChangeNotifier {
  StillnessChallengeController({
    required this.source,
    required this.target,
    required this.tolerance,
  });

  static const int _windowSampleCount = 5;
  static const Duration _maxSampleGap = Duration(milliseconds: 250);

  final StillnessSampleSource source;
  final Duration target;
  final double tolerance;
  final List<StillnessSample> _window = <StillnessSample>[];
  StreamSubscription<StillnessSample>? _subscription;
  Duration? _lastSampleAt;
  bool _wasStable = false;
  bool _foreground = true;
  bool _disposed = false;

  StillnessState _state = const StillnessState();
  StillnessState get state => _state;

  void start() {
    if (_subscription != null || _disposed) return;
    _subscription = source.watch().listen(
      _onSample,
      onError: (Object _) {
        if (_disposed || _state.phase == StillnessPhase.completed) return;
        _setState(
          _state.copyWith(
            phase: StillnessPhase.failed,
            errorMessage: '传感器暂不可用，请退出后重试',
          ),
        );
      },
    );
  }

  void pause() {
    if (_disposed || !_foreground || _state.phase == StillnessPhase.completed) {
      return;
    }
    _foreground = false;
    _window.clear();
    _lastSampleAt = null;
    _wasStable = false;
    _setState(_state.copyWith(phase: StillnessPhase.paused, stability: 0));
  }

  void resume() {
    if (_disposed || _foreground || _state.phase == StillnessPhase.completed) {
      return;
    }
    _foreground = true;
    _window.clear();
    _lastSampleAt = null;
    _wasStable = false;
    _setState(_state.copyWith(phase: StillnessPhase.stabilizing, stability: 0));
  }

  void _onSample(StillnessSample sample) {
    if (_disposed || !_foreground || _state.phase == StillnessPhase.completed) {
      return;
    }
    _window.add(sample);
    if (_window.length > _windowSampleCount) _window.removeAt(0);

    final Duration? previousAt = _lastSampleAt;
    _lastSampleAt = sample.timestamp;
    if (_window.length < _windowSampleCount) {
      _wasStable = false;
      _setState(
        _state.copyWith(phase: StillnessPhase.stabilizing, stability: 0),
      );
      return;
    }

    final double meanX =
        _window.fold(0.0, (double sum, StillnessSample s) => sum + s.x) /
        _window.length;
    final double meanY =
        _window.fold(0.0, (double sum, StillnessSample s) => sum + s.y) /
        _window.length;
    final double meanZ =
        _window.fold(0.0, (double sum, StillnessSample s) => sum + s.z) /
        _window.length;
    final double variance =
        _window.fold(0.0, (double sum, StillnessSample s) {
          final double dx = s.x - meanX;
          final double dy = s.y - meanY;
          final double dz = s.z - meanZ;
          return sum + dx * dx + dy * dy + dz * dz;
        }) /
        _window.length;
    final double stability = (1 - variance / tolerance).clamp(0.0, 1.0);
    final bool stable = variance <= tolerance;

    if (!stable) {
      final bool hadProgress = _state.stableFor > Duration.zero;
      _wasStable = false;
      _setState(
        _state.copyWith(
          phase: StillnessPhase.stabilizing,
          stableFor: Duration.zero,
          stability: stability,
          resetCount: _state.resetCount + (hadProgress ? 1 : 0),
        ),
      );
      return;
    }

    Duration stableFor = _state.stableFor;
    if (_wasStable && previousAt != null) {
      final Duration delta = sample.timestamp - previousAt;
      if (!delta.isNegative && delta <= _maxSampleGap) {
        stableFor += delta;
      }
    }
    _wasStable = true;
    if (stableFor >= target) {
      _setState(
        _state.copyWith(
          phase: StillnessPhase.completed,
          stableFor: target,
          stability: stability,
          completionCount: 1,
        ),
      );
      return;
    }
    _setState(
      _state.copyWith(
        phase: StillnessPhase.holding,
        stableFor: stableFor,
        stability: stability,
      ),
    );
  }

  void _setState(StillnessState next) {
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
