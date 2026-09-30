import 'dart:async';

import 'package:chengyin_app/core/feature_flags.dart';
import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/auth_api.dart';
import 'package:chengyin_app/data/api/config_api.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _PendingConfigApi implements ConfigApi {
  final Completer<Map<String, dynamic>> response =
      Completer<Map<String, dynamic>>();

  @override
  Future<Map<String, dynamic>> fetchFeatures() => response.future;
}

class _FailingAuthApi extends AuthApi {
  _FailingAuthApi()
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  @override
  Future<Map<String, dynamic>> userInfo() async {
    throw Exception('offline');
  }
}

class _SuccessfulAuthApi extends AuthApi {
  _SuccessfulAuthApi()
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  @override
  Future<Map<String, dynamic>> loginWithPhone(String phone, String code) async {
    return <String, dynamic>{
      'code': 200,
      'token': 'fresh-token',
      'data': <String, dynamic>{'id': 7, 'nickname': '测试用户'},
    };
  }

  @override
  Future<void> logout() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('启动恢复不等待远端灰度开关，开关保持失败关闭并在后台刷新', () async {
    final api = _PendingConfigApi();
    final container = ProviderContainer(
      overrides: <dynamic>[configApiProvider.overrideWithValue(api)].cast(),
    );
    addTearDown(container.dispose);

    try {
      await container
          .read(authControllerProvider.notifier)
          .bootstrap()
          .timeout(const Duration(seconds: 2));

      expect(container.read(authControllerProvider).initialized, isTrue);
      expect(container.read(featureFlagProvider('communityPostRead')), isFalse);

      api.response.complete(<String, dynamic>{'communityPostRead': true});
      await Future<void>.delayed(Duration.zero);

      expect(container.read(featureFlagProvider('communityPostRead')), isTrue);
    } finally {
      if (!api.response.isCompleted) {
        api.response.complete(<String, dynamic>{});
      }
    }
  });

  test('存量 token 恢复失败后仍在后台刷新匿名灰度开关', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'cy_jwt': 'stale-token',
    });
    final api = _PendingConfigApi();
    final container = ProviderContainer(
      overrides: <dynamic>[
        authApiProvider.overrideWithValue(_FailingAuthApi()),
        configApiProvider.overrideWithValue(api),
      ].cast(),
    );
    addTearDown(container.dispose);

    await container
        .read(authControllerProvider.notifier)
        .bootstrap()
        .timeout(const Duration(seconds: 2));

    expect(container.read(authControllerProvider).initialized, isTrue);
    expect(container.read(featureFlagProvider('communityPostRead')), isFalse);

    api.response.complete(<String, dynamic>{'communityPostRead': true});
    await Future<void>.delayed(Duration.zero);

    expect(container.read(featureFlagProvider('communityPostRead')), isTrue);
  });

  test('登录成功不等待远端灰度开关，并在后台应用登录态配置', () async {
    final api = _PendingConfigApi();
    final container = ProviderContainer(
      overrides: <dynamic>[
        authApiProvider.overrideWithValue(_SuccessfulAuthApi()),
        configApiProvider.overrideWithValue(api),
      ].cast(),
    );
    addTearDown(container.dispose);

    await container
        .read(authControllerProvider.notifier)
        .loginWithPhone('13800138000', '123456')
        .timeout(const Duration(seconds: 2));

    expect(container.read(authControllerProvider).isLoggedIn, isTrue);
    expect(container.read(featureFlagProvider('communityPostWrite')), isFalse);

    api.response.complete(<String, dynamic>{'communityPostWrite': true});
    await Future<void>.delayed(Duration.zero);

    expect(container.read(featureFlagProvider('communityPostWrite')), isTrue);
  });

  test('退出不等待远端灰度开关，立即失败关闭并在后台刷新匿名配置', () async {
    final api = _PendingConfigApi();
    final container = ProviderContainer(
      overrides: <dynamic>[
        authApiProvider.overrideWithValue(_SuccessfulAuthApi()),
        configApiProvider.overrideWithValue(api),
      ].cast(),
    );
    addTearDown(container.dispose);

    await container
        .read(authControllerProvider.notifier)
        .loginWithPhone('13800138000', '123456')
        .timeout(const Duration(seconds: 2));
    await container
        .read(authControllerProvider.notifier)
        .logout()
        .timeout(const Duration(seconds: 2));

    expect(container.read(authControllerProvider).isLoggedIn, isFalse);
    expect(container.read(featureFlagProvider('communityPostRead')), isFalse);

    api.response.complete(<String, dynamic>{'communityPostRead': true});
    await Future<void>.delayed(Duration.zero);

    expect(container.read(featureFlagProvider('communityPostRead')), isTrue);
  });
}
