import 'dart:convert';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/merchant_aftercare_api.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/models/merchant_aftercare.dart';
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

  test('售后列表先查 aftercare read，无权限不请求业务接口', () async {
    final List<String> sent = <String>[];
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    client.dio.httpClientAdapter = _StubAdapter((RequestOptions request) {
      sent.add(request.path);
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'active': true,
          'merchant': <String, dynamic>{'id': 7, 'name': '茶室'},
          'roleCode': 'MERCHANT_CHECKIN',
          'permissions': <String>['merchant:verify'],
        },
      };
    });

    await expectLater(
      MerchantAftercareApi(client).listPage(
        bucket: MerchantAftercareBucket.pending,
        pageNum: 1,
        pageSize: 20,
      ),
      throwsA(isA<MerchantAccessDeniedException>()),
    );
    expect(sent, <String>['/api/merchant/access/me']);
  });
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.reply);
  final Map<String, dynamic> Function(RequestOptions request) reply;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(reply(options)),
    200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
