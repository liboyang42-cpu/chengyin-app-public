import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/providers.dart';
import '../../data/api/game_session_api.dart';
import 'player_game_pending_store.dart';

/// 玩家视角的对局会话(独立 provider:商家那份是 `GameSessionGateway`,
/// 替身互不牵连;俱乐部那份只有复盘读,也不要并进来)。
final playerGameSessionApiProvider = Provider<PlayerGameSessionGateway>((ref) {
  return GameSessionApi(ref.watch(dioClientProvider));
});

final playerGamePendingStoreProvider = Provider<PlayerGamePendingStore>((ref) {
  return PlayerGamePendingStore(const FlutterSecureStorage());
});

final playerGameRoleSeenStoreProvider = Provider<PlayerGameRoleSeenStore>((
  ref,
) {
  return PlayerGameRoleSeenStore(const FlutterSecureStorage());
});

/// 写状态机(小程序 `gameModule.write.status` 同一套)。
enum PlayerGameWriteStatus { idle, submitting, confirmed, error, unknown }

/// 本站任务凭证:三种输入类型(TEXT/SCAN/PHOTO)共用一个形状。
///
/// ★ 只活在内存里,不进本地存储 —— 它是「还没提交的现场内容」,
///   断网重进后由玩家自己重新采(小程序同样只在内存里攒)。
class PlayerTaskEvidence {
  const PlayerTaskEvidence({
    this.type = '',
    this.text = '',
    this.evidenceUrls = const <String>[],
    this.statusText = '',
  });

  final String type;
  final String text;
  final List<String> evidenceUrls;
  final String statusText;

  bool get ready => evidenceUrls.isNotEmpty;

  PlayerTaskEvidence copyWith({
    String? type,
    String? text,
    List<String>? evidenceUrls,
    String? statusText,
  }) => PlayerTaskEvidence(
    type: type ?? this.type,
    text: text ?? this.text,
    evidenceUrls: evidenceUrls ?? this.evidenceUrls,
    statusText: statusText ?? this.statusText,
  );
}

class PlayerGameModuleState {
  const PlayerGameModuleState({
    required this.activityId,
    this.loading = false,
    this.enabled = false,
    this.stale = false,
    this.error = '',
    this.projection,
    this.writeStatus = PlayerGameWriteStatus.idle,
    this.writeRequestId = '',
    this.writeMessage = '',
    this.canRetry = false,
    this.evidence = const <int, PlayerTaskEvidence>{},
    this.revealedAnswers = const <int, String>{},
  });

  final int activityId;
  final bool loading;

  /// 服务端给了这一局的玩家投影。没有投影时整块不显示(不是报错态)。
  final bool enabled;

  /// 这次同步失败、界面上是上一次的快照。
  final bool stale;
  final String error;
  final PlayerGameProjection? projection;
  final PlayerGameWriteStatus writeStatus;
  final String writeRequestId;
  final String writeMessage;
  final bool canRetry;
  final Map<int, PlayerTaskEvidence> evidence;
  final Map<int, String> revealedAnswers;

  bool get writeBlocked =>
      writeStatus == PlayerGameWriteStatus.submitting ||
      writeStatus == PlayerGameWriteStatus.unknown;

  /// 章节卡上那枚身份胶囊(小程序 `pcard__role`)的显示条件与文案。
  bool get chipVisible =>
      enabled ||
      error.isNotEmpty ||
      (projection?.role.code.isNotEmpty ?? false);

  String get chipLabel {
    if (error.isNotEmpty) return '状态待同步';
    final String name = projection?.role.name.trim() ?? '';
    return name.isEmpty ? '身份待分配' : name;
  }

  PlayerGameModuleState copyWith({
    bool? loading,
    bool? enabled,
    bool? stale,
    String? error,
    PlayerGameProjection? projection,
    PlayerGameWriteStatus? writeStatus,
    String? writeRequestId,
    String? writeMessage,
    bool? canRetry,
    Map<int, PlayerTaskEvidence>? evidence,
    Map<int, String>? revealedAnswers,
  }) => PlayerGameModuleState(
    activityId: activityId,
    loading: loading ?? this.loading,
    enabled: enabled ?? this.enabled,
    stale: stale ?? this.stale,
    error: error ?? this.error,
    projection: projection ?? this.projection,
    writeStatus: writeStatus ?? this.writeStatus,
    writeRequestId: writeRequestId ?? this.writeRequestId,
    writeMessage: writeMessage ?? this.writeMessage,
    canRetry: canRetry ?? this.canRetry,
    evidence: evidence ?? this.evidence,
    revealedAnswers: revealedAnswers ?? this.revealedAnswers,
  );
}

