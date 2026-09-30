import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/providers.dart';
import '../../core/util/coord.dart';
import '../../data/api/play_api.dart';
import '../../data/models/checkin_models.dart';
import '../../data/models/preference_play.dart';
import '../assets/assets_page.dart';
import '../points/points_controller.dart';
import '../profile/profile_controller.dart';

/// 游玩会话状态机(按 activityId 区分 family,离开页面自动释放)。
///
/// build() 首次触发 load() 拉 /api/play/nodes;checkin(code) 调 /api/play/checkin
/// 成功后回拉节点刷新进度,并失效积分/成长 provider(打卡会发分/给徽章)。
typedef PlaySessionKey = ({int? activityId, int? topicId});
typedef _RouteSemanticAction = ({
  String transport,
  int nodeId,
  String discriminator,
});

final playSessionProvider = NotifierProvider.autoDispose
    .family<PlaySessionController, AsyncValue<PlayNodesResult>, PlaySessionKey>(
      PlaySessionController.new,
    );

class PlaySessionController extends Notifier<AsyncValue<PlayNodesResult>> {
  PlaySessionController(this._key);

  final PlaySessionKey _key;
  bool _loadedOnce = false;
  bool _firstDataPending = true;
  PlayRouteState? _routeState;
  final Map<_RouteSemanticAction, RouteAdvanceToken> _pendingRouteActions =
      <_RouteSemanticAction, RouteAdvanceToken>{};
  static int _routeActionSequence = 0;

  /// 后端 AjaxResult 表示结构化路线冲突的业务码(端上按码判定,不看中文 msg)。
  static const int _routeConflictCode = 409;

  @override
  AsyncValue<PlayNodesResult> build() {
    if (!_loadedOnce) {
      _loadedOnce = true;
      Future<void>.microtask(load);
    }
    return const AsyncValue<PlayNodesResult>.loading();
  }

  Future<void> load() async {
    _firstDataPending = true;
    state = const AsyncValue<PlayNodesResult>.loading();
    final next = await AsyncValue.guard(_fetchCurrent);
    _rememberRouteState(next);
    if (ref.mounted) state = next;
  }

  /// 真源 `loadData(first)` 的 first:首载(进页/手动重载)为 true,打卡后自动
  /// 回拉为 false。《预制人生》换轨只认首载,否则打卡回包会把用户踢出通用游玩页。
  /// 单次消费 —— 同一份首屏数据反复重建不能重复换轨。
  bool consumeFirstLoadData() {
    if (!_firstDataPending) return false;
    _firstDataPending = false;
    return true;
  }

  Future<PlayNodesResult> _fetchCurrent() {
    final PlayApi api = ref.read(playApiProvider);
    final int? topicId = _key.topicId;
    return topicId != null
        ? api.fetchTopicNodes(topicId)
        : api.fetchNodes(_key.activityId!);
  }

  /// 读取当前活动/主题会话的途中台词；空回包由调用方当作不展示。
  Future<String?> companionLine() => ref
      .read(playApiProvider)
      .companionLine(activityId: _key.activityId, topicId: _key.topicId);

  /// 扫码打卡。成功返回发奖结果并刷新进度;失败抛 [PlayException](UI 用其 message 提示)。
  Future<CheckinReward> checkin(String code) async {
    final api = ref.read(playApiProvider);
    final topicId = _key.topicId;
    final reward = await _completeRouteAction(
      (transport: 'checkin', nodeId: 0, discriminator: code.trim()),
      (RouteAdvanceToken? routeAdvance) => topicId != null
          ? api.submitTopicCheckin(
              topicId: topicId,
              code: code,
              routeAdvance: routeAdvance,
            )
          : api.submitCheckin(
              activityId: _key.activityId!,
              code: code,
              routeAdvance: routeAdvance,
            ),
    );
    // App-5:打卡发分/给徽章,失效积分与成长页,使其重新拉取
    ref.invalidate(pointsProvider);
    ref.invalidate(pointsListProvider);
    ref.invalidate(growthCenterProvider);
    return reward;
  }

