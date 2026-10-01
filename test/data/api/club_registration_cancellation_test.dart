import 'dart:convert';
import 'dart:typed_data';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/club_api.dart';

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
  for (final status in ['NOT_NEEDED', 'MANUAL_REVIEW', 'DISPATCH_PENDING', 'DISPATCHING', 'PROCESSING', 'SUCCESS', 'PENDING_MANUAL', 'MANUAL_HANDLED', 'MANUAL_VERIFIED', 'UNCONFIRMED']) {
    test('cancel-by-owner preserves $status and message', () async {
      final client = DioClient(TokenStore(const FlutterSecureStorage()));
      final adapter = _StubAdapter((_) => {
        'code': 200, 'msg': '原始反馈', 'data': {
          'registrationId': 11, 'cancellationStatus': 'CANCELLED',
          'cashRefundStatus': status, 'pointsRefundStatus': 'PARTIAL',
        },
      });
      client.dio.httpClientAdapter = adapter;
      final result = await ClubApi(client).cancelRegistrationByOwner(11);
      expect(result.cashRefundStatus, status);
      expect(result.pointsRefundStatus, 'PARTIAL');
      expect(result.message, '原始反馈');
      expect(result.registrationId, 11);
      expect(adapter.sent.single.path, '/api/registration/cancel-by-owner');
      expect(Map<String, String>.fromEntries((adapter.sent.single.data as FormData).fields), {'id': '11'});
    });
  }
  test('missing outcome remains unconfirmed instead of refund success', () async {
    final client = DioClient(TokenStore(const FlutterSecureStorage()));
    client.dio.httpClientAdapter = _StubAdapter((_) => {'code': 200});
    final result = await ClubApi(client).cancelRegistrationByOwner(11);
    expect(result.cashRefundStatus, 'UNCONFIRMED');
    expect(result.cancellationStatus, 'UNCONFIRMED');
    expect(result.message, '');
  });
  for (final malformed in <Object?>[null, <dynamic>[], 'SUCCESS', 1,
    {'registrationId': 'invalid', 'cancellationStatus': true,
      'cashRefundStatus': 1, 'pointsRefundStatus': <dynamic>['RETURNED']}]) {
    test('malformed receipt does not manufacture cancellation or refund success: $malformed', () async {
      final client = DioClient(TokenStore(const FlutterSecureStorage()));
      client.dio.httpClientAdapter = _StubAdapter((_) => {'code': 200, 'msg': 'Original receipt', 'data': malformed});
      final result = await ClubApi(client).cancelRegistrationByOwner(11);
      expect(result.registrationId, isNull);
      expect(result.cancellationStatus, 'UNCONFIRMED');
      expect(result.cashRefundStatus, 'UNCONFIRMED');
      expect(result.pointsRefundStatus, 'UNCONFIRMED');
      expect(result.message, 'Original receipt');
    });
  }
  test('business rejection is never converted into a successful outcome', () async {
    final client = DioClient(TokenStore(const FlutterSecureStorage()));
    client.dio.httpClientAdapter = _StubAdapter((_) => {
      'code': 500, 'msg': '  Refund was rejected  ',
      'data': {'cashRefundStatus': 'SUCCESS'},
    });
    await expectLater(ClubApi(client).cancelRegistrationByOwner(11),
      throwsA(isA<ClubApiException>().having((e) => e.message, 'original message', '  Refund was rejected  ')));
  });

}
