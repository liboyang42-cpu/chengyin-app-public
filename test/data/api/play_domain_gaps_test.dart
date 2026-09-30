import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/play_session_controller.dart';

void main() {
  test('主题通行证会话用 topicId 拉节点，不把它冒充 activityId', () async {
    final _FakePlayApi api = _FakePlayApi();
    final ProviderContainer container = ProviderContainer(
      overrides: <dynamic>[playApiProvider.overrideWithValue(api)].cast(),
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      playSessionProvider((activityId: null, topicId: 73)),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container
        .read(playSessionProvider((activityId: null, topicId: 73)).notifier)
        .load();

    expect(api.fetchedTopicId, 73);
  });

  test('提示解锁只作用于当前节点，并回读明文与本次实扣', () async {
    final _FakePlayApi api = _FakePlayApi();
    final ProviderContainer container = ProviderContainer(
      overrides: <dynamic>[playApiProvider.overrideWithValue(api)].cast(),
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      playSessionProvider((activityId: 42, topicId: null)),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final PlaySessionController notifier = container.read(
      playSessionProvider((activityId: 42, topicId: null)).notifier,
    );
    await notifier.load();

    final HintUnlockResult result = await notifier.unlockHint(12);

    expect(api.unlockedNodeId, 12, reason: '解锁必须指向玩家当前点开的节点');
    expect(result.hints, <String>['先看门牌', '答案在树冠下']);
    expect(result.cost, 6, reason: 'UI 必须展示服务端回读的本次实扣，不能继续显示标价');
  });

  test('滤镜成片仍唯一复用 upload + photo 完成链', () async {
    final _FakePlayApi api = _FakePlayApi();
    final ProviderContainer container = ProviderContainer(
      overrides: <dynamic>[playApiProvider.overrideWithValue(api)].cast(),
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      playSessionProvider((activityId: 43, topicId: null)),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final PlaySessionController notifier = container.read(
      playSessionProvider((activityId: 43, topicId: null)).notifier,
    );
    await notifier.load();

    final CheckinReward reward = await notifier.filterPhoto(
      19,
      '/tmp/night-vision.png',
    );

    expect(api.uploadedPath, '/tmp/night-vision.png');
    expect(api.photoNodeId, 19);
    expect(api.photoUrl, 'https://example.com/filter-shot.png');
    expect(
      api.sensorResultCalls,
      0,
      reason: 'filter_shot 永远不得走 /sensor-result',
    );
    expect(reward.xpAwarded, 18);
  });
}

class _FakePlayApi implements PlayApi {
  final PlayNodesResult nodes = const PlayNodesResult(
    topicId: 71,
    mode: 2,
    playable: true,
    total: 0,
    doneCount: 0,
    nodes: <PlayNode>[],
  );

  int? unlockedNodeId;
  String? uploadedPath;
  int? photoNodeId;
  String? photoUrl;
  int sensorResultCalls = 0;
  int? fetchedTopicId;

  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async => nodes;

  @override
  Future<PlayNodesResult> fetchTopicNodes(int topicId) async {
    fetchedTopicId = topicId;
    return nodes;
  }

  @override
  Future<HintUnlockResult> unlockHint(int nodeId) async {
    unlockedNodeId = nodeId;
    return const HintUnlockResult(hint1: '先看门牌', hint2: '答案在树冠下', cost: 6);
  }

  @override
  Future<String> uploadImage(String filePath) async {
    uploadedPath = filePath;
    return 'https://example.com/filter-shot.png';
  }

  @override
  Future<CheckinReward> submitPhoto({
    required int activityId,
    required int nodeId,
    required String picUrl,
    RouteAdvanceToken? routeAdvance,
  }) async {
    photoNodeId = nodeId;
    photoUrl = picUrl;
    return CheckinReward(
      nodeId: nodeId,
      firstTime: true,
      doneCount: 1,
      total: 1,
      completed: true,
      newBadges: const <PlayBadge>[],
      xpAwarded: 18,
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
    sensorResultCalls += 1;
    throw StateError('filter_shot 不应走 sensor-result');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