  /// 答题打卡(vm1 文字 / vm3 选项字母)。成功刷新进度+失效积分/成长 provider,
  /// 返回发奖结果;失败抛 [PlayException](UI 用其 message 提示后端原文)。
  Future<CheckinReward> answer(int nodeId, String answerText) async {
    final api = ref.read(playApiProvider);
    final topicId = _key.topicId;
    final reward = await _completeRouteAction(
      (transport: 'answer', nodeId: nodeId, discriminator: answerText.trim()),
      (RouteAdvanceToken? routeAdvance) => topicId != null
          ? api.submitTopicAnswer(
              topicId: topicId,
              nodeId: nodeId,
              answer: answerText,
              routeAdvance: routeAdvance,
            )
          : api.submitAnswer(
              activityId: _key.activityId!,
              nodeId: nodeId,
              answer: answerText,
              routeAdvance: routeAdvance,
            ),
    );
    ref.invalidate(pointsProvider);
    ref.invalidate(pointsListProvider);
    ref.invalidate(growthCenterProvider);
    return reward;
  }

  /// 城市定向谜题逐级提示。提示本身不完成节点，UI 采用服务端返回的提示正文与分数上限。
  Future<PuzzleHintResult> requestPuzzleHint(int nodeId, int level) => ref
      .read(playApiProvider)
      .requestPuzzleHint(
        activityId: _key.activityId,
        topicId: _key.topicId,
        nodeId: nodeId,
        level: level,
      );

  /// 查看答案并以零解谜分完成节点；成功后回拉服务端进度，不在客户端猜完成态。
  Future<PuzzleRevealResult> revealPuzzle(
    int nodeId, {
    required String routeActionId,
    required int expectedRouteVersion,
  }) => ref
      .read(playApiProvider)
      .revealPuzzle(
        activityId: _key.activityId,
        topicId: _key.topicId,
        nodeId: nodeId,
        routeActionId: routeActionId,
        expectedRouteVersion: expectedRouteVersion,
      );

  /// 写后从服务端读取当前会话。只有 [apply] 为 true 才更新页面，且不先切 loading，
  /// 避免提交成功后在结果弹窗出现前卸载交互页。
  Future<PlayNodesResult> readback({bool apply = true}) async {
    final PlayNodesResult result = await _fetchCurrent();
    if (apply) applyReadback(result);
    return result;
  }

  void applyReadback(PlayNodesResult result) {
    if (!ref.mounted) return;
    _routeState = result.routeState;
    state = AsyncValue<PlayNodesResult>.data(result);
  }

  void invalidatePlayRewards() {
    ref.invalidate(pointsProvider);
    ref.invalidate(pointsListProvider);
    ref.invalidate(growthCenterProvider);
  }

  /// 拍照打卡(vm2)。先把本地图片上传 OSS 拿 picUrl,再 /api/play/photo 上报。
  /// 成功刷新进度+失效积分/成长 provider,返回发奖结果;失败抛 [PlayException]
  /// (UI 用其 message 显示后端原文,如图片安全检查不过)。
  Future<CheckinReward> photo(int nodeId, String filePath) async {
    return _submitPhoto(nodeId, filePath, refreshPoints: true);
  }

  /// vm=2/filter_shot 仍走同一个 /photo 真源，但服务端只发 XP/徽章；
  /// 因此不刷新积分读侧，避免 UI 暗示积分经济发生了变化。
  Future<CheckinReward> filterPhoto(int nodeId, String filePath) async {
    return _submitPhoto(nodeId, filePath, refreshPoints: false);
  }

  Future<CheckinReward> _submitPhoto(
    int nodeId,
    String filePath, {
    required bool refreshPoints,
  }) async {
    final api = ref.read(playApiProvider);
    final picUrl = await api.uploadImage(filePath);
    final topicId = _key.topicId;
    final reward = await _completeRouteAction(
      (transport: 'photo', nodeId: nodeId, discriminator: filePath),
      (RouteAdvanceToken? routeAdvance) => topicId != null
          ? api.submitTopicPhoto(
              topicId: topicId,
              nodeId: nodeId,
              picUrl: picUrl,
              routeAdvance: routeAdvance,
            )
          : api.submitPhoto(
              activityId: _key.activityId!,
              nodeId: nodeId,
              picUrl: picUrl,
              routeAdvance: routeAdvance,
            ),
    );
    if (refreshPoints) {
      ref.invalidate(pointsProvider);
      ref.invalidate(pointsListProvider);
    }
    ref.invalidate(growthCenterProvider);
    return reward;
  }

