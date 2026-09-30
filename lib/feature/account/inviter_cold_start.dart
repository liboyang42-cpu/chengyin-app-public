import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/router/door_entry.dart';

/// 冷启动邀请人归因。真源 `pages/index/index.js handleInviter`:
/// 分享链接带 `inviter`(或 `id`)→ 登录落地后自动绑一次,
/// 本地 `has_inviter` 闸挡住重复绑(后端本来也只绑一次,
/// 但省一次注定失败的请求,也避免失败文案打扰用户)。
class InviterFlagStore {
  InviterFlagStore(this._storage);

  final FlutterSecureStorage _storage;
  static const String _key = 'has_inviter';

  Future<bool> get bound async => await _storage.read(key: _key) == '1';

  Future<void> markBound() => _storage.write(key: _key, value: '1');
}

/// 归因主链(依赖注入版,可单测)。真源口径:只在成功回包时打标记,
/// 失败既不重试也不提示 —— 新用户冷启动当场没有会话,
/// 等登录落地后由调用方补发一次(小程序 A-01 的同一条链)。
Future<void> consumeColdStartInviter({
  required String inviterId,
  required int? currentUserId,
  required Future<bool> Function() isBound,
  required Future<void> Function() markBound,
  required Future<void> Function(String inviterId) bind,
}) async {
  final bool hasInviter = await isBound();
  if (!shouldBindInviter(
    inviterId: inviterId,
    currentUserId: currentUserId,
    hasInviter: hasInviter,
  )) {
    return;
  }
  try {
    await bind(inviterId);
    await markBound();
  } catch (_) {
    // 静默:绑没绑上只有后端知道,重试不会有变化(同真源无 fail 分支)。
  }
}
