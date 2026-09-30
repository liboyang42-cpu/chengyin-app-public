// 高级玩法控制器(parity/play-advanced 补入链路的决策层)。
//
// 这个控制器管三件事:什么时候**可以写**、写丢了怎么**核验**、
// 核验之后**重放还是重试**。算法接错不会报错,只会把动作悄悄丢一次
// 或者重复提交一轮,所以下面每条都对着崩溃/多扣分场景写。

import 'package:chengyin_app/data/api/advanced_play_api.dart';
import 'package:chengyin_app/data/models/advanced_play.dart';
import 'package:chengyin_app/feature/play/advanced/advanced_play_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> stateJson({
    int sessionId = 7,
    int activityId = 3,
    int topicId = 0,
    int nodeId = 11,
    int version = 1,
    String status = 'RUNNING',
    int? deadlineMillis,
    bool leaderboardEnabled = false,
    bool multiplayerEnabled = false,
    Map<String, Object?> playKit = const <String, Object?>{},
  }) => <String, dynamic>{
    'sessionId': sessionId,
    'activityId': activityId,
    'topicId': topicId,
    'nodeId': nodeId,
    'status': status,
    'version': version,
    'score': 0,
    'readyForBase': false,
    if (deadlineMillis != null) 'deadlineAt': deadlineMillis,
    'config': <String, dynamic>{
      'leaderboard': <String, dynamic>{'enabled': leaderboardEnabled},
      'multiplayer': <String, dynamic>{'enabled': multiplayerEnabled},
    },
    'draws': <dynamic>[],
    'playKit': playKit,
    'multiplayer': <String, dynamic>{},
  };

  AdvancedPlayController controllerFor(_FakeGateway gateway) {
    final AdvancedPlayController controller = AdvancedPlayController(
      gateway: gateway,
      activityId: 3,
      topicId: 0,
      nodeId: 11,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('start 成功进入 ready，榜单开关打开时自动拉同行者榜', () async {
    final _FakeGateway gateway = _FakeGateway(
      startState: stateJson(leaderboardEnabled: true),
    );
    gateway.leaderboardRows = <AdvancedPlayLeaderboardRow>[
      AdvancedPlayLeaderboardRow.fromJson(<String, Object?>{
        'rank': 1,
        'ownerId': 5,
        'displayName': '阿岚',
        'score': 10,
        'elapsedSeconds': 20,
        'completedUnits': 1,
      }),
    ];
    final AdvancedPlayController controller = controllerFor(gateway);

    await controller.start();

    expect(controller.phase, AdvancedPlayPhase.ready);
    expect(controller.state?.sessionId, 7);
    expect(gateway.leaderboardCalls, 1);
    expect(controller.leaderboard.single.displayName, '阿岚');
  });

  test('榜单开关关闭时不拉榜(负控:开关必须真的生效)', () async {
    final _FakeGateway gateway = _FakeGateway(startState: stateJson());
    final AdvancedPlayController controller = controllerFor(gateway);

    await controller.start();

    expect(controller.phase, AdvancedPlayPhase.ready);
    expect(gateway.leaderboardCalls, 0);
  });

  test('★ 网络不确定 + 权威版本前进 → 用同一幂等键重放，不产生第二个键', () async {
    final _FakeGateway gateway = _FakeGateway(startState: stateJson());
    bool first = true;
    gateway.actionReply =
        (String action, Map<String, Object?> payload, int version, String key) {
          if (first) {
            first = false;
            throw const AdvancedPlayTransportException('结果尚未确认，请核对服务端状态');
          }
          return AdvancedPlayState.fromJson(stateJson(version: 2));
        };
    gateway.stateReply = (_) => AdvancedPlayState.fromJson(
      stateJson(version: 2),
    );
    final AdvancedPlayController controller = controllerFor(gateway);
    await controller.start();

    await controller.submit('PICK', <String, Object?>{'slot': 1});
    expect(controller.phase, AdvancedPlayPhase.unknown);

    await controller.resolveUnknown();

    expect(controller.phase, AdvancedPlayPhase.ready);
    expect(gateway.actionCalls, hasLength(2));
    expect(
      gateway.actionCalls[0].idempotencyKey,
      gateway.actionCalls[1].idempotencyKey,
    );
    expect(gateway.actionCalls[0].version, 1);
    expect(gateway.actionCalls[0].action, 'PICK');
  });

  test('★ 多人局权威版本前进不自动重放，进 retryable 由人确认', () async {
    final _FakeGateway gateway = _FakeGateway(
      startState: stateJson(multiplayerEnabled: true),
    );
    gateway.actionReply =
        (String action, Map<String, Object?> payload, int version, String key) =>
            throw const AdvancedPlayTransportException('结果尚未确认');
    gateway.stateReply = (_) => AdvancedPlayState.fromJson(
      stateJson(version: 2, multiplayerEnabled: true),
    );
    final AdvancedPlayController controller = controllerFor(gateway);
    await controller.start();

    await controller.submit('COMPLETE_UNIT', const <String, Object?>{});
    await controller.resolveUnknown();

    expect(controller.phase, AdvancedPlayPhase.retryable);
    expect(gateway.actionCalls, hasLength(1));
  });

  test('版本原地踏步 → retryable，重试复用同一键', () async {
    final _FakeGateway gateway = _FakeGateway(startState: stateJson());
    bool first = true;
    gateway.actionReply =
        (String action, Map<String, Object?> payload, int version, String key) {
          if (first) {
            first = false;
            throw const AdvancedPlayTransportException('结果尚未确认');
          }
          return AdvancedPlayState.fromJson(stateJson(version: 2));
        };
    gateway.stateReply = (_) => AdvancedPlayState.fromJson(
      stateJson(version: 1),
    );
    final AdvancedPlayController controller = controllerFor(gateway);
    await controller.start();

    await controller.submit('PICK', const <String, Object?>{});
    await controller.resolveUnknown();
    expect(controller.phase, AdvancedPlayPhase.retryable);

    await controller.retryPending();
    expect(controller.phase, AdvancedPlayPhase.ready);
    expect(
      gateway.actionCalls[0].idempotencyKey,
      gateway.actionCalls[1].idempotencyKey,
    );
  });

  test('★ 权威回执换了节点 → error，不落状态', () async {
    final _FakeGateway gateway = _FakeGateway(startState: stateJson(nodeId: 99));
    final AdvancedPlayController controller = controllerFor(gateway);

    await controller.start();

    expect(controller.phase, AdvancedPlayPhase.error);
    expect(controller.state, isNull);
  });

  test('★ 计时已结束时拒绝就绪——过期局不能继续写', () async {
    final DateTime now = DateTime(2026, 9, 17, 12);
    final _FakeGateway gateway = _FakeGateway(
      startState: stateJson(
        deadlineMillis: now
            .subtract(const Duration(seconds: 1))
            .millisecondsSinceEpoch,
      ),
    );
    final AdvancedPlayController controller = AdvancedPlayController(
      gateway: gateway,
      activityId: 3,
      topicId: 0,
      nodeId: 11,
      now: () => now,
    );
    addTearDown(controller.dispose);

    await controller.start();

    expect(controller.phase, AdvancedPlayPhase.error);
  });

  test('★ 依赖微信受信步数的玩法 → unsupported，不给伪造入口', () async {
    final _FakeGateway gateway = _FakeGateway(
      startState: stateJson(
        playKit: <String, Object?>{
          'steps': <String, Object?>{'reached': false},
        },
      ),
    );
    final AdvancedPlayController controller = controllerFor(gateway);

    await controller.start();

    expect(controller.phase, AdvancedPlayPhase.unsupported);
  });

  test('未配置的角色不发请求(负控:本地先挡)', () async {
    final _FakeGateway gateway = _FakeGateway(
      startState: stateJson(multiplayerEnabled: true),
    );
    final AdvancedPlayController controller = controllerFor(gateway);
    await controller.start();

    await controller.assignRole(5, 'NOT_IN_CONFIG');

    expect(gateway.actionCalls, isEmpty);
    expect(controller.phase, AdvancedPlayPhase.ready);
  });

  test('start 之前 submit 不发请求(canWrite 闸)', () async {
    final _FakeGateway gateway = _FakeGateway(startState: stateJson());
    final AdvancedPlayController controller = controllerFor(gateway);

    await controller.submit('PICK', const <String, Object?>{});

    expect(gateway.actionCalls, isEmpty);
  });

  test('幂等键:动作名大小写/键序无关，payload 变则换键', () {
    final String a = buildAdvancedPlayIdempotencyKey(
      7,
      1,
      'pick',
      <String, Object?>{'slot': 1, 'note': 'a'},
    );
    final String b = buildAdvancedPlayIdempotencyKey(
      7,
      1,
      ' PICK ',
      <String, Object?>{'note': 'a', 'slot': 1},
    );
    final String c = buildAdvancedPlayIdempotencyKey(
      7,
      1,
      'pick',
      <String, Object?>{'slot': 2, 'note': 'a'},
    );
    expect(a, b);
    expect(a, isNot(c));
    expect(a.startsWith('ap:7:1:'), isTrue);
    expect(buildAdvancedPlayUnitId(7, 3), 'unit-7-v3');
  });
}

class _FakeGateway implements AdvancedPlayGateway {
  _FakeGateway({required this.startState});

  final Map<String, dynamic> startState;
  AdvancedPlayState Function(String, Map<String, Object?>, int, String)?
  actionReply;
  AdvancedPlayState Function(int)? stateReply;
  List<AdvancedPlayLeaderboardRow> leaderboardRows =
      const <AdvancedPlayLeaderboardRow>[];

  int leaderboardCalls = 0;
  final List<({String action, Map<String, Object?> payload, int version, String idempotencyKey})>
  actionCalls =
      <({String action, Map<String, Object?> payload, int version, String idempotencyKey})>[];

  @override
  Future<AdvancedPlayState> start({
    required int activityId,
    required int topicId,
    required int nodeId,
  }) async => AdvancedPlayState.fromJson(startState);

  @override
  Future<AdvancedPlayState> action({
    required int sessionId,
    required int version,
    required String idempotencyKey,
    required String action,
    required Map<String, Object?> payload,
  }) async {
    actionCalls.add((
      action: action,
      payload: payload,
      version: version,
      idempotencyKey: idempotencyKey,
    ));
    return actionReply!(action, payload, version, idempotencyKey);
  }

  @override
  Future<AdvancedPlayState> state(int sessionId) async => stateReply!(sessionId);

  @override
  Future<List<AdvancedPlayLeaderboardRow>> leaderboard({
    required int activityId,
    required int topicId,
    required int nodeId,
  }) async {
    leaderboardCalls += 1;
    return leaderboardRows;
  }
}