  /// GPS 到达打卡(vm5 / needGps)。lng/lat 为已转好的 gcj02 坐标(调用方负责
  /// 把 geolocator 的 WGS84 转 gcj02)。成功刷新进度+失效积分/成长 provider,
  /// 返回发奖结果;失败抛 [PlayException](UI 用其 message 显示后端原文)。
  Future<CheckinReward> arrive(int nodeId, double lng, double lat) async {
    final api = ref.read(playApiProvider);
    final topicId = _key.topicId;
    final reward = await _completeRouteAction(
      (transport: 'arrive', nodeId: nodeId, discriminator: ''),
      (RouteAdvanceToken? routeAdvance) => topicId != null
          ? api.submitTopicArrive(
              topicId: topicId,
              nodeId: nodeId,
              longitude: lng,
              latitude: lat,
              routeAdvance: routeAdvance,
            )
          : api.submitArrive(
              activityId: _key.activityId!,
              nodeId: nodeId,
              longitude: lng,
              latitude: lat,
              routeAdvance: routeAdvance,
            ),
    );
    ref.invalidate(pointsProvider);
    ref.invalidate(pointsListProvider);
    ref.invalidate(growthCenterProvider);
    return reward;
  }

  /// App 传感器挑战(vm7)。后端按 XP_BADGE_ONLY 结算，因此这里只失效成长读侧，
  /// 不刷新积分余额，避免把探索值误当成积分经济。
  Future<CheckinReward> sensorResult(
    int nodeId,
    String sensorType,
    Map<String, dynamic> payload,
  ) async {
    final topicId = _key.topicId;
    final CheckinReward reward = await _completeRouteAction(
      (transport: 'sensor-result', nodeId: nodeId, discriminator: sensorType),
      (RouteAdvanceToken? routeAdvance) => ref
          .read(playApiProvider)
          .submitSensorResult(
            activityId: topicId != null ? null : _key.activityId!,
            topicId: topicId,
            nodeId: nodeId,
            sensorType: sensorType,
            payload: payload,
            routeAdvance: routeAdvance,
          ),
    );
    ref.invalidate(growthCenterProvider);
    return reward;
  }

  Future<PreferenceQuestionnaire> preference(int nodeId) => ref
      .read(playApiProvider)
      .fetchPreference(
        activityId: _key.activityId,
        topicId: _key.topicId,
        nodeId: nodeId,
      );

  /// vm=6 由偏好提交接口在服务端求值并完成节点。
  /// 并列取舍回包不刷新；最终回包只接收 `progress`，不二次完成。
  Future<PreferenceSubmission> submitPreference(
    int nodeId,
    Map<String, String> choices, {
    String? reuseTagCode,
  }) async {
    const String transport = 'preference';
    final action = (transport: transport, nodeId: nodeId, discriminator: '');
    final RouteAdvanceToken? token = _routeTokenFor(action);
    final PlayApi api = ref.read(playApiProvider);
    Future<PreferenceSubmission> submit(RouteAdvanceToken? routeAdvance) =>
        api.submitPreference(
          activityId: _key.activityId,
          topicId: _key.topicId,
          nodeId: nodeId,
          choices: choices,
          reuseTagCode: reuseTagCode,
          routeAdvance: routeAdvance,
        );

    late PreferenceSubmission submission;
    try {
      submission = await submit(token);
    } catch (error) {
      if (!_isRouteConflict(error)) {
        _discardPendingUnlessUncertain(action, error);
        rethrow;
      }
      final RouteAdvanceToken retryToken = await _routeTokenAfterConflict(
        action,
        error,
      );
      try {
        submission = await submit(retryToken);
      } catch (retryError) {
        _discardPendingUnlessUncertain(action, retryError);
        rethrow;
      }
    }

    if (submission.needsTiebreak) {
      if (submission.tiebreak == null) {
        _pendingRouteActions.remove(action);
        throw PlayException('取舍题未下发，请重试');
      }
      return submission;
    }

    final CheckinReward? progress = submission.progress;
    if (submission.evaluation == null || progress == null) {
      // HTTP 成功但结果缺失时无法确定服务端是否已推进，
      // 保留同一 route token，让重试依赖服务端幂等读回。
      throw PlayException('偏好结果不完整，请重试');
    }

    _pendingRouteActions.remove(action);
    _acceptRewardRouteState(progress.routeState);
    await _reloadAfterCompletion();
    ref.invalidate(pointsProvider);
    ref.invalidate(pointsListProvider);
    ref.invalidate(growthCenterProvider);
    return submission;
  }

