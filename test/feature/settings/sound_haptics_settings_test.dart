import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/settings/sound_haptics_settings.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('缺失存储使用小程序六项默认值', () async {
    final SecureSoundHapticsSettingsStore store =
        SecureSoundHapticsSettingsStore(const FlutterSecureStorage());

    expect(await store.read(), SoundHapticsSettings.defaults);
  });

  test('部分存储合并小程序默认值', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      SoundHapticsSettings.storageKey: '{"ocean":true,"sound":false}',
    });
    final SecureSoundHapticsSettingsStore store =
        SecureSoundHapticsSettingsStore(const FlutterSecureStorage());

    final SoundHapticsSettings value = await store.read();
    expect(value.sound, isFalse);
    expect(value.haptics, isTrue);
    expect(value.airplane, isTrue);
    expect(value.ocean, isTrue);
    expect(value.raindrop, isFalse);
    expect(value.forest, isFalse);
  });

  test('损坏或非 bool 存储 fail closed', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      SoundHapticsSettings.storageKey: '{"sound":1}',
    });
    final SecureSoundHapticsSettingsStore store =
        SecureSoundHapticsSettingsStore(const FlutterSecureStorage());

    expect(store.read, throwsFormatException);
  });

  test('写入沿用小程序 key 并完整保存六项', () async {
    const FlutterSecureStorage storage = FlutterSecureStorage();
    final SecureSoundHapticsSettingsStore store =
        SecureSoundHapticsSettingsStore(storage);
    final SoundHapticsSettings changed = SoundHapticsSettings.defaults
        .copyWithKey('forest', true);

    await store.write(changed);

    expect(await store.read(), changed);
    final String raw = (await storage.read(
      key: SoundHapticsSettings.storageKey,
    ))!;
    for (final String key in SoundHapticsSettings.keys) {
      expect(raw, contains('"$key"'));
    }
  });

  test('未知 key 不会静默改错设置', () {
    expect(
      () => SoundHapticsSettings.defaults.copyWithKey('unknown', true),
      throwsArgumentError,
    );
  });
}
