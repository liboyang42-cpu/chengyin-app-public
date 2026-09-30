import 'package:chengyin_app/core/feature_flags.dart';
import 'dart:async';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/request_session_scope.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/auth_api.dart';
import 'package:chengyin_app/data/api/config_api.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _AuthApi extends AuthApi {
  _AuthApi() : super(DioClient(TokenStore(const FlutterSecureStorage())));

  @override
  Future<Map<String, dynamic>> loginWithPhone(String phone, String code) async =>
      <String, dynamic>{
        'code': 200,
        'token': 'test-token',
        'data': <String, dynamic>{'id': 42, 'role': 'player'},
      };

  @override
  Future<Map<String, dynamic>> userInfo() async => <String, dynamic>{
    'code': 200,
    'appUser': <String, dynamic>{'userId': 42, 'role': 'player'},
  };
}

class _ConfigApi implements ConfigApi {
  @override
  Future<Map<String, dynamic>> fetchFeatures() async => <String, dynamic>{};
}

class _RegistrationApi implements RegistrationApi {
  final List<String> bound = <String>[];
  final firstBinding = Completer<void>();

  @override
  Future<void> setInviter(String id) async {
    bound.add(id);
    if (!firstBinding.isCompleted) firstBinding.complete();
  }

  @override
  Future<void> setInviterForSession(String id, RequestSessionScope scope) async {
    expect(scope.isCurrent(), isTrue);
    await setInviter(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final restore in [false, true]) {
    test('pending invitation is replayed by ${restore ? 'cold restore' : 'SMS login'}', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'pending_inviter_v1': '{"inviter":"7","owner":null}',
        if (restore) 'cy_jwt': 'test-token',
      });
      final registration = _RegistrationApi();
      final container = ProviderContainer(overrides: [
        authApiProvider.overrideWithValue(_AuthApi()),
        configApiProvider.overrideWithValue(_ConfigApi()),
        registrationApiProvider.overrideWithValue(registration),
      ]);
      addTearDown(container.dispose);
      final auth = container.read(authControllerProvider.notifier);
      if (restore) {
        await auth.bootstrap();
      } else {
        expect(await auth.loginWithPhone('13800138000', '123456'), isNull);
      }
      // This must complete from the auth hook, before the test requests replay.
      await registration.firstBinding.future.timeout(const Duration(seconds: 2));
      // Drain the service queue, which already contains the auth-triggered replay.
      // A second replay is intentionally idempotent.
      await container.read(pendingInviterProvider).replay();
      expect(registration.bound, ['7']);
      expect(container.read(authControllerProvider).user?.id, 42);
      const storage = FlutterSecureStorage();
      expect(await storage.read(key: 'has_inviter_v1_42'), '1');
      expect(await storage.read(key: 'pending_inviter_v1'), isNull);
    });
  }
}
