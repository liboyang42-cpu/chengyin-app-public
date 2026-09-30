import '../../core/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/network/dio_client.dart';
import '../models/merchant_operator.dart';

abstract interface class MerchantOperatorIntentStore {
  Future<String?> read(String intentKey);
  Future<void> write(String intentKey, String requestId);
  Future<void> delete(String intentKey);
}

class SecureMerchantOperatorIntentStore implements MerchantOperatorIntentStore {
  SecureMerchantOperatorIntentStore(this._storage);

  final FlutterSecureStorage _storage;

  static const String _storageKey = 'merchant_operator_request_intents_v1';
  static const Duration _ttl = Duration(hours: 24);

  @override
  Future<String?> read(String intentKey) async {
    final Map<String, dynamic> intents = await _readAll();
    final Object? raw = intents[intentKey];
    if (raw is! Map<String, dynamic>) {
      if (raw != null) await _writeAll(_without(intents, intentKey));
      return null;
    }
    final String requestId = (raw['requestId'] ?? '').toString().trim();
    final int expiresAt = switch (raw['expiresAt']) {
      final int value => value,
      final num value => value.toInt(),
      final String value => int.tryParse(value) ?? 0,
      _ => 0,
    };
    if (!_validRequestId(requestId) ||
        expiresAt <= DateTime.now().millisecondsSinceEpoch) {
      await _writeAll(_without(intents, intentKey));
      return null;
    }
    return requestId;
  }

  @override
  Future<void> write(String intentKey, String requestId) async {
    if (intentKey.trim().isEmpty || !_validRequestId(requestId)) {
      throw ArgumentError('经营团队幂等意图无效');
    }
    final Map<String, dynamic> intents = await _readAll();
    intents[intentKey] = <String, dynamic>{
      'requestId': requestId,
      'expiresAt': DateTime.now().add(_ttl).millisecondsSinceEpoch,
    };
    await _writeAll(intents);
  }

  @override
  Future<void> delete(String intentKey) async {
    final Map<String, dynamic> intents = await _readAll();
    if (!intents.containsKey(intentKey)) return;
    await _writeAll(_without(intents, intentKey));
  }

  Future<Map<String, dynamic>> _readAll() async {
    final String? raw = await _storage.read(key: _storageKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Corrupt local recovery data is discarded; the server remains authoritative.
    }
    return <String, dynamic>{};
  }

  Future<void> _writeAll(Map<String, dynamic> intents) => intents.isEmpty
      ? _storage.delete(key: _storageKey)
      : _storage.write(key: _storageKey, value: jsonEncode(intents));

  Map<String, dynamic> _without(Map<String, dynamic> source, String key) =>
      Map<String, dynamic>.from(source)..remove(key);

  bool _validRequestId(String value) =>
      value.isNotEmpty &&
      value.length <= 64 &&
      RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value);
}

abstract interface class MerchantOperatorGateway {
  Future<MerchantOperatorAccess> access();
  Future<List<MerchantAssignableRole>> roles();
  Future<MerchantTeam> team();
  Future<MerchantInviteCreation> invite({
    required MerchantOperatorRole role,
    required String requestId,
  });
  Future<MerchantOperator> acceptInvite({
    required String token,
    required String requestId,
  });
  Future<MerchantOperatorReceipt> updateRole({
    required MerchantOperator operator,
    required MerchantOperatorRole role,
    required String requestId,
  });
  Future<MerchantOperatorReceipt> remove({
    required MerchantOperator operator,
    required String reason,
    required String requestId,
  });
  Future<MerchantInviteReceipt> revokeInvite({
    required MerchantOperatorInvite invite,
    required String reason,
    required String requestId,
  });
}

class MerchantOperatorApi implements MerchantOperatorGateway {
  MerchantOperatorApi(this._client);

  final DioClient _client;

  @override
  Future<MerchantOperatorAccess> access() async {
    final Map<String, dynamic> data = await _postObject(
      '/api/merchant/access/me',
      fallback: '经营身份加载失败',
    );
    return MerchantOperatorAccess.fromJson(data);
  }

