import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  test(
    'playerCode POSTs the authenticated endpoint and returns data.qr',
    () async {
      RequestOptions? captured;
      final AccountApi api = _apiWith((RequestOptions options) {
        captured = options;
        return <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{'qr': 'https://cdn.example/player.png'},
        };
      });

      expect(await api.playerCode(), 'https://cdn.example/player.png');
      expect(captured?.method, 'POST');
      expect(captured?.path, '/api/user/player-code');
    },
  );

  test(
    'playerCode preserves backend failure instead of fabricating a code',
    () async {
      final AccountApi api = _apiWith(
        (_) => <String, dynamic>{'code': 500, 'msg': '个人码生成服务繁忙，请稍后重试'},
      );

      await expectLater(
        api.playerCode(),
        throwsA(
          isA<Exception>().having(
            (Exception error) => error.toString(),
            'message',
            contains('个人码生成服务繁忙，请稍后重试'),
          ),
        ),
      );
    },
  );

  test(
    'playerCode fails closed when success body has no non-empty qr',
    () async {
      final AccountApi api = _apiWith(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{'qr': ''},
        },
      );

      await expectLater(api.playerCode(), throwsA(isA<Exception>()));
    },
  );
}

AccountApi _apiWith(
  Map<String, dynamic> Function(RequestOptions options) reply,
) {
  final DioClient client = DioClient(TokenStore(const FlutterSecureStorage()));
  client.dio.httpClientAdapter = _StubAdapter(reply);
  return AccountApi(client);
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
