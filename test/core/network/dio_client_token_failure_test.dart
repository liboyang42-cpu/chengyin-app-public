import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _UnreadableTokenStore extends TokenStore {
  _UnreadableTokenStore() : super(const FlutterSecureStorage());

  @override
  Future<String?> read() => throw PlatformException(
    code: '-34018',
    message: 'A required entitlement is not present',
  );
}

class _UnclearableTokenStore extends TokenStore {
  _UnclearableTokenStore() : super(const FlutterSecureStorage());

  @override
  Future<String?> read() async => 'expired-token';

  @override
  Future<void> clear() => throw PlatformException(
    code: '-34018',
    message: 'A required entitlement is not present',
  );
}

class _UnauthorizedAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString('{}', 401);

  @override
  void close({bool force = false}) {}
}

void main() {
  test('钥匙串暂不可读时匿名请求仍可发送', () async {
    final DioClient client = DioClient(_UnreadableTokenStore());
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: <String, dynamic>{'ok': true},
            ),
          );
        },
      ),
    );

    final Response<Map<String, dynamic>> response = await client.dio
        .get<Map<String, dynamic>>('/probe');

    expect(response.data, <String, dynamic>{'ok': true});
  });

  test('401 时即使钥匙串清理失败也会通知登出并交付原错误', () async {
    var unauthorizedNotified = false;
    final DioClient client = DioClient(
      _UnclearableTokenStore(),
      onUnauthorized: () => unauthorizedNotified = true,
    );
    client.dio.httpClientAdapter = _UnauthorizedAdapter();

    await expectLater(
      client.dio.get<void>('/protected'),
      throwsA(isA<DioException>()),
    );
    expect(unauthorizedNotified, isTrue);
  });
}
