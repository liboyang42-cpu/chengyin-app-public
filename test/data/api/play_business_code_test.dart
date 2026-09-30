import 'dart:convert';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真实 `PlayApi` + stub HTTP adapter(HTTP 200)覆盖 AjaxResult 业务码矩阵:
/// 后端不同出口可能把顶层 `code` 发成数字字符串("200"/"409"),端上必须统一
/// 解析;解析不出的类型 fail closed,绝不误判成功,也绝不 TypeError。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  test('所有完成 transport(FormData + JSON)接受 num 与数字字符串业务码 200', () async {
    for (final Object code in <Object>[200, '200']) {
      for (final (String name, Future<Object?> Function(PlayApi) call)
          in _completionTransports()) {
        final _Stub stub = _stub(<String, dynamic>{
          'code': code,
          'data': _rewardData,
        });

        await call(PlayApi(stub.client));

        expect(stub.sent, hasLength(1), reason: '$name code=$code');
      }
    }
  });

  test(
    '所有完成 transport 对 num 与数字字符串业务码 409 抛 PlayException(code:409) 且保留原文',
    () async {
      for (final Object code in <Object>[409, '409']) {
        for (final (String name, Future<Object?> Function(PlayApi) call)
            in _completionTransports()) {
          final _Stub stub = _stub(<String, dynamic>{
            'code': code,
            'msg': '路线状态已更新',
          });

          await expectLater(
            call(PlayApi(stub.client)),
            throwsA(
              isA<PlayException>()
                  .having((PlayException e) => e.code, 'code', 409)
                  .having((PlayException e) => e.message, 'message', '路线状态已更新'),
            ),
            reason: '$name code=$code',
          );
        }
      }
    },
  );

  test('无法解析的业务码 fail closed:抛 PlayException 而非 TypeError,也不误判成功', () async {
    for (final Object? code in <Object?>[
      true,
      'abc',
      '20x0',
      <String, dynamic>{},
      null,
    ]) {
      final _Stub stub = _stub(<String, dynamic>{'code': code, 'msg': '后端异常'});

      await expectLater(
        PlayApi(stub.client).submitCheckin(activityId: 41, code: 'scan'),
        throwsA(
          isA<PlayException>()
              .having((PlayException e) => e.code, 'code', isNull)
              .having((PlayException e) => e.message, 'message', '后端异常'),
        ),
        reason: 'code=$code 必须 fail closed',
      );
    }
  });

  test('fetchRouteState 按 activityId/topicId 唯一会话参数恢复读取', () async {
    final List<(Future<void> Function(PlayApi), Map<String, dynamic>)> cases =
        <(Future<void> Function(PlayApi), Map<String, dynamic>)>[
          (
            (PlayApi api) => api.fetchRouteState(activityId: 41),
            <String, dynamic>{'activityId': 41},
          ),
          (
            (PlayApi api) => api.fetchRouteState(topicId: 71),
            <String, dynamic>{'topicId': 71},
          ),
        ];

    for (final (Future<void> Function(PlayApi) call, Map<String, dynamic> query)
        in cases) {
      final _Stub stub = _stub(<String, dynamic>{
        'code': 200,
        'data': _routeState(version: 6),
      });

      await call(PlayApi(stub.client));

      expect(stub.sent.single.path, '/api/play/route-state');
      expect(stub.sent.single.queryParameters, query);
    }
  });

  test('fetchRouteState 同时给 activityId/topicId 时本地拒绝,不发请求', () async {
    final _Stub stub = _stub(<String, dynamic>{'code': 200});

    await expectLater(
      PlayApi(stub.client).fetchRouteState(activityId: 41, topicId: 71),
      throwsArgumentError,
    );
    expect(stub.sent, isEmpty);
  });

  test('fetchRouteState 接受数字字符串业务码 200(不 TypeError)', () async {
    final _Stub stub = _stub(<String, dynamic>{
      'code': '200',
      'data': _routeState(version: 6),
    });

    final state = await PlayApi(stub.client).fetchRouteState(activityId: 41);

    expect(state.version, 6);
    expect(stub.sent.single.path, '/api/play/route-state');
  });

  test('fetchRouteState 未知业务码类型 fail closed:保留 msg 且不 TypeError', () async {
    for (final Object? code in <Object?>[
      true,
      'abc',
      '20x0',
      <String, dynamic>{},
      null,
    ]) {
      final _Stub stub = _stub(<String, dynamic>{
        'code': code,
        'msg': '路线状态加载失败',
      });

      await expectLater(
        PlayApi(stub.client).fetchRouteState(activityId: 41),
        throwsA(
          isA<PlayException>()
              .having((PlayException e) => e.code, 'code', isNull)
              .having((PlayException e) => e.message, 'message', '路线状态加载失败'),
        ),
        reason: 'code=$code 必须 fail closed',
      );
    }
  });

  test('fetchRouteState 数字字符串业务码 409 抛 PlayException(code:409) 保留原文', () async {
    final _Stub stub = _stub(<String, dynamic>{
      'code': '409',
      'msg': '路线状态已更新',
    });

    await expectLater(
      PlayApi(stub.client).fetchRouteState(activityId: 41),
      throwsA(
        isA<PlayException>()
            .having((PlayException e) => e.code, 'code', 409)
            .having((PlayException e) => e.message, 'message', '路线状态已更新'),
      ),
    );
  });

  test('其余 AjaxResult 加载出口对数字字符串码与未知类型同样 fail closed', () async {
    final List<(String, Future<Object?> Function(PlayApi))> exits =
        <(String, Future<Object?> Function(PlayApi))>[
          ('fetchNodes', (PlayApi api) => api.fetchNodes(41)),
          ('fetchTopicNodes', (PlayApi api) => api.fetchTopicNodes(71)),
          ('companionLine', (PlayApi api) => api.companionLine(activityId: 41)),
          ('unlockHint', (PlayApi api) => api.unlockHint(7)),
          ('ending', (PlayApi api) => api.ending(activityId: 41)),
          ('myCompleted', (PlayApi api) => api.myCompleted()),
        ];

    for (final (String name, Future<Object?> Function(PlayApi) call) in exits) {
      for (final Object? code in <Object?>['abc', true, null]) {
        final _Stub stub = _stub(<String, dynamic>{
          'code': code,
          'msg': '后端异常',
        });

        await expectLater(
          call(PlayApi(stub.client)),
          throwsA(isA<Exception>()),
          reason: '$name code=$code 必须 fail closed 且不是 TypeError',
        );
      }
    }
  });

  test('偏好题出口接受数字字符串业务码 200(不 TypeError)', () async {
    final _Stub stub = _stub(<String, dynamic>{
      'code': '200',
      'data': <String, dynamic>{'nodeId': 17, 'steps': <dynamic>[]},
    });

    final questionnaire = await PlayApi(
      stub.client,
    ).fetchPreference(topicId: 71, nodeId: 17);

    expect(questionnaire.nodeId, 17);
    expect(stub.sent.single.path, '/api/play/preference/17');
  });

  test('偏好题出口未知业务码类型 fail closed:保留 msg 且不 TypeError', () async {
    for (final Object? code in <Object?>[
      true,
      'abc',
      '20x0',
      <String, dynamic>{},
      null,
    ]) {
      final _Stub stub = _stub(<String, dynamic>{
        'code': code,
        'msg': '偏好题加载失败',
      });

      await expectLater(
        PlayApi(stub.client).fetchPreference(topicId: 71, nodeId: 17),
        throwsA(
          isA<PlayException>()
              .having((PlayException e) => e.code, 'code', isNull)
              .having((PlayException e) => e.message, 'message', '偏好题加载失败'),
        ),
        reason: 'code=$code 必须 fail closed',
      );
    }
  });

  group('★ 首屏空态要能分到类:402 / registered / 回包形状', () {
    test('业务码 402(没有自玩通行证)带码抛出 —— 端上按码落 needPass', () async {
      for (final Object code in <Object>[402, '402']) {
        final _Stub stub = _stub(<String, dynamic>{
          'code': code,
          'msg': '请先购买自玩通行证',
        });

        await expectLater(
          PlayApi(stub.client).fetchTopicNodes(71),
          throwsA(
            isA<PlayException>()
                .having((PlayException e) => e.code, 'code', 402)
                .having((PlayException e) => e.message, 'message', '请先购买自玩通行证'),
          ),
          reason: 'code=$code',
        );
      }
    });

    test('registered 是三态:后端没发这个字段不得判成「未报名」', () async {
      Future<PlayNodesResult> fetchWith(Object? registered) {
        final _Stub stub = _stub(<String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'total': 1,
            'nodes': <dynamic>[
              <String, dynamic>{
                'nodeId': 7,
                'name': '第一站',
                'address': '',
                'sortId': 1,
                'done': 0,
              },
            ],
            'registered': ?registered,
          },
        });
        return PlayApi(stub.client).fetchNodes(41);
      }

      expect((await fetchWith(false)).registered, isFalse);
      expect((await fetchWith(true)).registered, isTrue);
      expect((await fetchWith(null)).registered, isNull);
    });

    test('★ 回包缺 nodes 数组落「路线没加载出来」,不许顺着兜底报成「还在配置中」', () async {
      for (final Map<String, dynamic> data in <Map<String, dynamic>>[
        <String, dynamic>{'total': 0},
        <String, dynamic>{
          'total': 0,
          'nodes': <dynamic>['不是对象'],
        },
        <String, dynamic>{'total': 0, 'nodes': 'x'},
      ]) {
        final _Stub stub = _stub(<String, dynamic>{'code': 200, 'data': data});

        await expectLater(
          PlayApi(stub.client).fetchNodes(41),
          throwsA(
            isA<PlayException>().having(
              (PlayException e) => e.message,
              'message',
              kPlayRouteShapeBrokenTip,
            ),
          ),
          reason: 'data=$data 是坏回包,不是空路线',
        );
      }
    });

    test('空数组是合法回包(真没配节点),照常解析成空列表', () async {
      final _Stub stub = _stub(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'total': 0, 'nodes': <dynamic>[]},
      });

      final result = await PlayApi(stub.client).fetchNodes(41);

      expect(result.nodes, isEmpty);
      expect(result.registered, isNull);
    });
  });
}