  Future<PreferenceInheritedTag> confirmPreferenceTag(int tagId) =>
      ref.read(playApiProvider).confirmPreferenceTag(tagId);

  Future<PreferenceInheritedTag> correctPreferenceTag(
    int tagId,
    String tagValue,
  ) => ref.read(playApiProvider).correctPreferenceTag(tagId, tagValue);

  Future<CheckinReward> _completeRouteAction(
    _RouteSemanticAction action,
    Future<CheckinReward> Function(RouteAdvanceToken? routeAdvance) submit,
  ) async {
    try {
      return await _runRouteAction(action, submit, _routeTokenFor(action));
    } catch (error) {
      if (!_isRouteConflict(error)) {
        _discardPendingUnlessUncertain(action, error);
        rethrow;
      }
      final RouteAdvanceToken retryToken = await _routeTokenAfterConflict(
        action,
        error,
      );
      try {
        return await _runRouteAction(action, submit, retryToken);
      } catch (retryError) {
        _discardPendingUnlessUncertain(action, retryError);
        rethrow;
      }
    }
  }

  void _discardPendingUnlessUncertain(
    _RouteSemanticAction action,
    Object error,
  ) {
    if (!_isNetworkOutcomeUnknown(error)) {
      _pendingRouteActions.remove(action);
    }
  }

  Future<CheckinReward> _runRouteAction(
    _RouteSemanticAction action,
    Future<CheckinReward> Function(RouteAdvanceToken? routeAdvance) submit,
    RouteAdvanceToken? token,
  ) async {
    final CheckinReward reward = await submit(token);
    _pendingRouteActions.remove(action);
    _acceptRewardRouteState(reward.routeState);
    await _reloadAfterCompletion();
    return reward;
  }

  /// 结构化路线冲突(AjaxResult 业务码 409)的无感恢复:先取权威 state/version,
  /// 当前节点已完成则不二次提交;未完成才基于新版本自动重试,且最多一次。
  ///
  /// ★ 权威 state 到手前**保留**原 pending 票据:fetch 失败/空包/脏包时原样
  ///   抛回业务 409(保留原 code 与 msg),让下一次同语义动作仍复用原
  ///   actionId/version —— 不把「可恢复冲突」改写成丢票或 fetch 错误。
  Future<RouteAdvanceToken> _routeTokenAfterConflict(
    _RouteSemanticAction action,
    Object originalError,
  ) async {
    final PlayRouteState authoritative;
    try {
      authoritative = await ref
          .read(playApiProvider)
          .fetchRouteState(activityId: _key.activityId, topicId: _key.topicId);
    } catch (_) {
      // fetch 失败/空/脏包:原票据未动,抛回原业务 409,不改成 fetch 错误。
      throw originalError;
    }

    // 拿到权威 state 后才丢弃旧票。
    _pendingRouteActions.remove(action);

    final int? actedNodeId = action.nodeId > 0
        ? action.nodeId
        : _routeState?.currentNodeId;
    _acceptRewardRouteState(authoritative);

    if (actedNodeId != null &&
        authoritative.stateOf(actedNodeId) == PlayRouteNodeState.completed) {
      // 动作已在服务端生效:接受权威 state 并刷新节点,绝不二次提交。
      // CheckinReward 需要 firstTime/xp/徽章等权威状态无法反推的奖励数据,
      // 构造回包等于造奖励;故这里刷新后抛可重试错误,由 UI 提示用户重试。
      await _reloadAfterCompletion();
      throw PlayException('该节点已完成,请刷新后重试');
    }

    final RouteAdvanceToken retryToken = RouteAdvanceToken(
      actionId: _newRouteActionId(),
      expectedRouteVersion: authoritative.version,
    );
    _pendingRouteActions[action] = retryToken;
    return retryToken;
  }

