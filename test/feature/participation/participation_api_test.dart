import 'dart:convert';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/feature/participation/participation_api.dart';
import 'package:chengyin_app/feature/participation/participation_models.dart';
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

  test('我的参与列表调用 my-joined 且同时保留主题与活动记录', () async {
    final _StubAdapter adapter = _StubAdapter(<String, dynamic>{
      'code': 200,
      'data': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'ownerType': 1,
          'ownerId': 11,
          'registrationStatus': 2,
          'cmsTopic': <String, dynamic>{'name': '主题路线'},
        },
        <String, dynamic>{
          'id': 2,
          'ownerType': 2,
          'ownerId': 22,
          'registrationStatus': 2,
          'cmsActivity': <String, dynamic>{'name': '线下活动'},
        },
      ],
    });
    final ParticipationApi api = _api(adapter);

    final List<ParticipationRecord> rows = await api.list();

    expect(adapter.last?.path, '/api/registration/my-joined');
    expect(rows.map((ParticipationRecord row) => row.ownerType), <int>[1, 2]);
    expect(rows.map((ParticipationRecord row) => row.sourceName), <String>[
      '主题路线',
      '线下活动',
    ]);
  });

  test('参与详情打真源玩家侧 registration/info 并把 id 放表单参数', () async {
    final _StubAdapter adapter = _StubAdapter(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{
        'id': 37,
        'ownerType': 1,
        'ownerId': 11,
        'registrationStatus': 2,
        'cmsTopic': <String, dynamic>{
          'name': '夜游苏河',
          'startDate': '2026-08-24 09:00:00',
          'endDate': '2026-08-25 18:00:00',
        },
      },
    });
    final ParticipationDetail detail = await _api(adapter).detail(37);

    // ★ merchant/info 是商家视图,真源玩家侧详情 = registration/info
    //   (components/scene-member-participation-detail getData)。
    expect(adapter.last?.path, '/api/registration/info');
    final FormData form = adapter.last!.data! as FormData;
    expect(form.fields.single.key, 'id');
    expect(form.fields.single.value, '37');
    expect(detail.topicName, '夜游苏河');
    expect(detail.statusText, isNotEmpty);
  });

  test('接口非 200 保留后端错误，不能伪装成空参与记录', () async {
    final ParticipationApi api = _api(
      _StubAdapter(<String, dynamic>{'code': 500, 'msg': '请先登录'}),
    );

    await expectLater(
      api.list(),
      throwsA(
        isA<ParticipationApiException>().having(
          (ParticipationApiException error) => error.message,
          'message',
          '请先登录',
        ),
      ),
    );
  });
}

ParticipationApi _api(_StubAdapter adapter) {
  final DioClient client = DioClient(TokenStore(const FlutterSecureStorage()));
  client.dio.httpClientAdapter = adapter;
  return ParticipationApi(
    client,
    now: () => DateTime.parse('2026-08-23T12:00:00Z'),
  );
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.reply);

  final Map<String, dynamic> reply;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return ResponseBody.fromString(
      jsonEncode(reply),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
