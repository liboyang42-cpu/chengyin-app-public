import 'package:chengyin_app/core/feature_flags.dart';
import 'dart:async';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/auth_api.dart';
import 'package:chengyin_app/data/api/config_api.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api extends AuthApi {
  _Api() : super(DioClient(TokenStore(const FlutterSecureStorage())));
  final logins = <Completer<Map<String, dynamic>>>[];
  final infos = <Completer<Map<String, dynamic>>>[];
  final logoutStarted = Completer<void>();
  final logoutDone = Completer<void>();
  @override
  Future<Map<String, dynamic>> loginWithPhone(String phone, String code) {
    final result = Completer<Map<String, dynamic>>();
    logins.add(result);
    return result.future;
  }
  @override
  Future<Map<String, dynamic>> userInfo() {
    final result = Completer<Map<String, dynamic>>();
    infos.add(result);
    return result.future;
  }
  @override
  Future<void> logout() {
    logoutStarted.complete();
    return logoutDone.future;
  }
}
class _SlowStore extends TokenStore {
  _SlowStore() : super(const FlutterSecureStorage());
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> write(String token) async {
    started.complete();
    await release.future;
    await super.write(token);
  }
}

class _Config implements ConfigApi {
  @override
  Future<Map<String, dynamic>> fetchFeatures() async => {};
}
Map<String, dynamic> _login(int id) => {
  'code': 200, 'token': 'token-$id', 'data': {'id': id, 'role': 'player'},
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Api api;
  late ProviderContainer container;
  late AuthController auth;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    api = _Api();
    container = ProviderContainer(overrides: [
      authApiProvider.overrideWithValue(api),
      configApiProvider.overrideWithValue(_Config()),
    ]);
    auth = container.read(authControllerProvider.notifier);
  });
  tearDown(() => container.dispose());
  test('malformed success never authenticates or persists a credential', () async {
    for (final body in [
      {'code': 200, 'data': {'id': 7}},
      {'code': 200, 'token': 'bad'},
      {'code': 200, 'token': 'bad', 'data': {'id': 0}},
    ]) {
      final login = auth.loginWithPhone('test', 'test');
      api.logins.last.complete(body);
      expect(await login, isNotNull);
      expect(container.read(authControllerProvider).isLoggedIn, isFalse);
      expect(await container.read(tokenStoreProvider).read(), isNull);
    }
  });
  test('stale failed login does not access resources after disposal', () async {
    final temporary = ProviderContainer(overrides: [
      authApiProvider.overrideWithValue(api),
    ]);
    final controller = temporary.read(authControllerProvider.notifier);
    final login = controller.loginWithPhone('test', 'test');
    temporary.dispose();
    api.logins.single.completeError(StateError('offline'));
    expect(await login, isNull);
  });
  test('out-of-order login completion preserves most recent attempt', () async {
    final first = auth.loginWithPhone('first', 'test');
    final second = auth.loginWithPhone('second', 'test');
    api.logins[1].complete(_login(2));
    await second;
    api.logins[0].complete(_login(1));
    await first;
    expect(container.read(authControllerProvider).user?.id, 2);
    expect(await container.read(tokenStoreProvider).read(), 'token-2');
  });
  test('logout routes immediately; pending revocation cannot clear new login', () async {
    final first = auth.loginWithPhone('first', 'test');
    api.logins.single.complete(_login(1));
    await first;
    final logout = auth.logout();
    expect(container.read(authControllerProvider).isLoggedIn, isFalse);
    await api.logoutStarted.future;
    final next = auth.loginWithPhone('second', 'test');
    api.logins.last.complete(_login(2));
    api.logoutDone.complete();
    await logout;
    await next;
    expect(container.read(authControllerProvider).user?.id, 2);
    expect(await container.read(tokenStoreProvider).read(), 'token-2');
  });
  test('expiration during a pending keychain write clears the late credential', () async {
    final store = _SlowStore();
    container.dispose();
    container = ProviderContainer(overrides: [
      tokenStoreProvider.overrideWithValue(store),
      authApiProvider.overrideWithValue(api),
      configApiProvider.overrideWithValue(_Config()),
    ]);
    auth = container.read(authControllerProvider.notifier);
    final login = auth.loginWithPhone('first', 'test');
    api.logins.single.complete(_login(1));
    await store.started.future;
    final expiration = auth.expireSession();
    expect(container.read(authControllerProvider).isLoggedIn, isFalse);
    store.release.complete();
    await login;
    await expiration;
    expect(await store.read(), isNull);
    expect(container.read(authControllerProvider).isLoggedIn, isFalse);
  });
  test('role refresh completing after expiration cannot restore user', () async {
    final login = auth.loginWithPhone('first', 'test');
    api.logins.single.complete(_login(1));
    await login;
    final refresh = auth.refreshRole();
    await auth.expireSession();
    api.infos.single.complete({'code': 200, 'appUser': {'userId': 1}});
    await refresh;
    expect(container.read(authControllerProvider).isLoggedIn, isFalse);
  });
  test('stale failed bootstrap cannot clear newly signed-in token', () async {
    await container.read(tokenStoreProvider).write('cold-token');
    final bootstrap = auth.bootstrap();
    while (api.infos.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final login = auth.loginWithPhone('new', 'test');
    api.logins.single.complete(_login(2));
    await login;
    api.infos.single.complete({'code': 401});
    await bootstrap;
    expect(container.read(authControllerProvider).user?.id, 2);
    expect(await container.read(tokenStoreProvider).read(), 'token-2');
  });
}