/// 这一局的玩家模块。页面开一次 `load()`;所有写都先落存根再发,回执为准。
class PlayerGameModuleController extends Notifier<PlayerGameModuleState> {
  PlayerGameModuleController(this.activityId);

  final int activityId;
  PlayerGamePendingWrite? _pending;
  bool _loadInFlight = false;

  PlayerGameSessionGateway get _gateway =>
      ref.read(playerGameSessionApiProvider);

  PlayerGamePendingStore get _store => ref.read(playerGamePendingStoreProvider);

  @override
  PlayerGameModuleState build() =>
      PlayerGameModuleState(activityId: activityId);

  Future<void> load() async {
    if (_loadInFlight || activityId <= 0) return;
    _loadInFlight = true;
    try {
      state = state.copyWith(loading: true, error: '');
      // 上次没收敛的写:进页先用原 requestId 回读,不自动重发。
      if (_pending == null) {
        try {
          _pending = await _store.read(activityId);
        } on FormatException {
          _pending = null;
        }
      }
      if (_pending != null) {
        state = state.copyWith(
          writeStatus: PlayerGameWriteStatus.unknown,
          writeRequestId: _pending!.requestId,
          writeMessage: '正在核对上次操作；不会自动重发现场内容',
          canRetry: false,
        );
        await reconcile(reload: false);
      }
      await _loadProjection();
    } finally {
      _loadInFlight = false;
    }
  }

  Future<void> _loadProjection() async {
    try {
      final PlayerGameProjection projection = await _gateway.loadPlayerView(
        activityId: activityId,
      );
      state = state.copyWith(
        loading: false,
        enabled: true,
        stale: false,
        error: '',
        projection: projection,
      );
    } on GameSessionContractException catch (error) {
      _applyLoadFailure(error.message, absent: _isAbsent(error));
    } catch (_) {
      _applyLoadFailure('本局状态暂未同步', absent: false);
    }
  }

  /// 服务端说「这一局不存在/没准备好/模块关着」——不显示,也不是报错。
  bool _isAbsent(GameSessionContractException error) => const <String>{
    'GAME_SESSION_NOT_FOUND',
    'GAME_SESSION_NOT_PREPARED',
    'GAME_MODULE_DISABLED',
  }.contains(error.reasonCode);

  void _applyLoadFailure(String message, {required bool absent}) {
    final bool retained =
        !absent && state.enabled && (state.projection?.revision ?? -1) >= 0;
    state = state.copyWith(
      loading: false,
      enabled: retained,
      stale: retained,
      error: absent ? '' : message,
    );
  }

  String _requestId(String prefix) {
    final String random = Random.secure().nextInt(1 << 32).toRadixString(16);
    return 'pg-$prefix-$activityId-${DateTime.now().microsecondsSinceEpoch}-$random';
  }

  Future<void> confirmRole() async {
    final PlayerGameProjection? projection = state.projection;
    if (projection == null || !state.enabled || state.writeBlocked) return;
    await _submit(
      GameSessionCommand.playerConfirmRole(
        activityId: activityId,
        requestId: _requestId('role'),
        expectedRevision: projection.revision,
      ),
      submittingMessage: '正在确认身份…',
      confirmedMessage: '身份已确认',
      rejectedMessage: '身份确认未被接受',
      unknownMessage: '身份确认结果待核对，请勿重复提交',
    );
  }

  Future<void> submitChoice(int nodeId, String choiceId) async {
    final PlayerGameProjection? projection = state.projection;
    if (projection == null ||
        !state.enabled ||
        state.writeBlocked ||
        !projection.availableActions.contains('PLAYER_CHOICE')) {
      return;
    }
    await _submit(
      GameSessionCommand.playerChoice(
        activityId: activityId,
        nodeId: nodeId,
        requestId: _requestId('choice-$nodeId'),
        expectedRevision: projection.revision,
        choiceId: choiceId,
      ),
      submittingMessage: '正在记录选择…',
      confirmedMessage: '选择已由服务端记录',
      rejectedMessage: '选择未被接受',
      unknownMessage: '结果待核对，请勿重复提交',
    );
  }

  Future<void> submitTask(
    int nodeId,
    String taskCode,
    List<String> evidenceUrls,
  ) async {
    final PlayerGameProjection? projection = state.projection;
    if (projection == null ||
        !state.enabled ||
        state.writeBlocked ||
        !projection.availableActions.contains('PLAYER_SUBMIT')) {
      return;
    }
    await _submit(
      GameSessionCommand.playerSubmit(
        activityId: activityId,
        nodeId: nodeId,
        requestId: _requestId('submit-$nodeId'),
        expectedRevision: projection.revision,
        taskCode: taskCode,
        evidenceUrls: evidenceUrls,
      ),
      submittingMessage: '正在提交本站任务…',
      confirmedMessage: _taskConfirmedMessage(nodeId),
      rejectedMessage: '本站任务未被接受',
      unknownMessage: '提交结果待核对，请勿重复提交',
      onApplied: (_) =>
          _setEvidence(nodeId, PlayerTaskEvidence(type: _inputTypeOf(nodeId))),
    );
  }

