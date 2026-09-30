import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/providers.dart';

/// 与小程序 `scene-sound-haptics` 同源的六项本地偏好。
class SoundHapticsSettings {
  const SoundHapticsSettings({
    required this.sound,
    required this.haptics,
    required this.airplane,
    required this.ocean,
    required this.raindrop,
    required this.forest,
  });

  static const String storageKey = 'scene_sound_haptics';
  static const List<String> keys = <String>[
    'sound',
    'haptics',
    'airplane',
    'ocean',
    'raindrop',
    'forest',
  ];
  static const SoundHapticsSettings defaults = SoundHapticsSettings(
    sound: true,
    haptics: true,
    airplane: true,
    ocean: false,
    raindrop: false,
    forest: false,
  );

  final bool sound;
  final bool haptics;
  final bool airplane;
  final bool ocean;
  final bool raindrop;
  final bool forest;

  bool valueFor(String key) => switch (key) {
    'sound' => sound,
    'haptics' => haptics,
    'airplane' => airplane,
    'ocean' => ocean,
    'raindrop' => raindrop,
    'forest' => forest,
    _ => throw ArgumentError.value(key, 'key', '未知的声音与触感设置'),
  };

  SoundHapticsSettings copyWithKey(String key, bool value) => switch (key) {
    'sound' => _copy(sound: value),
    'haptics' => _copy(haptics: value),
    'airplane' => _copy(airplane: value),
    'ocean' => _copy(ocean: value),
    'raindrop' => _copy(raindrop: value),
    'forest' => _copy(forest: value),
    _ => throw ArgumentError.value(key, 'key', '未知的声音与触感设置'),
  };

  SoundHapticsSettings _copy({
    bool? sound,
    bool? haptics,
    bool? airplane,
    bool? ocean,
    bool? raindrop,
    bool? forest,
  }) {
    return SoundHapticsSettings(
      sound: sound ?? this.sound,
      haptics: haptics ?? this.haptics,
      airplane: airplane ?? this.airplane,
      ocean: ocean ?? this.ocean,
      raindrop: raindrop ?? this.raindrop,
      forest: forest ?? this.forest,
    );
  }

  Map<String, bool> toJson() => <String, bool>{
    'sound': sound,
    'haptics': haptics,
    'airplane': airplane,
    'ocean': ocean,
    'raindrop': raindrop,
    'forest': forest,
  };

  static SoundHapticsSettings fromStoredJson(String? raw) {
    if (raw == null) return defaults;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('声音与触感设置已损坏');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('声音与触感设置不是对象');
    }
    SoundHapticsSettings value = defaults;
    for (final String key in keys) {
      if (!decoded.containsKey(key)) continue;
      final Object? field = decoded[key];
      if (field is! bool) {
        throw FormatException('声音与触感设置 $key 不是 bool');
      }
      value = value.copyWithKey(key, field);
    }
    return value;
  }

  @override
  bool operator ==(Object other) =>
      other is SoundHapticsSettings &&
      sound == other.sound &&
      haptics == other.haptics &&
      airplane == other.airplane &&
      ocean == other.ocean &&
      raindrop == other.raindrop &&
      forest == other.forest;

  @override
  int get hashCode =>
      Object.hash(sound, haptics, airplane, ocean, raindrop, forest);
}

abstract interface class SoundHapticsSettingsStore {
  Future<SoundHapticsSettings> read();

  Future<void> write(SoundHapticsSettings value);
}

class SecureSoundHapticsSettingsStore implements SoundHapticsSettingsStore {
  SecureSoundHapticsSettingsStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<SoundHapticsSettings> read() async {
    final String? raw = await _storage.read(
      key: SoundHapticsSettings.storageKey,
    );
    return SoundHapticsSettings.fromStoredJson(raw);
  }

  @override
  Future<void> write(SoundHapticsSettings value) {
    return _storage.write(
      key: SoundHapticsSettings.storageKey,
      value: jsonEncode(value.toJson()),
    );
  }
}

final soundHapticsSettingsStoreProvider = Provider<SoundHapticsSettingsStore>(
  (Ref ref) =>
      SecureSoundHapticsSettingsStore(ref.watch(secureStorageProvider)),
);
