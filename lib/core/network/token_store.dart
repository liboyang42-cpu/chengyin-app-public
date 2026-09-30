import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// JWT 安全存储(iOS 钥匙串 / Android Keystore)。**禁止明文存 token**。
class TokenStore {
  TokenStore(this._storage);
  final FlutterSecureStorage _storage;

  static const String _kToken = 'cy_jwt';

  Future<String?> read() => _storage.read(key: _kToken);
  Future<void> write(String token) =>
      _storage.write(key: _kToken, value: token);
  Future<void> clear() => _storage.delete(key: _kToken);
}
