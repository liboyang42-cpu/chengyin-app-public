import 'dart:convert';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/play_session_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 控制器 × **真实 PlayApi × stub HTTP adapter**(HTTP 200)的端到端矩阵:
/// 业务 409 必须经由真实 AjaxResult 解析路径进入恢复逻辑;权威 state 取不到时
/// 原 pending 票据不得丢失。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  test(
    '真实 adapter:fetchRouteState 失败时保留原票据,下一次动作复用同一 actionId/version',
    () async {
      final _RoutingAdapter adapter = _RoutingAdapter();
      int nodesVersion = 5;
      int answerCalls = 0;
      adapter.on('/api/play/nodes', (_) => _nodesBody(version: nodesVersion));
      adapter.on('/api/play/answer', (RequestOptions _) {
        answerCalls += 1;
        if (answerCalls == 1) {
          return <String, dynamic>{'code': '409', 'msg': '路线状态已更新'};
        }
        nodesVersion = 6;
        return _rewardBody(version: 6);
      });
      // 脏/空权威包:fetchRouteState 抛「路线状态不可用」,控制器不得把它
      // 改写成 fetch 错误,也不得丢弃原票据。
      adapter.on(
        '/api/play/route-state',
        (_) => <String, dynamic>{'code': 200, 'data': null},
      );

      final _Harness harness = await _harness(PlayApi(_client(adapter)));
      addTearDown(harness.dispose);

      await expectLater(
        harness.notifier.answer(7, 'A'),
        throwsA(
          isA<PlayException>().having((PlayException e) => e.code, 'code', 409),
        ),
      );
      await harness.notifier.answer(7, 'A');

      final List<RequestOptions> answers = adapter.sentFor('/api/play/answer');
      expect(answers, hasLength(2));
      expect(
        _formField(answers[0], 'routeActionId'),
        _formField(answers[1], 'routeActionId'),
        reason: 'fetch 失败后下一次同语义动作必须复用原 actionId',
      );
      expect(_formField(answers[0], 'expectedRouteVersion'), '5');
      expect(_formField(answers[1], 'expectedRouteVersion'), '5');
      expect(adapter.sentFor('/api/play/route-state'), hasLength(1));
    },
  );

  test('真实 adapter:字符串业务码 409 走完整恢复,取权威版本后重试一次成功', () async {
    final _RoutingAdapter adapter = _RoutingAdapter();
    int nodesVersion = 5;
    int answerCalls = 0;
    adapter.on('/api/play/nodes', (_) => _nodesBody(version: nodesVersion));
    adapter.on(
      '/api/play/route-state',
      (_) => <String, dynamic>{
        'code': 200,
        'data': _routeStateData(version: 6),
      },
    );
    adapter.on('/api/play/answer', (RequestOptions _) {
      answerCalls += 1;
      if (answerCalls == 1) {
        return <String, dynamic>{'code': '409', 'msg': '路线状态已更新'};
      }
      nodesVersion = 7;
      return _rewardBody(version: 7);
    });

    final _Harness harness = await _harness(PlayApi(_client(adapter)));
    addTearDown(harness.dispose);

    final CheckinReward reward = await harness.notifier.answer(7, 'A');

    final List<RequestOptions> answers = adapter.sentFor('/api/play/answer');
    expect(answers, hasLength(2));
    expect(
      _formField(answers[0], 'routeActionId'),
      isNot(_formField(answers[1], 'routeActionId')),
      reason: '拿到权威版本后必须换新票',
    );
    expect(_formField(answers[0], 'expectedRouteVersion'), '5');
    expect(_formField(answers[1], 'expectedRouteVersion'), '6');
    expect(adapter.sentFor('/api/play/route-state'), hasLength(1));
    expect(reward.routeState?.version, 7);
  });

  test('真实 adapter:权威 state 显示已完成时清票且不二次提交', () async {
    final _RoutingAdapter adapter = _RoutingAdapter();
    int nodesVersion = 5;
    Map<String, dynamic> nodeStates = <String, dynamic>{'7': 'PLAYABLE'};
    int answerCalls = 0;
    adapter.on(
      '/api/play/nodes',
      (_) => _nodesBody(version: nodesVersion, nodeStates: nodeStates),
    );
    adapter.on('/api/play/route-state', (_) {
      // 权威 state 已显示节点完成,刷新节点也应看到同一版本。
      nodesVersion = 6;
      nodeStates = <String, dynamic>{'7': 'COMPLETED', '8': 'PLAYABLE'};
      return <String, dynamic>{
        'code': 200,
        'data': _routeStateData(version: 6, nodeStates: nodeStates),
      };
    });
    adapter.on('/api/play/answer', (RequestOptions _) {
      answerCalls += 1;
      return <String, dynamic>{'code': '409', 'msg': '路线状态已更新'};
    });

    final _Harness harness = await _harness(PlayApi(_client(adapter)));
    addTearDown(harness.dispose);

    await expectLater(
      harness.notifier.answer(7, 'A'),
      throwsA(
        isA<PlayException>().having(
          (PlayException e) => e.code,
          'code',
          isNull,
        ),
      ),
    );
    expect(answerCalls, 1, reason: '已完成节点绝不二次提交');
    expect(
      harness.container.read(harness.provider).value?.routeState?.version,
      6,
    );

    // 旧票已清:下一次同语义动作必须生成新 actionId。
    await expectLater(
      harness.notifier.answer(7, 'A'),
      throwsA(isA<PlayException>()),
    );
    final List<RequestOptions> answers = adapter.sentFor('/api/play/answer');
    expect(answers, hasLength(2));
    expect(
      _formField(answers[0], 'routeActionId'),
      isNot(_formField(answers[1], 'routeActionId')),
    );
  });
}

