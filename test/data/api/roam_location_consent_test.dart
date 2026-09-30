import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/account_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  ({AccountApi api, List<RequestOptions> sent}) build(
    List<Map<String, dynamic>> replies,
  ) {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final List<RequestOptions> sent = <RequestOptions>[];
    client.dio.httpClientAdapter = _SequenceAdapter((RequestOptions request) {
      sent.add(request);
      return replies.removeAt(0);
    });
    return (api: AccountApi(client), sent: sent);
  }

  test('漫游定位撤回必须 REVOKE 写后精确回读', () async {
    final result = build(<Map<String, dynamic>>[
      <String, dynamic>{'code': 200},
      <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'docType': 'privacy_policy',
          'scene': 'roam_location',
          'eventType': 'REVOKE',
        },
      },
    ]);

    final record = await result.api.revokeRoamLocationConsent(
      requestId: 'revoke-roam-1',
    );

    expect(record.eventType, 'REVOKE');
    expect(result.sent.map((RequestOptions request) => request.path), <String>[
      '/api/compliance/consents',
      '/api/compliance/consents/latest',
    ]);
    final Map<String, dynamic> write = (result.sent.first.data as Map)
        .cast<String, dynamic>();
    expect(write, <String, dynamic>{
      'docType': 'privacy_policy',
      'scene': 'roam_location',
      'eventType': 'REVOKE',
      'requestId': 'revoke-roam-1',
    });
  });

  test('POST 成功但 latest 不是精确 REVOKE 仍 fail closed', () async {
    final result = build(<Map<String, dynamic>>[
      <String, dynamic>{'code': 200},
      <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'docType': 'privacy_policy',
          'scene': 'roam_location',
          'eventType': 'AGREE',
        },
      },
    ]);

    await expectLater(
      result.api.revokeRoamLocationConsent(requestId: 'revoke-roam-2'),
      throwsA(
        predicate((Object error) => error.toString().contains('撤回状态未确认')),
      ),
    );
  });
}

class _SequenceAdapter implements HttpClientAdapter {
  _SequenceAdapter(this.onRequest);

  final Map<String, dynamic> Function(RequestOptions request) onRequest;

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
