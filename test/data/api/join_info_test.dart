import 'dart:convert';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
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

  RegistrationApi apiWith(Map<String, dynamic> reply) {
    final client = DioClient(TokenStore(const FlutterSecureStorage()));
    client.dio.httpClientAdapter = _StubAdapter(reply);
    return RegistrationApi(client);
  }

  test('join_info 的明确“查询失败”表示没有进行中报名', () async {
    final RegistrationApi api = apiWith(<String, dynamic>{
      'code': 500,
      'msg': '查询失败',
    });

    expect(await api.joinInfo(), isNull);
  });

  test('join_info 的登录或服务错误仍然抛出，不能伪装成空报名', () async {
    final RegistrationApi api = apiWith(<String, dynamic>{
      'code': 500,
      'msg': '请先登录',
    });

    await expectLater(
      api.joinInfo(),
      throwsA(predicate((Object error) => error.toString().contains('请先登录'))),
    );
  });

  for (final Map<String, dynamic> reply in <Map<String, dynamic>>[
    <String, dynamic>{'code': 200},
    <String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{'id': 0},
    },
  ]) {
    test('join_info 的 200 畸形数据保持 error：$reply', () async {
      await expectLater(
        apiWith(reply).joinInfo(),
        throwsA(
          predicate((Object error) => error.toString().contains('报名状态数据异常')),
        ),
      );
    });
  }
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.reply);

  final Map<String, dynamic> reply;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(reply),
    200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