  /// 只有 BRANCH 会话的结构化业务码 409 才算可恢复冲突;网络不确定/其他
  /// 4xx/LINEAR 一律走原行为,**不按中文 msg 匹配**,也不新增网络调用。
  bool _isRouteConflict(Object error) {
    if (_routeState?.isBranchGraph != true) return false;
    if (error is PlayException) return error.code == _routeConflictCode;
    if (error is DioException) {
      final Object? data = error.response?.data;
      if (data is! Map) return false;
      // 与 PlayApi 共用 fail-closed 解析器:num/数字字符串 409 才恢复,
      // 未知类型 → null → 不恢复,也绝不因 `as num?` 抛 TypeError。
      return PlayApi.businessCodeOf(data['code']) == _routeConflictCode;
    }
    return false;
  }

  RouteAdvanceToken? _routeTokenFor(_RouteSemanticAction action) {
    final PlayRouteState? routeState = _routeState;
    if (routeState == null || !routeState.isBranchGraph) return null;
    return _pendingRouteActions.putIfAbsent(
      action,
      () => RouteAdvanceToken(
        actionId: _newRouteActionId(),
        expectedRouteVersion: routeState.version,
      ),
    );
  }

  String _newRouteActionId() {
    final int sequence = _routeActionSequence++;
    final String instant = DateTime.now().microsecondsSinceEpoch.toRadixString(
      36,
    );
    return 'app-$instant-${sequence.toRadixString(36)}';
  }

  bool _isNetworkOutcomeUnknown(Object error) {
    if (error is! DioException) return false;
    final int? statusCode = error.response?.statusCode;
    return statusCode == null || statusCode >= 500;
  }

  void _acceptRewardRouteState(PlayRouteState? routeState) {
    if (routeState == null) return;
    _routeState = routeState;
    if (state case AsyncData<PlayNodesResult>(:final value)) {
      state = AsyncValue<PlayNodesResult>.data(
        value.withRouteState(routeState),
      );
    }
  }

  Future<void> _reloadAfterCompletion() async {
    final AsyncValue<PlayNodesResult> next = await AsyncValue.guard(
      _fetchCurrent,
    );
    _rememberRouteState(next);
    if (ref.mounted) state = next;
  }

  void _rememberRouteState(AsyncValue<PlayNodesResult> next) {
    if (next case AsyncData<PlayNodesResult>(:final value)) {
      _routeState = value.routeState;
    }
  }

  /// 解锁提示并刷新积分读侧。本次实扣以接口回包 cost 为准。
  Future<HintUnlockResult> unlockHint(int nodeId) async {
    final HintUnlockResult result = await ref
        .read(playApiProvider)
        .unlockHint(nodeId);
    ref.invalidate(pointsProvider);
    ref.invalidate(pointsListProvider);
    return result;
  }
}

class PlayNavigationPosition {
  const PlayNavigationPosition({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

abstract interface class PlayNavigationLocationSource {
  Future<PlayNavigationPosition> current();

  Stream<PlayNavigationPosition> watch();
}

class GeolocatorPlayNavigationLocationSource
    implements PlayNavigationLocationSource {
  @override
  Future<PlayNavigationPosition> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw PlayException('请开启系统定位后重试');
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw PlayException('需要定位权限才能开始前往');
    }
    return _convert(
      await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ),
    );
  }

  @override
  Stream<PlayNavigationPosition> watch() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 3,
    ),
  ).map(_convert);

  PlayNavigationPosition _convert(Position position) {
    final gcj = wgs84ToGcj02(position.longitude, position.latitude);
    return PlayNavigationPosition(latitude: gcj.lat, longitude: gcj.lng);
  }
}

final playNavigationLocationSourceProvider =
    Provider<PlayNavigationLocationSource>(
      (_) => GeolocatorPlayNavigationLocationSource(),
    );

final playCompanionDisplayDurationProvider = Provider<Duration>(
  (_) => const Duration(milliseconds: 3500),
);

class PlayNavigationState {
  const PlayNavigationState({
    this.targetNodeId,
    this.targetName = '',
    this.remainM = 0,
    this.totalM = 0,
    this.hit50 = false,
    this.hit90 = false,
    this.line,
  });

  final int? targetNodeId;
  final String targetName;
  final int remainM;
  final double totalM;
  final bool hit50;
  final bool hit90;
  final String? line;

