import 'dart:convert';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  test('route-state 按唯一会话参数恢复读取并解析强类型状态', () async {
    final _Stub stub = _stub(<String, dynamic>{
      'code': 200,
      'data': _routeState(version: 6),
    });

    final PlayRouteState state = await PlayApi(
      stub.client,
    ).fetchRouteState(activityId: 41);

    expect(stub.sent.single.path, '/api/play/route-state');
    expect(stub.sent.single.queryParameters, <String, dynamic>{
      'activityId': 41,
    });
    expect(state.routeMode, PlayRouteMode.branchGraph);
    expect(state.version, 6);
  });

  test('所有现存 FormData 完成 transport 可选透传同一 route token', () async {
    final _Stub stub = _stub(_rewardBody());
    final PlayApi api = PlayApi(stub.client);
    final RouteAdvanceToken token = RouteAdvanceToken(
      actionId: 'route-action-1',
      expectedRouteVersion: 4,
    );

    await api.submitCheckin(activityId: 41, code: 'scan', routeAdvance: token);
    await api.submitTopicCheckin(
      topicId: 71,
      code: 'scan',
      routeAdvance: token,
    );
    await api.submitAnswer(
      activityId: 41,
      nodeId: 7,
      answer: 'A',
      routeAdvance: token,
    );
    await api.submitTopicAnswer(
      topicId: 71,
      nodeId: 7,
      answer: 'A',
      routeAdvance: token,
    );
    await api.submitArrive(
      activityId: 41,
      nodeId: 7,
      longitude: 121.4,
      latitude: 31.2,
      routeAdvance: token,
    );
    await api.submitTopicArrive(
      topicId: 71,
      nodeId: 7,
      longitude: 121.4,
      latitude: 31.2,
      routeAdvance: token,
    );
    await api.submitPhoto(
      activityId: 41,
      nodeId: 7,
      picUrl: 'https://cdn.example.com/proof.jpg',
      routeAdvance: token,
    );
    await api.submitTopicPhoto(
      topicId: 71,
      nodeId: 7,
      picUrl: 'https://cdn.example.com/proof.jpg',
      routeAdvance: token,
    );

    expect(stub.sent, hasLength(8));
    for (final RequestOptions request in stub.sent) {
      final Map<String, String> fields = _formFields(request);
      expect(fields['routeActionId'], 'route-action-1', reason: request.path);
      expect(fields['expectedRouteVersion'], '4', reason: request.path);
      expect(fields, isNot(contains('outcomeCode')), reason: request.path);
      expect(fields, isNot(contains('targetNodeId')), reason: request.path);
    }
  });

  test('sensor-result JSON 完成 transport 透传 route token，不发送路线推演字段', () async {
    final _Stub stub = _stub(_rewardBody());
    await PlayApi(stub.client).submitSensorResult(
      topicId: 71,
      nodeId: 7,
      sensorType: 'still',
      payload: <String, dynamic>{'heldSec': 20},
      routeAdvance: RouteAdvanceToken(
        actionId: 'route-action-json',
        expectedRouteVersion: 9,
      ),
    );

    final Map<String, dynamic> json =
        stub.sent.single.data as Map<String, dynamic>;
    expect(json['routeActionId'], 'route-action-json');
    expect(json['expectedRouteVersion'], 9);
    expect(json, isNot(contains('outcomeCode')));
    expect(json, isNot(contains('targetNodeId')));
  });

  test('未提供 route token 时 FormData/JSON 保持 LINEAR 旧请求形状', () async {
    final _Stub stub = _stub(_rewardBody());
    final PlayApi api = PlayApi(stub.client);

    await api.submitCheckin(activityId: 41, code: 'scan');
    await api.submitSensorResult(
      activityId: 41,
      nodeId: 7,
      sensorType: 'steps',
      payload: <String, dynamic>{'steps': 500},
    );

    expect(_formFields(stub.sent.first), <String, String>{
      'activityId': '41',
      'code': 'scan',
    });
    final Map<String, dynamic> json =
        stub.sent.last.data as Map<String, dynamic>;
    expect(json, isNot(contains('routeActionId')));
    expect(json, isNot(contains('expectedRouteVersion')));
  });
}

Map<String, dynamic> _rewardBody() => <String, dynamic>{
  'code': 200,
  'data': <String, dynamic>{
    'nodeId': 7,
    'firstTime': true,
    'done': 1,
    'total': 2,
    'completed': false,
    'newBadges': <dynamic>[],
  },
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

Map<String, String> _formFields(RequestOptions request) => <String, String>{
  for (final MapEntry<String, String> field
      in (request.data as FormData).fields)
    field.key: field.value,
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
