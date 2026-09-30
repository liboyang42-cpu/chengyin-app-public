import 'dart:convert';
import 'dart:io';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/advanced_play_api.dart';
import 'package:chengyin_app/data/models/advanced_play.dart';
import 'package:chengyin_app/feature/play/advanced/advanced_play_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// 玩法 advanced 的**接口落点门**:四条端点经真实 [AdvancedPlayApi] × stub HTTP
/// adapter 走一遍,钉住路径 / 方法 / 请求字段 / 回执不兜底。
///
/// 为什么单开一个文件:controller 层的测试注入的是 fake gateway,证明不了
/// 「端点真的被发出去、字段名真的是这些」。字段名写错时服务端按 0 判,
/// 不报错,只是这个玩法永远不通过 —— 所以这一层必须自己钉死。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  group('端点落点', () {
    test('start/action/state/leaderboard 各自落到自己的 URL 与方法', () async {
      final _StubAdapter adapter = _StubAdapter();
      adapter.on(
        '/api/play/advanced/start',
        (RequestOptions _) => _stateBody(sessionId: 88, version: 0),
      );
      adapter.on(
        '/api/play/advanced/action',
        (RequestOptions _) => _stateBody(sessionId: 88, version: 1),
      );
      adapter.on(
        '/api/play/advanced/state',
        (RequestOptions _) => _stateBody(sessionId: 88, version: 1),
      );
      adapter.on(
        '/api/play/advanced/leaderboard',
        (RequestOptions _) => _leaderboardBody(),
      );
      final AdvancedPlayApi api = AdvancedPlayApi(_client(adapter));

      await api.start(activityId: 42, topicId: 71, nodeId: 7);
      await api.action(
        sessionId: 88,
        version: 0,
        idempotencyKey: 'k1',
        action: 'DRAW',
        payload: const <String, Object?>{},
      );
      await api.state(88);
      await api.leaderboard(activityId: 42, topicId: 71, nodeId: 7);

      expect(adapter.sentFor('/api/play/advanced/start').single.method, 'POST');
      expect(
        adapter.sentFor('/api/play/advanced/action').single.method,
        'POST',
      );
      expect(adapter.sentFor('/api/play/advanced/state').single.method, 'GET');
      expect(
        adapter.sentFor('/api/play/advanced/leaderboard').single.method,
        'GET',
      );
      // 落点就是这四条;少一条或多一条都说明接线变了。
      expect(adapter.sent.map((RequestOptions r) => r.path).toSet(), <String>{
        '/api/play/advanced/start',
        '/api/play/advanced/action',
        '/api/play/advanced/state',
        '/api/play/advanced/leaderboard',
      });
    });
  });

  group('对账工具假红回归门', () {
    test('API 文件里真的写着这四条路径字面量,且没被注释掉', () {
      final String source = File(
        'lib/data/api/advanced_play_api.dart',
      ).readAsStringSync();
      final List<String> live = source
          .split('\n')
          .where((String line) => !line.trimLeft().startsWith('//'))
          .toList();
      for (final String path in <String>[
        '/api/play/advanced/start',
        '/api/play/advanced/action',
        '/api/play/advanced/state',
        '/api/play/advanced/leaderboard',
      ]) {
        expect(
          live.where((String line) => line.contains("'$path'")),
          isNotEmpty,
          reason: '$path 的路径字面量必须还在代码里(注释不算接通)',
        );
      }
    });

    test('页面注册的 gateway 就是真实实现,不是空壳', () {
      final String providers = File(
        'lib/core/providers.dart',
      ).readAsStringSync();
      expect(
        providers,
        contains('AdvancedPlayApi(ref.watch(dioClientProvider))'),
        reason: 'provider 必须构造真实 API;换成空实现这条玩法就静默失效',
      );
    });
  });

  group('请求字段', () {
    test('start 的 body 就是 activityId/topicId/nodeId', () async {
      final _StubAdapter adapter = _StubAdapter();
      adapter.on(
        '/api/play/advanced/start',
        (RequestOptions _) => _stateBody(sessionId: 88, version: 0),
      );
      await AdvancedPlayApi(
        _client(adapter),
      ).start(activityId: 42, topicId: 71, nodeId: 7);

      expect(_jsonBody(adapter.sentFor('/api/play/advanced/start').single), {
        'activityId': 42,
        'topicId': 71,
        'nodeId': 7,
      });
    });

    test('action 的 body 五个字段一个都不能改', () async {
      final _StubAdapter adapter = _StubAdapter();
      adapter.on(
        '/api/play/advanced/action',
        (RequestOptions _) => _stateBody(sessionId: 88, version: 1),
      );
      await AdvancedPlayApi(_client(adapter)).action(
        sessionId: 88,
        version: 0,
        idempotencyKey: 'session-88-v0-COMPLETE_UNIT',
        action: 'complete_unit',
        payload: const <String, Object?>{'unitId': 'u-1'},
      );

      expect(_jsonBody(adapter.sentFor('/api/play/advanced/action').single), {
        'sessionId': 88,
        'version': 0,
        'idempotencyKey': 'session-88-v0-COMPLETE_UNIT',
        // 动作名统一大写:服务端按大写 switch。
        'action': 'COMPLETE_UNIT',
        'payload': <String, Object?>{'unitId': 'u-1'},
      });
    });

    test('state 用 query 传 sessionId,不是 body', () async {
      final _StubAdapter adapter = _StubAdapter();
      adapter.on(
        '/api/play/advanced/state',
        (RequestOptions _) => _stateBody(sessionId: 88, version: 1),
      );
      await AdvancedPlayApi(_client(adapter)).state(88);

      final RequestOptions sent = adapter
          .sentFor('/api/play/advanced/state')
          .single;
      expect(sent.queryParameters, <String, Object?>{'sessionId': 88});
    });

    test('leaderboard 三个定位参数齐全 —— 缺一个会拉到别人的榜', () async {
      final _StubAdapter adapter = _StubAdapter();
      adapter.on(
        '/api/play/advanced/leaderboard',
        (RequestOptions _) => _leaderboardBody(),
      );
      await AdvancedPlayApi(
        _client(adapter),
      ).leaderboard(activityId: 42, topicId: 71, nodeId: 7);

      expect(
        adapter
            .sentFor('/api/play/advanced/leaderboard')
            .single
            .queryParameters,
        <String, Object?>{'activityId': 42, 'topicId': 71, 'nodeId': 7},
      );
    });
  });

  group('回执不兜底', () {
    test('start 回执节点与请求不一致 → 契约异常,不静默当成别的局', () async {
      final _StubAdapter adapter = _StubAdapter();
      adapter.on(
        '/api/play/advanced/start',
        (RequestOptions _) =>
            _stateBody(sessionId: 88, version: 0, nodeId: 999),
      );

      await expectLater(
        AdvancedPlayApi(
          _client(adapter),
        ).start(activityId: 42, topicId: 71, nodeId: 7),
        throwsA(isA<AdvancedPlayContractException>()),
      );
    });

    test('action 回执 version 未前进 → 契约异常(不能当成功继续加锁)', () async {
      final _StubAdapter adapter = _StubAdapter();
      adapter.on(
        '/api/play/advanced/action',
        (RequestOptions _) => _stateBody(sessionId: 88, version: 3),
      );

      await expectLater(
        AdvancedPlayApi(_client(adapter)).action(
          sessionId: 88,
          version: 3,
          idempotencyKey: 'k1',
          action: 'DRAW',
          payload: const <String, Object?>{},
        ),
        throwsA(isA<AdvancedPlayContractException>()),
      );
    });

    test('state 回读的是别的 session → 契约异常', () async {
      final _StubAdapter adapter = _StubAdapter();
      adapter.on(
        '/api/play/advanced/state',
        (RequestOptions _) => _stateBody(sessionId: 99, version: 1),
      );

      await expectLater(
        AdvancedPlayApi(_client(adapter)).state(88),
        throwsA(isA<AdvancedPlayContractException>()),
      );
    });

    test('leaderboard data 不是数组 → 契约异常,不显示空榜骗人', () async {
      final _StubAdapter adapter = _StubAdapter();
      adapter.on(
        '/api/play/advanced/leaderboard',
        (RequestOptions _) => <String, dynamic>{'code': 200, 'data': null},
      );

      await expectLater(
        AdvancedPlayApi(
          _client(adapter),
        ).leaderboard(activityId: 42, topicId: 71, nodeId: 7),
        throwsA(isA<AdvancedPlayContractException>()),
      );
    });

    test('榜单行缺 displayName → 契约异常', () async {
      final _StubAdapter adapter = _StubAdapter();
      adapter.on(
        '/api/play/advanced/leaderboard',
        (RequestOptions _) => <String, dynamic>{
          'code': 200,
          'data': <Object?>[
            <String, dynamic>{
              'rank': 1,
              'ownerId': 5,
              'score': 10,
              'elapsedSeconds': 3,
              'completedUnits': 1,
            },
          ],
        },
      );

      await expectLater(
        AdvancedPlayApi(
          _client(adapter),
        ).leaderboard(activityId: 42, topicId: 71, nodeId: 7),
        throwsA(isA<AdvancedPlayContractException>()),
      );
    });

    test('业务码非 200 走业务异常,带着服务端那句原话', () async {
      final _StubAdapter adapter = _StubAdapter();
      adapter.on(
        '/api/play/advanced/action',
        (RequestOptions _) => <String, dynamic>{
          'code': '409',
          'msg': '玩法状态已更新',
        },
      );

      await expectLater(
        AdvancedPlayApi(_client(adapter)).action(
          sessionId: 88,
          version: 0,
          idempotencyKey: 'k1',
          action: 'DRAW',
          payload: const <String, Object?>{},
        ),
        throwsA(
          isA<AdvancedPlayBusinessException>().having(
            (AdvancedPlayBusinessException e) => e.message,
            'message',
            contains('状态已更新'),
          ),
        ),
      );
    });

    test('榜单 metricValue 按服务端 metric 算,不写死分数', () {
      const AdvancedPlayLeaderboardRow row = AdvancedPlayLeaderboardRow(
        rank: 1,
        ownerId: 5,
        displayName: '甲',
        score: 10,
        elapsedSeconds: 42,
        completedUnits: 3,
      );
      expect(row.metricValue('ELAPSED_TIME'), '42s');
      expect(row.metricValue('COMPLETED_UNITS'), '3');
      expect(row.metricValue('SCORE'), '10');
    });
  });

  group('经控制器:幂等键与权威回读', () {
    test('响应没回来 → 回读确认未写入 → 重试复用同一幂等键,服务端才能 replay 去重', () async {
      final _StubAdapter adapter = _StubAdapter();
      adapter.on(
        '/api/play/advanced/start',
        (RequestOptions _) => _stateBody(sessionId: 88, version: 0),
      );
      // 回读说 version 还是 0 = 服务端还没写入这一步。
      adapter.on(
        '/api/play/advanced/state',
        (RequestOptions _) => _stateBody(sessionId: 88, version: 0),
      );
      adapter.on(
        '/api/play/advanced/action',
        (RequestOptions _) => _stateBody(sessionId: 88, version: 1),
      );
      final AdvancedPlayController controller = AdvancedPlayController(
        gateway: AdvancedPlayApi(_client(adapter)),
        activityId: 42,
        topicId: 71,
        nodeId: 7,
      );
      addTearDown(controller.dispose);

      await controller.start();
      expect(controller.phase, AdvancedPlayPhase.ready);

      // 请求发出去了、响应没回来。必须仍然记在案:这一次调用真的上了网。
      adapter.dropNextActionResponse = true;
      await controller.submit('DRAW');
      expect(controller.phase, AdvancedPlayPhase.unknown);

      // 结果未知不是失败:由界面上的「再核对一次」驱动权威回读。
      await controller.resolveUnknown();
      expect(
        controller.phase,
        AdvancedPlayPhase.retryable,
        reason: '回读没看到这一步写入,才允许重试',
      );

      await controller.retryPending();
      expect(controller.phase, AdvancedPlayPhase.ready);
      expect(controller.state!.version, 1);

      final List<RequestOptions> actions = adapter.sentFor(
        '/api/play/advanced/action',
      );
      expect(actions, hasLength(2), reason: '一次原发 + 一次重试');
      expect(
        _jsonBody(actions[0])['idempotencyKey'],
        _jsonBody(actions[1])['idempotencyKey'],
        reason: '同一次意图重试必须复用同一个键,否则服务端去重拦不住重复写',
      );
      expect(
        _jsonBody(actions[0])['version'],
        _jsonBody(actions[1])['version'],
      );
    });

    test('服务端说状态已更新 → 回读权威状态,不是停在 error 让玩家拿旧 version 乱重发', () async {
      final _StubAdapter adapter = _StubAdapter();
      adapter.on(
        '/api/play/advanced/start',
        (RequestOptions _) => _stateBody(sessionId: 88, version: 0),
      );
      // 服务端的「状态已更新」是业务码非 200 + msg,不是 200 带空 data。
      adapter.on(
        '/api/play/advanced/action',
        (RequestOptions _) => <String, dynamic>{
          'code': '409',
          'msg': '玩法状态已更新',
        },
      );
      adapter.on(
        '/api/play/advanced/state',
        (RequestOptions _) => _stateBody(sessionId: 88, version: 4),
      );
      final AdvancedPlayController controller = AdvancedPlayController(
        gateway: AdvancedPlayApi(_client(adapter)),
        activityId: 42,
        topicId: 71,
        nodeId: 7,
      );
      addTearDown(controller.dispose);

      await controller.start();
      await controller.submit('DRAW');

      expect(controller.phase, AdvancedPlayPhase.ready);
      expect(controller.state!.version, 4);
      expect(controller.message, contains('状态已更新'));
      expect(
        adapter.sentFor('/api/play/advanced/state'),
        hasLength(1),
        reason: '冲突后必须回读权威状态',
      );
    });
  });
}

