import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/models/game_session.dart';

const Set<String> playerGamePendingActions = <String>{
  'CONFIRM_ROLE',
  'PLAYER_CHOICE',
  'PLAYER_SUBMIT',
  'PLAYER_HINT',
  'PLAYER_REVEAL',
};

/// 玩家视角的「在途写」存根(对齐小程序 `game_player_pending_<activityId>`)。
///
/// 只存「回执索引 + 完整原命令」:网络断在「发出去了」和「没发出去」之间时,
/// 唯一能把结果收敛掉的入口是用原 requestId 回读或重放(服务端按 requestId 幂等)。
/// 作用域按 activityId —— 小程序就是这么记的;商家那份按 ownerMemberId 隔离,
/// 因为一个商家成员身份会流转过很多场活动,玩家的一局则只属于这一场。
class PlayerGamePendingWrite {
  const PlayerGamePendingWrite({
    required this.activityId,
    required this.nodeId,
    required this.requestId,
    required this.expectedRevision,
    required this.action,
    required this.payload,
  });

  final int activityId;
  final int? nodeId;
  final String requestId;
  final int expectedRevision;
  final String action;
  final Map<String, dynamic> payload;

  factory PlayerGamePendingWrite.fromCommand(GameSessionCommand command) =>
      PlayerGamePendingWrite(
        activityId: command.activityId,
        nodeId: command.nodeId,
        requestId: command.requestId,
        expectedRevision: command.expectedRevision,
        action: command.action,
        payload: Map<String, dynamic>.unmodifiable(command.payload),
      );

  GameSessionCommand toCommand() => GameSessionCommand(
    activityId: activityId,
    nodeId: nodeId,
    requestId: requestId,
    expectedRevision: expectedRevision,
    action: action,
    payload: Map<String, dynamic>.unmodifiable(payload),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'activityId': activityId,
    'nodeId': nodeId,
    'requestId': requestId,
    'expectedRevision': expectedRevision,
    'action': action,
    'payload': payload,
  };

  factory PlayerGamePendingWrite.fromJson(Map<String, dynamic> json) {
    final Object? rawNodeId = json['nodeId'];
    return PlayerGamePendingWrite(
      activityId: (json['activityId'] as num?)?.toInt() ?? 0,
      nodeId: rawNodeId is num ? rawNodeId.toInt() : null,
      requestId: (json['requestId'] ?? '').toString(),
      expectedRevision: (json['expectedRevision'] as num?)?.toInt() ?? -1,
      action: (json['action'] ?? '').toString(),
      payload: json['payload'] is Map<String, dynamic>
          ? Map<String, dynamic>.unmodifiable(
              json['payload'] as Map<String, dynamic>,
            )
          : const <String, dynamic>{},
    );
  }

  bool get valid =>
      activityId > 0 &&
      (nodeId == null || nodeId! > 0) &&
      expectedRevision >= 0 &&
      RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(requestId) &&
      playerGamePendingActions.contains(action) &&
      (action == 'CONFIRM_ROLE' ? nodeId == null : nodeId != null);
}

class PlayerGamePendingStore {
  PlayerGamePendingStore(this._storage);
  PlayerGamePendingStore.memory() : _storage = null;

  final FlutterSecureStorage? _storage;
  final Map<int, PlayerGamePendingWrite> _memory =
      <int, PlayerGamePendingWrite>{};

  String _key(int activityId) => 'player_game_pending_v1_$activityId';

  Future<PlayerGamePendingWrite?> read(int activityId) async {
    if (activityId <= 0) return null;
    if (_storage == null) return _memory[activityId];
    final String? raw = await _storage.read(key: _key(activityId));
    if (raw == null) return null;
    try {
      final Object? value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) return null;
      final PlayerGamePendingWrite pending = PlayerGamePendingWrite.fromJson(
        value,
      );
      return pending.valid && pending.activityId == activityId ? pending : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> write(PlayerGamePendingWrite value) async {
    if (!value.valid) {
      throw const FormatException('INVALID_PLAYER_GAME_PENDING_WRITE');
    }
    if (_storage == null) {
      _memory[value.activityId] = value;
      return;
    }
    await _storage.write(
      key: _key(value.activityId),
      value: jsonEncode(value.toJson()),
    );
  }

  Future<void> clear(int activityId) async {
    if (_storage == null) {
      _memory.remove(activityId);
      return;
    }
    await _storage.delete(key: _key(activityId));
  }
}

/// 身份卡「首入一次」的记住范围:按 activityId 记本机(小程序 `role_seen_<id>`)。
class PlayerGameRoleSeenStore {
  PlayerGameRoleSeenStore(this._storage);
  PlayerGameRoleSeenStore.memory() : _storage = null;

  final FlutterSecureStorage? _storage;
  final Set<int> _memory = <int>{};

  String _key(int activityId) => 'player_role_seen_v1_$activityId';

  Future<bool> seen(int activityId) async {
    if (activityId <= 0) return false;
    if (_storage == null) return _memory.contains(activityId);
    return await _storage.read(key: _key(activityId)) != null;
  }

  Future<void> markSeen(int activityId) async {
    if (activityId <= 0) return;
    if (_storage == null) {
      _memory.add(activityId);
      return;
    }
    await _storage.write(key: _key(activityId), value: '1');
  }
}
