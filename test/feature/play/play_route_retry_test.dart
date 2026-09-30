import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/play_session_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BRANCH 同一语义动作网络不确定时复用票据，成功后新动作取新版本', () async {
    final _RoutePlayApi api = _RoutePlayApi(_nodes(branch: true, version: 1));
    final _Harness harness = await _harness(api);
    addTearDown(harness.dispose);
    int attempt = 0;
    bool consumedRewardStateBeforeReload = false;
    api.onFetch = () {
      if (attempt == 2) {
        consumedRewardStateBeforeReload =
            harness.container
                .read(harness.provider)
                .value
                ?.routeState
                ?.version ==
            2;
      }
    };
    api.onAnswer = (RouteAdvanceToken? token) async {
      attempt += 1;
      if (attempt == 1) throw _networkUnknown();
      final int nextVersion = attempt == 2 ? 2 : 3;
      api.nodes = _nodes(branch: true, version: nextVersion);
      return _reward(version: nextVersion);
    };

    await expectLater(
      harness.notifier.answer(7, 'A'),
      throwsA(isA<DioException>()),
    );
    await harness.notifier.answer(7, 'A');
    await harness.notifier.answer(7, 'A');

    expect(api.fetchRouteStateCalls, 0);
    expect(api.answerTokens, hasLength(3));
    expect(api.answerTokens[0]?.actionId, api.answerTokens[1]?.actionId);
    expect(api.answerTokens[0]?.expectedRouteVersion, 1);
    expect(api.answerTokens[1]?.expectedRouteVersion, 1);
    expect(api.answerTokens[2]?.actionId, isNot(api.answerTokens[1]?.actionId));
    expect(api.answerTokens[2]?.expectedRouteVersion, 2);
    expect(
      api.answerTokens.every(
        (RouteAdvanceToken? token) =>
            token != null && token.actionId.length <= 96,
      ),
      isTrue,
    );
    expect(consumedRewardStateBeforeReload, isTrue);
    expect(
      harness.container.read(harness.provider).value?.routeState?.version,
      3,
    );
  });

  test('BRANCH 明确 4xx 拒绝清除票据，下一次相同动作生成新 id', () async {
    final _RoutePlayApi api = _RoutePlayApi(_nodes(branch: true, version: 5));
    final _Harness harness = await _harness(api);
    addTearDown(harness.dispose);
    int attempt = 0;
    api.onAnswer = (RouteAdvanceToken? token) async {
      attempt += 1;
      if (attempt == 1) throw _httpRejected(409);
      api.nodes = _nodes(branch: true, version: 6);
      return _reward(version: 6);
    };

    await expectLater(
      harness.notifier.answer(7, 'A'),
      throwsA(isA<DioException>()),
    );
    await harness.notifier.answer(7, 'A');

    expect(api.answerTokens, hasLength(2));
    expect(api.answerTokens[0]?.expectedRouteVersion, 5);
    expect(api.answerTokens[1]?.expectedRouteVersion, 5);
    expect(api.answerTokens[1]?.actionId, isNot(api.answerTokens[0]?.actionId));
  });

  test('BRANCH AjaxResult 业务拒绝同样清除票据', () async {
    final _RoutePlayApi api = _RoutePlayApi(_nodes(branch: true, version: 5));
    final _Harness harness = await _harness(api);
    addTearDown(harness.dispose);
    int attempt = 0;
    api.onAnswer = (RouteAdvanceToken? token) async {
      attempt += 1;
      if (attempt == 1) throw PlayException('路线状态已更新');
      api.nodes = _nodes(branch: true, version: 6);
      return _reward(version: 6);
    };

    await expectLater(
      harness.notifier.answer(7, 'A'),
      throwsA(isA<PlayException>()),
    );
    await harness.notifier.answer(7, 'A');

    expect(api.answerTokens[1]?.actionId, isNot(api.answerTokens[0]?.actionId));
  });

  test('LINEAR 与未下发 routeState 时控制器不生成路线票据', () async {
    for (final PlayNodesResult nodes in <PlayNodesResult>[
      _nodes(branch: false, version: 0),
      _nodesWithoutRouteState(),
    ]) {
      final _RoutePlayApi api = _RoutePlayApi(nodes);
      final _Harness harness = await _harness(api);
      api.onAnswer = (_) async => _reward(version: null);

      await harness.notifier.answer(7, 'A');

      expect(api.answerTokens.single, isNull);
      harness.dispose();
    }
  });

  test('BRANCH 业务 409 冲突取权威版本后，最多自动重试一次成功', () async {
    final _RoutePlayApi api = _RoutePlayApi(_nodes(branch: true, version: 5));
    final _Harness harness = await _harness(api);
    addTearDown(harness.dispose);
    int attempt = 0;
    api.onAnswer = (RouteAdvanceToken? token) async {
      attempt += 1;
      if (attempt == 1) throw PlayException('路线状态已更新', code: 409);
      api.nodes = _nodes(branch: true, version: 7);
      return _reward(version: 7);
    };
    api.onFetchRouteState = () async => _authoritativeState(version: 6);

    final CheckinReward reward = await harness.notifier.answer(7, 'A');

    expect(api.fetchRouteStateCalls, 1);
    expect(api.answerTokens, hasLength(2));
    expect(api.answerTokens[0]?.expectedRouteVersion, 5);
    expect(api.answerTokens[1]?.expectedRouteVersion, 6);
    expect(api.answerTokens[1]?.actionId, isNot(api.answerTokens[0]?.actionId));
    expect(reward.routeState?.version, 7);
  });

  test('BRANCH 409 后权威状态显示当前节点已完成，不二次提交', () async {
    final _RoutePlayApi api = _RoutePlayApi(_nodes(branch: true, version: 5));
    final _Harness harness = await _harness(api);
    addTearDown(harness.dispose);
    api.onAnswer = (_) async => throw PlayException('路线状态已更新', code: 409);
    api.onFetchRouteState = () async => _authoritativeState(
      version: 6,
      nodeStates: <String, String>{'7': 'COMPLETED', '8': 'PLAYABLE'},
    );
    api.nodes = _nodes(
      branch: true,
      version: 6,
      nodeStates: <String, String>{'7': 'COMPLETED', '8': 'PLAYABLE'},
    );

    await expectLater(
      harness.notifier.answer(7, 'A'),
      throwsA(isA<PlayException>()),
    );

    expect(api.answerTokens, hasLength(1));
    expect(api.fetchRouteStateCalls, 1);
    expect(
      harness.container.read(harness.provider).value?.routeState?.version,
      6,
    );
  });

  test('BRANCH 原始 transport 的 AjaxResult body 业务码 409 同样恢复', () async {
    final _RoutePlayApi api = _RoutePlayApi(_nodes(branch: true, version: 5));
    final _Harness harness = await _harness(api);
    addTearDown(harness.dispose);
    int attempt = 0;
    api.onAnswer = (RouteAdvanceToken? token) async {
      attempt += 1;
      if (attempt == 1) throw _httpBusinessConflict();
      api.nodes = _nodes(branch: true, version: 7);
      return _reward(version: 7);
    };
    api.onFetchRouteState = () async => _authoritativeState(version: 6);

    final CheckinReward reward = await harness.notifier.answer(7, 'A');

    expect(api.fetchRouteStateCalls, 1);
    expect(api.answerTokens, hasLength(2));
    expect(api.answerTokens[1]?.expectedRouteVersion, 6);
    expect(reward.routeState?.version, 7);
  });

  test('BRANCH 409 重试再次冲突直接抛出，不递归不循环', () async {
    final _RoutePlayApi api = _RoutePlayApi(_nodes(branch: true, version: 5));
    final _Harness harness = await _harness(api);
    addTearDown(harness.dispose);
    int attempt = 0;
    api.onAnswer = (_) async {
      attempt += 1;
      throw PlayException('路线状态已更新', code: 409);
    };
    api.onFetchRouteState = () async => _authoritativeState(version: 6);

    await expectLater(
      harness.notifier.answer(7, 'A'),
      throwsA(isA<PlayException>()),
    );

    expect(attempt, 2);
    expect(api.fetchRouteStateCalls, 1);
    expect(api.answerTokens, hasLength(2));
  });

  test('BRANCH 409 后权威状态拉取失败直接抛出，不重发', () async {
    final _RoutePlayApi api = _RoutePlayApi(_nodes(branch: true, version: 5));
    final _Harness harness = await _harness(api);
    addTearDown(harness.dispose);
    api.onAnswer = (_) async => throw PlayException('路线状态已更新', code: 409);
    api.onFetchRouteState = () async => throw PlayException('路线状态加载失败');

    await expectLater(
      harness.notifier.answer(7, 'A'),
      throwsA(isA<PlayException>()),
    );

    expect(api.answerTokens, hasLength(1));
    expect(api.fetchRouteStateCalls, 1);
  });

  test('BRANCH 非 409 业务拒绝不拉取权威状态，原行为保持', () async {
    final _RoutePlayApi api = _RoutePlayApi(_nodes(branch: true, version: 5));
    final _Harness harness = await _harness(api);
    addTearDown(harness.dispose);
    api.onAnswer = (_) async => throw PlayException('答案不正确', code: 400);

    await expectLater(
      harness.notifier.answer(7, 'A'),
      throwsA(isA<PlayException>()),
    );

    expect(api.fetchRouteStateCalls, 0);
    expect(api.answerTokens, hasLength(1));
  });

  test('LINEAR 即便收到业务 409 也不拉取权威状态', () async {
    final _RoutePlayApi api = _RoutePlayApi(_nodes(branch: false, version: 0));
    final _Harness harness = await _harness(api);
    addTearDown(harness.dispose);
    api.onAnswer = (_) async => throw PlayException('路线状态已更新', code: 409);

    await expectLater(
      harness.notifier.answer(7, 'A'),
      throwsA(isA<PlayException>()),
    );

    expect(api.fetchRouteStateCalls, 0);
    expect(api.answerTokens.single, isNull);
  });

  test('BRANCH HTTP body 数字字符串业务码 409 同样进入权威恢复', () async {
    final _RoutePlayApi api = _RoutePlayApi(_nodes(branch: true, version: 5));
    final _Harness harness = await _harness(api);
    addTearDown(harness.dispose);
    int attempt = 0;
    api.onAnswer = (RouteAdvanceToken? token) async {
      attempt += 1;
      if (attempt == 1) throw _httpBusinessConflictString();
      api.nodes = _nodes(branch: true, version: 7);
      return _reward(version: 7);
    };
    api.onFetchRouteState = () async => _authoritativeState(version: 6);

    final CheckinReward reward = await harness.notifier.answer(7, 'A');

    expect(api.fetchRouteStateCalls, 1);
    expect(api.answerTokens, hasLength(2));
    expect(api.answerTokens[0]?.expectedRouteVersion, 5);
    expect(api.answerTokens[1]?.expectedRouteVersion, 6);
    expect(api.answerTokens[1]?.actionId, isNot(api.answerTokens[0]?.actionId));
    expect(reward.routeState?.version, 7);
  });

  test('BRANCH HTTP body 未知业务码类型不恢复、不崩溃(TypeError 回归护栏)', () async {
    final _RoutePlayApi api = _RoutePlayApi(_nodes(branch: true, version: 5));
    final _Harness harness = await _harness(api);
    addTearDown(harness.dispose);
    api.onAnswer = (_) async => throw _httpBusinessConflictUnknown();

    await expectLater(
      harness.notifier.answer(7, 'A'),
      throwsA(isA<DioException>()),
    );

    expect(api.fetchRouteStateCalls, 0);
    expect(api.answerTokens, hasLength(1));
  });

  test('LINEAR HTTP body 数字字符串业务码 409 不拉取权威状态', () async {
    final _RoutePlayApi api = _RoutePlayApi(_nodes(branch: false, version: 0));
    final _Harness harness = await _harness(api);
    addTearDown(harness.dispose);
    api.onAnswer = (_) async => throw _httpBusinessConflictString();

    await expectLater(
      harness.notifier.answer(7, 'A'),
      throwsA(isA<DioException>()),
    );

    expect(api.fetchRouteStateCalls, 0);
  });
}