DioClient _client(HttpClientAdapter adapter) {
  final DioClient client = DioClient(TokenStore(const FlutterSecureStorage()));
  client.dio.httpClientAdapter = adapter;
  return client;
}

Map<String, Object?> _jsonBody(RequestOptions request) =>
    (request.data as Map).map<String, Object?>(
      (Object? key, Object? value) => MapEntry('$key', value),
    );

class _StubAdapter implements HttpClientAdapter {
  final Map<String, Map<String, dynamic> Function(RequestOptions)> _handlers =
      <String, Map<String, dynamic> Function(RequestOptions)>{};
  final List<RequestOptions> sent = <RequestOptions>[];

  /// 下一次动作请求「发出去了但响应没回来」:请求照常记在案,只把响应吞掉。
  bool dropNextActionResponse = false;

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
    if (dropNextActionResponse && options.path == '/api/play/advanced/action') {
      dropNextActionResponse = false;
      throw DioException.connectionError(
        requestOptions: options,
        reason: '响应未送达',
      );
    }
    final Map<String, dynamic> Function(RequestOptions)? handler =
        _handlers[options.path];
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

Map<String, dynamic> _stateBody({
  required int sessionId,
  required int version,
  int nodeId = 7,
}) => <String, dynamic>{
  'code': 200,
  'data': <String, dynamic>{
    'sessionId': sessionId,
    'activityId': 42,
    'topicId': 71,
    'nodeId': nodeId,
    'status': 'RUNNING',
    'version': version,
    'score': 0,
    'readyForBase': false,
    'deadlineAt': null,
    'config': <String, dynamic>{
      'timer': <String, dynamic>{'enabled': false},
      'random': <String, dynamic>{'enabled': true, 'drawCount': 2},
      'branch': <String, dynamic>{'enabled': false},
      'leaderboard': <String, dynamic>{'enabled': false},
      'multiplayer': <String, dynamic>{'enabled': false},
    },
    'draws': <Object?>[],
    'branch': null,
    'multiplayer': <String, dynamic>{'roles': <String, dynamic>{}},
  },
};

Map<String, dynamic> _leaderboardBody() => <String, dynamic>{
  'code': 200,
  'data': <Object?>[
    <String, dynamic>{
      'rank': 1,
      'ownerId': 5,
      'displayName': '甲',
      'score': 10,
      'elapsedSeconds': 42,
      'completedUnits': 3,
    },
  ],
};
