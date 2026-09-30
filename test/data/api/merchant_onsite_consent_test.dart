import 'dart:convert';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/account_api.dart';
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

  test('AGREE 必须按 MERCHANT 范围写入，再从 latest 精确回读', () async {
    final harness = _build(<Map<String, dynamic>>[
      <String, dynamic>{'code': 200},
      _record(eventType: 'AGREE', merchantId: 71),
    ]);

    await harness.api.agreeMerchantOnsiteDataSharing(
      merchantId: 71,
      requestId: 'merchant-agree-71',
    );

    expect(harness.sent.map((RequestOptions request) => request.path), <String>[
      '/api/compliance/consents',
      '/api/compliance/consents/latest',
    ]);
    expect(
      (harness.sent.first.data as Map).cast<String, dynamic>(),
      <String, dynamic>{
        'docType': 'merchant_onsite_data_sharing',
        'scene': 'merchant_redeem',
        'scopeType': 'MERCHANT',
        'scopeId': 71,
        'eventType': 'AGREE',
        'requestId': 'merchant-agree-71',
      },
    );
    expect(
      (harness.sent.last.data as Map).cast<String, dynamic>(),
      <String, dynamic>{
        'docType': 'merchant_onsite_data_sharing',
        'scene': 'merchant_redeem',
        'scopeType': 'MERCHANT',
        'scopeId': 71,
      },
    );
  });

  test('REVOKE 写后精确回读；不复用 AGREE', () async {
    final harness = _build(<Map<String, dynamic>>[
      <String, dynamic>{'code': 200},
      _record(eventType: 'REVOKE', merchantId: 71),
    ]);

    await harness.api.revokeMerchantOnsiteDataSharing(
      merchantId: 71,
      requestId: 'merchant-revoke-71',
    );

    final write = (harness.sent.first.data as Map).cast<String, dynamic>();
    expect(write['eventType'], 'REVOKE');
  });

  test('写成功但 latest 没记录时 fail closed', () async {
    final harness = _build(<Map<String, dynamic>>[
      <String, dynamic>{'code': 200},
      <String, dynamic>{'code': 200},
    ]);

    await expectLater(
      harness.api.agreeMerchantOnsiteDataSharing(
        merchantId: 71,
        requestId: 'merchant-agree-71',
      ),
      throwsA(predicate((Object e) => e.toString().contains('状态未确认'))),
    );
  });

  test('latest 回读的事件或范围不匹配时 fail closed', () async {
    final harness = _build(<Map<String, dynamic>>[
      <String, dynamic>{'code': 200},
      _record(eventType: 'REVOKE', merchantId: 999),
    ]);

    await expectLater(
      harness.api.agreeMerchantOnsiteDataSharing(
        merchantId: 71,
        requestId: 'merchant-agree-71',
      ),
      throwsA(predicate((Object e) => e.toString().contains('状态未确认'))),
    );
  });

  test('写成功但 latest 请求失败时 fail closed', () async {
    final harness = _build(<Map<String, dynamic>>[
      <String, dynamic>{'code': 200},
      <String, dynamic>{'code': 500, 'msg': '授权状态暂不可用'},
    ]);

    await expectLater(
      harness.api.agreeMerchantOnsiteDataSharing(
        merchantId: 71,
        requestId: 'merchant-agree-71',
      ),
      throwsA(predicate((Object e) => e.toString().contains('暂不可用'))),
    );
    expect(harness.sent.length, 2);
  });

  test('无合法 merchantId 时不发请求', () async {
    final harness = _build(const <Map<String, dynamic>>[]);

    await expectLater(
      harness.api.agreeMerchantOnsiteDataSharing(
        merchantId: 0,
        requestId: 'merchant-agree-0',
      ),
      throwsArgumentError,
    );
    expect(harness.sent, isEmpty);
  });
}

Map<String, dynamic> _record({
  required String eventType,
  required int merchantId,
}) => <String, dynamic>{
  'code': 200,
  'data': <String, dynamic>{
    'docType': 'merchant_onsite_data_sharing',
    'scene': 'merchant_redeem',
    'scopeType': 'MERCHANT',
    'scopeId': merchantId,
    'eventType': eventType,
    'docVersion': 'v1',
  },
};

({AccountApi api, List<RequestOptions> sent}) _build(
  List<Map<String, dynamic>> replies,
) {
  final DioClient client = DioClient(TokenStore(const FlutterSecureStorage()));
  final sent = <RequestOptions>[];
  client.dio.httpClientAdapter = _QueueAdapter((RequestOptions request) {
    sent.add(request);
    return replies.removeAt(0);
  });
  return (api: AccountApi(client), sent: sent);
}

class _QueueAdapter implements HttpClientAdapter {
  _QueueAdapter(this.onRequest);
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
