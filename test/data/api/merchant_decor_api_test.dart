import 'dart:convert';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
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

  ({MerchantApi api, List<RequestOptions> sent}) build() {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final List<RequestOptions> sent = <RequestOptions>[];
    client.dio.httpClientAdapter = _StubAdapter((RequestOptions options) {
      sent.add(options);
      return <String, dynamic>{'code': 200};
    });
    return (api: MerchantApi(client), sent: sent);
  }

  test('相册子页只写 gallery，且值是 canonical JSON', () async {
    final r = build();
    await r.api.saveDecorGallery(<String>['a.jpg', 'b.jpg']);
    final Map<String, dynamic> body = (r.sent.single.data as Map)
        .cast<String, dynamic>();
    expect(body.keys, <String>['gallery']);
    expect(jsonDecode(body['gallery'] as String), <String>['a.jpg', 'b.jpg']);
  });

  test('品牌故事只带回原 storyTitle，不发空相册/标签', () async {
    final r = build();
    await r.api.saveDecorStoryTitle('夜归的灯');
    final Map<String, dynamic> body = (r.sent.single.data as Map)
        .cast<String, dynamic>();
    expect(body, <String, dynamic>{'storyTitle': '夜归的灯'});
  });
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.onRequest);
  final Map<String, dynamic> Function(RequestOptions options) onRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final List<int> bytes = utf8.encode(jsonEncode(onRequest(options)));
    return ResponseBody.fromBytes(
      bytes,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