  Future<void> submitHint(int nodeId, int level) async {
    final PlayerGameProjection? projection = state.projection;
    if (projection == null ||
        !state.enabled ||
        state.writeBlocked ||
        !projection.availableActions.contains('PLAYER_HINT')) {
      return;
    }
    await _submit(
      GameSessionCommand.playerHint(
        activityId: activityId,
        nodeId: nodeId,
        requestId: _requestId('hint-$nodeId-$level'),
        expectedRevision: projection.revision,
        level: level,
      ),
      submittingMessage: '正在获取提示…',
      confirmedMessage: '提示已由服务端揭示',
      rejectedMessage: '提示暂时不可用',
      unknownMessage: '提示结果待核对，请勿重复请求',
    );
  }

  Future<void> submitReveal(int nodeId) async {
    final PlayerGameProjection? projection = state.projection;
    if (projection == null ||
        !state.enabled ||
        state.writeBlocked ||
        !projection.availableActions.contains('PLAYER_REVEAL')) {
      return;
    }
    await _submit(
      GameSessionCommand.playerReveal(
        activityId: activityId,
        nodeId: nodeId,
        requestId: _requestId('reveal-$nodeId'),
        expectedRevision: projection.revision,
      ),
      submittingMessage: '正在揭示答案…',
      confirmedMessage: '答案已揭示，并记为兜底完成',
      rejectedMessage: '暂时不能揭示答案',
      unknownMessage: '揭示结果待核对，请勿重复请求',
      onApplied: _rememberReveal,
    );
  }

  /// 提交成功后写条上的文案(真源 `submitPlayerTask` 的 evidenceOnly 分支:
  /// 只收证据的 PHOTO 任务是「证据已记录」,其余是「任务已由服务端记录」)。
  String _taskConfirmedMessage(int nodeId) {
    final List<PlayerGameNode> nodes =
        state.projection?.nodes ?? const <PlayerGameNode>[];
    for (final PlayerGameNode node in nodes) {
      if (node.nodeId != nodeId) continue;
      final PlayerGameTask? task = node.task;
      final bool evidenceOnly =
          task != null &&
          task.inputType == 'PHOTO' &&
          task.completionPolicy == 'EVIDENCE_ONLY';
      return evidenceOnly ? '证据已记录' : '任务已由服务端记录';
    }
    return '任务已由服务端记录';
  }

  String _inputTypeOf(int nodeId) {
    final List<PlayerGameNode> nodes =
        state.projection?.nodes ?? const <PlayerGameNode>[];
    for (final PlayerGameNode node in nodes) {
      if (node.nodeId == nodeId) return node.task?.inputType ?? '';
    }
    return '';
  }

  void _setEvidence(int nodeId, PlayerTaskEvidence evidence) {
    state = state.copyWith(
      evidence: <int, PlayerTaskEvidence>{...state.evidence, nodeId: evidence},
    );
  }

  /// 现场凭证的本地攒写(TEXT/SCAN/PHOTO 三条都落这里)。
  void setEvidence(int nodeId, PlayerTaskEvidence evidence) =>
      _setEvidence(nodeId, evidence);

  /// 揭示回执带回来的答案正文(投影里没有,只在本次会话里有效)。
  String revealedAnswerFor(int nodeId) => state.revealedAnswers[nodeId] ?? '';

  /// APPLIED 回执里带回来的揭示正文(投影里没有,只能当场记住)。
  void _rememberReveal(GameSessionReceipt receipt) {
    final Object? raw = receipt.result['revealText'];
    final String text = raw is String ? raw.trim() : '';
    if (text.isEmpty) return;
    final int? nodeId = _pending?.nodeId;
    if (nodeId == null) return;
    state = state.copyWith(
      revealedAnswers: <int, String>{...state.revealedAnswers, nodeId: text},
    );
  }