  bool get active => targetNodeId != null;

  PlayNavigationState copyWith({
    int? targetNodeId,
    String? targetName,
    int? remainM,
    double? totalM,
    bool? hit50,
    bool? hit90,
    String? line,
    bool clearLine = false,
  }) => PlayNavigationState(
    targetNodeId: targetNodeId ?? this.targetNodeId,
    targetName: targetName ?? this.targetName,
    remainM: remainM ?? this.remainM,
    totalM: totalM ?? this.totalM,
    hit50: hit50 ?? this.hit50,
    hit90: hit90 ?? this.hit90,
    line: clearLine ? null : (line ?? this.line),
  );
}

final playNavigationProvider = NotifierProvider.autoDispose
    .family<PlayNavigationController, PlayNavigationState, PlaySessionKey>(
      PlayNavigationController.new,
    );

class PlayNavigationController extends Notifier<PlayNavigationState> {
  PlayNavigationController(this._key);

  final PlaySessionKey _key;
  StreamSubscription<PlayNavigationPosition>? _locationSubscription;
  Timer? _bubbleTimer;
  PlayNode? _target;
  int _navigationGeneration = 0;
  int _lineRequestGeneration = 0;
  int _lineDisplayGeneration = 0;

  @override
  PlayNavigationState build() {
    ref.onDispose(() {
      unawaited(_locationSubscription?.cancel());
      _bubbleTimer?.cancel();
    });
    return const PlayNavigationState();
  }

  Future<void> start(PlayNode node) async {
    if (node.latitude == null || node.longitude == null) return;
    final int navigationGeneration = ++_navigationGeneration;
    await _locationSubscription?.cancel();
    _bubbleTimer?.cancel();
    _lineRequestGeneration += 1;
    final PlayNavigationPosition origin = await ref
        .read(playNavigationLocationSourceProvider)
        .current();
    if (!ref.mounted || navigationGeneration != _navigationGeneration) return;
    final double totalM = Geolocator.distanceBetween(
      origin.latitude,
      origin.longitude,
      node.latitude!,
      node.longitude!,
    );
    _target = node;
    state = PlayNavigationState(
      targetNodeId: node.nodeId,
      targetName: node.name,
      remainM: totalM.round(),
      totalM: totalM > 0 ? totalM : 1,
    );
    _locationSubscription = ref
        .read(playNavigationLocationSourceProvider)
        .watch()
        .listen(
          (PlayNavigationPosition next) => unawaited(_accept(next)),
          onError: (_) {},
        );
  }

  Future<void> stop() async {
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    _bubbleTimer?.cancel();
    _target = null;
    _navigationGeneration += 1;
    _lineRequestGeneration += 1;
    _lineDisplayGeneration += 1;
    state = const PlayNavigationState();
  }

  Future<void> _accept(PlayNavigationPosition next) async {
    final PlayNode? target = _target;
    if (target == null || !state.active) return;
    final double remainM = Geolocator.distanceBetween(
      next.latitude,
      next.longitude,
      target.latitude!,
      target.longitude!,
    );
    state = state.copyWith(remainM: remainM.round());
    final double ratio = 1 - remainM / state.totalM;
    if (ratio >= 0.9 && !state.hit90) {
      state = state.copyWith(hit90: true);
      await _fetchCompanionLine();
    } else if (ratio >= 0.5 && !state.hit50) {
      state = state.copyWith(hit50: true);
      await _fetchCompanionLine();
    }
  }

  Future<void> _fetchCompanionLine() async {
    final int generation = ++_lineRequestGeneration;
    try {
      final String? line = await ref
          .read(playSessionProvider(_key).notifier)
          .companionLine();
      if (!ref.mounted ||
          generation != _lineRequestGeneration ||
          line == null) {
        return;
      }
      state = state.copyWith(line: line);
      _bubbleTimer?.cancel();
      final int displayGeneration = ++_lineDisplayGeneration;
      _bubbleTimer = Timer(ref.read(playCompanionDisplayDurationProvider), () {
        if (ref.mounted && displayGeneration == _lineDisplayGeneration) {
          state = state.copyWith(clearLine: true);
        }
      });
    } catch (_) {
      // 途中台词是非阻断增强；网络失败不打断导航和打卡。
    }
  }
}
