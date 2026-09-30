import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/ai_npc_api.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/data/models/npc.dart';
import 'package:chengyin_app/feature/play/play_session_page.dart';
import 'package:chengyin_app/feature/play/stillness_challenge_controller.dart';
import 'package:chengyin_app/feature/play/stillness_platform.dart';

void main() {
  testWidgets('PlaySessionPage 中 still 挑战完成后只展示服务端探索值', (
    WidgetTester tester,
  ) async {
    final _FakeMotionSource motion = _FakeMotionSource();
    final _FakeWakeLock wakeLock = _FakeWakeLock();
    addTearDown(motion.close);
    final _RecordingPlayApi api = _RecordingPlayApi(
      node: const PlayNode(
        nodeId: 7,
        name: '静止挑战',
        address: '测试地点',
        sortId: 1,
        done: false,
        validationMethod: 7,
        sensorType: 'still',
        sensorConfig: <String, dynamic>{'durationSec': 1, 'tolerance': 0.02},
      ),
    );
    await _pumpPage(tester, api, motion: motion, wakeLock: wakeLock);

    expect(find.text('App 专属挑战'), findsOneWidget);
    expect(find.text('点击开始静止挑战'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('静止挑战'),
        matching: find.byType(CupertinoButton),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('静止挑战'));
    await tester.pumpAndSettle();

    expect(find.text('同意并开始'), findsOneWidget);
    expect(wakeLock.enableCount, 0, reason: '用户确认用途前不得启用亮屏或读取传感器');
    await tester.tap(find.text('同意并开始'));
    await tester.pumpAndSettle();

    expect(find.text('APP 传感器挑战 · XP / 徽章'), findsOneWidget);
    expect(wakeLock.enableCount, 1);

    for (int i = 0; i <= 14; i++) {
      motion.emit(
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

    expect(api.completionRequests, <String>['sensor-result:still:1']);
    expect(find.text('+18 探索值'), findsOneWidget);
    expect(find.textContaining('积分'), findsNothing, reason: 'vm=7 不得冒充积分奖励');
  });

  testWidgets('B2 未实现的 steps 仍不可点击且不提交', (WidgetTester tester) async {
    final _RecordingPlayApi api = _RecordingPlayApi(
      node: const PlayNode(
        nodeId: 8,
        name: '极限计步',
        address: '测试地点',
        sortId: 1,
        done: false,
        validationMethod: 7,
        sensorType: 'steps',
        sensorConfig: <String, dynamic>{'durationSec': 60, 'targetSteps': 500},
      ),
    );
    await _pumpPage(tester, api);

    expect(find.text('该传感器玩法暂未开放'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('极限计步'),
        matching: find.byType(CupertinoButton),
      ),
      findsNothing,
    );
    expect(api.completionRequests, isEmpty);
  });

  testWidgets('PlaySessionPage 中 vm=2 仍可进入拍照原入口', (WidgetTester tester) async {
    final _RecordingPlayApi api = _RecordingPlayApi(
      node: const PlayNode(
        nodeId: 2,
        name: '滤镜拍摄',
        address: '测试地点',
        sortId: 1,
        done: false,
        validationMethod: 2,
      ),
    );
    await _pumpPage(tester, api);

    expect(
      find.ancestor(
        of: find.text('滤镜拍摄'),
        matching: find.byType(CupertinoButton),
      ),
      findsOneWidget,
      reason: 'vm=2 仍应保留原拍照入口',
    );
    await tester.tap(find.text('滤镜拍摄'));
    await tester.pumpAndSettle();

    expect(find.text('从相册选择'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(api.fetchCount, 1);
    expect(api.completionRequests, isEmpty, reason: '未选图前不应提交完成');
  });

  testWidgets('vm=2 filter_shot 进入专属取景器且不走普通选图', (WidgetTester tester) async {
    final _RecordingPlayApi api = _RecordingPlayApi(
      node: const PlayNode(
        nodeId: 9,
        name: '暗夜搜证',
        address: '测试地点',
        sortId: 1,
        done: false,
        validationMethod: 2,
        sensorType: 'filter_shot',
        sensorConfig: <String, dynamic>{'filterStyle': 'night_vision'},
      ),
    );
    await _pumpPage(tester, api);
    expect(find.text('滤镜相机'), findsOneWidget);

    await tester.tap(find.text('暗夜搜证'));
    await tester.pumpAndSettle();

    expect(find.text('同意并打开相机'), findsOneWidget);
    expect(find.textContaining('仅在本次滤镜拍摄中使用'), findsOneWidget);
    expect(
      find.text('从相册选择'),
      findsNothing,
      reason: 'filter_shot 不得回落普通相册绕过滤镜',
    );
    expect(api.completionRequests, isEmpty, reason: '用途确认前不得提交完成');
  });

  testWidgets('vm=2 filter_shot 非法 style fail-closed', (
    WidgetTester tester,
  ) async {
    final _RecordingPlayApi api = _RecordingPlayApi(
      node: const PlayNode(
        nodeId: 10,
        name: '坏配置滤镜',
        address: '测试地点',
        sortId: 1,
        done: false,
        validationMethod: 2,
        sensorType: 'filter_shot',
        sensorConfig: <String, dynamic>{'filterStyle': 'unknown'},
      ),
    );
    await _pumpPage(tester, api);

    await tester.tap(find.text('坏配置滤镜'));
    await tester.pump();

    expect(find.text('滤镜玩法配置无效，请联系活动方'), findsOneWidget);
    expect(find.text('同意并打开相机'), findsNothing);
    expect(find.text('从相册选择'), findsNothing);
    expect(api.completionRequests, isEmpty);
  });

  testWidgets('vm=2 未知子类不得降级到普通选图', (WidgetTester tester) async {
    final _RecordingPlayApi api = _RecordingPlayApi(
      node: const PlayNode(
        nodeId: 11,
        name: '错误子类',
        address: '测试地点',
        sortId: 1,
        done: false,
        validationMethod: 2,
        sensorType: 'filter-shot',
        sensorConfig: <String, dynamic>{'filterStyle': 'night_vision'},
      ),
    );
    await _pumpPage(tester, api);

    await tester.tap(find.text('错误子类'));
    await tester.pump();

    expect(find.text('滤镜玩法配置无效，请联系活动方'), findsOneWidget);
    expect(find.text('从相册选择'), findsNothing);
    expect(api.completionRequests, isEmpty);
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _RecordingPlayApi api, {
  StillnessSampleSource? motion,
  ScreenWakeLock? wakeLock,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playApiProvider.overrideWithValue(api),
        aiNpcApiProvider.overrideWithValue(_EmptyAiNpcApi()),
        if (motion != null)
          stillnessSampleSourceProvider.overrideWithValue(motion),
        if (wakeLock != null)
          screenWakeLockProvider.overrideWithValue(wakeLock),
      ],
      child: const MaterialApp(home: PlaySessionPage(activityId: 41)),
    ),
  );
  await tester.pumpAndSettle();
}

class _RecordingPlayApi implements PlayApi {
  _RecordingPlayApi({required this.node});

  final PlayNode node;
  int fetchCount = 0;
  final List<String> completionRequests = <String>[];

  CheckinReward get _reward => CheckinReward(
    nodeId: node.nodeId,
    firstTime: true,
    doneCount: 1,
    total: 1,
    completed: true,
    newBadges: const <PlayBadge>[],
    xpAwarded: 18,
  );

  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async {
    fetchCount += 1;
    return PlayNodesResult(
      topicId: 71,
      mode: 1,
      playable: true,
      total: 1,
      doneCount: 0,
      nodes: <PlayNode>[node],
    );
  }

  @override
  Future<CheckinReward> submitSensorResult({
    int? activityId,
    int? topicId,
    required int nodeId,
    required String sensorType,
    required Map<String, dynamic> payload,
    RouteAdvanceToken? routeAdvance,
  }) async {
    completionRequests.add('sensor-result:$sensorType:${payload['heldSec']}');
    return _reward;
  }

  @override
  Future<CheckinReward> submitPhoto({
    required int activityId,
    required int nodeId,
    required String picUrl,
    RouteAdvanceToken? routeAdvance,
  }) async {
    completionRequests.add('photo');
    return _reward;
  }

  @override
  Future<String> uploadImage(String filePath) async {
    completionRequests.add('upload');
    return 'https://example.com/photo.jpg';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMotionSource implements StillnessSampleSource {
  final StreamController<StillnessSample> _samples =
      StreamController<StillnessSample>.broadcast();

  @override
  Stream<StillnessSample> watch() => _samples.stream;

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

class _EmptyAiNpcApi implements AiNpcApi {
  @override
  Future<List<NpcProfile>> fetchProfiles({
    String scope = 'global',
    int? activityId,
  }) async => const <NpcProfile>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
