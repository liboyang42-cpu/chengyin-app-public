import 'dart:convert';
import 'dart:typed_data';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/models/registration_read_failure.dart';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.reply);
  final Map<String, dynamic> Function(RequestOptions options) reply;
  final List<RequestOptions> sent = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent.add(options);
    return ResponseBody.fromString(
      jsonEncode(reply(options)),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));
  final operations = <String, Future<Object?> Function(ActivityApi)>{
    'cancellation': (api) => api.cancelRegistrationWithOutcome(registrationId: 11, paid: true),
    'quote': (api) => api.quote(ownerId: 7),
    'payment readiness': (api) => api.paymentReadiness(),
    'activity tickets': (api) => api.ticketList(),
    'route tickets': (api) => api.topicTicketList(),
    'orders': (api) => api.orderList(),
    'detail': (api) => api.ticketInfo(11),
    'code': (api) => api.issueDynamicCode(11),
  };
  for (final op in operations.entries) {
    for (final supplied in [false, true]) {
      test('${op.key}: failure preserves message provenance ($supplied)', () async {
        final client = DioClient(TokenStore(const FlutterSecureStorage()));
        client.dio.httpClientAdapter = _StubAdapter((_) => {
          'code': 403, if (supplied) 'msg': '票券详情加载失败',
          'data': <dynamic>[],
        });
        await expectLater(op.value(ActivityApi(client)), throwsA(
          isA<RegistrationReadFailure>().having((e) => e.hasServerMessage, 'origin', supplied),
        ));
      });
    }
  }
  test('successful empty orders remain empty', () async {
    final client = DioClient(TokenStore(const FlutterSecureStorage()));
    client.dio.httpClientAdapter = _StubAdapter((_) => {'code': 200, 'data': <dynamic>[]});
    expect(await ActivityApi(client).orderList(), isEmpty);
  });
  for (final supplied in [false, true]) {
    test('payment failure records whether its identical fallback came from the server ($supplied)', () async {
      final client = DioClient(TokenStore(const FlutterSecureStorage()));
      client.dio.httpClientAdapter = _StubAdapter((_) => {
        'code': 409, if (supplied) 'msg': '获取支付参数失败',
      });
      await expectLater(ActivityApi(client).payApp(11), throwsA(
        isA<RegistrationCheckoutException>()
          .having((e) => e.code, 'unchanged routing code', 409)
          .having((e) => e.hasServerMessage, 'message origin', supplied),
      ));
    });
  }
  test('missing payment parameters is a local failure, not a server message or ready payment', () async {
    final client = DioClient(TokenStore(const FlutterSecureStorage()));
    client.dio.httpClientAdapter = _StubAdapter((_) => {'code': 200, 'data': <String, dynamic>{}});
    await expectLater(ActivityApi(client).payApp(11), throwsA(
      isA<RegistrationReadFailure>()
        .having((e) => e.kind, 'kind', RegistrationReadKind.paymentParameters)
        .having((e) => e.hasServerMessage, 'origin', false),
    ));
  });

}