typedef _Harness = ({
  ProviderContainer container,
  PlaySessionController notifier,
  dynamic provider,
  void Function() dispose,
});

Future<_Harness> _harness(_RoutePlayApi api) async {
  final ProviderContainer container = ProviderContainer(
    overrides: <dynamic>[playApiProvider.overrideWithValue(api)].cast(),
  );
  final provider = playSessionProvider((activityId: 41, topicId: null));
  final subscription = container.listen(
    provider,
    (_, _) {},
    fireImmediately: true,
  );
  final PlaySessionController notifier = container.read(provider.notifier);
  await notifier.load();
  await Future<void>.delayed(Duration.zero);
  return (
    container: container,
    notifier: notifier,
    provider: provider,
    dispose: () {
      subscription.close();
      container.dispose();
    },
  );
}

class _RoutePlayApi implements PlayApi {
  _RoutePlayApi(this.nodes);

  PlayNodesResult nodes;
  void Function()? onFetch;
  Future<CheckinReward> Function(RouteAdvanceToken? token)? onAnswer;
  final List<RouteAdvanceToken?> answerTokens = <RouteAdvanceToken?>[];
  int fetchRouteStateCalls = 0;
  Future<PlayRouteState> Function()? onFetchRouteState;

  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async {
    onFetch?.call();
    return nodes;
  }

