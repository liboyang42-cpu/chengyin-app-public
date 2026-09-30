import 'dart:convert';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/page_parity_api.dart';
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

  test('营销同意写入后必须从同一商家与渠道回读确认', () async {
    final harness = _build(<Map<String, dynamic>>[
      <String, dynamic>{'code': 200},
      <String, dynamic>{
        'code': 200,
        'data': <Map<String, dynamic>>[
          <String, dynamic>{
            'merchantRowId': 71,
            'merchantOwnerMemberId': 9,
            'merchantName': '夜航书店',
            'inAppOptedIn': true,
            'couponOptedIn': false,
          },
        ],
      },
    ]);

    final rows = await harness.api.setMarketingConsent(
      merchantRowId: 71,
      merchantOwnerMemberId: 9,
      channel: 'IN_APP',
      optedIn: true,
      requestId: 'crm-consent-opt-in-fixed',
    );

    expect(harness.sent.map((request) => request.method), <String>[
      'POST',
      'GET',
    ]);
    expect(
      (harness.sent.first.data as Map).cast<String, dynamic>(),
      <String, dynamic>{
        'merchantRowId': 71,
        'merchantOwnerMemberId': 9,
        'channel': 'IN_APP',
        'optedIn': true,
        'requestId': 'crm-consent-opt-in-fixed',
      },
    );
    expect(rows.single.merchantName, '夜航书店');
    expect(rows.single.inAppOptedIn, isTrue);
  });

  test('回读没有确认目标值时不能报告保存成功', () async {
    final harness = _build(<Map<String, dynamic>>[
      <String, dynamic>{'code': 200},
      <String, dynamic>{
        'code': 200,
        'data': <Map<String, dynamic>>[
          <String, dynamic>{
            'merchantRowId': 71,
            'merchantOwnerMemberId': 9,
            'merchantName': '夜航书店',
            'inAppOptedIn': false,
            'couponOptedIn': false,
          },
        ],
      },
    ]);

    await expectLater(
      harness.api.setMarketingConsent(
        merchantRowId: 71,
        merchantOwnerMemberId: 9,
        channel: 'IN_APP',
        optedIn: true,
        requestId: 'crm-consent-opt-in-fixed',
      ),
      throwsA(predicate((error) => error.toString().contains('状态未确认'))),
    );
  });
}

({PageParityApi api, List<RequestOptions> sent}) _build(
  List<Map<String, dynamic>> replies,
) {
  final client = DioClient(TokenStore(const FlutterSecureStorage()));
  final sent = <RequestOptions>[];
  client.dio.httpClientAdapter = _QueueAdapter((RequestOptions request) {
    sent.add(request);
    return replies.removeAt(0);
  });
  return (api: PageParityApi(client), sent: sent);
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
