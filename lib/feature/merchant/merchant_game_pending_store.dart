import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/models/game_session.dart';

class MerchantGamePendingWrite {
  const MerchantGamePendingWrite({
    required this.ownerMemberId,
    required this.activityId,
    required this.nodeId,
    required this.requestId,
    required this.expectedRevision,
    required this.action,
    required this.payload,
  });
  final int ownerMemberId;
  final int activityId;
  final int nodeId;
  final String requestId;
  final int expectedRevision;
  final String action;
  final Map<String, dynamic> payload;

  factory MerchantGamePendingWrite.fromCommand(
    GameSessionCommand command, {
    required int ownerMemberId,
  }) {
    final int? nodeId = command.nodeId;
    if (nodeId == null) {
      throw const FormatException('INVALID_MERCHANT_GAME_PENDING_WRITE');
    }
    return MerchantGamePendingWrite(
      ownerMemberId: ownerMemberId,
      activityId: command.activityId,
      nodeId: nodeId,
      requestId: command.requestId,
      expectedRevision: command.expectedRevision,
      action: command.action,
      payload: Map<String, dynamic>.unmodifiable(command.payload),
    );
  }

  GameSessionCommand toCommand() => GameSessionCommand(
    activityId: activityId,
    nodeId: nodeId,
    requestId: requestId,
    expectedRevision: expectedRevision,
    action: action,
    payload: Map<String, dynamic>.unmodifiable(payload),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'ownerMemberId': ownerMemberId,
    'activityId': activityId,
    'nodeId': nodeId,
    'requestId': requestId,
    'expectedRevision': expectedRevision,
    'action': action,
    'payload': payload,
  };
  factory MerchantGamePendingWrite.fromJson(Map<String, dynamic> json) =>
      MerchantGamePendingWrite(
        ownerMemberId: (json['ownerMemberId'] as num?)?.toInt() ?? 0,
        activityId: (json['activityId'] as num?)?.toInt() ?? 0,
        nodeId: (json['nodeId'] as num?)?.toInt() ?? 0,
        requestId: (json['requestId'] ?? '').toString(),
        expectedRevision: (json['expectedRevision'] as num?)?.toInt() ?? -1,
        action: (json['action'] ?? '').toString(),
        payload: json['payload'] is Map<String, dynamic>
            ? Map<String, dynamic>.unmodifiable(
                json['payload'] as Map<String, dynamic>,
              )
            : const <String, dynamic>{},
      );
  bool get valid =>
      ownerMemberId > 0 &&
      activityId > 0 &&
      nodeId > 0 &&
      expectedRevision >= 0 &&
      RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(requestId) &&
      action.isNotEmpty;
}

class MerchantGameLegacyPendingWrite {
  const MerchantGameLegacyPendingWrite({
    required this.activityId,
    required this.requestId,
    required this.action,
  });

  final int activityId;
  final String requestId;
  final String action;

  factory MerchantGameLegacyPendingWrite.fromJson(Map<String, dynamic> json) =>
      MerchantGameLegacyPendingWrite(
        activityId: (json['activityId'] as num?)?.toInt() ?? 0,
        requestId: (json['requestId'] ?? '').toString(),
        action: (json['action'] ?? '').toString(),
      );

  bool get valid =>
      activityId > 0 &&
      RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(requestId) &&
      action.isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'activityId': activityId,
    'requestId': requestId,
    'action': action,
  };
}

class MerchantGamePendingStore {
  MerchantGamePendingStore(this._storage);
  MerchantGamePendingStore.memory() : _storage = null;
  final FlutterSecureStorage? _storage;
  final Map<String, MerchantGamePendingWrite> _memory =
      <String, MerchantGamePendingWrite>{};
  final Map<int, MerchantGameLegacyPendingWrite> _legacyMemory =
      <int, MerchantGameLegacyPendingWrite>{};
  String _key(int ownerMemberId, int activityId) =>
      'merchant_game_pending_v2_${ownerMemberId}_$activityId';
  String _legacyKey(int activityId) => 'merchant_game_pending_v1_$activityId';

  Future<MerchantGamePendingWrite?> read(
    int activityId, {
    required int ownerMemberId,
  }) async {
    if (ownerMemberId <= 0) {
      throw ArgumentError.value(ownerMemberId, 'ownerMemberId');
    }
    if (_storage == null) {
      return _memory[_key(ownerMemberId, activityId)];
    }
    final raw = await _storage.read(key: _key(ownerMemberId, activityId));
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) return null;
      final pending = MerchantGamePendingWrite.fromJson(value);
      return pending.valid &&
              pending.activityId == activityId &&
              pending.ownerMemberId == ownerMemberId
          ? pending
          : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> write(MerchantGamePendingWrite value) async {
    if (!value.valid) {
      throw const FormatException('INVALID_MERCHANT_GAME_PENDING_WRITE');
    }
    if (_storage == null) {
      _memory[_key(value.ownerMemberId, value.activityId)] = value;
      return;
    }
    await _storage.write(
      key: _key(value.ownerMemberId, value.activityId),
      value: jsonEncode(value.toJson()),
    );
  }

  Future<void> clear(int activityId, {required int ownerMemberId}) async {
    if (ownerMemberId <= 0) {
      throw ArgumentError.value(ownerMemberId, 'ownerMemberId');
    }
    if (_storage == null) {
      _memory.remove(_key(ownerMemberId, activityId));
      return;
    }
    await _storage.delete(key: _key(ownerMemberId, activityId));
  }

  Future<MerchantGameLegacyPendingWrite?> readLegacy(int activityId) async {
    if (_storage == null) return _legacyMemory[activityId];
    final raw = await _storage.read(key: _legacyKey(activityId));
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) return null;
      final pending = MerchantGameLegacyPendingWrite.fromJson(value);
      return pending.valid && pending.activityId == activityId ? pending : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> clearLegacy(int activityId) async {
    if (_storage == null) {
      _legacyMemory.remove(activityId);
      return;
    }
    await _storage.delete(key: _legacyKey(activityId));
  }

  Future<void> writeLegacyForTest(MerchantGameLegacyPendingWrite value) async {
    if (_storage == null) {
      _legacyMemory[value.activityId] = value;
      return;
    }
    await _storage.write(
      key: _legacyKey(value.activityId),
      value: jsonEncode(value.toJson()),
    );
  }
}