typedef _Harness = ({
  ProviderContainer container,
  PlaySessionController notifier,
  dynamic provider,
  void Function() dispose,
});

Future<_Harness> _harness(PlayApi api) async {
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

DioClient _client(_RoutingAdapter adapter) {
  final DioClient client = DioClient(TokenStore(const FlutterSecureStorage()));
  client.dio.httpClientAdapter = adapter;
  return client;
}

class _RoutingAdapter implements HttpClientAdapter {
  final Map<String, Map<String, dynamic> Function(RequestOptions)> _handlers =
      <String, Map<String, dynamic> Function(RequestOptions)>{};
  final List<RequestOptions> sent = <RequestOptions>[];

  void on(
    String path,
    Map<String, dynamic> Function(RequestOptions options) handler,
  ) {
    _handlers[path] = handler;
  }

  List<RequestOptions> sentFor(String path) =>
      sent.where((RequestOptions r) => r.path == path).toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent.add(options);
    final handler = _handlers[options.path];
    return ResponseBody.fromString(
      jsonEncode(
        handler == null
            ? <String, dynamic>{
                'code': 404,
                'msg': 'unexpected ${options.path}',
              }
            : handler(options),
      ),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String _formField(RequestOptions request, String key) =>
    (request.data as FormData).fields
        .firstWhere((MapEntry<String, String> e) => e.key == key)
        .value;

Map<String, dynamic> _nodesBody({
  required int version,
  Map<String, dynamic> nodeStates = const <String, dynamic>{'7': 'PLAYABLE'},
}) => <String, dynamic>{
  'code': 200,
  'data': <String, dynamic>{
    'topicId': 71,
    'mode': 1,
    'playable': true,
    'total': 1,
    'doneCount': 0,
    'nodes': <dynamic>[],
    'routeState': _routeStateData(version: version, nodeStates: nodeStates),
  },
};

Map<String, dynamic> _routeStateData({
  required int version,
  Map<String, dynamic> nodeStates = const <String, dynamic>{'7': 'PLAYABLE'},
}) => <String, dynamic>{
  'routeMode': 'BRANCH_GRAPH',
  'sessionId': 91,
  'status': 'ACTIVE',
  'currentNodeId': 7,
  'recommendedNodeId': 7,
  'version': version,
  'nodeStates': nodeStates,
  'decisionLog': <dynamic>[],
};

Map<String, dynamic> _rewardBody({required int version}) => <String, dynamic>{
  'code': 200,
  'data': <String, dynamic>{
    'nodeId': 7,
    'firstTime': true,
    'done': 1,
    'total': 1,
    'completed': false,
    'newBadges': <dynamic>[],
    'routeState': _routeStateData(
      version: version,
      nodeStates: <String, dynamic>{'7': 'COMPLETED', '8': 'PLAYABLE'},
    ),
  },
};
