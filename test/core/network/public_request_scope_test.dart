import 'dart:async';
import 'dart:typed_data';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/request_session_scope.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _DelayedStore extends TokenStore {
  _DelayedStore() : super(const FlutterSecureStorage());
  final started = Completer<void>();
  final token = Completer<String?>();
  @override
  Future<String?> read() {
    started.complete();
    return token.future;
  }
}

class _Adapter implements HttpClientAdapter {
  int calls = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    expect(options.headers['Authorization'], isNull);
    return ResponseBody.fromString('{}', 200);
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final requiresAuth in [false, true]) {
    test('guest dispatch respects authentication requirement $requiresAuth', () async {
      final store = _DelayedStore();
      final adapter = _Adapter();
      final client = DioClient(store)..dio.httpClientAdapter = adapter;
      addTearDown(() => client.dio.close(force: true));
      final scope = RequestSessionScope(() => true,
          requireAuthentication: requiresAuth);
      final request = client.dio.get<void>('/public',
          options: Options(extra: {RequestSessionScope.extraKey: scope}));
      final result = expectLater(request,
          requiresAuth ? throwsA(isA<DioException>()) : completes);
      await store.started.future;
      store.token.complete(null);
      await result;
      expect(adapter.calls, requiresAuth ? 0 : 1);
    });
  }
  test('public read still rejects a changed generation during token read', () async {
    final store = _DelayedStore();
    final adapter = _Adapter();
    final client = DioClient(store)..dio.httpClientAdapter = adapter;
    addTearDown(() => client.dio.close(force: true));
    var current = true;
    final scope = RequestSessionScope(() => current, requireAuthentication: false);
    final request = client.dio.get<void>('/public',
        options: Options(extra: {RequestSessionScope.extraKey: scope}));
    final result = expectLater(request, throwsA(isA<DioException>()));
    await store.started.future;
    current = false;
    store.token.complete(null);
    await result;
    expect(adapter.calls, 0);
  });
}
