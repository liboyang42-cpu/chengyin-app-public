import '../../core/network/request_session_scope.dart';
import '../../core/network/dio_client.dart';
import '../models/club_director.dart';
import '../models/game_session.dart';
export '../models/game_session.dart';

class GameSessionContractException implements Exception {
  const GameSessionContractException(this.message, {this.reasonCode, this.isLocal = false});
  final String message;
  final String? reasonCode;
  /// True only for client-authored validation/fallback text, never inferred from text.
  final bool isLocal;
  @override
  String toString() => message;
}

class GameSessionRejectedException extends GameSessionContractException {
  const GameSessionRejectedException(super.message, {super.isLocal});
}

abstract interface class GameSessionGateway {
  Future<List<MerchantGameEntry>> loadMerchantEntries();
  Future<MerchantGameProjection> loadMerchantView({required int activityId});
  Future<GameSessionReceipt> submitAndReadReceipt(GameSessionCommand command);
  Future<GameSessionReceipt> readReceipt({
    required int activityId,
    required String requestId,
    required String expectedAction,
  });
}

abstract interface class PlayerGameSessionGateway {
  Future<PlayerGameProjection> loadPlayerView({required int activityId});
  Future<GameSessionReceipt> submitPlayerCommand(GameSessionCommand command);
  Future<GameSessionReceipt> readPlayerReceipt({
    required int activityId,
    required String requestId,
    required String expectedAction,
  });
}

/// 俱乐部视角(导演台):读一局的复盘状态 + 导出复盘数据。
///
/// ★ 单独一个接口,不并进 [GameSessionGateway]:商家页的四个替身
///   (含在途 PR 新增的那个)都 `implements GameSessionGateway`,
///   往里加方法会让它们在编译期一起红,而这五个端点里只有
///   `/api/game/session/recap/export` 是俱乐部的。
abstract interface class ClubGameSessionGateway {
  Future<ClubRecapState> loadClubView({required int activityId});

  Future<Map<String, dynamic>> loadClubRecapExport({required int activityId});
}

/// 导演台(4-C)的读投影 + 写 + 回执回读。
///
/// 又是单独一个接口:替身纪律与 [ClubGameSessionGateway] 同一条 ——
/// 已有测试往复盘那两个方法上塞假网关,方法加多了会把不相干的替身一起弄红。
abstract interface class ClubDirectorGateway {
  Future<ClubDirectorProjection> loadClubProjection({required int activityId});

  Future<GameSessionReceipt> submitClubCommand(GameSessionCommand command);

  Future<GameSessionReceipt> readClubReceipt({
    required int activityId,
    required String requestId,
    required String expectedAction,
  });
}

