import 'dart:async';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/roam_api.dart';
import 'package:chengyin_app/data/api/official_api.dart';
import 'package:chengyin_app/data/models/official_event.dart';
import 'package:chengyin_app/data/models/roam.dart';
import 'package:chengyin_app/data/models/roam_session.dart' as history;
import 'package:chengyin_app/data/models/roam_social.dart';
import 'package:chengyin_app/feature/roam/roam_live_controller.dart';
import 'package:chengyin_app/feature/roam/roam_session_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRoamApi implements RoamApi {
  final List<List<String>> revealBatches = <List<String>>[];
  final List<({int sessionId, int poiId, double lat, double lng})>
  discoverRequests = <({int sessionId, int poiId, double lat, double lng})>[];
  final List<({int sessionId, int sourceType, int sourceId})>
  shopVisitRequests = <({int sessionId, int sourceType, int sourceId})>[];
  final List<RoamShopVisit> shopVisitResults = <RoamShopVisit>[
    const RoamShopVisit(recorded: false, shops: 0),
    const RoamShopVisit(recorded: true, shops: 1),
  ];
  ShopStreakBadge? badgeConfig = const ShopStreakBadge(
    code: 'ROAM_SHOP_STREAK',
    name: '三店连亮',
    threshold: 3,
  );
  RoamFinishResult finishResult = const RoamFinishResult(
    totalXp: 70,
    newTiles: 2,
    newPois: 1,
    sessionShops: 3,
    shopMedal: ShopStreakBadge(code: 'ROAM_SHOP_STREAK', name: '服务端真章'),
  );
  final List<({String sessionId, List<int> poiIds, int distanceM})>
  finishRequests = <({String sessionId, List<int> poiIds, int distanceM})>[];

  /// 结算回「本次漫游已结算」(CAS 重试保护)的开关。
  bool finishAlreadySettled = false;

  /// `GET /api/roam/session` 的回执;null = 调用直接失败。
  RoamSessionFact? sessionFactReply;
  final List<({String? key, int? sessionId})> sessionFactRequests =
      <({String? key, int? sessionId})>[];

  final List<
    ({String name, double poiLat, double poiLng, double curLat, double curLng})
  >
  checkinRequests =
      <
        ({
          String name,
          double poiLat,
          double poiLng,
          double curLat,
          double curLng,
        })
      >[];
  RoamCheckinResult checkinReply = const RoamCheckinResult(
    outcome: RoamCheckinOutcome.lit,
    message: '已点亮',
    firstVisit: true,
    xp: 20,
  );
  Object? checkinError;
  Completer<void>? checkinGate;
  Object? revealError;

  @override
  Future<RoamCheckinResult> checkin({
    required String name,
    required double poiLat,
    required double poiLng,
    required double curLat,
    required double curLng,
  }) async {
    checkinRequests.add((
      name: name,
      poiLat: poiLat,
      poiLng: poiLng,
      curLat: curLat,
      curLng: curLng,
    ));
    if (checkinGate != null) await checkinGate!.future;
    if (checkinError != null) throw checkinError!;
    return checkinReply;
  }

  @override
  Future<RoamSessionFact> sessionFact({
    String? clientSessionKey,
    int? sessionId,
  }) async {
    sessionFactRequests.add((key: clientSessionKey, sessionId: sessionId));
    final RoamSessionFact? reply = sessionFactReply;
    if (reply == null) throw RoamApiException('漫游状态没能核对');
    return reply;
  }

  @override
  Future<List<RoamTile>> tiles({int? limit}) async => const <RoamTile>[
    RoamTile(key: 'historical-tile'),
  ];

  /// 2026-09-15 起控制器改用带游标的分页读端恢复版图
  /// (`GET /api/roam/tiles/page`,一次 5000 上限的旧端点在大版图上会缺一块),
  /// 假 API 跟着补上这一条 —— 否则 start() 在第一次 await 就抛,状态停在 idle。
  @override
  Future<RoamTilePage> tilesPage({int afterId = 0, int limit = 1000}) async =>
      const RoamTilePage(
        tiles: <String>['historical-tile'],
        nextAfterId: 0,
        hasMore: false,
      );

  @override
  Future<RoamRevealResult> revealTiles({
    required String sessionId,
    required List<String> tiles,
  }) async {
    revealBatches.add(List<String>.of(tiles));
    if (sessionId != '0' && revealError != null) throw revealError!;
    return RoamRevealResult(
      sessionId: sessionId == '0' ? '72' : sessionId,
      newlyRevealed: 1,
    );
  }

  @override
  Future<List<RoamPoi>> pois({
    required double lat,
    required double lng,
    int? radiusM,
  }) async => const <RoamPoi>[
    RoamPoi(id: 9, name: '苏州河驿站', lat: 31.2304, lng: 121.4737, xp: 20),
    RoamPoi(id: 11, name: '河畔咖啡', lat: 31.2304, lng: 121.4737, type: 2),
  ];

  @override
  Future<RoamPoiDiscovered> discoverPoi({
    required int sessionId,
    required int poiId,
    required double lat,
    required double lng,
  }) async {
    discoverRequests.add((
      sessionId: sessionId,
      poiId: poiId,
      lat: lat,
      lng: lng,
    ));
    return const RoamPoiDiscovered(
      discovered: true,
      poiId: 9,
      xp: 20,
      message: '发现新地点',
    );
  }

  @override
  Future<RoamShopVisit> shopVisit({
    required int sessionId,
    required int sourceType,
    required int sourceId,
    required double lat,
    required double lng,
  }) async {
    shopVisitRequests.add((
      sessionId: sessionId,
      sourceType: sourceType,
      sourceId: sourceId,
    ));
    return shopVisitResults.removeAt(0);
  }

  @override
  Future<ShopStreakBadge?> shopStreakBadge() async => badgeConfig;

  @override
  Future<RoamFinishResult> finishSession({
    required String sessionId,
    required List<int> poiIds,
    required int distanceM,
  }) async {
    finishRequests.add((
      sessionId: sessionId,
      poiIds: List<int>.of(poiIds),
      distanceM: distanceM,
    ));
    if (finishAlreadySettled) throw Exception('本次漫游已结算');
    return finishResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOfficialApi implements OfficialApi {
  final List<
    ({int eventId, String missionCode, int sessionId, String requestId})
  >
  arrivalRequests =
      <({int eventId, String missionCode, int sessionId, String requestId})>[];

  @override
  Future<OfficialEvent> detail(int id) async => OfficialEvent(
    id: id,
    title: '沿河点亮计划',
    status: 3,
    signed: true,
    contractVersion: 2,
    missions: const <OfficialMission>[
      OfficialMission(
        missionCode: 'ARRIVE_RIVER',
        title: '抵达河畔',
        canVerifyArrival: true,
      ),
    ],
  );

  @override
  Future<OfficialArrivalResult> verifyArrival({
    required int eventId,
    required String missionCode,
    required double latitude,
    required double longitude,
    required double accuracyM,
    required int sessionId,
    required String requestId,
  }) async {
    arrivalRequests.add((
      eventId: eventId,
      missionCode: missionCode,
      sessionId: sessionId,
      requestId: requestId,
    ));
    return const OfficialArrivalResult(accepted: true, completed: true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocationSource implements RoamLocationSource {
  _FakeLocationSource() {
    _positions = StreamController<RoamLivePosition>.broadcast(
      onCancel: () => cancelCalls += 1,
    );
  }

  late final StreamController<RoamLivePosition> _positions;
  int cancelCalls = 0;

  @override
  Future<RoamLivePosition> current() async =>
      const RoamLivePosition(latitude: 31.2304, longitude: 121.4737);

  @override
  Stream<RoamLivePosition> watch() => _positions.stream;

  void emit(RoamLivePosition position) => _positions.add(position);

  Future<void> close() => _positions.close();
}

class _RecordingRoamSessionStore implements RoamSessionStore {
  final List<history.RoamSession> sessions = <history.RoamSession>[];

  @override
  Future<void> prepend(history.RoamSession session) async {
    sessions.insert(0, session);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 起一个「正在漫游」的现场:start() 成功后 phase=roaming、sessionId=72。
class _RoamFixture {
  _RoamFixture() {
    api = _FakeRoamApi();
    locations = _FakeLocationSource();
    container = ProviderContainer(
      overrides: [
        roamApiProvider.overrideWithValue(api),
        roamLocationSourceProvider.overrideWithValue(locations),
      ],
    );
    subscription = container.listen(roamLiveControllerProvider, (_, _) {});
  }

  late final _FakeRoamApi api;
  late final _FakeLocationSource locations;
  late final ProviderContainer container;
  late final ProviderSubscription<Object?> subscription;

  RoamLiveState get state => container.read(roamLiveControllerProvider);
  RoamLiveController get controller =>
      container.read(roamLiveControllerProvider.notifier);

  Future<void> start() => controller.start(purposeAccepted: true);

  Future<void> dispose() async {
    subscription.close();
    container.dispose();
    await locations.close();
  }
}

void main() {
  test('撤回定位同意会取消实时位置流且不再追加轨迹', () async {
    final _FakeRoamApi api = _FakeRoamApi();
    final _FakeLocationSource locations = _FakeLocationSource();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        roamApiProvider.overrideWithValue(api),
        roamLocationSourceProvider.overrideWithValue(locations),
      ],
    );
    final subscription = container.listen(
      roamLiveControllerProvider,
      (_, _) {},
    );
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await locations.close();
    });

    final RoamLiveController controller = container.read(
      roamLiveControllerProvider.notifier,
    );
    await controller.start(purposeAccepted: true);
    expect(container.read(roamLiveControllerProvider).track, hasLength(1));

    await controller.stopLocationTracking();
    locations.emit(
      const RoamLivePosition(latitude: 31.231, longitude: 121.474),
    );
    await Future<void>.delayed(Duration.zero);

    expect(locations.cancelCalls, 1);
    expect(container.read(roamLiveControllerProvider).track, hasLength(1));
    expect(
      container.read(roamLiveControllerProvider).phase,
      RoamLivePhase.idle,
    );
  });

  test('启动恢复历史瓦片，走入新格后以上报回执更新版图', () async {
    final _FakeRoamApi api = _FakeRoamApi();
    final _FakeLocationSource locations = _FakeLocationSource();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        roamApiProvider.overrideWithValue(api),
        roamLocationSourceProvider.overrideWithValue(locations),
      ],
    );
    final subscription = container.listen(
      roamLiveControllerProvider,
      (_, _) {},
    );
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await locations.close();
    });

    await container
        .read(roamLiveControllerProvider.notifier)
        .start(purposeAccepted: true);

    RoamLiveState state = container.read(roamLiveControllerProvider);
    expect(state.phase, RoamLivePhase.roaming);
    expect(state.sessionId, '72', reason: '后续 POI/到店/结算必须引用服务端创建的会话');
    expect(state.revealedTiles, contains('historical-tile'));
    expect(api.revealBatches, hasLength(1), reason: '起点必须立即揭示，不能等下一次 GPS 回调');

    locations.emit(
      const RoamLivePosition(latitude: 31.2304, longitude: 121.4746),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    state = container.read(roamLiveControllerProvider);
    expect(api.revealBatches, hasLength(2));
    expect(state.newlyRevealed, 2, reason: '点亮数只累计后端 newlyRevealed 回执');
    expect(state.track, hasLength(2));
    expect(state.distanceM, greaterThan(0));
  });

  test('★ 途中的迷雾揭示失败:HUD 上是归类后的人话,不是异常原文(gap-spec-roam 附10)', () async {
    final _FakeRoamApi api = _FakeRoamApi()
      ..revealError = Exception(
        'DioException [bad response]: Status Code: 500',
      );
    final _FakeLocationSource locations = _FakeLocationSource();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        roamApiProvider.overrideWithValue(api),
        roamLocationSourceProvider.overrideWithValue(locations),
      ],
    );
    final subscription = container.listen(
      roamLiveControllerProvider,
      (_, _) {},
    );
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await locations.close();
    });

    await container
        .read(roamLiveControllerProvider.notifier)
        .start(purposeAccepted: true);

    locations.emit(
      const RoamLivePosition(latitude: 31.2304, longitude: 121.4746),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final RoamLiveState state = container.read(roamLiveControllerProvider);
    expect(state.phase, RoamLivePhase.roaming, reason: '揭示失败不能把这一局打回 idle');
    expect(state.error, '迷雾加载失败，请重试');
    expect(state.error, isNot(contains('DioException')));
  });

  test('发现 POI 沿用服务端会话与实时坐标，并只庆祝首次发现', () async {
    final _FakeRoamApi api = _FakeRoamApi();
    final _FakeLocationSource locations = _FakeLocationSource();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        roamApiProvider.overrideWithValue(api),
        roamLocationSourceProvider.overrideWithValue(locations),
      ],
    );
    final subscription = container.listen(
      roamLiveControllerProvider,
      (_, _) {},
    );
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await locations.close();
    });

    await container
        .read(roamLiveControllerProvider.notifier)
        .start(purposeAccepted: true);
    await container.read(roamLiveControllerProvider.notifier).discoverPoi(9);

    final RoamLiveState state = container.read(roamLiveControllerProvider);
    expect(api.discoverRequests.single.sessionId, 72);
    expect(api.discoverRequests.single.poiId, 9);
    expect(api.discoverRequests.single.lat, closeTo(31.2304, 1e-6));
    expect(state.discoveredPoiIds, contains(9));
    expect(state.lastXpAwarded, 20, reason: '只有 discovered=true 才能展示本次获得的探索值');
  });

  test('到店完成态只认 shop/visit 的 recorded 回执', () async {
    final _FakeRoamApi api = _FakeRoamApi();
    final _FakeLocationSource locations = _FakeLocationSource();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        roamApiProvider.overrideWithValue(api),
        roamLocationSourceProvider.overrideWithValue(locations),
      ],
    );
    final subscription = container.listen(
      roamLiveControllerProvider,
      (_, _) {},
    );
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await locations.close();
    });

    await container
        .read(roamLiveControllerProvider.notifier)
        .start(purposeAccepted: true);
    final RoamLiveController controller = container.read(
      roamLiveControllerProvider.notifier,
    );
    await controller.visitShop(11);
    expect(
      container.read(roamLiveControllerProvider).visitedShopIds,
      isNot(contains(11)),
      reason: 'recorded=false 是本会话重复到店，不能渲成新完成',
    );

    await controller.visitShop(11);
    final RoamLiveState state = container.read(roamLiveControllerProvider);
    expect(state.visitedShopIds, contains(11));
    expect(state.shops, 1);
    expect(api.shopVisitRequests, hasLength(2));
    expect(api.shopVisitRequests.last.sessionId, 72);
    expect(api.shopVisitRequests.last.sourceType, 1);
    expect(api.shopVisitRequests.last.sourceId, 11);
  });

  test('乐观徽章不冒充发章，结算与官方到达都沿用服务端会话', () async {
    final _FakeRoamApi api = _FakeRoamApi();
    final _RecordingRoamSessionStore sessionStore =
        _RecordingRoamSessionStore();
    api.shopVisitResults
      ..clear()
      ..add(const RoamShopVisit(recorded: true, shops: 3));
    final _FakeOfficialApi official = _FakeOfficialApi();
    final _FakeLocationSource locations = _FakeLocationSource();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        roamApiProvider.overrideWithValue(api),
        officialApiProvider.overrideWithValue(official),
        roamLocationSourceProvider.overrideWithValue(locations),
        roamSessionStoreProvider.overrideWithValue(sessionStore),
      ],
    );
    final subscription = container.listen(
      roamLiveControllerProvider,
      (_, _) {},
    );
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await locations.close();
    });

    final RoamLiveController controller = container.read(
      roamLiveControllerProvider.notifier,
    );
    await controller.start(
      purposeAccepted: true,
      eventId: 44,
      missionCode: 'ARRIVE_RIVER',
    );
    await controller.visitShop(11);
    RoamLiveState state = container.read(roamLiveControllerProvider);
    expect(state.badgeConfigStatus, RoamBadgeConfigStatus.enabled);
    expect(state.optimisticBadge?.name, '三店连亮');
    expect(state.finishResult, isNull, reason: '即时弹卡只是乐观 UI，尚未发生服务端发章');

    await controller.verifyOfficialArrival();
    expect(official.arrivalRequests.single.eventId, 44);
    expect(official.arrivalRequests.single.missionCode, 'ARRIVE_RIVER');
    expect(official.arrivalRequests.single.sessionId, 72);
    expect(official.arrivalRequests.single.requestId, isNotEmpty);
    expect(container.read(roamLiveControllerProvider).arrivalCompleted, isTrue);

    final int expectedExplorePct = ((state.revealedTiles.length * 100) ~/ 400)
        .clamp(0, 99);
    await controller.finish();
    state = container.read(roamLiveControllerProvider);
    expect(state.phase, RoamLivePhase.finished);
    expect(state.finishResult?.totalXp, 70, reason: '结束屏数字必须直接消费服务端 finish 回执');
    expect(state.finishResult?.shopMedal?.name, '服务端真章');
    expect(state.optimisticBadge, isNull);
    expect(api.finishRequests.single.sessionId, '72');
    expect(sessionStore.sessions, hasLength(1), reason: '结算后必须进入护照历史');
    final history.RoamSession saved = sessionStore.sessions.single;
    expect(saved.distance, 0);
    expect(saved.shops, 3, reason: '探店数只认服务端结算回执');
    expect(saved.medal, isNull);
    expect(saved.shopMedalName, '服务端真章');
    expect(saved.pois.map((history.RoamPoi poi) => poi.id), contains(11));
    expect(saved.track, isNotEmpty);
    expect(
      saved.explorePct,
      expectedExplorePct,
      reason: '护照结算必须写入本机探索百分比(源 _stats.explorePct)',
    );
  });

  test('勋章配置明确停用时不弹乐观徽章', () async {
    final _FakeRoamApi api = _FakeRoamApi();
    api.badgeConfig = null;
    api.shopVisitResults
      ..clear()
      ..add(const RoamShopVisit(recorded: true, shops: 3));
    final _FakeLocationSource locations = _FakeLocationSource();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        roamApiProvider.overrideWithValue(api),
        roamLocationSourceProvider.overrideWithValue(locations),
      ],
    );
    final subscription = container.listen(
      roamLiveControllerProvider,
      (_, _) {},
    );
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await locations.close();
    });

    final RoamLiveController controller = container.read(
      roamLiveControllerProvider.notifier,
    );
    await controller.start(purposeAccepted: true);
    await controller.visitShop(11);

    final RoamLiveState state = container.read(roamLiveControllerProvider);
    expect(state.badgeConfigStatus, RoamBadgeConfigStatus.disabled);
    expect(
      state.optimisticBadge,
      isNull,
      reason: '200 + data=null 是服务端停用指令，不能用本地阈值造一枚假章',
    );
  });

  test('★★ 结算回「已结算」时按 sessionId 把结果读回来,不再是白卡', () async {
    final _FakeRoamApi api = _FakeRoamApi()..finishAlreadySettled = true;
    api.sessionFactReply = const RoamSessionFact(
      state: RoamSessionState.finished,
      sessionId: '72',
      result: RoamFinishResult(totalXp: 88, newTiles: 3),
      resultComplete: true,
    );
    final _FakeLocationSource locations = _FakeLocationSource();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        roamApiProvider.overrideWithValue(api),
        roamLocationSourceProvider.overrideWithValue(locations),
      ],
    );
    final subscription = container.listen(
      roamLiveControllerProvider,
      (_, _) {},
    );
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await locations.close();
    });

    final RoamLiveController controller = container.read(
      roamLiveControllerProvider.notifier,
    );
    await controller.start(purposeAccepted: true);
    await controller.finish();

    final RoamLiveState state = container.read(roamLiveControllerProvider);
    expect(state.phase, RoamLivePhase.finished);
    expect(state.alreadySettled, isTrue);
    expect(api.sessionFactRequests.single.sessionId, 72);
    expect(
      state.finishResult?.totalXp,
      88,
      reason: '「已结算」那条错误没带结果 —— 结果只能从会话事实里读回来',
    );
  });

  test('★ 会话事实也读不回来时,「已结算」这个结论不丢,也不编数字', () async {
    final _FakeRoamApi api = _FakeRoamApi()..finishAlreadySettled = true;
    api.sessionFactReply = null; // sessionFact 抛
    final _FakeLocationSource locations = _FakeLocationSource();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        roamApiProvider.overrideWithValue(api),
        roamLocationSourceProvider.overrideWithValue(locations),
      ],
    );
    final subscription = container.listen(
      roamLiveControllerProvider,
      (_, _) {},
    );
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await locations.close();
    });

    final RoamLiveController controller = container.read(
      roamLiveControllerProvider.notifier,
    );
    await controller.start(purposeAccepted: true);
    await controller.finish();

    final RoamLiveState state = container.read(roamLiveControllerProvider);
    expect(state.phase, RoamLivePhase.finished);
    expect(state.alreadySettled, isTrue);
    expect(state.finishResult, isNull);
    expect(state.error, isNull, reason: '已结算不是错误');
  });

  group('★ 点地图针 → /api/roam/checkin(gap-spec-roam P0-3)', () {
    test('已点亮:上报点坐标+真实定位,首亮才计探索值', () async {
      final _RoamFixture f = _RoamFixture();
      addTearDown(f.dispose);
      await f.start();

      final RoamCheckinResult? result = await f.controller.checkinPin(
        name: '老钟楼',
        poiLat: 31.2310,
        poiLng: 121.4745,
      );

      final ({
        String name,
        double poiLat,
        double poiLng,
        double curLat,
        double curLng,
      })
      req = f.api.checkinRequests.single;
      expect(req.name, '老钟楼');
      expect(req.poiLat, closeTo(31.2310, 1e-6));
      expect(req.curLat, closeTo(31.2304, 1e-6), reason: '距离判据用真实定位,不是地图中心');
      expect(result?.outcome, RoamCheckinOutcome.lit);
      expect(f.state.actionMessage, '已点亮');
      expect(f.state.lastXpAwarded, 20, reason: 'firstVisit=true 才展示 +N 探索值');
      expect(f.state.actionBusy, isFalse);

      // 非首亮也是成功 —— 只是不再计探索值。
      f.api.checkinReply = const RoamCheckinResult(
        outcome: RoamCheckinOutcome.lit,
        message: '已点亮过',
      );
      await f.controller.checkinPin(
        name: '老钟楼',
        poiLat: 31.2310,
        poiLng: 121.4745,
      );
      expect(f.state.actionMessage, '已点亮过');
      expect(f.state.lastXpAwarded, 0);
      expect(f.state.error, isNull, reason: '来过不是失败');
    });

    test('太远:只报服务端原话,不发探索值、不落错误态', () async {
      final _RoamFixture f = _RoamFixture();
      addTearDown(f.dispose);
      await f.start();
      f.api.checkinReply = const RoamCheckinResult(
        outcome: RoamCheckinOutcome.tooFar,
        message: '离得有点远，走近点',
      );

      await f.controller.checkinPin(
        name: '老钟楼',
        poiLat: 31.2310,
        poiLng: 121.4745,
      );

      expect(f.state.actionMessage, '离得有点远，走近点');
      expect(f.state.lastXpAwarded, 0);
      expect(f.state.error, isNull);
    });

    test('参与据点:把服务端 poiId 原样交回页面跳扫码', () async {
      final _RoamFixture f = _RoamFixture();
      addTearDown(f.dispose);
      await f.start();
      f.api.checkinReply = const RoamCheckinResult(
        outcome: RoamCheckinOutcome.needsScan,
        message: '这是参与据点,去扫码核销',
        poiId: 77,
      );

      final RoamCheckinResult? result = await f.controller.checkinPin(
        name: '河畔咖啡',
        poiLat: 31.2304,
        poiLng: 121.4737,
      );

      expect(result?.poiId, 77, reason: '跳哪个据点由服务端说,不按本地列表猜');
      expect(f.state.lastXpAwarded, 0, reason: '没核销就没有探索值');
      expect(f.state.actionBusy, isFalse);
    });

    test('失败:给归类后的人话而不是异常原文,且不会卡在 busy', () async {
      final _RoamFixture f = _RoamFixture();
      addTearDown(f.dispose);
      await f.start();
      f.api.checkinError = Exception(
        'DioException [bad response]: status code: 502',
      );

      await f.controller.checkinPin(
        name: '老钟楼',
        poiLat: 31.2310,
        poiLng: 121.4745,
      );

      expect(f.state.error, '网络异常，请稍后重试');
      expect(f.state.error, isNot(contains('DioException')));
      expect(f.state.actionBusy, isFalse, reason: '失败后必须还能再点,不锁死');
    });

    test('在途:上一次 checkin 没回来时二次点针不重发请求', () async {
      final _RoamFixture f = _RoamFixture();
      addTearDown(f.dispose);
      await f.start();
      f.api.checkinGate = Completer<void>();

      final Future<RoamCheckinResult?> first = f.controller.checkinPin(
        name: '老钟楼',
        poiLat: 31.2310,
        poiLng: 121.4745,
      );
      await Future<void>.delayed(Duration.zero);
      expect(f.state.actionBusy, isTrue, reason: '点针后到回执前是「载」态');

      final RoamCheckinResult? second = await f.controller.checkinPin(
        name: '老钟楼',
        poiLat: 31.2310,
        poiLng: 121.4745,
      );
      expect(second, isNull);
      expect(f.api.checkinRequests, hasLength(1));

      f.api.checkinGate!.complete();
      expect((await first)?.outcome, RoamCheckinOutcome.lit);
      expect(f.state.actionBusy, isFalse);
    });
  });
}