  @override
  Future<List<MerchantAssignableRole>> roles() async {
    final List<dynamic> data = await _postList(
      '/api/merchant/operators/roles',
      fallback: '岗位列表加载失败',
    );
    return data
        .map(
          (Object? value) =>
              MerchantAssignableRole.fromJson(_object(value, '岗位列表')),
        )
        .toList(growable: false);
  }

  @override
  Future<MerchantTeam> team() async {
    final Map<String, dynamic> data = await _postObject(
      '/api/merchant/operators/list',
      fallback: '团队名单加载失败',
    );
    return MerchantTeam.fromJson(data);
  }

  @override
  Future<MerchantInviteCreation> invite({
    required MerchantOperatorRole role,
    required String requestId,
  }) async {
    final Map<String, dynamic> data = await _postObject(
      '/api/merchant/operators/invite',
      body: <String, dynamic>{
        'roleCode': role.wire,
        'requestId': _requestId(requestId),
      },
      fallback: '邀请创建失败',
    );
    final MerchantInviteCreation creation = MerchantInviteCreation.fromJson(
      data,
    );
    if (creation.invite.role != role ||
        creation.invite.status != MerchantInviteStatus.pending) {
      throw const MerchantOperatorApiException('邀请创建回执与岗位不匹配');
    }
    return creation;
  }

  @override
  Future<MerchantOperator> acceptInvite({
    required String token,
    required String requestId,
  }) async {
    final String normalizedToken = token.trim();
    if (normalizedToken.length < 16 || normalizedToken.length > 256) {
      throw ArgumentError.value(token, 'token', '邀请凭证无效');
    }
    final Map<String, dynamic> data = await _postObject(
      '/api/merchant/operators/invite/accept',
      body: <String, dynamic>{
        'token': normalizedToken,
        'requestId': _requestId(requestId),
      },
      fallback: '邀请无效或已失效',
    );
    final MerchantOperator operator = MerchantOperator.fromJson(data);
    if (operator.status != MerchantOperatorStatus.active) {
      throw const MerchantOperatorApiException('加入团队回执状态无效');
    }
    return operator;
  }

  @override
  Future<MerchantOperatorReceipt> updateRole({
    required MerchantOperator operator,
    required MerchantOperatorRole role,
    required String requestId,
  }) async {
    final Map<String, dynamic> data = await _postObject(
      '/api/merchant/operators/role',
      body: <String, dynamic>{
        'operatorId': operator.id,
        'roleCode': role.wire,
        'version': operator.version,
        'requestId': _requestId(requestId),
      },
      fallback: '岗位修改失败',
    );
    final MerchantOperatorReceipt receipt = MerchantOperatorReceipt.fromJson(
      data,
      expectedId: operator.id,
      minimumVersion: operator.version + 1,
    );
    if (receipt.mutationState == MerchantMutationState.exactResult &&
        (receipt.operator.status != MerchantOperatorStatus.active ||
            receipt.operator.version != operator.version + 1 ||
            receipt.operator.role != role)) {
      throw const MerchantOperatorApiException('岗位修改回执不完整');
    }
    if (receipt.mutationState == MerchantMutationState.laterAuthoritative &&
        receipt.operator.version < operator.version + 2) {
      throw const MerchantOperatorApiException('岗位后续状态回执不完整');
    }
    return receipt;
  }

  @override
  Future<MerchantOperatorReceipt> remove({
    required MerchantOperator operator,
    required String reason,
    required String requestId,
  }) async {
    final Map<String, dynamic> data = await _postObject(
      '/api/merchant/operators/remove',
      body: <String, dynamic>{
        'operatorId': operator.id,
        'version': operator.version,
        'reason': _reason(reason),
        'requestId': _requestId(requestId),
      },
      fallback: '成员移除失败',
    );
    return _operatorRevocationReceipt(data, operator);
  }

