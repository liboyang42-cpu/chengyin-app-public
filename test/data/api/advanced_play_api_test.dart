// 高级单人玩法接口(`/api/play/advanced/*`,4 条)。
//
// 这条链是 2026-09-17 从 `feature/figma-confirmed-0909` 补进 parity/play-advanced 的:
// start → action → state → leaderboard。后端把玩法局当**权威状态机**——
// 动作必须带 sessionId + version + 幂等键。客户端接错不会当场报错,
// 只会把「别的局」「过期的回执」当成本次成功,所以这里每条都测静默错误。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/advanced_play_api.dart';
import 'package:chengyin_app/data/models/advanced_play.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  ({AdvancedPlayApi api, List<RequestOptions> sent}) build(
    Map<String, dynamic> Function(RequestOptions) reply,
  ) {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final List<RequestOptions> sent = <RequestOptions>[];
    client.dio.httpClientAdapter = _StubAdapter((RequestOptions options) {
      sent.add(options);
      return reply(options);
    });
    return (api: AdvancedPlayApi(client), sent: sent);
  }

  Map<String, dynamic> state({
    int sessionId = 7,
    int activityId = 3,
    int topicId = 0,
    int nodeId = 11,
    int version = 1,
    String status = 'RUNNING',
  }) => <String, dynamic>{
    'sessionId': sessionId,
    'activityId': activityId,
    'topicId': topicId,
    'nodeId': nodeId,
    'status': status,
    'version': version,
    'score': 0,
    'readyForBase': false,
    'config': <String, dynamic>{},
    'draws': <dynamic>[],
    'playKit': <String, dynamic>{},
    'multiplayer': <String, dynamic>{},
  };

  group('start', () {
    test('走 POST /api/play/advanced/start，定位三件套原样传出', () async {
      final r = build(
        (_) => <String, dynamic>{'code': 200, 'data': state()},
      );
      final AdvancedPlayState result = await r.api.start(
        activityId: 3,
        topicId: 0,
        nodeId: 11,
      );
      expect(result.sessionId, 7);
      expect(r.sent.single.method, 'POST');
      expect(r.sent.single.path, '/api/play/advanced/start');
      expect(r.sent.single.data, <String, Object?>{
        'activityId': 3,
        'topicId': 0,
        'nodeId': 11,
      });
    });

    test('★ 回执换了节点必须拒绝——不能把别的局当自己的', () async {
      final r = build(
        (_) => <String, dynamic>{'code': 200, 'data': state(nodeId: 99)},
      );
      await expectLater(
        r.api.start(activityId: 3, topicId: 0, nodeId: 11),
        throwsA(isA<AdvancedPlayContractException>()),
      );
    });
  });

  group('action', () {
    test('参数不完整时本地拒绝，不发任何请求', () async {
      final r = build((_) => <String, dynamic>{'code': 200, 'data': state()});
      await expectLater(
        r.api.action(
          sessionId: 0,
          version: 1,
          idempotencyKey: 'k',
          action: 'PICK',
          payload: const <String, Object?>{},
        ),
        throwsA(isA<AdvancedPlayContractException>()),
      );
      await expectLater(
        r.api.action(
          sessionId: 7,
          version: 1,
          idempotencyKey: '',
          action: 'PICK',
          payload: const <String, Object?>{},
        ),
        throwsA(isA<AdvancedPlayContractException>()),
      );
      expect(r.sent, isEmpty);
    });

    test('动作名转大写，version 与幂等键原样送出', () async {
      final r = build(
        (_) => <String, dynamic>{'code': 200, 'data': state(version: 2)},
      );
      final AdvancedPlayState result = await r.api.action(
        sessionId: 7,
        version: 1,
        idempotencyKey: 'ap:7:1:abc',
        action: ' pick ',
        payload: const <String, Object?>{'slot': 2},
      );
      expect(result.version, 2);
      final Map<String, Object?> body =
          r.sent.single.data! as Map<String, Object?>;
      expect(body['action'], 'PICK');
      expect(body['version'], 1);
      expect(body['idempotencyKey'], 'ap:7:1:abc');
      expect(body['payload'], <String, Object?>{'slot': 2});
    });

    test('★ 回执版本原地踏步必须拒绝——过期回执不能被当成功', () async {
      final r = build(
        (_) => <String, dynamic>{'code': 200, 'data': state(version: 1)},
      );
      await expectLater(
        r.api.action(
          sessionId: 7,
          version: 1,
          idempotencyKey: 'ap:7:1:abc',
          action: 'PICK',
          payload: const <String, Object?>{},
        ),
        throwsA(isA<AdvancedPlayContractException>()),
      );
    });
  });

  group('state', () {
    test('走 GET + sessionId query，回执换局必须拒绝', () async {
      final r = build(
        (_) => <String, dynamic>{'code': 200, 'data': state(sessionId: 8)},
      );
      await expectLater(
        r.api.state(7),
        throwsA(isA<AdvancedPlayContractException>()),
      );
      expect(r.sent.single.method, 'GET');
      expect(r.sent.single.path, '/api/play/advanced/state');
      expect(r.sent.single.queryParameters, <String, Object?>{'sessionId': 7});
    });

    test('业务码非 200 时抛后端原文，不吞成成功', () async {
      final r = build(
        (_) => <String, dynamic>{'code': 500, 'msg': '节点不在进行中'},
      );
      await expectLater(
        r.api.state(7),
        throwsA(
          isA<AdvancedPlayBusinessException>().having(
            (AdvancedPlayBusinessException e) => e.message,
            'message',
            '节点不在进行中',
          ),
        ),
      );
    });
  });

  group('leaderboard', () {
    test('走 GET + 三件套 query，正常行按名次解析', () async {
      final r = build(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <dynamic>[
            <String, dynamic>{
              'rank': 1,
              'ownerId': 5,
              'displayName': '阿岚',
              'score': 30,
              'elapsedSeconds': 12,
              'completedUnits': 2,
            },
          ],
        },
      );
      final List<AdvancedPlayLeaderboardRow> rows = await r.api.leaderboard(
        activityId: 3,
        topicId: 0,
        nodeId: 11,
      );
      expect(rows.single.displayName, '阿岚');
      expect(rows.single.metricValue('COMPLETED_UNITS'), '2');
      expect(r.sent.single.queryParameters, <String, Object?>{
        'activityId': 3,
        'topicId': 0,
        'nodeId': 11,
      });
    });

    test('★ 行缺 displayName 视为回执不完整，不能渲染空名字', () async {
      final r = build(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <dynamic>[
            <String, dynamic>{
              'rank': 1,
              'ownerId': 5,
              'score': 3,
              'elapsedSeconds': 1,
              'completedUnits': 1,
            },
          ],
        },
      );
      await expectLater(
        r.api.leaderboard(activityId: 3, topicId: 0, nodeId: 11),
        throwsA(isA<AdvancedPlayContractException>()),
      );
    });
  });

  test('断网抛传输异常，不把没送达当成功', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    client.dio.httpClientAdapter = _ThrowingAdapter();
    final AdvancedPlayApi api = AdvancedPlayApi(client);
    await expectLater(
      api.start(activityId: 3, topicId: 0, nodeId: 11),
      throwsA(isA<AdvancedPlayTransportException>()),
    );
  });
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.onRequest);
  final Map<String, dynamic> Function(RequestOptions) onRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(onRequest(options)),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(requestOptions: options, message: '断网');
  }

  @override
  void close({bool force = false}) {}
}