List<(String, Future<Object?> Function(PlayApi))> _completionTransports() =>
    <(String, Future<Object?> Function(PlayApi))>[
      (
        'submitCheckin',
        (PlayApi api) => api.submitCheckin(activityId: 41, code: 'scan'),
      ),
      (
        'submitTopicCheckin',
        (PlayApi api) => api.submitTopicCheckin(topicId: 71, code: 'scan'),
      ),
      (
        'submitAnswer',
        (PlayApi api) =>
            api.submitAnswer(activityId: 41, nodeId: 7, answer: 'A'),
      ),
      (
        'submitTopicAnswer',
        (PlayApi api) =>
            api.submitTopicAnswer(topicId: 71, nodeId: 7, answer: 'A'),
      ),
      (
        'submitArrive',
        (PlayApi api) => api.submitArrive(
          activityId: 41,
          nodeId: 7,
          longitude: 121.4,
          latitude: 31.2,
        ),
      ),
      (
        'submitTopicArrive',
        (PlayApi api) => api.submitTopicArrive(
          topicId: 71,
          nodeId: 7,
          longitude: 121.4,
          latitude: 31.2,
        ),
      ),
      (
        'submitPhoto',
        (PlayApi api) => api.submitPhoto(
          activityId: 41,
          nodeId: 7,
          picUrl: 'https://cdn.example.com/proof.jpg',
        ),
      ),
      (
        'submitTopicPhoto',
        (PlayApi api) => api.submitTopicPhoto(
          topicId: 71,
          nodeId: 7,
          picUrl: 'https://cdn.example.com/proof.jpg',
        ),
      ),
      (
        'submitSensorResult',
        (PlayApi api) => api.submitSensorResult(
          activityId: 41,
          nodeId: 7,
          sensorType: 'still',
          payload: <String, dynamic>{'heldSec': 20},
        ),
      ),
    ];

const Map<String, dynamic> _rewardData = <String, dynamic>{
  'nodeId': 7,
  'firstTime': true,
  'done': 1,
  'total': 2,
  'completed': false,
  'newBadges': <dynamic>[],
};

Map<String, dynamic> _routeState({required int version}) => <String, dynamic>{
  'routeMode': 'BRANCH_GRAPH',
  'sessionId': 91,
  'status': 'ACTIVE',
  'currentNodeId': 7,
  'recommendedNodeId': 7,
  'version': version,
  'nodeStates': <String, dynamic>{'7': 'PLAYABLE'},
  'decisionLog': <dynamic>[],
};

typedef _Stub = ({DioClient client, List<RequestOptions> sent});

_Stub _stub(Map<String, dynamic> reply) {
  final DioClient client = DioClient(TokenStore(const FlutterSecureStorage()));
  final List<RequestOptions> sent = <RequestOptions>[];
  client.dio.httpClientAdapter = _StubAdapter((RequestOptions options) {
    sent.add(options);
    return reply;
  });
  return (client: client, sent: sent);
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