  @override
  Future<MerchantInviteReceipt> revokeInvite({
    required MerchantOperatorInvite invite,
    required String reason,
    required String requestId,
  }) async {
    final Map<String, dynamic> data = await _postObject(
      '/api/merchant/operators/invite/revoke',
      body: <String, dynamic>{
        'inviteId': invite.id,
        'version': invite.version,
        'reason': _reason(reason),
        'requestId': _requestId(requestId),
      },
      fallback: '邀请撤销失败',
    );
    final MerchantInviteReceipt receipt = MerchantInviteReceipt.fromJson(
      data,
      expectedId: invite.id,
      minimumVersion: invite.version + 1,
      expectedStatus: MerchantInviteStatus.revoked,
    );
    _requireMutationVersion(
      state: receipt.mutationState,
      actual: receipt.invite.version,
      previous: invite.version,
      message: '邀请撤销回执不完整',
    );
    return receipt;
  }

  MerchantOperatorReceipt _operatorRevocationReceipt(
    Map<String, dynamic> data,
    MerchantOperator operator,
  ) {
    final MerchantOperatorReceipt receipt = MerchantOperatorReceipt.fromJson(
      data,
      expectedId: operator.id,
      minimumVersion: operator.version + 1,
      expectedStatus: MerchantOperatorStatus.revoked,
    );
    _requireMutationVersion(
      state: receipt.mutationState,
      actual: receipt.operator.version,
      previous: operator.version,
      message: '成员移除回执不完整',
    );
    return receipt;
  }

  void _requireMutationVersion({
    required MerchantMutationState state,
    required int actual,
    required int previous,
    required String message,
  }) {
    final bool valid = switch (state) {
      MerchantMutationState.exactResult => actual == previous + 1,
      MerchantMutationState.laterAuthoritative => actual >= previous + 2,
    };
    if (!valid) throw MerchantOperatorApiException(message);
  }

  Future<Map<String, dynamic>> _postObject(
    String path, {
    Map<String, dynamic>? body,
    required String fallback,
  }) async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      path,
      data: body,
    );
    final Map<String, dynamic> envelope = response.data ?? <String, dynamic>{};
    _requireSuccess(envelope, fallback);
    return _object(envelope['data'], fallback);
  }

  Future<List<dynamic>> _postList(
    String path, {
    required String fallback,
  }) async {
    final response = await _client.dio.post<Map<String, dynamic>>(path);
    final Map<String, dynamic> envelope = response.data ?? <String, dynamic>{};
    _requireSuccess(envelope, fallback);
    final Object? data = envelope['data'];
    if (data is! List<dynamic>) {
      throw MerchantOperatorApiException('$fallback：回执不完整');
    }
    return data;
  }

  void _requireSuccess(Map<String, dynamic> body, String fallback) {
    final int? code = switch (body['code']) {
      final int number => number,
      final num number => number.toInt(),
      final String text => int.tryParse(text),
      _ => null,
    };
    if (code != 200) {
      throw MerchantOperatorApiException(
        (body['msg'] ?? fallback).toString(),
        code: code,
      );
    }
  }

  Map<String, dynamic> _object(Object? value, String field) {
    if (value is Map<String, dynamic>) return value;
    throw MerchantOperatorApiException('$field：回执不完整');
  }

  String _requestId(String value) {
    final String normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.length > 64 ||
        !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(normalized)) {
      throw ArgumentError.value(value, 'requestId', '格式不合法');
    }
    return normalized;
  }

  String _reason(String value) {
    final String normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 200) {
      throw ArgumentError.value(value, 'reason', '格式不合法');
    }
    return normalized;
  }
}

class MerchantOperatorApiException implements Exception {
  const MerchantOperatorApiException(this.message, {this.code});

  final String message;
  final int? code;

  bool get isUnauthorized => code == 401;
  bool get isForbidden => code == 403;
  bool get isConflict => code == 409;
  bool get isClientError => code != null && code! >= 400 && code! < 500;

  @override
  String toString() => message;
}

/// 定义在本文件而非 core/providers.dart:Riverpod 不要求 provider 集中声明。
final merchantOperatorApiProvider = Provider<MerchantOperatorGateway>((ref) {
  return MerchantOperatorApi(ref.watch(dioClientProvider));
});
