import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// JWT 安全存储(iOS 钥匙串 / Android Keystore)。**禁止明文存 token**。
class TokenStore {
  TokenStore(this._storage);
  final FlutterSecureStorage _storage;
  Future<void> _sessionTail = Future<void>.value();

  /// Serialize compare/delete and controller session writes as one transaction.
  /// Actions use read/write/clear directly; do not nest this method.
  Future<T> sessionOperation<T>(Future<T> Function() action) {
    final operation = _sessionTail.then((_) => action());
    _sessionTail = operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }


  static const String _kToken = 'cy_jwt';

  Future<String?> read() => _storage.read(key: _kToken);
  Future<void> write(String token) =>
      _storage.write(key: _kToken, value: token);
  Future<void> clear() => _storage.delete(key: _kToken);
}
