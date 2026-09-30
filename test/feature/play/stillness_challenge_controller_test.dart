import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/play/stillness_challenge_controller.dart';

void main() {
  test('配置缺 durationSec 时 fail-closed，缺 tolerance 时用安全默认值', () {
    expect(StillnessConfig.tryParse(<String, dynamic>{}), isNull);
    expect(
      StillnessConfig.tryParse(<String, dynamic>{'durationSec': 30})?.tolerance,
      defaultStillnessTolerance,
    );
    expect(
      StillnessConfig.tryParse(<String, dynamic>{
        'durationSec': 30,
        'tolerance': 0,
      }),
      isNull,
    );
  });

  test('静止达到目标只完成一次', () async {
    final _FakeMotionSource source = _FakeMotionSource();
    final StillnessChallengeController controller =
        StillnessChallengeController(
          source: source,
          target: const Duration(milliseconds: 500),
          tolerance: 0.02,
        )..start();
    addTearDown(() async {
      controller.dispose();
      await source.close();
    });

    for (int i = 0; i <= 10; i++) {
      source.emit(_stableSample(i * 100));
      await _drainEvents();
    }

    expect(controller.state.phase, StillnessPhase.completed);
    expect(controller.state.stableFor, const Duration(milliseconds: 500));
    expect(controller.state.completionCount, 1);

    source.emit(_stableSample(1200));
    await _drainEvents();
    expect(controller.state.completionCount, 1, reason: '完成后继续采样不能重复提交');
  });

  test('晃动会把已累计静止时间清零', () async {
    final _FakeMotionSource source = _FakeMotionSource();
    final StillnessChallengeController controller =
        StillnessChallengeController(
          source: source,
          target: const Duration(seconds: 3),
          tolerance: 0.02,
        )..start();
    addTearDown(() async {
      controller.dispose();
      await source.close();
    });

    for (int i = 0; i <= 8; i++) {
      source.emit(_stableSample(i * 100));
      await _drainEvents();
    }
    expect(controller.state.stableFor, greaterThan(Duration.zero));

    source.emit(
      const StillnessSample(
        x: 18,
        y: 0,
        z: 0,
        timestamp: Duration(milliseconds: 900),
      ),
    );
    await _drainEvents();

    expect(controller.state.stableFor, Duration.zero);
    expect(controller.state.resetCount, 1);
    expect(controller.state.phase, StillnessPhase.stabilizing);
  });

  test('加速度模长相同但方向改变也必须重置', () async {
    final _FakeMotionSource source = _FakeMotionSource();
    final StillnessChallengeController controller =
        StillnessChallengeController(
          source: source,
          target: const Duration(seconds: 3),
          tolerance: 0.02,
        )..start();
    addTearDown(() async {
      controller.dispose();
      await source.close();
    });

    for (int i = 0; i <= 8; i++) {
      source.emit(_stableSample(i * 100));
      await _drainEvents();
    }
    expect(controller.state.stableFor, greaterThan(Duration.zero));

    source.emit(
      const StillnessSample(
        x: 9.80,
        y: 0,
        z: 0,
        timestamp: Duration(milliseconds: 900),
      ),
    );
    await _drainEvents();

    expect(controller.state.stableFor, Duration.zero);
    expect(controller.state.resetCount, 1);
  });

  test('切到后台不累计时间，回前台后从原进度继续', () async {
    final _FakeMotionSource source = _FakeMotionSource();
    final StillnessChallengeController controller =
        StillnessChallengeController(
          source: source,
          target: const Duration(seconds: 2),
          tolerance: 0.02,
        )..start();
    addTearDown(() async {
      controller.dispose();
      await source.close();
    });

    for (int i = 0; i <= 8; i++) {
      source.emit(_stableSample(i * 100));
      await _drainEvents();
    }
    final Duration beforePause = controller.state.stableFor;
    expect(beforePause, greaterThan(Duration.zero));

    controller.pause();
    source.emit(_stableSample(10000));
    source.emit(_stableSample(11000));
    await _drainEvents();
    expect(controller.state.phase, StillnessPhase.paused);
    expect(controller.state.stableFor, beforePause);

    controller.resume();
    for (int i = 0; i <= 5; i++) {
      source.emit(_stableSample(11100 + i * 100));
      await _drainEvents();
    }

    expect(
      controller.state.stableFor,
      beforePause + const Duration(milliseconds: 100),
    );
    expect(controller.state.phase, isNot(StillnessPhase.completed));
  });
}

StillnessSample _stableSample(int milliseconds) => StillnessSample(
  x: 0.01,
  y: -0.01,
  z: 9.80,
  timestamp: Duration(milliseconds: milliseconds),
);

Future<void> _drainEvents() => Future<void>.delayed(Duration.zero);

class _FakeMotionSource implements StillnessSampleSource {
  final StreamController<StillnessSample> _samples =
      StreamController<StillnessSample>.broadcast();

  @override
  Stream<StillnessSample> watch() => _samples.stream;

  void emit(StillnessSample sample) => _samples.add(sample);

  Future<void> close() => _samples.close();
}
