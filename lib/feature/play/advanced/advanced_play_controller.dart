import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../data/api/advanced_play_api.dart';
import '../../../data/models/advanced_play.dart';

enum AdvancedPlayPhase {
  idle,
  loading,
  ready,
  acting,
  unknown,
  retryable,
  unsupported,
  error,
}

@immutable
class AdvancedPlayPendingAction {
  const AdvancedPlayPendingAction({
    required this.sessionId,
    required this.version,
    required this.idempotencyKey,
    required this.action,
    required this.payload,
  });

  final int sessionId;
  final int version;
  final String idempotencyKey;
  final String action;
  final Map<String, Object?> payload;
}

class AdvancedPlayController extends ChangeNotifier {
  AdvancedPlayController({
    required this.gateway,
    required this.activityId,
    required this.topicId,
    required this.nodeId,
    this.uploadPhoto,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final AdvancedPlayGateway gateway;
  final int activityId;
  final int topicId;
  final int nodeId;
  final DateTime Function() now;

  /// 拍照问答两步链的第一步:把手机里的临时照片传上去、换回一个服务端地址
  /// (真源是页面拿共享上传入口 `app.getUploadClient().uploadAll`,打的正是
  /// 其余上传位同一条 `/api/common/uploadOSS`)。传进来的是**生产实现**
  /// (`PlayApi.uploadImage`);没接上这条口时,宿主给的是实话而不是静默。
  final Future<String> Function(String filePath)? uploadPhoto;

  /// 双击锁(真源 `_qaPhotoUploading` 同一条):一次拍照上传在途时,
  /// 后到的 shoot 直接忽略 —— 组件拍完照不锁自己(要能换图重试),
  /// 锁必须在页面/宿主这一侧,不然会起第二个必被静默丢掉的请求。
  bool qaPhotoUploading = false;

  AdvancedPlayPhase _phase = AdvancedPlayPhase.idle;
  AdvancedPlayState? _state;
  AdvancedPlayPendingAction? _pending;
  List<AdvancedPlayLeaderboardRow> _leaderboard =
      const <AdvancedPlayLeaderboardRow>[];
  String _message = '';
  bool _disposed = false;

  AdvancedPlayPhase get phase => _phase;
  AdvancedPlayState? get state => _state;
  List<AdvancedPlayLeaderboardRow> get leaderboard => _leaderboard;
  String get message => _message;
  bool get canWrite =>
      _phase == AdvancedPlayPhase.ready && _state?.isRunning == true;
  bool get readyForBase =>
      _phase == AdvancedPlayPhase.ready && _state?.readyForBase == true;

  Future<void> start() async {
    if (_phase == AdvancedPlayPhase.loading) return;
    _pending = null;
    _leaderboard = const <AdvancedPlayLeaderboardRow>[];
    _set(AdvancedPlayPhase.loading, '');
    try {
      _accept(
        await gateway.start(
          activityId: activityId,
          topicId: topicId,
          nodeId: nodeId,
        ),
      );
      if (_phase == AdvancedPlayPhase.ready &&
          _state!.mechanics.leaderboardEnabled) {
        await loadLeaderboard();
      }
    } on AdvancedPlayException catch (error) {
      _set(AdvancedPlayPhase.error, error.message);
    } catch (_) {
      _set(AdvancedPlayPhase.error, '高级玩法暂时无法加载');
    }
  }

  Future<void> submit(
    String action, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) async {
    final AdvancedPlayState? current = _state;
    if (!canWrite || current == null) return;
    final String normalizedAction = action.trim().toUpperCase();
    final AdvancedPlayPendingAction pending = AdvancedPlayPendingAction(
      sessionId: current.sessionId,
      version: current.version,
      idempotencyKey: buildAdvancedPlayIdempotencyKey(
        current.sessionId,
        current.version,
        normalizedAction,
        payload,
      ),
      action: normalizedAction,
      payload: Map<String, Object?>.unmodifiable(payload),
    );
    _pending = pending;
    await _send(pending);
  }

  Future<void> retryPending() async {
    final AdvancedPlayPendingAction? pending = _pending;
    if (_phase != AdvancedPlayPhase.retryable || pending == null) return;
    await _send(pending);
  }

  Future<void> completeCurrentUnit() async {
    final AdvancedPlayState? current = _state;
    if (!canWrite || current == null || !current.isMultiplayer) return;
    await submit('COMPLETE_UNIT', <String, Object?>{
      'unitId': buildAdvancedPlayUnitId(current.sessionId, current.version),
    });
  }

  Future<void> assignRole(int memberId, String roleId) async {
    final AdvancedPlayState? current = _state;
    final String normalizedRoleId = roleId.trim();
    if (!canWrite ||
        current == null ||
        !current.isMultiplayer ||
        memberId <= 0 ||
        normalizedRoleId.isEmpty ||
        !current.mechanics.multiplayer.roles.any(
          (AdvancedPlayRole role) => role.id == normalizedRoleId,
        )) {
      return;
    }
    await submit('ASSIGN_ROLE', <String, Object?>{
      'memberId': memberId,
      'roleId': normalizedRoleId,
    });
  }

  Future<void> _send(AdvancedPlayPendingAction pending) async {
    _set(AdvancedPlayPhase.acting, '');
    try {
      _accept(
        await gateway.action(
          sessionId: pending.sessionId,
          version: pending.version,
          idempotencyKey: pending.idempotencyKey,
          action: pending.action,
          payload: pending.payload,
        ),
      );
      _pending = null;
      if (_phase == AdvancedPlayPhase.ready &&
          _state!.mechanics.leaderboardEnabled) {
        await loadLeaderboard();
      }
    } on AdvancedPlayTransportException catch (error) {
      _set(AdvancedPlayPhase.unknown, error.message);
    } on AdvancedPlayBusinessException catch (error) {
      if (error.message.contains('状态已更新')) {
        await _refreshAfterConflict(error.message);
      } else {
        _set(AdvancedPlayPhase.error, error.message);
      }
    } on AdvancedPlayException catch (error) {
      _set(AdvancedPlayPhase.error, error.message);
    } catch (_) {
      _set(AdvancedPlayPhase.error, '高级玩法回执无法识别');
    }
  }

  Future<void> resolveUnknown() async {
    final AdvancedPlayPendingAction? pending = _pending;
    if (_phase != AdvancedPlayPhase.unknown || pending == null) return;
    _set(AdvancedPlayPhase.loading, '正在核对服务端权威状态');
    try {
      final AdvancedPlayState readback = await gateway.state(pending.sessionId);
      _requireCurrentScope(readback);
      _state = readback;
      if (readback.isMultiplayer) {
        _set(AdvancedPlayPhase.retryable, '队友可能更新了状态，不能确认刚才这一步；可用原请求标识安全核验重放');
      } else if (readback.version > pending.version) {
        // 版本前进可能来自同账号的另一台设备，不足以证明本动作。
        // 用原幂等键重放：已落库时服务端 replay，未落库时则明确拒绝旧 version。
        await _send(pending);
      } else if (readback.version == pending.version) {
        _set(AdvancedPlayPhase.retryable, '刚才的动作未写入，可使用同一请求标识安全重试');
      } else {
        _set(AdvancedPlayPhase.error, '权威状态版本异常，请退出节点后重试');
      }
    } on AdvancedPlayException catch (error) {
      _set(AdvancedPlayPhase.unknown, '${error.message}；仍未确认结果，请勿重复提交');
    } catch (_) {
      _set(AdvancedPlayPhase.unknown, '仍未核对上，请勿重复提交');
    }
  }

  Future<void> refreshAuthoritative() async {
    final AdvancedPlayState? current = _state;
    if (current == null || _phase == AdvancedPlayPhase.loading) return;
    _set(AdvancedPlayPhase.loading, '正在核对服务端权威状态');
    try {
      _accept(await gateway.state(current.sessionId));
    } on AdvancedPlayException catch (error) {
      _set(AdvancedPlayPhase.error, error.message);
    } catch (_) {
      _set(AdvancedPlayPhase.error, '权威状态暂时无法读取');
    }
  }

  Future<void> _refreshAfterConflict(String conflictMessage) async {
    final AdvancedPlayState? current = _state;
    if (current == null) return;
    try {
      final AdvancedPlayState readback = await gateway.state(current.sessionId);
      _pending = null;
      _accept(readback);
      if (_phase == AdvancedPlayPhase.ready) {
        _set(AdvancedPlayPhase.ready, conflictMessage);
      }
    } on AdvancedPlayException catch (error) {
      _set(AdvancedPlayPhase.error, error.message);
    }
  }

  Future<void> loadLeaderboard() async {
    final AdvancedPlayState? current = _state;
    if (current == null || !current.mechanics.leaderboardEnabled) return;
    try {
      _leaderboard = await gateway.leaderboard(
        activityId: activityId,
        topicId: topicId,
        nodeId: nodeId,
      );
      _notify();
    } on AdvancedPlayException catch (error) {
      _message = error.message;
      _notify();
    }
  }

  void _accept(AdvancedPlayState value) {
    _requireCurrentScope(value);
    _state = value;
    if (value.needsUnavailableStepVerification) {
      _set(
        AdvancedPlayPhase.unsupported,
        '该单人玩法需要微信运动的受信步数回执，App 暂不提供伪造或不可验证的入口',
      );
      return;
    }
    if (value.isRunning &&
        value.deadlineAt != null &&
        value.remainingSeconds(now()) == 0) {
      _set(AdvancedPlayPhase.error, '计时已结束，服务端尚未确认最终状态');
      return;
    }
    _set(AdvancedPlayPhase.ready, '');
  }

  void _requireCurrentScope(AdvancedPlayState value) {
    if (value.activityId != activityId ||
        value.topicId != topicId ||
        value.nodeId != nodeId) {
      throw const AdvancedPlayContractException('高级玩法权威回执与当前节点不匹配');
    }
  }

  void _set(AdvancedPlayPhase value, String message) {
    _phase = value;
    _message = message;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String buildAdvancedPlayIdempotencyKey(
  int sessionId,
  int version,
  String action,
  Map<String, Object?> payload,
) {
  final String canonical = jsonEncode(<Object?>[
    action.trim().toUpperCase(),
    _canonical(payload),
  ]);
  int hash = 0xcbf29ce484222325;
  for (final int byte in utf8.encode(canonical)) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return 'ap:$sessionId:$version:${hash.toRadixString(16).padLeft(16, '0')}';
}

String buildAdvancedPlayUnitId(int sessionId, int version) =>
    'unit-$sessionId-v$version';

Object? _canonical(Object? value) {
  if (value is Map) {
    final List<String> keys = value.keys.map((key) => '$key').toList()..sort();
    return <String, Object?>{
      for (final String key in keys) key: _canonical(value[key]),
    };
  }
  if (value is List) return value.map(_canonical).toList(growable: false);
  return value;
}
