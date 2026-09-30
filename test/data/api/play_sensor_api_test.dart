import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/play_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  test('sensor-result 按 activityId 上报 camelCase 契约', () async {
    final _Stub stub = _stub(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{
        'nodeId': 7,
        'firstTime': true,
        'completed': false,
        'done': 1,
        'total': 2,
        'xp': 18,
        'newBadges': <dynamic>[],
      },
    });

    final reward = await PlayApi(stub.client).submitSensorResult(
      activityId: 41,
      nodeId: 7,
      sensorType: 'still',
      payload: <String, dynamic>{'heldSec': 20},
    );

    expect(stub.sent.single.path, '/api/play/sensor-result');
    expect(stub.sent.single.contentType, Headers.jsonContentType);
    expect(_json(stub.sent.single), <String, dynamic>{
      'activityId': 41,
      'nodeId': 7,
      'sensorType': 'still',
      'payload': <String, dynamic>{'heldSec': 20},
    });
    expect(reward.nodeId, 7);
    expect(reward.firstTime, isTrue);
    expect(reward.doneCount, 1);
    expect(reward.xpAwarded, 18, reason: '传感器奖励只能展示后端回读的探索值');
  });

  test('sensor-result 按 topicId 上报，不夹带 activityId', () async {
    final _Stub stub = _stub(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{},
    });

    await PlayApi(stub.client).submitSensorResult(
      topicId: 71,
      nodeId: 8,
      sensorType: 'steps',
      payload: <String, dynamic>{'steps': 500},
    );

    expect(_json(stub.sent.single), <String, dynamic>{
      'topicId': 71,
      'nodeId': 8,
      'sensorType': 'steps',
      'payload': <String, dynamic>{'steps': 500},
    });
  });

  test('sensor-result 允许 audio_clip', () async {
    final _Stub stub = _stub(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{},
    });

    await PlayApi(stub.client).submitSensorResult(
      activityId: 41,
      nodeId: 9,
      sensorType: 'audio_clip',
      payload: <String, dynamic>{'mediaUrl': 'https://cdn.example.com/a.m4a'},
    );

    expect(_json(stub.sent.single)['sensorType'], 'audio_clip');
  });

  test('sensor-result 播放上下文必须且只能给一个', () async {
    final _Stub stub = _stub(<String, dynamic>{'code': 200});
    final PlayApi api = PlayApi(stub.client);

    await expectLater(
      api.submitSensorResult(
        nodeId: 7,
        sensorType: 'still',
        payload: <String, dynamic>{'heldSec': 20},
      ),
      throwsArgumentError,
    );
    await expectLater(
      api.submitSensorResult(
        activityId: 41,
        topicId: 71,
        nodeId: 7,
        sensorType: 'still',
        payload: <String, dynamic>{'heldSec': 20},
      ),
      throwsArgumentError,
    );
    expect(stub.sent, isEmpty, reason: '本地契约不合法时不应发请求');
  });

  test('sensor-result 拒绝 filter_shot 与未知 sensorType，且不发请求', () async {
    final _Stub stub = _stub(<String, dynamic>{'code': 200});
    final PlayApi api = PlayApi(stub.client);

    for (final String sensorType in <String>['filter_shot', 'heart_rate']) {
      await expectLater(
        api.submitSensorResult(
          activityId: 41,
          nodeId: 7,
          sensorType: sensorType,
          payload: <String, dynamic>{},
        ),
        throwsArgumentError,
        reason: '$sensorType 不属于 vm=7 允许的传感器类型',
      );
    }

    expect(stub.sent, isEmpty, reason: 'sensorType 不合法必须在 Dio 之前拦截');
  });

  test('sensor-result 错误原文从服务端回读', () async {
    final _Stub stub = _stub(<String, dynamic>{'code': 500, 'msg': '静止时长未达标'});

    await expectLater(
      PlayApi(stub.client).submitSensorResult(
        activityId: 41,
        nodeId: 7,
        sensorType: 'still',
        payload: <String, dynamic>{'heldSec': 8},
      ),
      throwsA(
        isA<PlayException>().having(
          (PlayException error) => error.message,
          'message',
          '静止时长未达标',
        ),
      ),
    );
    expect(stub.sent, hasLength(1), reason: '错误必须来自真实请求回包');
  });
}

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

Map<String, dynamic> _json(RequestOptions options) =>
    options.data as Map<String, dynamic>;

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