class GameSessionApi
    implements
        GameSessionGateway,
        PlayerGameSessionGateway,
        ClubGameSessionGateway,
        ClubDirectorGateway {
  GameSessionApi(this._client);
  final DioClient _client;

  @override
  Future<List<MerchantGameEntry>> loadMerchantEntries() async {
    final body = await _get('/api/game/session/merchant/entries');
    final raw = body['data'];
    if (raw is! List) throw const GameSessionContractException('本站入口不可用', isLocal: true);
    final entries = raw
        .whereType<Map<String, dynamic>>()
        .map(MerchantGameEntry.fromJson)
        .toList();
    if (entries.length != raw.length || entries.any((entry) => !entry.valid)) {
      throw const GameSessionContractException('本站入口数据无效', isLocal: true);
    }
    return entries;
  }

  @override
  Future<MerchantGameProjection> loadMerchantView({
    required int activityId,
  }) async {
    if (activityId <= 0) throw const GameSessionContractException('活动参数无效', isLocal: true);
    final body = await _get(
      '/api/game/session/view',
      query: <String, dynamic>{
        'activityId': activityId,
        'perspective': 'MERCHANT',
      },
    );
    try {
      return MerchantGameProjection.fromJson(_object(body['data']));
    } on FormatException {
      throw const GameSessionContractException('本站状态不可用', isLocal: true);
    }
  }

  @override
  Future<PlayerGameProjection> loadPlayerView({required int activityId}) async {
    if (activityId <= 0) throw const GameSessionContractException('活动参数无效', isLocal: true);
    final body = await _get(
      '/api/game/session/view',
      query: <String, dynamic>{
        'activityId': activityId,
        'perspective': 'PLAYER',
      },
    );
    try {
      return PlayerGameProjection.fromJson(_object(body['data']));
    } on FormatException {
      throw const GameSessionContractException('本局玩家状态不可用', isLocal: true);
    }
  }

  @override
  Future<ClubRecapState> loadClubView({required int activityId}) async {
    if (activityId <= 0) throw const GameSessionContractException('活动参数无效', isLocal: true);
    final body = await _get(
      '/api/game/session/view',
      query: <String, dynamic>{'activityId': activityId, 'perspective': 'CLUB'},
    );
    final raw = _object(body['data']);
    // 身份三重对齐小程序 game-session-client 的 validProjectionIdentity:
    // perspective / activityId / revision,外加「未准备」态允许没有 sessionId
    // (别的状态没有 sessionId 就是坏回执,不能当成空进度)。
    final int? revision = _safeInteger(raw['revision']);
    final bool notPrepared =
        _text(raw['status']) == 'NOT_PREPARED' && raw['sessionId'] == null;
    if (_text(raw['perspective']).toUpperCase() != 'CLUB' ||
        _safePositiveInteger(raw['activityId']) != activityId ||
        revision == null ||
        revision < 0 ||
        (_safePositiveInteger(raw['sessionId']) == null && !notPrepared)) {
      throw const GameSessionContractException('本局复盘状态不可用', isLocal: true);
    }
    final Object? recap = raw['recap'];
    return ClubRecapState(
      recapAvailable: recap is Map<String, dynamic>,
      exportAvailable:
          recap is Map<String, dynamic> && recap['exportAvailable'] == true,
    );
  }

  @override
  Future<Map<String, dynamic>> loadClubRecapExport({
    required int activityId,
  }) async {
    if (activityId <= 0) throw const GameSessionContractException('活动参数无效', isLocal: true);
    final body = await _get(
      '/api/game/session/recap/export',
      query: <String, dynamic>{'activityId': activityId},
    );
    // 真源 `copyRecap` 复制的是 normalize 之后的**白名单**结构,不是原始响应:
    // 信封 / 身份 / 逐字段任一不合格就整份拒绝(与真源同句文案),坏数据不进剪贴板。
    final Map<String, dynamic>? normalized = normalizeClubRecapExport(
      body['data'],
      activityId: activityId,
    );
    if (normalized == null) {
      throw const GameSessionContractException('复盘导出数据无效', isLocal: true);
    }
    return normalized;
  }

  @override
  Future<ClubDirectorProjection> loadClubProjection({
    required int activityId,
  }) async {
    if (activityId <= 0) throw const GameSessionContractException('活动参数无效', isLocal: true);
    final body = await _get(
      '/api/game/session/view',
      query: <String, dynamic>{'activityId': activityId, 'perspective': 'CLUB'},
    );
    final ClubDirectorProjection projection;
    try {
      projection = ClubDirectorProjection.fromJson(_object(body['data']));
    } on ClubDirectorFormatException catch (error) {
      throw GameSessionContractException(error.message, reasonCode: error.code, isLocal: true);
    }
    // 适配器同款闸:别场的投影不许画进这一页(拿错场比报错更危险)。
    if (projection.activityId != activityId) {
      throw const GameSessionContractException(
        '活动导演数据与当前活动不匹配',
        isLocal: true,
        reasonCode: 'PROJECTION_MISMATCH',
      );
    }
    return projection;
  }

  @override
  Future<GameSessionReceipt> submitClubCommand(
    GameSessionCommand command,
  ) async {
    if (!clubDirectorActions.contains(command.action)) {
      throw const GameSessionContractException('导演操作无效', isLocal: true);
    }
    final body = await _post('/api/game/session/command', command.toJson());
    // 与玩家那条同形:回执身份核不上会在这里抛,由控制器一律按「结果待核对」收。
    return _playerReceipt(
      body['data'],
      activityId: command.activityId,
      requestId: command.requestId,
      expectedAction: command.action,
    );
  }

  @override
  Future<GameSessionReceipt> readClubReceipt({
    required int activityId,
    required String requestId,
    required String expectedAction,
  }) => readReceipt(
    activityId: activityId,
    requestId: requestId,
    expectedAction: expectedAction,
  );

  @override
  Future<GameSessionReceipt> submitPlayerCommand(
    GameSessionCommand command,
  ) async {
    if (!const <String>{
      'CONFIRM_ROLE',
      'PLAYER_CHOICE',
      'PLAYER_SUBMIT',
      'PLAYER_HINT',
      'PLAYER_REVEAL',
    }.contains(command.action)) {
      throw const GameSessionContractException('玩家操作无效', isLocal: true);
    }
    final body = await _post('/api/game/session/command', command.toJson());
    return _playerReceipt(
      body['data'],
      activityId: command.activityId,
      requestId: command.requestId,
      expectedAction: command.action,
    );
  }

  @override
  Future<GameSessionReceipt> readPlayerReceipt({
    required int activityId,
    required String requestId,
    required String expectedAction,
  }) async {
    final body = await _get(
      '/api/game/session/receipt',
      query: <String, dynamic>{
        'activityId': activityId,
        'requestId': requestId,
      },
    );
    return _playerReceipt(
      body['data'],
      activityId: activityId,
      requestId: requestId,
      expectedAction: expectedAction,
    );
  }

  @override
  Future<GameSessionReceipt> submitAndReadReceipt(
    GameSessionCommand command,
  ) async {
    await _post('/api/game/session/command', command.toJson());
    return readReceipt(
      activityId: command.activityId,
      requestId: command.requestId,
      expectedAction: command.action,
    );
  }

  @override
  Future<GameSessionReceipt> readReceipt({
    required int activityId,
    required String requestId,
    required String expectedAction,
  }) async {
    final body = await _get(
      '/api/game/session/receipt',
      query: <String, dynamic>{
        'activityId': activityId,
        'requestId': requestId,
      },
    );
    final raw = _object(body['data']);
    final outcomeText = raw['outcome'] is String
        ? raw['outcome'] as String
        : '';
    final outcome = switch (outcomeText) {
      'APPLIED' => GameReceiptOutcome.applied,
      'FAILED' => GameReceiptOutcome.failed,
      _ => GameReceiptOutcome.pending,
    };
    final receipt = GameSessionReceipt(
      activityId: _safeInteger(raw['activityId']) ?? 0,
      requestId: raw['requestId'] is String ? raw['requestId'] as String : '',
      action: raw['action'] is String ? raw['action'] as String : '',
      outcome: outcome,
      receiptId: (_safePositiveInteger(raw['receiptId']) ?? '').toString(),
      revision: _safeInteger(raw['revision']) ?? -1,
    );
    final identityMatches =
        receipt.activityId == activityId &&
        receipt.requestId == requestId &&
        receipt.action == expectedAction;
    if (identityMatches &&
        receipt.outcome == GameReceiptOutcome.failed &&
        receipt.receiptId.isNotEmpty &&
        receipt.revision >= 0) {
      final result = raw['result'];
      final rawReason = result is Map<String, dynamic>
          ? (result['reason'] ?? '').toString().trim()
          : '';
      final reason =
          rawReason.length <= 300 &&
              !RegExp(
                r'(?:/api/|exception|\.java\b|\bselect\b)',
                caseSensitive: false,
              ).hasMatch(rawReason)
          ? rawReason
          : '';
      throw GameSessionRejectedException(reason.isEmpty ? '操作未能完成' : reason, isLocal: reason.isEmpty);
    }
    if (!identityMatches ||
        receipt.outcome != GameReceiptOutcome.applied ||
        receipt.receiptId.isEmpty ||
        receipt.revision < 0) {
      throw const GameSessionContractException('操作结果尚未确认，请刷新本站状态', isLocal: true);
    }
    return receipt;
  }

  GameSessionReceipt _playerReceipt(
    Object? value, {
    required int activityId,
    required String requestId,
    required String expectedAction,
  }) {
    final raw = _object(value);
    final rawOutcome = raw['outcome'] is String ? raw['outcome'] as String : '';
    final outcome = switch (rawOutcome) {
      'APPLIED' => GameReceiptOutcome.applied,
      'FAILED' => GameReceiptOutcome.failed,
      'PENDING' => GameReceiptOutcome.pending,
      _ => null,
    };
    final rawActivityId = _safeInteger(raw['activityId']);
    final rawRevision = _safeInteger(raw['revision']);
    final Object? rawReceiptId = raw['receiptId'];
    final int? receiptId = _safePositiveInteger(rawReceiptId);
    if (outcome == null ||
        rawActivityId == null ||
        rawRevision == null ||
        (rawReceiptId != null && receiptId == null)) {
      throw const GameSessionContractException('操作结果身份无法确认', isLocal: true);
    }
    final receipt = GameSessionReceipt(
      activityId: rawActivityId,
      requestId: raw['requestId'] is String ? raw['requestId'] as String : '',
      action: raw['action'] is String ? raw['action'] as String : '',
      outcome: outcome,
      receiptId: (receiptId ?? '').toString(),
      revision: rawRevision,
      result: raw['result'] is Map<String, dynamic>
          ? Map<String, dynamic>.unmodifiable(
              raw['result'] as Map<String, dynamic>,
            )
          : const <String, dynamic>{},
    );
    if (receipt.activityId != activityId ||
        receipt.requestId != requestId ||
        receipt.action != expectedAction ||
        receipt.revision < 0 ||
        (receipt.outcome != GameReceiptOutcome.pending &&
            receipt.receiptId.isEmpty)) {
      throw const GameSessionContractException('操作结果身份无法确认', isLocal: true);
    }
    return receipt;
  }

  int? _safeInteger(Object? value) {
    const maxSafeInteger = 9007199254740991;
    return value is int && value.abs() <= maxSafeInteger ? value : null;
  }

  int? _safePositiveInteger(Object? value) {
    final int? parsed = _safeInteger(value);
    return parsed != null && parsed > 0 ? parsed : null;
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      path,
      queryParameters: query,
      options: RequestSessionScope.options(),
    );
    return _success(response.data);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> data,
  ) async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      path,
      data: data,
      options: RequestSessionScope.options(),
    );
    return _success(response.data);
  }

  Map<String, dynamic> _success(Map<String, dynamic>? body) {
    final value = body ?? <String, dynamic>{};
    if ((value['code'] as num?)?.toInt() != 200) {
      final Object? rawData = value['data'];
      final String candidate = rawData is Map<String, dynamic>
          ? _text(rawData['reasonCode']).toUpperCase()
          : '';
      final String? reasonCode =
          RegExp(r'^[A-Z][A-Z0-9_]{2,63}$').hasMatch(candidate)
          ? candidate
          : null;
      throw GameSessionContractException(
        (value['msg'] ?? '请求失败').toString(),
        isLocal: value['msg'] == null,
        reasonCode: reasonCode,
      );
    }
    return value;
  }

  Map<String, dynamic> _object(Object? value) => value is Map<String, dynamic>
      ? value
      : throw const GameSessionContractException('服务端返回不完整', isLocal: true);

  String _text(Object? value) => value is String ? value.trim() : '';
}
