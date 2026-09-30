import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/network/dio_client.dart';
import '../../core/providers.dart';
import '../../core/util/coord.dart';
import '../../data/api/roam_api.dart';
import '../../data/models/official_event.dart';
import '../../data/models/roam.dart';
import '../../data/models/roam_session.dart' as history;
import '../../data/models/roam_social.dart';
import 'roam_history_page.dart';
import 'roam_live_math.dart';

enum RoamLivePhase { idle, starting, roaming, finishing, finished }

enum RoamBadgeConfigStatus { notLoaded, enabled, disabled, unknown }

class RoamLivePosition {
  const RoamLivePosition({
    required this.latitude,
    required this.longitude,
    this.accuracyM = 0,
  });

  final double latitude;
  final double longitude;
  final double accuracyM;
}

class RoamLiveState {
  const RoamLiveState({
    this.phase = RoamLivePhase.idle,
    this.sessionId = '0',
    this.location,
    this.track = const <RoamLivePosition>[],
    this.revealedTiles = const <String>{},
    this.pois = const <RoamPoi>[],
    this.discoveredPoiIds = const <int>{},
    this.visitedShopIds = const <int>{},
    this.newlyRevealed = 0,
    this.distanceM = 0,
    this.actionBusy = false,
    this.actionMessage,
    this.lastXpAwarded = 0,
    this.shops = 0,
    this.badgeConfigStatus = RoamBadgeConfigStatus.notLoaded,
    this.badgeConfig,
    this.optimisticBadge,
    this.finishResult,
    this.alreadySettled = false,
    this.boundEvent,
    this.boundMissionCode,
    this.arrivalBusy = false,
    this.arrivalCompleted = false,
    this.arrivalMessage,
    this.nearbyRunners = const <RoamRunner>[],
    this.hangoutNear,
    this.error,
  });

  final RoamLivePhase phase;
  final String sessionId;
  final RoamLivePosition? location;
  final List<RoamLivePosition> track;
  final Set<String> revealedTiles;
  final List<RoamPoi> pois;
  final Set<int> discoveredPoiIds;
  final Set<int> visitedShopIds;
  final int newlyRevealed;
  final int distanceM;
  final bool actionBusy;
  final String? actionMessage;
  final int lastXpAwarded;
  final int shops;
  final RoamBadgeConfigStatus badgeConfigStatus;
  final ShopStreakBadge? badgeConfig;
  final ShopStreakBadge? optimisticBadge;
  final RoamFinishResult? finishResult;
  final bool alreadySettled;
  final OfficialEvent? boundEvent;
  final String? boundMissionCode;
  final bool arrivalBusy;
  final bool arrivalCompleted;
  final String? arrivalMessage;

  /// 附近还在走的人(服务端截位后的位置,只用于「看得出有人在走」)。
  final List<RoamRunner> nearbyRunners;

  /// 附近有人在组局那张卡(null = 没拉到或已关掉)。
  final RoamHangoutItem? hangoutNear;
  final String? error;

