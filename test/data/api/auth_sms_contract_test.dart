import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/auth_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  test('sendSmsCode POSTs phone as form data and accepts code 200', () async {
    RequestOptions? captured;
    final AuthApi api = _apiWith((RequestOptions options) {
      captured = options;
      return <String, dynamic>{'code': 200, 'msg': '验证码已发送'};
    });

    final Map<String, dynamic> body = await api.sendSmsCode('13800138000');

    expect(body['code'], 200);
    expect(captured?.method, 'POST');
    expect(captured?.path, '/api/sms/send');
    final FormData form = captured?.data as FormData;
    expect(
      form.fields.any(
        (MapEntry<String, String> field) =>
            field.key == 'phone' && field.value == '13800138000',
      ),
      isTrue,
    );
  });

  test(
    'sendSmsCode throws backend message when the channel is not configured',
    () async {
      final AuthApi api = _apiWith(
        (_) => <String, dynamic>{'code': 500, 'msg': '短信服务未配置'},
      );

      await expectLater(
        api.sendSmsCode('13800138000'),
        throwsA(
          isA<Exception>().having(
            (Exception error) => error.toString(),
            'message',
            contains('短信服务未配置'),
          ),
        ),
      );
    },
  );
}

AuthApi _apiWith(Map<String, dynamic> Function(RequestOptions options) reply) {
  final DioClient client = DioClient(TokenStore(const FlutterSecureStorage()));
  client.dio.httpClientAdapter = _StubAdapter(reply);
  return AuthApi(client);
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.reply);

  final Map<String, dynamic> Function(RequestOptions options) reply;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(reply(options)),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
