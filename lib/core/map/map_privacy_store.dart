import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class MapPrivacyStore {
  MapPrivacyStore(this._storage);

  // ★ 键名保留 `amap_` 前缀:地图已换 Apple Maps(Task 1.4),但改键名会让
  //   所有老用户的「已同意」静默失效、重新弹一次同意页。名字难看 < 用户重来一遍。
  static const String _key = 'amap_privacy_agreed';
  final FlutterSecureStorage _storage;
  bool _revokedInMemory = false;

  Future<bool> hasAgreed() async {
    if (_revokedInMemory) return false;
    return await _storage.read(key: _key) == 'true';
  }

  Future<void> setAgreed(bool agreed) async {
    if (agreed) {
      await _storage.write(key: _key, value: 'true');
      _revokedInMemory = false;
    } else {
      // 服务端已撤回后，即使本地钥匙串删除失败，本次进程也必须 fail closed。
      _revokedInMemory = true;
      await _storage.delete(key: _key);
    }
  }
}
