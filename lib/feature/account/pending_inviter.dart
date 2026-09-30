import 'dart:convert';

/// Persist a guest referral until authentication, then claim it for that account.
/// A failed or interrupted bind must never be replayed for a different account.
class PendingInviter {
  PendingInviter({
    required this.read,
    required this.write,
    required this.remove,
    required this.currentUserId,
    required this.bind,
    this.bindForUser,
  });

  final Future<String?> Function(String key) read;
  final Future<void> Function(String key, String value) write;
  final Future<void> Function(String key) remove;
  final int? Function() currentUserId;
  final Future<void> Function(String inviterId) bind;
  final Future<void> Function(String inviterId, int userId)? bindForUser;
  static const String pendingKey = 'pending_inviter_v1';
  Future<void> _tail = Future<void>.value();

  Future<void> _enqueue(Future<void> Function() operation) {
    // Storage/network failures must not prevent entry or poison the queue.
    _tail = _tail.then((_) => operation()).catchError((Object _) {});
    return _tail;
  }

  Future<void> capture(String raw) {
    final int? inviter = int.tryParse(raw.trim());
    if (inviter == null || inviter <= 0) return Future<void>.value();
    final int? owner = currentUserId();
    return _enqueue(() async {
      if (inviter == owner) return;
      await write(pendingKey, jsonEncode(<String, dynamic>{
        'inviter': '$inviter',
        'owner': owner,
      }));
      await _replay();
    });
  }

  Future<void> replay() => _enqueue(_replay);

  Future<void> _replay() async {
    final int? userId = currentUserId();
    if (userId == null || userId <= 0) return;
    final String? raw = await read(pendingKey);
    if (raw == null || currentUserId() != userId) return;
    final dynamic value = jsonDecode(raw);
    if (value is! Map<String, dynamic>) return;
    final String? inviter = value['inviter'] as String?;
    final dynamic owner = value['owner'];
    if (owner != null && owner != userId) return;
    if (inviter == null || (int.tryParse(inviter) ?? 0) <= 0) return;
    // Claim before any network operation. Never copy the legacy device-global
    // has_inviter flag: it cannot tell us which account actually bound it.
    await write(pendingKey, jsonEncode(<String, dynamic>{
      'inviter': inviter,
      'owner': userId,
    }));
    final String boundKey = 'has_inviter_v1_$userId';
    final bool bound = await read(boundKey) == '1';
    if (currentUserId() != userId) return;
    if (inviter == '$userId' || bound) {
      await remove(pendingKey);
      return;
    }
    if (bindForUser != null) {
      await bindForUser!(inviter, userId);
    } else {
      await bind(inviter);
    }
    if (currentUserId() != userId) return;
    await write(boundKey, '1');
    await remove(pendingKey);
  }
}
