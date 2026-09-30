import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/stillness_challenge_controller.dart';
import 'package:chengyin_app/feature/play/stillness_challenge_page.dart';
import 'package:chengyin_app/feature/play/stillness_platform.dart';

void main() {
  testWidgets('系统切后台会暂停挑战并关闭亮屏', (WidgetTester tester) async {
    final _FakeMotionSource source = _FakeMotionSource();
    final _FakeWakeLock wakeLock = _FakeWakeLock();
    addTearDown(source.close);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    await tester.pumpWidget(
      MaterialApp(
        home: StillnessChallengePage(
          title: '不动如山',
          config: const StillnessConfig(
            duration: Duration(seconds: 30),
            tolerance: 0.02,
          ),
          source: source,
          wakeLock: wakeLock,
          onSubmit: (_) async => const CheckinReward(
            nodeId: 7,
            firstTime: true,
            doneCount: 1,
            total: 1,
            completed: true,
            newBadges: <PlayBadge>[],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(source.watchCount, 0, reason: '用途说明确认前不得触发系统运动权限');
    expect(wakeLock.enableCount, 0);
    expect(find.textContaining('不后台采集'), findsOneWidget);

    await tester.tap(find.text('同意并开始'));
    await tester.pumpAndSettle();
    expect(source.watchCount, 1);
    expect(wakeLock.enableCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(tester.binding.lifecycleState, AppLifecycleState.paused);
    expect(wakeLock.disableCount, 1);
    expect(wakeLock.enableCount, 1, reason: '后台不能继续保持屏幕常亮');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(wakeLock.enableCount, 2);
    expect(find.text('先稳住手机 · 检测中'), findsOneWidget);
  });

  testWidgets('街头摆烂使用充电皮文案', (WidgetTester tester) async {
    final _FakeMotionSource source = _FakeMotionSource();
    final _FakeWakeLock wakeLock = _FakeWakeLock();
    addTearDown(source.close);

    await tester.pumpWidget(
      MaterialApp(
        home: StillnessChallengePage(
          title: '街头摆烂',
          config: const StillnessConfig(
            duration: Duration(minutes: 5),
            tolerance: 0.02,
          ),
          source: source,
          wakeLock: wakeLock,
          onSubmit: (_) async => const CheckinReward(
            nodeId: 8,
            firstTime: true,
            doneCount: 1,
            total: 1,
            completed: true,
            newBadges: <PlayBadge>[],
          ),
        ),
      ),
    );
    await tester.tap(find.text('同意并开始'));
    await tester.pumpAndSettle();

    expect(find.text('把手机放稳 · 开始充电'), findsOneWidget);
    expect(find.text('猫向导陪你摆烂充电中…'), findsOneWidget);
  });

  testWidgets('非业务异常不向用户暴露实现细节', (WidgetTester tester) async {
    final _FakeMotionSource source = _FakeMotionSource();
    final _FakeWakeLock wakeLock = _FakeWakeLock();
    addTearDown(source.close);

    await tester.pumpWidget(
      MaterialApp(
        home: StillnessChallengePage(
          title: '不动如山',
          config: const StillnessConfig(
            duration: Duration(seconds: 1),
            tolerance: 0.02,
          ),
          source: source,
          wakeLock: wakeLock,
          onSubmit: (_) async => throw StateError('internal-token'),
        ),
      ),
    );
    await tester.tap(find.text('同意并开始'));
    await tester.pumpAndSettle();

    for (int i = 0; i <= 14; i++) {
      source.emit(
        StillnessSample(
          x: 0.01,
          y: -0.01,
          z: 9.8,
          timestamp: Duration(milliseconds: i * 100),
        ),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('提交失败，请重试'), findsOneWidget);
    expect(find.textContaining('internal-token'), findsNothing);
  });
}

class _FakeMotionSource implements StillnessSampleSource {
  final StreamController<StillnessSample> _samples =
      StreamController<StillnessSample>.broadcast();

  int watchCount = 0;

  @override
  Stream<StillnessSample> watch() {
    watchCount += 1;
    return _samples.stream;
  }

  void emit(StillnessSample sample) => _samples.add(sample);

  Future<void> close() => _samples.close();
}

class _FakeWakeLock implements ScreenWakeLock {
  int enableCount = 0;
  int disableCount = 0;

  @override
  Future<void> enable() async => enableCount += 1;

  @override
  Future<void> disable() async => disableCount += 1;
}
