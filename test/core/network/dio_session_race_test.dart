import 'dart:async';
import 'dart:typed_data';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:dio/dio.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/auth_api.dart';
import 'package:chengyin_app/data/api/config_api.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _DelayedUnauthorized implements HttpClientAdapter {
  final started = Completer<RequestOptions>();
  final finish = Completer<ResponseBody>();
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    started.complete(options);
    return finish.future;
  }
  @override
  void close({bool force = false}) {}
}

class _PendingLoginApi extends AuthApi {
  _PendingLoginApi(DioClient client) : super(client);
  final result = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> loginWithPhone(String phone, String code) => result.future;
}

class _Config implements ConfigApi {
  @override
  Future<Map<String, dynamic>> fetchFeatures() async => {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a delayed 401 for an old token preserves replacement token and session', () async {
    FlutterSecureStorage.setMockInitialValues({'cy_jwt': 'old'});
    final store = TokenStore(const FlutterSecureStorage());
    var notifications = 0;
    final client = DioClient(store, onUnauthorized: () => notifications++);
    final adapter = _DelayedUnauthorized();
    client.dio.httpClientAdapter = adapter;
    final request = client.dio.get<void>('/protected');
    final assertion = expectLater(request, throwsA(isA<DioException>()));
    expect((await adapter.started.future).headers['Authorization'], 'old');
    await store.sessionOperation(() => store.write('new'));
    adapter.finish.complete(ResponseBody.fromString('{}', 401));
    await assertion;
    expect(await store.read(), 'new');
    expect(notifications, 0);
  });
  test('anonymous 401 cannot cancel a pending login', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = TokenStore(const FlutterSecureStorage());
    late AuthController auth;
    final client = DioClient(store, onUnauthorized: () => auth.expireSession());
    final api = _PendingLoginApi(client);
    final container = ProviderContainer(overrides: [
      tokenStoreProvider.overrideWithValue(store),
      authApiProvider.overrideWithValue(api),
      configApiProvider.overrideWithValue(_Config()),
    ]);
    addTearDown(container.dispose);
    auth = container.read(authControllerProvider.notifier);
    final adapter = _DelayedUnauthorized();
    client.dio.httpClientAdapter = adapter;
    final request = client.dio.get<void>('/protected');
    final assertion = expectLater(request, throwsA(isA<DioException>()));
    expect((await adapter.started.future).headers['Authorization'], isNull);
    final login = auth.loginWithPhone('test', 'test');
    adapter.finish.complete(ResponseBody.fromString('{}', 401));
    await assertion;
    expect(container.read(authControllerProvider).loading, isTrue);
    api.result.complete({'code': 200, 'token': 'new', 'data': {'id': 7}});
    expect(await login, isNull);
    expect(container.read(authControllerProvider).user?.id, 7);
    expect(await store.read(), 'new');
  });
  test('logout 401 does not recursively expire a replacement login', () async {
    FlutterSecureStorage.setMockInitialValues({'cy_jwt': 'old'});
    final store = TokenStore(const FlutterSecureStorage());
    var notifications = 0;
    final client = DioClient(store, onUnauthorized: () => notifications++);
    final adapter = _DelayedUnauthorized();
    client.dio.httpClientAdapter = adapter;
    final request = client.dio.post<void>('/api/logout');
    final assertion = expectLater(request, throwsA(isA<DioException>()));
    await adapter.started.future;
    adapter.finish.complete(ResponseBody.fromString('{}', 401));
    await assertion;
    expect(notifications, 0);
  });
}