  Future<void> _submit(
    GameSessionCommand command, {
    required String submittingMessage,
    required String confirmedMessage,
    required String rejectedMessage,
    required String unknownMessage,
    void Function(GameSessionReceipt receipt)? onApplied,
  }) async {
    if (state.writeBlocked) return;
    state = state.copyWith(
      writeStatus: PlayerGameWriteStatus.submitting,
      writeRequestId: command.requestId,
      writeMessage: submittingMessage,
      canRetry: false,
    );
    final PlayerGamePendingWrite pending;
    try {
      pending = PlayerGamePendingWrite.fromCommand(command);
      await _store.write(pending);
    } catch (_) {
      state = state.copyWith(
        writeStatus: PlayerGameWriteStatus.error,
        writeRequestId: '',
        writeMessage: '无法安全保存本次操作，请检查存储后重试',
        canRetry: false,
      );
      return;
    }
    _pending = pending;
    try {
      final GameSessionReceipt receipt = await _gateway.submitPlayerCommand(
        command,
      );
      if (receipt.outcome != GameReceiptOutcome.applied) {
        state = state.copyWith(
          writeStatus: PlayerGameWriteStatus.unknown,
          writeMessage: unknownMessage,
          canRetry: true,
        );
        return;
      }
      onApplied?.call(receipt);
      await _settleApplied(confirmedMessage);
    } on GameSessionRejectedException catch (error) {
      await _settleFailed(
        error.message.isEmpty ? rejectedMessage : error.message,
      );
    } on GameSessionContractException catch (error) {
      state = state.copyWith(
        writeStatus: PlayerGameWriteStatus.unknown,
        writeMessage: error.message.isEmpty ? unknownMessage : error.message,
        canRetry: true,
      );
    } catch (_) {
      state = state.copyWith(
        writeStatus: PlayerGameWriteStatus.unknown,
        writeMessage: unknownMessage,
        canRetry: true,
      );
    }
  }

  Future<void> _settleApplied(String message) async {
    await _store.clear(activityId);
    _pending = null;
    state = state.copyWith(
      writeStatus: PlayerGameWriteStatus.confirmed,
      writeMessage: message,
      canRetry: false,
    );
    unawaited(HapticFeedback.mediumImpact());
    await _loadProjection();
  }

  Future<void> _settleFailed(String message) async {
    await _store.clear(activityId);
    _pending = null;
    state = state.copyWith(
      writeStatus: PlayerGameWriteStatus.error,
      writeMessage: message,
      canRetry: false,
    );
  }

  /// 「核对结果」:用原 requestId 回读,不重发。
  Future<void> reconcile({bool reload = true}) async {
    final PlayerGamePendingWrite? pending = _pending;
    if (pending == null ||
        state.writeStatus == PlayerGameWriteStatus.submitting) {
      return;
    }
    state = state.copyWith(writeMessage: '正在核对服务端结果…');
    try {
      final GameSessionReceipt receipt = await _gateway.readPlayerReceipt(
        activityId: pending.activityId,
        requestId: pending.requestId,
        expectedAction: pending.action,
      );
      if (receipt.outcome != GameReceiptOutcome.applied) {
        state = state.copyWith(
          writeStatus: PlayerGameWriteStatus.unknown,
          writeMessage: '服务端还没有最终结果，稍后再核对',
          canRetry: true,
        );
        return;
      }
      if (reload) {
        await _settleApplied('操作已由服务端确认');
      } else {
        await _store.clear(activityId);
        _pending = null;
        state = state.copyWith(
          writeStatus: PlayerGameWriteStatus.confirmed,
          writeMessage: '操作已由服务端确认',
          canRetry: false,
        );
      }
    } on GameSessionRejectedException catch (error) {
      await _settleFailed(error.message.isEmpty ? '操作未能完成' : error.message);
    } catch (_) {
      state = state.copyWith(
        writeStatus: PlayerGameWriteStatus.unknown,
        writeMessage: '暂时核不上服务端结果，网络恢复后再试',
        canRetry: true,
      );
    }
  }

  /// 「重试原操作」:同一个 requestId + 同一份 payload 重放(服务端幂等)。
  Future<void> retryPending() async {
    final PlayerGamePendingWrite? pending = _pending;
    if (pending == null ||
        state.writeStatus != PlayerGameWriteStatus.unknown ||
        !state.canRetry) {
      return;
    }
    GameSessionCommand command;
    try {
      command = pending.toCommand();
    } on FormatException {
      await _settleFailed('这次操作已无法安全重放，请重新发起');
      return;
    }
    final String nodeId = pending.nodeId?.toString() ?? '';
    await _submit(
      command,
      submittingMessage: '正在重试原操作…',
      confirmedMessage: '操作已由服务端确认',
      rejectedMessage: '原操作未能完成',
      unknownMessage: '重试结果仍待核对，请勿重复提交',
      onApplied: nodeId.isEmpty ? null : _maybeRememberRevealFromRetry,
    );
  }

  void _maybeRememberRevealFromRetry(GameSessionReceipt receipt) {
    if (_pending?.action == 'PLAYER_REVEAL') _rememberReveal(receipt);
  }
}

final playerGameModuleProvider =
    NotifierProvider.family<
      PlayerGameModuleController,
      PlayerGameModuleState,
      int
    >(PlayerGameModuleController.new);
