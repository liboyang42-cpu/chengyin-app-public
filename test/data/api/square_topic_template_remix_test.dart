import 'dart:convert';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/square_api.dart';
import 'package:chengyin_app/data/models/square_post.dart';
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

  test('SquarePost 只在真模板且 sportTopicId 为正数时允许改编', () {
    SquarePost post(Map<String, dynamic> json) =>
        SquarePost.fromJson(<String, dynamic>{'id': 7, 'memberId': 9, ...json});

    expect(
      post(<String, dynamic>{
        'isTopicTemplate': true,
        'sportTopicId': 9201,
      }).canRemixTopicTemplate,
      isTrue,
    );
    expect(
      post(<String, dynamic>{
        'isTopicTemplate': false,
        'sportTopicId': 9201,
      }).canRemixTopicTemplate,
      isFalse,
    );
    expect(
      post(<String, dynamic>{'isTopicTemplate': true}).canRemixTopicTemplate,
      isFalse,
    );
  });

  test('POST /api/template/topic-template/use 以表单传 id 并读回新 topicId', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    late RequestOptions sent;
    client.dio.httpClientAdapter = _StubAdapter((RequestOptions request) {
      sent = request;
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'topicId': 9302},
      };
    });

    final int copiedId = await SquareApi(client).remixTopicTemplate(9201);

    expect(sent.path, '/api/template/topic-template/use');
    expect(sent.method, 'POST');
    expect(sent.data, isA<FormData>());
    expect(
      <String, String>{
        for (final MapEntry<String, String> field
            in (sent.data as FormData).fields)
          field.key: field.value,
      },
      <String, String>{'id': '9201'},
    );
    expect(copiedId, 9302);
  });

  test('失败保留后端原话，200 但缺 topicId 也不假成功', () async {
    Future<Object> run(Map<String, dynamic> body) async {
      final DioClient client = DioClient(
        TokenStore(const FlutterSecureStorage()),
      );
      client.dio.httpClientAdapter = _StubAdapter((_) => body);
      try {
        await SquareApi(client).remixTopicTemplate(9201);
        return StateError('本应失败');
      } catch (error) {
        return error;
      }
    }

    expect(
      (await run(<String, dynamic>{'code': 500, 'msg': '模板已停用'})).toString(),
      '模板已停用',
    );
    expect(
      (await run(<String, dynamic>{'code': 200, 'msg': '副本未生成'})).toString(),
      '副本未生成',
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
  ) async => ResponseBody.fromString(
    jsonEncode(onRequest(options)),
    200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
