import 'package:chengyin_app/core/map/map_privacy_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _DeleteFailingStorage extends FlutterSecureStorage {
  const _DeleteFailingStorage();

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
  }) async {
    throw Exception('钥匙串删除失败');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('privacy consent defaults false and persists true', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final store = MapPrivacyStore(const FlutterSecureStorage());

    expect(await store.hasAgreed(), isFalse);
    await store.setAgreed(true);
    expect(await store.hasAgreed(), isTrue);
  });

  test('privacy consent can be revoked', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final store = MapPrivacyStore(const FlutterSecureStorage());

    await store.setAgreed(true);
    await store.setAgreed(false);

    expect(await store.hasAgreed(), isFalse);
  });

  test('本地删除失败时当前会话仍 fail closed 为 false', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'amap_privacy_agreed': 'true',
    });
    final store = MapPrivacyStore(const _DeleteFailingStorage());

    await expectLater(store.setAgreed(false), throwsException);

    expect(await store.hasAgreed(), isFalse);
  });
}
