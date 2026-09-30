import 'dart:convert';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/im_api.dart';
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

  test('mute 严格发送后端合同 1/0，不发送 true/false', () async {
    final harness = _build();

    await harness.api.mute(7, muted: true);
    await harness.api.mute(7, muted: false);

    expect(_fields(harness.sent[0]), <String, String>{
      'conversation_id': '7',
      'muted': '1',
    });
    expect(_fields(harness.sent[1]), <String, String>{
      'conversation_id': '7',
      'muted': '0',
    });
  });

  test('标已读只提交当前会话，不依赖 unread 大于零', () async {
    final harness = _build();

    await harness.api.read(7);

    expect(harness.sent.single.path, '/api/im/read');
    expect(_fields(harness.sent.single), <String, String>{
      'conversation_id': '7',
    });
  });
}

Map<String, String> _fields(RequestOptions request) => <String, String>{
  for (final MapEntry<String, String> entry
      in (request.data as FormData).fields)
    entry.key: entry.value,
};

({ImApi api, List<RequestOptions> sent}) _build() {
  final client = DioClient(TokenStore(const FlutterSecureStorage()));
  final sent = <RequestOptions>[];
  client.dio.httpClientAdapter = _StubAdapter((RequestOptions request) {
    sent.add(request);
    return <String, dynamic>{'code': 200};
  });
  return (api: ImApi(client), sent: sent);
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