  RoamLiveState copyWith({
    RoamLivePhase? phase,
    String? sessionId,
    RoamLivePosition? location,
    List<RoamLivePosition>? track,
    Set<String>? revealedTiles,
    List<RoamPoi>? pois,
    Set<int>? discoveredPoiIds,
    Set<int>? visitedShopIds,
    int? newlyRevealed,
    int? distanceM,
    bool? actionBusy,
    String? actionMessage,
    int? lastXpAwarded,
    int? shops,
    RoamBadgeConfigStatus? badgeConfigStatus,
    ShopStreakBadge? badgeConfig,
    ShopStreakBadge? optimisticBadge,
    bool clearOptimisticBadge = false,
    RoamFinishResult? finishResult,
    bool? alreadySettled,
    OfficialEvent? boundEvent,
    String? boundMissionCode,
    bool? arrivalBusy,
    bool? arrivalCompleted,
    String? arrivalMessage,
    List<RoamRunner>? nearbyRunners,
    RoamHangoutItem? hangoutNear,
    bool clearHangoutNear = false,
    String? error,
    bool clearError = false,
    bool clearActionMessage = false,
  }) {
    return RoamLiveState(
      phase: phase ?? this.phase,
      sessionId: sessionId ?? this.sessionId,
      location: location ?? this.location,
      track: track ?? this.track,
      revealedTiles: revealedTiles ?? this.revealedTiles,
      pois: pois ?? this.pois,
      discoveredPoiIds: discoveredPoiIds ?? this.discoveredPoiIds,
      visitedShopIds: visitedShopIds ?? this.visitedShopIds,
      newlyRevealed: newlyRevealed ?? this.newlyRevealed,
      distanceM: distanceM ?? this.distanceM,
      actionBusy: actionBusy ?? this.actionBusy,
      actionMessage: clearActionMessage
          ? null
          : (actionMessage ?? this.actionMessage),
      lastXpAwarded: lastXpAwarded ?? this.lastXpAwarded,
      shops: shops ?? this.shops,
      badgeConfigStatus: badgeConfigStatus ?? this.badgeConfigStatus,
      badgeConfig: badgeConfig ?? this.badgeConfig,
      optimisticBadge: clearOptimisticBadge
          ? null
          : (optimisticBadge ?? this.optimisticBadge),
      finishResult: finishResult ?? this.finishResult,
      alreadySettled: alreadySettled ?? this.alreadySettled,
      boundEvent: boundEvent ?? this.boundEvent,
      boundMissionCode: boundMissionCode ?? this.boundMissionCode,
      arrivalBusy: arrivalBusy ?? this.arrivalBusy,
      arrivalCompleted: arrivalCompleted ?? this.arrivalCompleted,
      arrivalMessage: arrivalMessage ?? this.arrivalMessage,
      nearbyRunners: nearbyRunners ?? this.nearbyRunners,
      hangoutNear: clearHangoutNear ? null : (hangoutNear ?? this.hangoutNear),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

abstract interface class RoamLocationSource {
  Future<RoamLivePosition> current();

  Stream<RoamLivePosition> watch();
}

class RoamLocationException implements Exception {
  const RoamLocationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GeolocatorRoamLocationSource implements RoamLocationSource {
  @override
  Future<RoamLivePosition> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const RoamLocationException('请开启系统定位后重试');
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const RoamLocationException('定位权限已被永久关闭，请到系统设置中开启');
    }
    if (permission == LocationPermission.denied) {
      throw const RoamLocationException('需要定位权限才能开始实时漫游');
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
  Stream<RoamLivePosition> watch() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).map(_convert);
  }

  RoamLivePosition _convert(Position position) {
    final gcj = wgs84ToGcj02(position.longitude, position.latitude);
    return RoamLivePosition(
      latitude: gcj.lat,
      longitude: gcj.lng,
      accuracyM: position.accuracy,
    );
  }
}

final roamLocationSourceProvider = Provider<RoamLocationSource>(
  (_) => GeolocatorRoamLocationSource(),
);

final roamLiveControllerProvider =
    NotifierProvider.autoDispose<RoamLiveController, RoamLiveState>(
      RoamLiveController.new,
    );

class RoamLiveController extends Notifier<RoamLiveState> {
  StreamSubscription<RoamLivePosition>? _locationSubscription;
  int _locationGeneration = 0;
  var _positionBusy = false;
  String? _arrivalRequestId;
  DateTime? _startedAt;

  /// 附近的人心跳:上报 30s 一次、拉别人 45s 一次(与小程序同一档节奏)。
  /// ★ 停止上报 = 立刻消失:退出漫游/关定位/结算都会让 _acceptPosition 不再被调用,
  ///   服务端 5 分钟没收到就把你从别人的地图上摘掉。这是「在线」唯一的开关,
  ///   不另做一个能勾却不影响上报的假开关。
  DateTime? _presenceAt;
  DateTime? _runnersAt;
  DateTime? _hangoutAt;
  String? _hangoutDismissedId;

  @override
  RoamLiveState build() {
    ref.onDispose(() {
      unawaited(_locationSubscription?.cancel());
    });
    return const RoamLiveState();
  }

  Future<void> start({
    required bool purposeAccepted,
    int? eventId,
    String? missionCode,
  }) async {
    if (!purposeAccepted || state.phase == RoamLivePhase.starting) return;
    final int generation = ++_locationGeneration;
    _startedAt = null;
    state = const RoamLiveState(phase: RoamLivePhase.starting);
    try {
      final RoamLivePosition position = await ref
          .read(roamLocationSourceProvider)
          .current();
      final List<RoamTile> historical = await _loadHistoricalTiles();
      final String firstKey = roamTileKey(
        position.latitude,
        position.longitude,
      );
      final RoamRevealResult reveal = await ref
          .read(roamApiProvider)
          .revealTiles(sessionId: '0', tiles: <String>[firstKey]);
      if (!ref.mounted || generation != _locationGeneration) return;
      state = RoamLiveState(
        phase: RoamLivePhase.roaming,
        sessionId: reveal.sessionId,
        location: position,
        track: <RoamLivePosition>[position],
        revealedTiles: <String>{
          ...historical.map((RoamTile tile) => tile.key),
          firstKey,
        },
        newlyRevealed: reveal.newlyRevealed,
      );
      _startedAt = DateTime.now();
      try {
        final List<RoamPoi> pois = await ref
            .read(roamApiProvider)
            .pois(lat: position.latitude, lng: position.longitude);
        if (!ref.mounted) return;
        state = state.copyWith(pois: pois);
      } catch (error) {
        if (ref.mounted) {
          state = state.copyWith(
            error: friendlyErrorMessage(error, fallback: '附近地点没加载出来'),
          );
        }
      }
      await _loadBadgeConfig();
      if (eventId != null && eventId > 0) {
        await _loadBoundEvent(eventId, missionCode);
      }
      if (!ref.mounted || generation != _locationGeneration) return;
      // 开局先报一次心跳,再按位移继续 —— 拉不到就是别人还看不见我,
      // 不是这一局开不起来,所以这两条都是静默的。
      unawaited(_reportPresence(position));
      unawaited(_fetchRunners(position));
      unawaited(_fetchNearbyHangout(position));
      _locationSubscription = ref
          .read(roamLocationSourceProvider)
          .watch()
          .listen(
            (RoamLivePosition next) => unawaited(_acceptPosition(next)),
            onError: (Object error, StackTrace _) {
              if (!ref.mounted) return;
              state = state.copyWith(
                error: friendlyErrorMessage(error, fallback: '位置更新中断，请稍后重试'),
              );
            },
          );
    } catch (error) {
      state = RoamLiveState(
        error: friendlyErrorMessage(error, fallback: '这次漫游没能开始，请重试'),
      );
    }
  }

  /// 撤回定位同意后立即停止传感器事件与新轨迹写入；不伪造服务端结算。
  Future<void> stopLocationTracking() async {
    _locationGeneration += 1;
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    _positionBusy = false;
    if (ref.mounted &&
        (state.phase == RoamLivePhase.starting ||
            state.phase == RoamLivePhase.roaming ||
            state.phase == RoamLivePhase.finishing)) {
      state = state.copyWith(phase: RoamLivePhase.idle);
    }
  }

  /// 恢复版图:一次最多 2000 格,按游标翻页(小程序同一条链
  /// `GET /api/roam/tiles/page`)。翻到没有下一页为止 —— 老版一次性读
  /// `/api/roam/tiles` 有 5000 上限,重装设备后版图会缺一块。
  Future<List<RoamTile>> _loadHistoricalTiles() async {
    final List<RoamTile> out = <RoamTile>[];
    int afterId = 0;
    for (int page = 0; page < 10; page++) {
      final RoamTilePage result = await ref
          .read(roamApiProvider)
          .tilesPage(afterId: afterId, limit: 1000);
      out.addAll(result.tiles.map((String key) => RoamTile(key: key)));
      if (!result.hasMore || result.nextAfterId <= afterId) break;
      afterId = result.nextAfterId;
    }
    return out;
  }

  /// 本机 20×20 格的口径(与小程序同源);后端只存不算,并会再 clamp 一次。
  int _explorePct() {
    final int pct = (state.revealedTiles.length * 100) ~/ 400;
    return pct.clamp(0, 99);
  }

  Future<void> _reportPresence(RoamLivePosition position) async {
    final int sessionId = int.tryParse(state.sessionId) ?? 0;
    if (sessionId <= 0 || state.phase != RoamLivePhase.roaming) return;
    final DateTime now = DateTime.now();
    if (_presenceAt != null &&
        now.difference(_presenceAt!) < const Duration(seconds: 30)) {
      return;
    }
    _presenceAt = now;
    try {
      await ref
          .read(roamApiProvider)
          .reportPresence(
            sessionId: state.sessionId,
            lat: position.latitude,
            lng: position.longitude,
            explorePct: _explorePct(),
          );
    } catch (_) {
      // 静默:心跳失败不该打断一次漫游。
    }
  }

  Future<void> _fetchRunners(RoamLivePosition position) async {
    final DateTime now = DateTime.now();
    if (_runnersAt != null &&
        now.difference(_runnersAt!) < const Duration(seconds: 45)) {
      return;
    }
    _runnersAt = now;
    try {
      final List<RoamRunner> rows = await ref
          .read(roamApiProvider)
          .nearbyRunners(lat: position.latitude, lng: position.longitude);
      if (!ref.mounted) return;
      // 一个人都没有也要落:上一批里走远的人得消失。
      state = state.copyWith(nearbyRunners: rows);
    } catch (_) {
      // 拉不到保持上一批,不清空 —— 闪掉再回来更难看。
    }
  }

  Future<void> _fetchNearbyHangout(RoamLivePosition position) async {
    final DateTime now = DateTime.now();
    if (_hangoutAt != null &&
        now.difference(_hangoutAt!) < const Duration(seconds: 45)) {
      return;
    }
    _hangoutAt = now;
    try {
      final RoamHangoutNearby nearby = await ref
          .read(roamApiProvider)
          .hangoutNearby(lat: position.latitude, lng: position.longitude);
      if (!ref.mounted) return;
      final RoamHangoutItem? row = nearby.items
          .where((RoamHangoutItem item) => item.isHangout)
          .firstOrNull;
      if (row == null) {
        state = state.copyWith(clearHangoutNear: true);
        return;
      }
      if (_hangoutDismissedId == row.id.toString()) return;
      state = state.copyWith(hangoutNear: row);
    } catch (_) {
      // 拉不到就保持上一张,不闪。
    }
  }

  /// 关掉那张「附近有人在组局」的卡:这一次不想看,下一轮别再浮出来。
  void dismissHangoutNear() {
    final RoamHangoutItem? current = state.hangoutNear;
    if (current != null) _hangoutDismissedId = current.id.toString();
    state = state.copyWith(clearHangoutNear: true);
  }

  Future<void> _loadBadgeConfig() async {
    try {
      final ShopStreakBadge? config = await ref
          .read(roamApiProvider)
          .shopStreakBadge();
      if (!ref.mounted) return;
      state = state.copyWith(
        badgeConfigStatus: config == null
            ? RoamBadgeConfigStatus.disabled
            : RoamBadgeConfigStatus.enabled,
        badgeConfig: config,
      );
    } catch (_) {
      if (ref.mounted) {
        state = state.copyWith(
          badgeConfigStatus: RoamBadgeConfigStatus.unknown,
        );
      }
    }
  }

  Future<void> _loadBoundEvent(int eventId, String? missionCode) async {
    try {
      final OfficialEvent event = await ref
          .read(officialApiProvider)
          .detail(eventId);
      if (!ref.mounted) return;
      final String? selected = _selectArrivalMission(event, missionCode);
      state = state.copyWith(
        boundEvent: event,
        boundMissionCode: selected,
        arrivalMessage: selected == null ? '本活动当前没有可验证的到达任务' : null,
      );
    } catch (error) {
      if (ref.mounted) {
        debugPrint('[roam-live] 活动信息读取失败: $error');
        state = state.copyWith(
          arrivalMessage: friendlyOrBackendMessage(
            error,
            fallback: '活动信息没能读取，请稍后重试',
          ),
        );
      }
    }
  }

  String? _selectArrivalMission(OfficialEvent event, String? preferred) {
    for (final OfficialMission mission in event.missions) {
      if (mission.missionCode == preferred &&
          mission.canVerifyArrival &&
          !mission.complete) {
        return mission.missionCode;
      }
    }
    for (final OfficialMission mission in event.missions) {
      if (mission.canVerifyArrival && !mission.complete) {
        return mission.missionCode;
      }
    }
    return null;
  }

  Future<void> verifyOfficialArrival() async {
    if (state.phase != RoamLivePhase.roaming || state.arrivalBusy) return;
    final OfficialEvent? event = state.boundEvent;
    final String? missionCode = state.boundMissionCode;
    final RoamLivePosition? location = state.location;
    final int? sessionId = int.tryParse(state.sessionId);
    if (event == null || missionCode == null || location == null) return;
    if (!event.signed) {
      state = state.copyWith(arrivalMessage: '请先报名；报名后的新到达才会计入本场活动。');
      return;
    }
    if (event.paused) {
      state = state.copyWith(arrivalMessage: '活动当前暂停，暂不接受新的到达验证。');
      return;
    }
    if (event.status != 3) {
      state = state.copyWith(arrivalMessage: '活动尚未进行中，暂不能验证到达。');
      return;
    }
    if (sessionId == null || sessionId <= 0) {
      state = state.copyWith(arrivalMessage: '先开始漫游并建立本次会话后再验证。');
      return;
    }
    _arrivalRequestId ??=
        'arrival-${event.id}-$missionCode-${DateTime.now().millisecondsSinceEpoch}';
    state = state.copyWith(arrivalBusy: true, arrivalMessage: '正在核验到达…');
    try {
      final OfficialArrivalResult result = await ref
          .read(officialApiProvider)
          .verifyArrival(
            eventId: event.id,
            missionCode: missionCode,
            latitude: location.latitude,
            longitude: location.longitude,
            accuracyM: location.accuracyM,
            sessionId: sessionId,
            requestId: _arrivalRequestId!,
          );
      if (!ref.mounted) return;
      if (result.accepted) {
        state = state.copyWith(
          arrivalBusy: false,
          arrivalCompleted: result.completed,
          arrivalMessage: result.completed
              ? '验证成功，任务证据已写入本场活动。'
              : '到达证据已写入，等待任务条件完成。',
        );
      } else {
        _arrivalRequestId = null;
        state = state.copyWith(
          arrivalBusy: false,
          arrivalMessage: _arrivalReason(result.reason),
        );
      }
    } catch (error) {
      if (ref.mounted) {
        // 异常原文只进日志 —— 上屏的永远是人话(后端原话优先)。
        debugPrint('[roam-live] 到达验证失败: $error');
        state = state.copyWith(
          arrivalBusy: false,
          arrivalMessage: friendlyOrBackendMessage(
            error,
            fallback: '验证没有送达，请稍后重试',
          ),
        );
      }
    }
  }

  String _arrivalReason(String? reason) {
    return switch (reason) {
      'NOT_SIGNED' => '当前报名资格无效，不能写入活动证据。',
      'ACTIVITY_NOT_LIVE' => '活动不在进行中，不能验证到达。',
      'LOCATION_INVALID' => '定位数据无效，请在地图定位稳定后重试。',
      'LOCATION_ACCURACY_TOO_LOW' => '定位精度不足，请到开阔处等待定位稳定后重试。',
      'DISTANCE_TOO_FAR' => '距离活动目标仍有一段距离，靠近后再验证。',
      'MOVE_TOO_FAST' => '位置变化异常快，本次验证已被风控拦截。',
      'ROAM_CONTEXT_REQUIRED' => '缺少本次漫游会话，先开始漫游再验证。',
      'SESSION_NOT_OWNED' => '本次漫游会话不属于当前账号。',
      'POI_UNAVAILABLE' => '活动引用点当前不可用，已反馈给运营。',
      'EVENT_POINT_ADAPTER_DISABLED' => '活动自有点验证尚未完成安全核验，暂不计奖。',
      'EVENT_POINT_CONFIG_INVALID' => '活动自有点配置不完整，暂不能验证。',
      _ => '服务端没有接受本次到达验证，请稍后重试。',
    };
  }

  Future<void> discoverPoi(int poiId) async {
    if (state.phase != RoamLivePhase.roaming || state.actionBusy) return;
    final RoamLivePosition? location = state.location;
    final int? sessionId = int.tryParse(state.sessionId);
    final RoamPoi? poi = _poiById(poiId);
    if (location == null ||
        sessionId == null ||
        sessionId <= 0 ||
        poi == null) {
      state = state.copyWith(error: '当前漫游状态不可用，请重新开始');
      return;
    }
    if (poi.type == 2) {
      state = state.copyWith(error: '商户据点请使用到店打卡');
      return;
    }
    state = state.copyWith(
      actionBusy: true,
      clearError: true,
      clearActionMessage: true,
      lastXpAwarded: 0,
    );
    try {
      final RoamPoiDiscovered result = await ref
          .read(roamApiProvider)
          .discoverPoi(
            sessionId: sessionId,
            poiId: poi.id,
            lat: location.latitude,
            lng: location.longitude,
          );
      if (!ref.mounted) return;
      state = state.copyWith(
        actionBusy: false,
        discoveredPoiIds: <int>{...state.discoveredPoiIds, poi.id},
        actionMessage: result.message,
        lastXpAwarded: result.discovered ? result.xp : 0,
      );
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          actionBusy: false,
          error: friendlyErrorMessage(error, fallback: '这个地点没能打卡，请稍后再试'),
        );
      }
    }
  }

