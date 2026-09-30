// 玩法操作系统接口(`/api/play/os/{topicId}` 与 `/api/play/tag/{tagId}/revoke`)。
//
// 撤回标签是**写**操作:请求发出后网络断在回执前,结果只有服务端知道。
// 接错成「本地直接当成功」会让用户以为撤回了、服务端其实还在,
// 所以这里把「回执必须自洽 + 结果未知要上报」两件事钉住。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/play_os_api.dart';
import 'package:chengyin_app/data/models/play_operating_system.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  ({PlayOsApi api, List<RequestOptions> sent}) build(
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
    return (api: PlayOsApi(client), sent: sent);
  }

  group('load', () {
    test('走 GET /api/play/os/{topicId}，非正数 topicId 本地拒绝', () async {
      final r = build(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'topicId': 42,
            'edition': '2026 夏',
            'tags': <dynamic>[
              <String, dynamic>{'id': 5, 'tagValue': '露营', 'status': 'ACTIVE'},
            ],
          },
        },
      );
      final PlayOperatingSystem os = await r.api.load(42);
      expect(os.topicId, 42);
      expect(os.tags.single.value, '露营');
      expect(r.sent.single.method, 'GET');
      expect(r.sent.single.path, '/api/play/os/42');
      await expectLater(r.api.load(0), throwsArgumentError);
      expect(r.sent, hasLength(1));
    });

    test('data 不是对象时按加载失败抛出，不返回空壳', () async {
      final r = build(
        (_) => <String, dynamic>{'code': 200, 'data': <dynamic>[]},
      );
      await expectLater(
        r.api.load(42),
        throwsA(isA<PlayOsApiException>()),
      );
    });
  });

  group('revokeTag', () {
    test('走 POST /api/play/tag/{tagId}/revoke，回执 REVOKED 才算数', () async {
      final r = build(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'id': 5,
            'tagValue': '露营',
            'status': 'REVOKED',
          },
        },
      );
      final PlayOsTag tag = await r.api.revokeTag(5);
      expect(tag.revoked, isTrue);
      expect(r.sent.single.method, 'POST');
      expect(r.sent.single.path, '/api/play/tag/5/revoke');
    });

    test('★ 回执还是 ACTIVE 时按「结果未知」上报，不能本地当撤回成功', () async {
      final r = build(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'id': 5,
            'tagValue': '露营',
            'status': 'ACTIVE',
          },
        },
      );
      await expectLater(
        r.api.revokeTag(5),
        throwsA(
          isA<PlayOsApiException>().having(
            (PlayOsApiException e) => e.writeOutcomeUnknown,
            'writeOutcomeUnknown',
            isTrue,
          ),
        ),
      );
    });

    test('★ 回执换了别的标签 id 视为不完整', () async {
      final r = build(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'id': 6,
            'tagValue': '露营',
            'status': 'REVOKED',
          },
        },
      );
      await expectLater(
        r.api.revokeTag(5),
        throwsA(isA<PlayOsApiException>()),
      );
    });

    test('断网(无响应)标记 writeOutcomeUnknown，提醒重查而不是重试写', () async {
      final DioClient client = DioClient(
        TokenStore(const FlutterSecureStorage()),
      );
      client.dio.httpClientAdapter = _ThrowingAdapter();
      await expectLater(
        PlayOsApi(client).revokeTag(5),
        throwsA(
          isA<PlayOsApiException>().having(
            (PlayOsApiException e) => e.writeOutcomeUnknown,
            'writeOutcomeUnknown',
            isTrue,
          ),
        ),
      );
    });

    test('服务端明确报错时不算「结果未知」，带后端原文', () async {
      final DioClient client = DioClient(
        TokenStore(const FlutterSecureStorage()),
      );
      client.dio.httpClientAdapter = _StubAdapter(
        (_) => <String, dynamic>{'code': 500, 'msg': '标签不存在'},
        statusCode: 500,
      );
      await expectLater(
        PlayOsApi(client).revokeTag(5),
        throwsA(
          isA<PlayOsApiException>()
              .having(
                (PlayOsApiException e) => e.message,
                'message',
                '标签不存在',
              )
              .having(
                (PlayOsApiException e) => e.writeOutcomeUnknown,
                'writeOutcomeUnknown',
                isFalse,
              ),
        ),
      );
    });
  });
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.onRequest, {this.statusCode = 200});
  final Map<String, dynamic> Function(RequestOptions) onRequest;
  final int statusCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(onRequest(options)),
      statusCode,
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
