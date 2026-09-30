// 撤回章节承接申请的请求契约(真源 github/master):
//   `merchantinfo.js:948` 发的是 { applicationId } —— 不是 { id }。
//   发错键后端读不到,只回「缺少申请」;而 200 的 UI 看起来毫无差别,
//   所以这类错只能靠契约门守。

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

  test('撤回申请发 applicationId(后端只读这个键)', () async {
    final ({MerchantApi merchant, List<RequestOptions> sent}) harness = _build(
      <Object>[
        _ok(<String, dynamic>{'id': 88}),
      ],
    );

    await harness.merchant.withdrawChapterApplication(88);

    final RequestOptions request = harness.sent.single;
    expect(request.path, '/api/merchant/chapter-application/withdraw');
    expect(request.method, 'POST');
    expect(request.data, <String, dynamic>{'applicationId': 88});
  });
}

Map<String, dynamic> _ok(Object data) => <String, dynamic>{
  'code': 200,
  'data': data,
};

({MerchantApi merchant, List<RequestOptions> sent}) _build(
  List<Object> replies,
) {
  final DioClient client = DioClient(TokenStore(const FlutterSecureStorage()));
  final List<RequestOptions> sent = <RequestOptions>[];
  client.dio.httpClientAdapter = _QueueAdapter((RequestOptions request) {
    sent.add(request);
    return replies.removeAt(0) as Map<String, dynamic>;
  });
  return (merchant: MerchantApi(client), sent: sent);
}

class _QueueAdapter implements HttpClientAdapter {
  _QueueAdapter(this.handler);

  final Map<String, dynamic> Function(RequestOptions request) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(handler(options)),
    200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