  Future<void> visitShop(int poiId) async {
    if (state.phase != RoamLivePhase.roaming || state.actionBusy) return;
    final RoamLivePosition? location = state.location;
    final int? sessionId = int.tryParse(state.sessionId);
    final RoamPoi? poi = _poiById(poiId);
    if (location == null ||
        sessionId == null ||
        sessionId <= 0 ||
        poi == null) {
      state = state.copyWith(error: '当前漫游状态不可用，请重新开始');
      return;
    }
    if (poi.type != 2) {
      state = state.copyWith(error: '这个地点不属于商户据点');
      return;
    }
    state = state.copyWith(
      actionBusy: true,
      clearError: true,
      clearActionMessage: true,
      lastXpAwarded: 0,
    );
    try {
      final RoamShopVisit visit = await ref
          .read(roamApiProvider)
          .shopVisit(
            sessionId: sessionId,
            sourceType: 1,
            sourceId: poi.id,
            lat: location.latitude,
            lng: location.longitude,
          );
      if (!ref.mounted) return;
      state = state.copyWith(
        actionBusy: false,
        visitedShopIds: visit.recorded
            ? <int>{...state.visitedShopIds, poi.id}
            : state.visitedShopIds,
        shops: visit.shops,
        optimisticBadge:
            visit.recorded &&
                state.badgeConfigStatus == RoamBadgeConfigStatus.enabled &&
                state.badgeConfig?.threshold != null &&
                visit.shops == state.badgeConfig!.threshold
            ? state.badgeConfig
            : null,
        actionMessage: visit.recorded ? '到店已记录' : '这家店本次漫游已打过卡',
      );
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          actionBusy: false,
          error: friendlyErrorMessage(error, fallback: '到店打卡没成功，请稍后再试'),
        );
      }
    }
  }

  void dismissOptimisticBadge() {
    state = state.copyWith(clearOptimisticBadge: true);
  }

  /// 点地图针(城市地点)→ `POST /api/roam/checkin`,对应源 `onPoiTap`。
  ///
  /// ★ 三态一律以服务端回执为准([RoamCheckinResult]):太远 / 参与据点(要
  ///   扫码,带 poiId 交页面跳据点详情) / 已点亮(首亮才发探索值)。
  ///   源用地图中心当「我在哪」判距离,App 有真定位,直接取 [state.location]。
  Future<RoamCheckinResult?> checkinPin({
    required String name,
    required double poiLat,
    required double poiLng,
  }) async {
    if (state.phase != RoamLivePhase.roaming || state.actionBusy) return null;
    final RoamLivePosition? location = state.location;
    if (location == null) {
      state = state.copyWith(error: '当前漫游状态不可用，请重新开始');
      return null;
    }
    state = state.copyWith(
      actionBusy: true,
      clearError: true,
      clearActionMessage: true,
      lastXpAwarded: 0,
    );
    try {
      final RoamCheckinResult result = await ref
          .read(roamApiProvider)
          .checkin(
            name: name,
            poiLat: poiLat,
            poiLng: poiLng,
            curLat: location.latitude,
            curLng: location.longitude,
          );
      if (!ref.mounted) return null;
      state = state.copyWith(
        actionBusy: false,
        actionMessage: result.message,
        lastXpAwarded:
            result.outcome == RoamCheckinOutcome.lit && result.firstVisit
            ? result.xp
            : 0,
      );
      return result;
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          actionBusy: false,
          error: friendlyErrorMessage(error, fallback: '这个地点没能打卡，请稍后再试'),
        );
      }
      return null;
    }
  }

  Future<void> finish() async {
    if (state.phase != RoamLivePhase.roaming || state.actionBusy) return;
    final int? sessionId = int.tryParse(state.sessionId);
    if (sessionId == null || sessionId <= 0) {
      state = state.copyWith(error: '漫游会话尚未建立，暂时无法结算');
      return;
    }
    state = state.copyWith(
      phase: RoamLivePhase.finishing,
      clearError: true,
      clearActionMessage: true,
    );
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    try {
      final RoamFinishResult result = await ref
          .read(roamApiProvider)
          .finishSession(
            sessionId: state.sessionId,
            poiIds: state.discoveredPoiIds.toList(),
            distanceM: state.distanceM,
          );
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: RoamLivePhase.finished,
        finishResult: result,
        clearOptimisticBadge: true,
      );
      await _persistSession(result);
    } catch (error) {
      if (!ref.mounted) return;
      if (error.toString().contains('本次漫游已结算')) {
        // 已结算**不是失败**,但这条错误只说不重复发,没带回结果。
        // 按 sessionId 读回事实(快照 `pages/roam/index.js:1459` 的 FINISHED 分支
        // 就是拿 `fact.result` 直接展示)—— 有结果就补上,
        // 别让用户看到一张没有探索值的「已结算」白卡。
        RoamFinishResult? settled;
        try {
          final RoamSessionFact fact = await ref
              .read(roamApiProvider)
              .sessionFact(sessionId: sessionId);
          if (fact.state == RoamSessionState.finished) settled = fact.result;
        } catch (_) {
          // 读不回来不影响「已结算」这个结论:保持原样,不编数字。
        }
        if (!ref.mounted) return;
        state = state.copyWith(
          phase: RoamLivePhase.finished,
          alreadySettled: true,
          finishResult: settled,
          clearOptimisticBadge: true,
        );
      } else {
        state = state.copyWith(
          phase: RoamLivePhase.roaming,
          error: friendlyErrorMessage(error, fallback: '这次漫游没能结算，请重试'),
        );
      }
    }
  }

  Future<void> _persistSession(RoamFinishResult result) async {
    final DateTime now = DateTime.now();
    final int durSec = now.difference(_startedAt ?? now).inSeconds;
    final Set<int> completed = <int>{
      ...state.discoveredPoiIds,
      ...state.visitedShopIds,
    };
    final List<history.RoamPoi> pois = state.pois
        .where((RoamPoi poi) => completed.contains(poi.id))
        .map(
          (RoamPoi poi) => history.RoamPoi(
            id: poi.id,
            name: poi.name,
            cat: poi.type == 2 ? 'merchant' : 'landmark',
            lat: poi.lat,
            lng: poi.lng,
          ),
        )
        .toList(growable: false);
    final List<history.RoamPoint> track = <history.RoamPoint>[
      for (int index = 0; index < state.track.length; index += 3)
        history.RoamPoint(
          lat: state.track[index].latitude,
          lng: state.track[index].longitude,
        ),
    ];
    final String hh = now.hour.toString().padLeft(2, '0');
    final String mm = now.minute.toString().padLeft(2, '0');
    try {
      await ref
          .read(roamSessionStoreProvider)
          .prepend(
            history.RoamSession(
              ts: now.millisecondsSinceEpoch,
              zone: '这片街区',
              date: '${now.month}月${now.day}日',
              dateLine: '今天 · ${now.hour < 12 ? '上午' : '下午'} $hh:$mm',
              distance: state.distanceM / 1000,
              shops: result.sessionShops,
              time: history.formatRoamDuration(durSec),
              durSec: durSec,
              pois: pois,
              track: track,
              medal: result.medal,
              shopMedalName: result.shopMedal?.name,
              // 真源 pages/roam/index.js finish 块 `explorePct: this._stats.explorePct`;
              // 源里的 `photos: _sessionPhotos.slice(-8)` 依赖探店相机流程,App 尚无
              // session 照片生产者,暂不落(登记为依赖未建)。
              explorePct: _explorePct(),
            ),
          );
      if (ref.mounted) ref.invalidate(roamHistoryProvider);
    } catch (_) {
      // 与小程序一致：本地护照落盘失败不能推翻服务端结算事实。
    }
  }

  RoamPoi? _poiById(int poiId) {
    for (final RoamPoi poi in state.pois) {
      if (poi.id == poiId) return poi;
    }
    return null;
  }

  Future<void> _acceptPosition(RoamLivePosition next) async {
    if (_positionBusy || state.phase != RoamLivePhase.roaming) return;
    if (next.accuracyM > 80) return;
    final RoamLivePosition? previous = state.location;
    if (previous == null) return;
    final double moved = roamDistanceMeters(
      previous.latitude,
      previous.longitude,
      next.latitude,
      next.longitude,
    );
    if (moved < 3) return;
    if (moved > 120) {
      state = state.copyWith(location: next, clearError: true);
      unawaited(_reportPresence(next));
      unawaited(_fetchRunners(next));
      unawaited(_fetchNearbyHangout(next));
      return;
    }

    final int distanceM = state.distanceM + moved.round();
    final List<RoamLivePosition> track = <RoamLivePosition>[
      ...state.track,
      next,
    ];
    final String key = roamTileKey(next.latitude, next.longitude);
    state = state.copyWith(
      location: next,
      track: track,
      distanceM: distanceM,
      clearError: true,
    );
    unawaited(_reportPresence(next));
    unawaited(_fetchRunners(next));
    unawaited(_fetchNearbyHangout(next));
    if (state.revealedTiles.contains(key)) return;

    _positionBusy = true;
    try {
      final RoamRevealResult reveal = await ref
          .read(roamApiProvider)
          .revealTiles(sessionId: state.sessionId, tiles: <String>[key]);
      if (!ref.mounted) return;
      state = state.copyWith(
        sessionId: reveal.sessionId,
        revealedTiles: <String>{...state.revealedTiles, key},
        newlyRevealed: state.newlyRevealed + reveal.newlyRevealed,
      );
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          error: friendlyErrorMessage(error, fallback: '迷雾加载失败，请重试'),
        );
      }
    } finally {
      _positionBusy = false;
    }
  }
}
