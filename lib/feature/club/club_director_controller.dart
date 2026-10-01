import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/providers.dart';
import '../../core/network/session_data.dart';
import '../../core/network/request_session_scope.dart';
import '../auth/auth_controller.dart';
import '../../data/api/game_session_api.dart';
import '../../data/models/club_director.dart';
import 'club_login_gate.dart';

/// 活动导演台(4-C)。逐条对齐小程序真源
/// `pages/club/topic-detail/director.js` 的状态机 +
/// `utils/club-game-director-adapter.js` 的写安全收敛:
/// 每一条写都**先落存根再发** —— 网络断在「发出去了」和「没发出去」之间时,
/// 唯一能把结果收敛掉的入口是用原 requestId 回读(核对结果)或幂等重放
/// (重试原操作)。丢了这两个出口,主理人只能靠猜。
///
/// 与玩家线 `player_game_module_controller.dart` 是同构的,但两边不合并:
/// 导演台的锁定语义更狠(unknown-write 锁**全部**写,玩家只锁本站),
/// 文案也各自跟自己的真源,并成一个控制器必然两头失真。

/// 写状态机(小程序 `writeState` 的五个取值)。
enum ClubDirectorWriteState {
  idle,
  submitting,
  unknownWrite,
  receiptReading,
  storageError,
}

/// 投影读取态(小程序 `loadState`:loading/ready/empty/network-error/business-error)。
enum ClubDirectorLoadState {
  loading,
  ready,
  empty,
  networkError,
  businessError,
}

/// 一次写请求的结果(页面据此决定 toast;终态同时已写进 [ClubDirectorState])。
enum ClubDirectorWriteResult {
  /// 被闸门挡下(锁定中 / 投影没就绪 / 草稿不合法),没有发出任何东西。
  blocked,

  /// 回执 APPLIED:服务端确认生效。
  confirmed,

  /// 终态回执 FAILED:明确没生效。
  rejected,

  /// 结果未知:已锁定全部写,只能核对或重放。
  unknown,
}

/// 「预计恢复时间」:后端强制必填,不接受「暂停到不知道什么时候」(真源同话)。
String clubDirectorResumeEta(DateTime from, {int minutes = 30}) {
  final DateTime d = from.add(Duration(minutes: minutes));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} '
      '${two(d.hour)}:${two(d.minute)}:00';
}