  @override
  Future<PlayRouteState> fetchRouteState({int? activityId, int? topicId}) {
    fetchRouteStateCalls += 1;
    return onFetchRouteState!();
  }

  @override
  Future<CheckinReward> submitAnswer({
    required int activityId,
    required int nodeId,
    required String answer,
    RouteAdvanceToken? routeAdvance,
  }) async {
    answerTokens.add(routeAdvance);
    return onAnswer!(routeAdvance);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PlayNodesResult _nodes({
  required bool branch,
  required int version,
  Map<String, String> nodeStates = const <String, String>{'7': 'PLAYABLE'},
}) => PlayNodesResult.fromJson(<String, dynamic>{
  'topicId': 71,
  'mode': 1,
  'playable': true,
  'total': 1,
  'doneCount': 0,
  'nodes': <dynamic>[],
  'routeState': <String, dynamic>{
    'routeMode': branch ? 'BRANCH_GRAPH' : 'LINEAR',
    'sessionId': branch ? 91 : null,
    'status': 'ACTIVE',
    'currentNodeId': 7,
    'recommendedNodeId': 7,
    'version': version,
    'nodeStates': nodeStates,
    'decisionLog': <dynamic>[],
  },
});

PlayRouteState _authoritativeState({
  required int version,
  Map<String, String> nodeStates = const <String, String>{'7': 'PLAYABLE'},
}) => PlayRouteState.fromJson(<String, dynamic>{
  'routeMode': 'BRANCH_GRAPH',
  'sessionId': 91,
  'status': 'ACTIVE',
  'currentNodeId': 7,
  'recommendedNodeId': 7,
  'version': version,
  'nodeStates': nodeStates,
  'decisionLog': <dynamic>[],
})!;

PlayNodesResult _nodesWithoutRouteState() =>
    PlayNodesResult.fromJson(<String, dynamic>{
      'topicId': 71,
      'mode': 1,
      'playable': true,
      'total': 1,
      'doneCount': 0,
      'nodes': <dynamic>[],
    });

CheckinReward _reward({required int? version}) =>
    CheckinReward.fromJson(<String, dynamic>{
      'nodeId': 7,
      'firstTime': true,
      'done': 1,
      'total': 1,
      'completed': false,
      'newBadges': <dynamic>[],
      if (version != null)
        'routeState': <String, dynamic>{
          'routeMode': 'BRANCH_GRAPH',
          'sessionId': 91,
          'status': 'ACTIVE',
          'currentNodeId': 8,
          'recommendedNodeId': 8,
          'version': version,
          'nodeStates': <String, dynamic>{'7': 'COMPLETED', '8': 'PLAYABLE'},
          'decisionLog': <dynamic>[],
        },
    });

DioException _networkUnknown() {
  final RequestOptions request = RequestOptions(path: '/api/play/answer');
  return DioException(
    requestOptions: request,
    type: DioExceptionType.connectionError,
    error: 'offline',
  );
}

DioException _httpRejected(int statusCode) {
  final RequestOptions request = RequestOptions(path: '/api/play/answer');
  return DioException(
    requestOptions: request,
    response: Response<dynamic>(
      requestOptions: request,
      statusCode: statusCode,
    ),
    type: DioExceptionType.badResponse,
  );
}

DioException _httpBusinessConflict() {
  final RequestOptions request = RequestOptions(path: '/api/play/answer');
  return DioException(
    requestOptions: request,
    response: Response<dynamic>(
      requestOptions: request,
      statusCode: 409,
      data: <String, dynamic>{'code': 409, 'msg': '路线状态已更新'},
    ),
    type: DioExceptionType.badResponse,
  );
}

DioException _httpBusinessConflictString() {
  final RequestOptions request = RequestOptions(path: '/api/play/answer');
  return DioException(
    requestOptions: request,
    response: Response<dynamic>(
      requestOptions: request,
      statusCode: 409,
      data: <String, dynamic>{'code': '409', 'msg': '路线状态已更新'},
    ),
    type: DioExceptionType.badResponse,
  );
}

DioException _httpBusinessConflictUnknown() {
  final RequestOptions request = RequestOptions(path: '/api/play/answer');
  return DioException(
    requestOptions: request,
    response: Response<dynamic>(
      requestOptions: request,
      statusCode: 409,
      data: <String, dynamic>{'code': true, 'msg': '未知业务码'},
    ),
    type: DioExceptionType.badResponse,
  );
}
