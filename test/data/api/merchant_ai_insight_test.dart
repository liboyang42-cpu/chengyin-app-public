import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  test('店铺参谋用登录态 POST 且不传商家 ID', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final List<RequestOptions> sent = <RequestOptions>[];
    client.dio.httpClientAdapter = _StubAdapter((RequestOptions options) {
      sent.add(options);
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'generatedAt': '14:25',
          'facts': <String, dynamic>{
            'checkin': <String, dynamic>{'total': 3},
            'crowd': <String, dynamic>{'members': 2},
            'supply': <String, dynamic>{'activeOffers': 1},
          },
        },
      };
    });

    final result = await MerchantApi(client).merchantInsight();

    expect(sent.single.path, '/api/ai/merchant/insight');
    expect(sent.single.method, 'POST');
    expect(sent.single.data, isNull);
    expect(result.facts.checkin.total, 3);
  });

  test('成功码但缺 facts 不能冒充空数据页', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    client.dio.httpClientAdapter = _StubAdapter(
      (_) => <String, dynamic>{'code': 200, 'data': <String, dynamic>{}},
    );

    await expectLater(
      MerchantApi(client).merchantInsight(),
      throwsA(
        isA<MerchantApiException>().having(
          (MerchantApiException e) => e.message,
          'message',
          '店铺数据加载失败',
        ),
      ),
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