/// 在途写的存根(小程序 `pendingWrite` 收据索引 + 完整原命令)。
/// 收据索引够核对;带上 payload 才能让「重试原操作」在杀进程后仍然可重放
/// —— 小程序重试用的是内存里的原命令,杀了就只能核对,App 侧不做这个退化。
class ClubDirectorPendingWrite {
  const ClubDirectorPendingWrite({
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

  factory ClubDirectorPendingWrite.fromCommand(GameSessionCommand command) =>
      ClubDirectorPendingWrite(
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

  factory ClubDirectorPendingWrite.fromJson(Map<String, dynamic> json) {
    final Object? rawNodeId = json['nodeId'];
    return ClubDirectorPendingWrite(
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

  /// 与命令构造同一套闸:坏存根宁可当没有,也不能被当成可重放的原命令。
  bool get valid =>
      activityId > 0 &&
      (nodeId == null || nodeId! > 0) &&
      expectedRevision >= 0 &&
      RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(requestId) &&
      clubDirectorActions.contains(action) &&
      (clubDirectorNodeActions.contains(action)
          ? nodeId != null
          : nodeId == null);
}

class ClubDirectorPendingStore {
  ClubDirectorPendingStore(this._storage, {this.ownerId});
  ClubDirectorPendingStore.memory({this.ownerId}) : _storage = null;

  final int? ownerId;

  final FlutterSecureStorage? _storage;
  ClubDirectorPendingWrite? _memory;

  String _key(int activityId) => ownerId == null
      ? 'club_director_pending_v1_$activityId'
      : 'club_director_pending_v2_${ownerId}_$activityId';

  /// Unowned legacy data is never exposed, migrated, replayed, or deleted.
  /// Presence alone blocks new commands until ownership can be established.
  Future<bool> hasUnownedLegacy(int activityId) async {
    if (_storage == null || ownerId == null || activityId <= 0) return false;
    return await _storage.read(key: 'club_director_pending_v1_$activityId') != null;
  }

  Future<ClubDirectorPendingWrite?> read(int activityId) async {
    if (activityId <= 0) return null;
    if (_storage == null) {
      final ClubDirectorPendingWrite? value = _memory;
      return value != null && value.activityId == activityId ? value : null;
    }
    final String? raw = await _storage.read(key: _key(activityId));
    if (raw == null) return null;
    try {
      final Object? value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) return null;
      final ClubDirectorPendingWrite pending =
          ClubDirectorPendingWrite.fromJson(value);
      return pending.valid && pending.activityId == activityId ? pending : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> write(ClubDirectorPendingWrite value) async {
    if (!value.valid) {
      throw const FormatException('INVALID_CLUB_DIRECTOR_PENDING_WRITE');
    }
    if (_storage == null) {
      _memory = value;
      return;
    }
    await _storage.write(
      key: _key(value.activityId),
      value: jsonEncode(value.toJson()),
    );
  }

  Future<void> clear(int activityId) async {
    if (_storage == null) {
      _memory = null;
      return;
    }
    await _storage.delete(key: _key(activityId));
  }
}

/// Provenance for copy created locally by this controller; never inferred from text.
enum ClubDirectorLocalMessage {
  legacyOwnerUnknown,
  ownerRequired,
  projectionMismatch,
  recoveredPending,
  versionPending,
  submitting,
  storageFailed,
  resultPending,
  requestPending,
  rejected,
  readingReceipt,
  stillPending,
  verificationUnavailable,
  retryStorageFailed,
  retrying,
  retryPending,
  loadUnavailable,
  needsSession,
  networkUnavailable,
}

enum ClubDirectorReconcileResult { confirmed, rejected }

class ClubDirectorState {
  const ClubDirectorState({
    required this.activityId,
    this.load = ClubDirectorLoadState.loading,
    this.errorText = '',
    this.localErrorMessage,
    this.projection,
    this.writeState = ClubDirectorWriteState.idle,
    this.writeMessage = '',
    this.localWriteMessage,
    this.canRetryUnknownWrite = false,
    this.refreshTick = 0,
    this.loginRequired = false,
  });

  final int activityId;
  final ClubDirectorLoadState load;
  final String errorText;
  final ClubDirectorLocalMessage? localErrorMessage;
  final ClubDirectorProjection? projection;
  final ClubDirectorWriteState writeState;
  final String writeMessage;
  final ClubDirectorLocalMessage? localWriteMessage;

  /// 「重试原操作」出不出(小程序 `canRetryUnknownWrite`)。
  final bool canRetryUnknownWrite;

  /// 后端以 401 表态「没登录/登录过期」(#258 口径:401 ≠ 无权限 ≠ 网络错)。
  /// 页面据此把导演台格子换成登录引导,而不是「暂时无法打开/查网络」的死路。
  final bool loginRequired;

  /// 每次写被服务端确认 +1。宿主页 listen 它去回读主题详情
  /// (director.js 写成功后一起 `fetchDetail()`:核销数/场次都在变)。
  final int refreshTick;

  /// unknown-write 锁**全部**写 —— 这不是提示,是安全出口没按下去之前的闸门。
  bool get writeLocked =>
      writeState == ClubDirectorWriteState.submitting ||
      writeState == ClubDirectorWriteState.unknownWrite ||
      writeState == ClubDirectorWriteState.receiptReading;

  ClubDirectorState copyWith({
    ClubDirectorLoadState? load,
    String? errorText,
    ClubDirectorLocalMessage? localErrorMessage,
    ClubDirectorProjection? projection,
    ClubDirectorWriteState? writeState,
    String? writeMessage,
    ClubDirectorLocalMessage? localWriteMessage,
    bool? canRetryUnknownWrite,
    int? refreshTick,
    bool? loginRequired,
  }) => ClubDirectorState(
    activityId: activityId,
    load: load ?? this.load,
    errorText: errorText ?? this.errorText,
    localErrorMessage: localErrorMessage ?? (errorText == null ? this.localErrorMessage : null),
    projection: projection ?? this.projection,
    writeState: writeState ?? this.writeState,
    writeMessage: writeMessage ?? this.writeMessage,
    localWriteMessage: localWriteMessage ?? (writeMessage == null ? this.localWriteMessage : null),
    canRetryUnknownWrite: canRetryUnknownWrite ?? this.canRetryUnknownWrite,
    refreshTick: refreshTick ?? this.refreshTick,
    loginRequired: loginRequired ?? this.loginRequired,
  );
}

final clubDirectorApiProvider = Provider<ClubDirectorGateway>((ref) {
  ref.watch(sessionDataKeyProvider);
  return GameSessionApi(ref.watch(dioClientProvider));
});

final clubDirectorPendingStoreProvider = Provider<ClubDirectorPendingStore>((
  ref,
) {
  return ClubDirectorPendingStore(
    const FlutterSecureStorage(),
    ownerId: ref.watch(sessionDataKeyProvider).userId,
  );
});

/// 一局的导演台。宿主在活动确定且 canDirect 时开一次 [load]。
class ClubDirectorController extends Notifier<ClubDirectorState> {
  ClubDirectorController(this.activityId);

  final int activityId;
  GameSessionCommand? _pendingCommand;
  String _unknownRequestId = '';
  bool _loadInFlight = false;
  int _requestSequence = 0;

  ClubDirectorGateway get _gateway => ref.read(clubDirectorApiProvider);
  ClubDirectorPendingStore get _store =>
      ref.read(clubDirectorPendingStoreProvider);

  @override
  ClubDirectorState build() {
    ref.watch(sessionDataKeyProvider);
    _generation += 1;
    _pendingCommand = null;
    _unknownRequestId = '';
    _loadInFlight = false;
    return ClubDirectorState(activityId: activityId);
  }

  int _generation = 0;
  bool get _current => ref.mounted &&
      RequestSessionScope.current?.isCurrent() == true;

  Future<T> _owned<T>(T stale, Future<T> Function() action) async {
    if (!ref.mounted) return stale;
    final key = ref.read(sessionDataKeyProvider);
    final owner = key.userId;
    if (owner == null || key.loading || !key.initialized) return stale;
    final generation = _generation;
    final auth = ref.read(authControllerProvider.notifier).requestScope(owner);
    final scope = RequestSessionScope(() => ref.mounted &&
        generation == _generation &&
        ref.read(sessionDataKeyProvider) == key && auth.isCurrent());
    if (!scope.isCurrent()) return stale;
    final result = await RequestSessionScope.run(scope, action);
    return scope.isCurrent() ? result : stale;
  }

  /// 小程序 `initDirector` + `loadProjection`:先收敛上次没收敛的写,再拉投影;
  /// 投影就绪后自动核对一次(核对不重发)。
  Future<void> load() => _owned<void>(null, _loadOwned);

  Future<void> _loadOwned() async {
    if (_loadInFlight || activityId <= 0) return;
    _loadInFlight = true;
    try {
      state = state.copyWith(
        load: ClubDirectorLoadState.loading,
        errorText: '',
      );
      final legacyBlocked = await _store.hasUnownedLegacy(activityId);
      if (!_current) return;
      final restored = legacyBlocked ? null : await _restorePending();
      if (!_current) return;
      if (legacyBlocked) {
        _pendingCommand = null;
        _unknownRequestId = '';
      } else {
        _pendingCommand ??= restored;
      }
      if (legacyBlocked && _pendingCommand == null) {
        state = state.copyWith(
          writeState: ClubDirectorWriteState.unknownWrite,
          writeMessage: '存在无法确认归属的历史操作，写操作保持锁定',
          localWriteMessage: ClubDirectorLocalMessage.legacyOwnerUnknown,
          canRetryUnknownWrite: false,
        );
      }
      if (_pendingCommand != null) {
        _unknownRequestId = _pendingCommand!.requestId;
        state = state.copyWith(
          writeState: ClubDirectorWriteState.unknownWrite,
          writeMessage: '检测到上次未确认的操作，正在准备核对',
          localWriteMessage: ClubDirectorLocalMessage.recoveredPending,
          canRetryUnknownWrite: true,
        );
      }
      final bool ready = await _loadProjection();
      if (_current && ready && state.writeLocked && _unknownRequestId.isNotEmpty) {
        await reconcile();
      }
    } finally {
      if (_current) _loadInFlight = false;
    }
  }

  Future<GameSessionCommand?> _restorePending() async {
    final store = _store;
    try {
      final ClubDirectorPendingWrite? pending = await store.read(activityId);
      if (!_current) return null;
      if (pending == null) return null;
      return pending.toCommand();
    } on FormatException {
      if (!_current) return null;
      await store.clear(activityId);
      return null;
    }
  }

  Future<bool> _loadProjection() async {
    if (!_current) return false;
    try {
      final ClubDirectorProjection projection = await _gateway
          .loadClubProjection(activityId: activityId);
      if (!_current) return false;
      state = state.copyWith(
        load: ClubDirectorLoadState.ready,
        errorText: '',
        projection: projection,
        loginRequired: false,
      );
      return true;
    } catch (error) {
      if (!_current) return false;
      state = state.copyWith(
        load: _classifyLoadFailure(error),
        errorText: _loadFailureText(error),
        localErrorMessage: _loadFailureMessage(error),
        loginRequired: clubLoginRequired(error),
      );
      return false;
    }
  }

  /// 小程序 `classifyLoadError`:「局不存在」是空态,不是报错。
  ClubDirectorLoadState _classifyLoadFailure(Object error) {
    if (error is GameSessionContractException) {
      const Set<String> absentCodes = <String>{
        'SESSION_NOT_FOUND',
        'NOT_FOUND',
        'GAME_SESSION_NOT_FOUND',
      };
      if (absentCodes.contains(error.reasonCode)) {
        return ClubDirectorLoadState.empty;
      }
      return ClubDirectorLoadState.businessError;
    }
    if (error is DioException && error.type != DioExceptionType.badResponse) {
      return ClubDirectorLoadState.networkError;
    }
    return ClubDirectorLoadState.businessError;
  }

  ClubDirectorLocalMessage? _loadFailureMessage(Object error) {
    if (error is GameSessionContractException) {
      if (error.isLocal) {
        return switch (error.reasonCode) {
          'OWNER_REQUIRED' => ClubDirectorLocalMessage.ownerRequired,
          'PROJECTION_MISMATCH' => ClubDirectorLocalMessage.projectionMismatch,
          'SESSION_NOT_FOUND' || 'NOT_FOUND' || 'GAME_SESSION_NOT_FOUND' => ClubDirectorLocalMessage.needsSession,
          _ => ClubDirectorLocalMessage.loadUnavailable,
        };
      }
      return error.message.isEmpty ? ClubDirectorLocalMessage.loadUnavailable : null;
    }
    if (state.load == ClubDirectorLoadState.empty) {
      return ClubDirectorLocalMessage.needsSession;
    }
    return error is DioException
        ? ClubDirectorLocalMessage.networkUnavailable
        : ClubDirectorLocalMessage.loadUnavailable;
  }

  String _loadFailureText(Object error) {
    if (error is GameSessionContractException) {
      return error.message.isEmpty ? '活动导演台暂时无法打开' : error.message;
    }
    if (state.load == ClubDirectorLoadState.empty) {
      return '先从俱乐部管理区开一场，再进入导演台。';
    }
    return error is DioException ? '网络不可用，请稍后重试' : '活动导演台暂时无法打开';
  }

  // ─── 三态主链:PREPARE / START / FINISH ───
  //
  // 「当前不能进入准备 / 准备未完成,暂时不能开局 / 当前不能结束活动」这三句闸
  // 在页面(确认弹层开出来之前),和小程序 onPrepareSession/onStartSession/
  // onFinishSession 的落点一致;控制器只兜底执行安全(锁定中/没投影/没版本号不发)。

  Future<ClubDirectorWriteResult> prepare() =>
      _execute('PREPARE', const <String, dynamic>{});

  Future<ClubDirectorWriteResult> start() =>
      _execute('START', const <String, dynamic>{});

  Future<ClubDirectorWriteResult> finish() =>
      _execute('FINISH', const <String, dynamic>{});

  // ─── D4–D8 与榜单的写 ───

  Future<ClubDirectorWriteResult> assignRole({
    required int teamId,
    required int memberId,
    required String roleCode,
  }) {
    final ClubDirectorProjection? p = state.projection;
    if (p == null || !p.canAssignRoles) {
      return Future<ClubDirectorWriteResult>.value(
        ClubDirectorWriteResult.blocked,
      );
    }
    return _execute('ASSIGN_ROLES', <String, dynamic>{
      'teamId': teamId,
      'assignments': <Map<String, dynamic>>[
        <String, dynamic>{'memberId': memberId, 'roleCode': roleCode},
      ],
    });
  }

  /// 接管:来源必须已确认、目标是同队无角色成员、原因 1–200
  /// (小程序 `takeoverPayload` 的闸,不合法不发)。
  Future<ClubDirectorWriteResult> takeover({
    required int teamId,
    required int sourceMemberId,
    required int targetMemberId,
    required String reason,
  }) {
    final ClubDirectorProjection? p = state.projection;
    final ClubDirectorTakeover? payload = p == null
        ? null
        : ClubDirectorTakeover.validate(
            roles: p.roles,
            teamId: teamId,
            sourceMemberId: sourceMemberId,
            targetMemberId: targetMemberId,
            reason: reason,
          );
    if (p == null || !p.canTakeoverRoles || payload == null) {
      return Future<ClubDirectorWriteResult>.value(
        ClubDirectorWriteResult.blocked,
      );
    }
    return _execute('TAKEOVER_ROLE', payload.toPayload());
  }

  Future<ClubDirectorWriteResult> broadcast({
    required String targetType,
    required String content,
    Object? targetId,
    String? roleCode,
  }) {
    final ClubDirectorProjection? p = state.projection;
    if (p == null || !p.canBroadcast) {
      return Future<ClubDirectorWriteResult>.value(
        ClubDirectorWriteResult.blocked,
      );
    }
    final Map<String, dynamic> payload = <String, dynamic>{
      'targetType': targetType,
      'content': content,
    };
    if (targetType == 'TEAM' && targetId != null) {
      payload['targetId'] = targetId;
    }
    if (targetType == 'ROLE' && roleCode != null) {
      payload['roleCode'] = roleCode;
    }
    return _execute('BROADCAST', payload);
  }

  Future<ClubDirectorWriteResult> unlockChapter({
    required int chapterId,
    required String reason,
  }) {
    final ClubDirectorProjection? p = state.projection;
    if (p == null ||
        !p.canUnlockChapter ||
        reason.trim().isEmpty ||
        !p.unlockChapterOptions.any(
          (ClubDirectorChapterOption o) => o.chapterId == chapterId,
        )) {
      return Future<ClubDirectorWriteResult>.value(
        ClubDirectorWriteResult.blocked,
      );
    }
    return _execute('UNLOCK_CHAPTER', <String, dynamic>{
      'chapterId': chapterId,
      'reason': reason.trim(),
    });
  }

  Future<ClubDirectorWriteResult> setLeaderboardVisibility(bool visible) {
    final ClubDirectorProjection? p = state.projection;
    if (p == null || !p.canToggleLeaderboard) {
      return Future<ClubDirectorWriteResult>.value(
        ClubDirectorWriteResult.blocked,
      );
    }
    return _execute('SET_LEADERBOARD_VISIBILITY', <String, dynamic>{
      'visible': visible,
    });
  }

  /// 暂停本站。方案不是这里挑的:没有 → 只停本站;恰好一个 → 带上;
  /// 多个 → 不替主理人挑也不丢(页面先挡:「有多个备用方案，请到后台指定」)。
  Future<ClubDirectorWriteResult> stationPause(
    int nodeId, {
    required String reason,
    ClubDirectorFallbackPlan? plan,
    DateTime? now,
  }) {
    final ClubDirectorProjection? p = state.projection;
    if (p == null ||
        !p.hasAction('CLUB_STATION_PAUSE') ||
        reason.trim().length < 2) {
      return Future<ClubDirectorWriteResult>.value(
        ClubDirectorWriteResult.blocked,
      );
    }
    final Map<String, dynamic> payload = <String, dynamic>{
      'reasonCode': 'ONSITE',
      'reason': reason.trim(),
      'resumeEta': clubDirectorResumeEta(now ?? DateTime.now()),
    };
    if (plan != null) {
      payload['fallbackPlanCode'] = plan.planCode;
      payload['fallbackPlanVersion'] = plan.version;
    }
    return _execute('CLUB_STATION_PAUSE', payload, nodeId: nodeId);
  }

  Future<ClubDirectorWriteResult> stationResume(int nodeId) {
    final ClubDirectorProjection? p = state.projection;
    if (p == null || !p.hasAction('CLUB_STATION_RESUME')) {
      return Future<ClubDirectorWriteResult>.value(
        ClubDirectorWriteResult.blocked,
      );
    }
    return _execute(
      'CLUB_STATION_RESUME',
      const <String, dynamic>{},
      nodeId: nodeId,
    );
  }

  /// 驳回重交。俱乐部拿不到证据内容,所以只有「打回重交」,没有「通过」(真源)。
  Future<ClubDirectorWriteResult> rejectSubmission({
    required int submissionId,
    required String reason,
  }) {
    final ClubDirectorProjection? p = state.projection;
    if (p == null ||
        !p.hasAction('CLUB_REJECT_SUBMISSION') ||
        reason.trim().length < 2) {
      return Future<ClubDirectorWriteResult>.value(
        ClubDirectorWriteResult.blocked,
      );
    }
    return _execute('CLUB_REJECT_SUBMISSION', <String, dynamic>{
      'submissionId': submissionId,
      'reasonCode': 'ONSITE_REJECT',
      'reason': reason.trim(),
    });
  }

  // ─── 写入安全内核(executeAction / onReconcile / retry 三件套) ───

  Future<ClubDirectorWriteResult> _execute(
    String action,
    Map<String, dynamic> payload, {
    int? nodeId,
  }) {
    if (!ref.mounted || state.load != ClubDirectorLoadState.ready) {
      return Future.value(ClubDirectorWriteResult.blocked);
    }
    return _owned(ClubDirectorWriteResult.unknown,
        () => _executeOwned(action, payload, nodeId: nodeId));
  }

  Future<ClubDirectorWriteResult> _executeOwned(
    String action,
    Map<String, dynamic> payload, {
    int? nodeId,
  }) async {
    if (state.writeLocked) return ClubDirectorWriteResult.blocked;
    if (state.load != ClubDirectorLoadState.ready) {
      return ClubDirectorWriteResult.blocked;
    }
    final int? revision = state.projection?.revision;
    if (revision == null) {
      state = state.copyWith(
        writeMessage: '状态版本待确认，请先重新加载',
        localWriteMessage: ClubDirectorLocalMessage.versionPending,
        canRetryUnknownWrite: false,
      );
      return ClubDirectorWriteResult.blocked;
    }
    final GameSessionCommand command;
    try {
      command = GameSessionCommand(
        activityId: activityId,
        nodeId: nodeId,
        requestId: _nextRequestId(),
        expectedRevision: revision,
        action: action,
        payload: payload,
      );
    } on FormatException {
      return ClubDirectorWriteResult.blocked;
    }
    state = state.copyWith(
      writeState: ClubDirectorWriteState.submitting,
      writeMessage: '正在提交…',
      localWriteMessage: ClubDirectorLocalMessage.submitting,
      canRetryUnknownWrite: false,
    );
    _unknownRequestId = '';
    _pendingCommand = command;
    final saved = await _savePending(command);
    if (!_current) return ClubDirectorWriteResult.unknown;
    if (!saved) {
      _pendingCommand = null;
      state = state.copyWith(
        writeState: ClubDirectorWriteState.storageError,
        writeMessage: '无法安全保存本次操作，请检查存储后重试',
        localWriteMessage: ClubDirectorLocalMessage.storageFailed,
        canRetryUnknownWrite: false,
      );
      return ClubDirectorWriteResult.blocked;
    }
    try {
      final GameSessionReceipt receipt = await _gateway.submitClubCommand(
        command,
      );
      if (!_current) return ClubDirectorWriteResult.unknown;
      switch (receipt.outcome) {
        case GameReceiptOutcome.applied:
          return await _settleConfirmed(notifyHost: true);
        case GameReceiptOutcome.failed:
          await _settleRejectedTerminal();
          return ClubDirectorWriteResult.rejected;
        case GameReceiptOutcome.pending:
          _unknownRequestId = command.requestId;
          state = state.copyWith(
            writeState: ClubDirectorWriteState.unknownWrite,
            writeMessage: '结果待核对，核对前已锁定全部写操作',
            localWriteMessage: ClubDirectorLocalMessage.resultPending,
            canRetryUnknownWrite: true,
          );
          return ClubDirectorWriteResult.unknown;
      }
    } catch (_) {
      if (!_current) return ClubDirectorWriteResult.unknown;
      // 真源的口径:拿不到**终态回执**就一律算「发没发出去不确定」—— 连业务
      // 报错也不例外(服务端明确拒绝会给一张 FAILED 回执,走上面那条分支)。
      // 把信封错误当「明确没生效」放行,才是真的危险。
      _unknownRequestId = command.requestId;
      state = state.copyWith(
        writeState: ClubDirectorWriteState.unknownWrite,
        writeMessage: '请求结果待核对，核对前已锁定全部写操作',
        localWriteMessage: ClubDirectorLocalMessage.requestPending,
        canRetryUnknownWrite: true,
      );
      return ClubDirectorWriteResult.unknown;
    }
  }

  Future<void> _settleRejectedTerminal() async {
    if (!_current) return;
    await _store.clear(activityId);
    if (!_current) return;
    _pendingCommand = null;
    _unknownRequestId = '';
    state = state.copyWith(
      writeState: ClubDirectorWriteState.idle,
      writeMessage: '操作未生效，请刷新后重试',
      localWriteMessage: ClubDirectorLocalMessage.rejected,
      canRetryUnknownWrite: false,
    );
  }

  Future<ClubDirectorWriteResult> _settleConfirmed({
    bool notifyHost = false,
  }) async {
    if (!_current) return ClubDirectorWriteResult.unknown;
    await _store.clear(activityId);
    if (!_current) return ClubDirectorWriteResult.unknown;
    _pendingCommand = null;
    _unknownRequestId = '';
    state = state.copyWith(
      writeState: ClubDirectorWriteState.idle,
      writeMessage: '',
      canRetryUnknownWrite: false,
      // executeAction 的成功路径要带宿主页一起刷(核销数/场次都在变);
      // 核对/重试收敛回来只重拉投影就够。
      refreshTick: notifyHost ? state.refreshTick + 1 : state.refreshTick,
    );
    await _loadProjection();
    return ClubDirectorWriteResult.confirmed;
  }

  Future<bool> _savePending(GameSessionCommand command) async {
    if (!_current) return false;
    try {
      await _store.write(ClubDirectorPendingWrite.fromCommand(command));
      return true;
    } catch (_) {
      return false;
    }
  }

  String _nextRequestId() {
    _requestSequence += 1;
    return 'gd-$activityId-${DateTime.now().millisecondsSinceEpoch}-$_requestSequence';
  }

  /// 「核对结果」:用原 requestId 回读,不重发。返回要提示的话(可 null)。
  Future<String?> reconcile() async => switch (await reconcileOutcome()) {
    ClubDirectorReconcileResult.confirmed => '结果已确认',
    ClubDirectorReconcileResult.rejected => '操作未生效',
    null => null,
  };

  Future<ClubDirectorReconcileResult?> reconcileOutcome() =>
      _owned<ClubDirectorReconcileResult?>(null, _reconcileOwned);

  Future<ClubDirectorReconcileResult?> _reconcileOwned() async {
    final GameSessionCommand? command = _pendingCommand;
    if (!state.writeLocked || _unknownRequestId.isEmpty || command == null) {
      return null;
    }
    final String requestId = _unknownRequestId;
    state = state.copyWith(
      writeState: ClubDirectorWriteState.receiptReading,
      writeMessage: '正在核对最终结果…',
      localWriteMessage: ClubDirectorLocalMessage.readingReceipt,
    );
    try {
      await _gateway.readClubReceipt(
        activityId: activityId,
        requestId: requestId,
        expectedAction: command.action,
      );
      if (!_current) return null;
      await _settleConfirmed();
      return ClubDirectorReconcileResult.confirmed;
    } on GameSessionRejectedException {
      if (!_current) return null;
      await _settleConfirmed();
      return ClubDirectorReconcileResult.rejected;
    } on GameSessionContractException {
      if (!_current) return null;
      state = state.copyWith(
        writeState: ClubDirectorWriteState.unknownWrite,
        writeMessage: '结果仍待核对，写操作继续锁定',
        localWriteMessage: ClubDirectorLocalMessage.stillPending,
        canRetryUnknownWrite: true,
      );
      return null;
    } catch (_) {
      if (!_current) return null;
      state = state.copyWith(
        writeState: ClubDirectorWriteState.unknownWrite,
        writeMessage: '暂时无法核对，写操作继续锁定',
        localWriteMessage: ClubDirectorLocalMessage.verificationUnavailable,
        canRetryUnknownWrite: true,
      );
      return null;
    }
  }

  /// 「重试原操作」:同一个 requestId + 同一份 payload 重放(服务端幂等)。
  Future<ClubDirectorWriteResult> retryPending() =>
      _owned(ClubDirectorWriteResult.unknown, _retryOwned);

  Future<ClubDirectorWriteResult> _retryOwned() async {
    final GameSessionCommand? command = _pendingCommand;
    if (!state.writeLocked ||
        state.writeState != ClubDirectorWriteState.unknownWrite ||
        command == null) {
      return ClubDirectorWriteResult.blocked;
    }
    final saved = await _savePending(command);
    if (!_current) return ClubDirectorWriteResult.unknown;
    if (!saved) {
      state = state.copyWith(
        writeState: ClubDirectorWriteState.unknownWrite,
        writeMessage: '无法安全保存重试状态；原操作仍待核对',
        localWriteMessage: ClubDirectorLocalMessage.retryStorageFailed,
        canRetryUnknownWrite: true,
      );
      return ClubDirectorWriteResult.blocked;
    }
    state = state.copyWith(
      writeState: ClubDirectorWriteState.submitting,
      writeMessage: '正在用原请求号重试…',
      localWriteMessage: ClubDirectorLocalMessage.retrying,
      canRetryUnknownWrite: false,
    );
    try {
      final GameSessionReceipt receipt = await _gateway.submitClubCommand(
        command,
      );
      if (!_current) return ClubDirectorWriteResult.unknown;
      switch (receipt.outcome) {
        case GameReceiptOutcome.applied:
          return await _settleConfirmed();
        case GameReceiptOutcome.failed:
          await _settleRejectedTerminal();
          await _loadProjection();
          return ClubDirectorWriteResult.rejected;
        case GameReceiptOutcome.pending:
          state = state.copyWith(
            writeState: ClubDirectorWriteState.unknownWrite,
            writeMessage: '结果仍待核对，写操作继续锁定',
            localWriteMessage: ClubDirectorLocalMessage.stillPending,
            canRetryUnknownWrite: true,
          );
          return ClubDirectorWriteResult.unknown;
      }
    } on GameSessionRejectedException {
      if (!_current) return ClubDirectorWriteResult.unknown;
      await _settleRejectedTerminal();
      await _loadProjection();
      return ClubDirectorWriteResult.rejected;
    } on GameSessionContractException {
      if (!_current) return ClubDirectorWriteResult.unknown;
      state = state.copyWith(
        writeState: ClubDirectorWriteState.unknownWrite,
        writeMessage: '重试结果仍待核对，写操作继续锁定',
        localWriteMessage: ClubDirectorLocalMessage.retryPending,
        canRetryUnknownWrite: true,
      );
      return ClubDirectorWriteResult.unknown;
    } catch (_) {
      if (!_current) return ClubDirectorWriteResult.unknown;
      state = state.copyWith(
        writeState: ClubDirectorWriteState.unknownWrite,
        writeMessage: '重试结果仍待核对，写操作继续锁定',
        localWriteMessage: ClubDirectorLocalMessage.retryPending,
        canRetryUnknownWrite: true,
      );
      return ClubDirectorWriteResult.unknown;
    }
  }
}

final clubDirectorProvider =
    NotifierProvider.family<ClubDirectorController, ClubDirectorState, int>(
      ClubDirectorController.new,
    );
