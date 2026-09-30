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

  test(
    'preference GET uses the node path and the one authoritative session id',
    () async {
      final _Stub stub = _stub(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'nodeId': 17,
          'steps': <dynamic>[_step('space', '空间偏好')],
          'inheritedTags': <dynamic>[],
        },
      });

      final questionnaire = await PlayApi(
        stub.client,
      ).fetchPreference(topicId: 71, nodeId: 17);

      expect(stub.sent.single.method, 'GET');
      expect(stub.sent.single.path, '/api/play/preference/17');
      expect(stub.sent.single.queryParameters, <String, dynamic>{
        'topicId': 71,
      });
      expect(questionnaire.steps.single.title, '空间偏好');
    },
  );

  test(
    'preference POST sends only choices, session and optional route token',
    () async {
      final _Stub stub = _stub(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'evaluation': <String, dynamic>{
            'resultCode': 'compact',
            'title': '先减负',
            'body': '你选择了紧凑',
            'nextStep': '清理一层柜子',
            'nextStepDays': 7,
            'choices': <dynamic>['紧凑'],
          },
          'progress': <String, dynamic>{
            'nodeId': 17,
            'firstTime': true,
            'done': 1,
            'total': 2,
            'completed': false,
            'newBadges': <dynamic>[],
          },
        },
      });

      await PlayApi(stub.client).submitPreference(
        activityId: 41,
        nodeId: 17,
        choices: const <String, String>{'space': 'A'},
        routeAdvance: RouteAdvanceToken(
          actionId: 'preference-action-1',
          expectedRouteVersion: 4,
        ),
      );

      final RequestOptions request = stub.sent.single;
      expect(request.method, 'POST');
      expect(request.path, '/api/play/preference/17/submit');
      expect(request.data, <String, dynamic>{
        'activityId': 41,
        'choices': <String, String>{'space': 'A'},
        'routeActionId': 'preference-action-1',
        'expectedRouteVersion': 4,
      });
      expect(request.data, isNot(contains('outcomeCode')));
      expect(request.data, isNot(contains('targetNodeId')));
    },
  );

  test('preference reuse is sent only when explicitly supplied', () async {
    final _Stub stub = _stub(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{'needsTiebreak': true},
    });

    await PlayApi(stub.client).submitPreference(
      topicId: 71,
      nodeId: 17,
      choices: const <String, String>{},
      reuseTagCode: 'space_constraints',
    );

    expect(stub.sent.single.data, <String, dynamic>{
      'topicId': 71,
      'choices': <String, String>{},
      'reuseTagCode': 'space_constraints',
    });
  });

  test(
    'pending preference tags use the server confirm and correct paths',
    () async {
      final _Stub confirmStub = _stub(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'id': 23,
          'tagCode': 'space_constraints',
          'tagValue': 'compact',
          'status': 1,
        },
      });
      final tag = await PlayApi(confirmStub.client).confirmPreferenceTag(23);

      expect(confirmStub.sent.single.method, 'POST');
      expect(confirmStub.sent.single.path, '/api/play/tag/23/confirm');
      expect(tag.status, 1);

      final _Stub correctStub = _stub(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'id': 23,
          'tagCode': 'space_constraints',
          'tagValue': 'open',
          'status': 0,
        },
      });
      final corrected = await PlayApi(
        correctStub.client,
      ).correctPreferenceTag(23, 'open');

      expect(correctStub.sent.single.path, '/api/play/tag/23/correct');
      expect(correctStub.sent.single.data, <String, dynamic>{
        'tagValue': 'open',
      });
      expect(corrected.tagValue, 'open');
    },
  );

  test('AjaxResult business rejection exposes the server message', () async {
    final _Stub stub = _stub(<String, dynamic>{'code': 500, 'msg': '路线状态已更新'});

    await expectLater(
      PlayApi(stub.client).submitPreference(
        topicId: 71,
        nodeId: 17,
        choices: const <String, String>{'space': 'A'},
      ),
      throwsA(
        isA<PlayException>().having(
          (PlayException error) => error.message,
          'message',
          '路线状态已更新',
        ),
      ),
    );
  });

  test(
    'preference route conflict preserves the structured string code',
    () async {
      final _Stub stub = _stub(<String, dynamic>{
        'code': '409',
        'msg': '路线状态已更新',
      });

      await expectLater(
        PlayApi(stub.client).submitPreference(
          topicId: 71,
          nodeId: 17,
          choices: const <String, String>{'space': 'A'},
        ),
        throwsA(
          isA<PlayException>()
              .having((PlayException error) => error.code, 'code', 409)
              .having(
                (PlayException error) => error.message,
                'message',
                '路线状态已更新',
              ),
        ),
      );
    },
  );
}

Map<String, dynamic> _step(String key, String title) => <String, dynamic>{
  'key': key,
  'type': 'single',
  'title': title,
  'options': <dynamic>[
    <String, dynamic>{'key': 'A', 'text': '紧凑'},
    <String, dynamic>{'key': 'B', 'text': '通透'},
  ],
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
