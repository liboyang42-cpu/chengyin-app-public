import 'package:chengyin_app/core/feature_flags.dart';
// 退出登录。
//
// ★ App 此前**只清本地 token,从不通知服务端**。
//   后端 `/api/logout`(ApiLoginController:166)会 `delLoginAppUser(token)`
//   把这份凭据作废;不调它的话,**token 在服务端一直有效** ——
//   手机丢了、或在别人设备上登录后退出,那份凭据仍然能用。
//
// ⚠️ 同时必须守住反过来的那条:**服务端失败不能阻断本地退出**。
//   用户点了退出就必须退成,否则网络一断人就被困在已登录状态里。
//   这是「尽力而为」不是「必须成功」——两条一起才对,少一条都是 bug。

import 'dart:io';
import 'dart:async';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/auth_api.dart';
import 'package:chengyin_app/data/api/config_api.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:flutter_test/flutter_test.dart';

class _Store extends TokenStore {
  _Store() : super(const FlutterSecureStorage());
  String? token = 'synthetic-session';
  int clears = 0;
  @override
  Future<String?> read() async => token;
  @override
  Future<void> clear() async { clears++; token = null; }
}

class _Auth extends AuthController {
  @override
  AuthState build() => AuthState(initialized: true,
      user: User(id: 1, nickname: 'Fixture', avatar: '', role: 'player'));
}

class _Api implements AuthApi {
  final started = Completer<void>();
  final response = Completer<void>();
  int calls = 0;
  @override
  Future<void> logout() {
    calls++;
    started.complete();
    return response.future;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Config implements ConfigApi {
  @override
  Future<Map<String, dynamic>> fetchFeatures() async => {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final String api = File('lib/data/api/auth_api.dart').readAsStringSync();
  final String ctrl = File(
    'lib/feature/auth/auth_controller.dart',
  ).readAsStringSync();

  test('★ 退出时必须通知服务端作废 token', () {
    expect(
      api.contains("'/api/logout'"),
      isTrue,
      reason: 'AuthApi 里没有 logout —— token 会在服务端一直有效',
    );
    expect(
      ctrl.contains('authApiProvider).logout()'),
      isTrue,
      reason: 'AuthController.logout 没有调服务端',
    );
  });

  for (final serverFails in [false, true]) {
    test('logout clears locally after server ${serverFails ? "failure" : "success"}', () async {
      final store = _Store();
      final api = _Api();
      final container = ProviderContainer(overrides: [
        tokenStoreProvider.overrideWithValue(store),
        authApiProvider.overrideWithValue(api),
        configApiProvider.overrideWithValue(_Config()),
        authControllerProvider.overrideWith(_Auth.new),
      ]);
      addTearDown(container.dispose);
      final controller = container.read(authControllerProvider.notifier);
      final logout = controller.logout();
      expect(container.read(authControllerProvider).isLoggedIn, isFalse,
          reason: 'Pending server revocation must not trap the user on a signed-in screen');
      await api.started.future;
      expect(api.calls, 1);
      expect(store.token, 'synthetic-session',
          reason: 'Server revocation still needs the original credential');
      if (serverFails) {
        api.response.completeError(StateError('synthetic offline failure'));
      } else {
        api.response.complete();
      }
      await logout;
      expect(store.clears, 1, reason: 'Server failure must not skip local cleanup');
      expect(store.token, isNull);
      expect(container.read(authControllerProvider).isLoggedIn, isFalse);
      expect(container.read(authControllerProvider).initialized, isTrue);
    });
  }

  test('★ 401 只做本地失效，不得再请求 logout 造成递归', () {
    final String providers = File('lib/core/providers.dart').readAsStringSync();
    expect(providers, contains('.expireSession()'));
    expect(
      providers.substring(
        providers.indexOf('onUnauthorized:'),
        providers.indexOf('onUnauthorized:') + 220,
      ),
      isNot(contains('.logout()')),
    );
  });

  test('本地状态也要复位成未登录', () {
    expect(ctrl.contains('state = const AuthState(initialized: true)'), isTrue);
  });
}
