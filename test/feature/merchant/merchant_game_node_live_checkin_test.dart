// 商家游戏节点页的「出示打卡码」= 现场打卡码(`chapter-node/live-checkin-code`)。
//
// ★ 真源两颗码分在两页、两条端点,别混:
//   · 现场打卡码 = `pages/merchant/game-node/index.wxml:140`(`wx:if="{{station.playable}}"`)
//     → `index.js:556` POST `/api/merchant/chapter-node/live-checkin-code`;
//   · 店内海报码 = `pages/topic/merchantinfo/merchantinfo.js:2858` poster-code。
//   这条带 `ttlMs`,扫过即作废,所以它的可用性判据(session 在跑 + 本站可接待)
//   也比海报码严。
//
// ★ 可用性口径不是「服务端给了 playable 就算」——真源
//   `utils/game-session-merchant.js:158` 把它重新算了一遍:
//   `raw.playable === true && stationConfigured && status∈{READY,ACTIVE}
//    && sessionStatus∈{READY,RUNNING}`。测试按这条口径钉。

import 'dart:typed_data';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/game_session_api.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/feature/merchant/merchant_game_node_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_game_pending_store.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const Key _liveCodeButton = Key('merchant-game-live-code');

void main() {
  group('playable 派生口径(utils/game-session-merchant.js:158)', () {
    test('服务端 playable + 本站备齐 + 局在跑 → 可出示现场码', () {
      final projection = _projection('ACTIVE', playable: true);
      final station = projection.stations.single;
      expect(station.playable, isTrue, reason: '服务端字段只管读出来');
      expect(projection.allowsLiveCheckin(station), isTrue);
    });

    test('★ 服务端没给 playable,本地不许替它乐观', () {
      final projection = _projection('ACTIVE', playable: false);
      expect(projection.allowsLiveCheckin(projection.stations.single), isFalse);
    });

    test('★ 本站没备齐(清单没勾 / 没容量 / 服务时段残缺)→ 不算可接待', () {
      for (final station in <MerchantGameStation>[
        _station(playable: true, checklistChecked: false),
        _station(playable: true, capacity: 0),
        _station(playable: true, serviceStartAt: '', serviceEndAt: ''),
        _station(playable: true, serviceEndAt: '2099-01-01 09:00'),
      ]) {
        expect(
          _projection(
            'ACTIVE',
            stationOverride: station,
          ).allowsLiveCheckin(station),
          isFalse,
          reason: '备齐是 playable 的一部分,不是提示文案',
        );
      }
    });

    test('★ 局没开 / 站没就绪 → 不给出示(过期码比没有码更坏)', () {
      final ready = _projection('READY', playable: true);
      expect(
        ready.allowsLiveCheckin(ready.stations.single),
        isTrue,
        reason: 'READY 局 + READY 站是合法的可接待态',
      );
      for (final session in <String>['PREPARING', 'FINISHED', 'CANCELLED']) {
        final projection = _projection(
          'ACTIVE',
          playable: true,
          status: session,
        );
        expect(
          projection.allowsLiveCheckin(projection.stations.single),
          isFalse,
          reason: '$session 局里出示现场码 = 给玩家一张扫不动的码',
        );
      }
      for (final station in <String>[
        'INVITED',
        'ACCEPTED',
        'PAUSED',
        'CLOSED',
      ]) {
        final projection = _projection(station, playable: true);
        expect(
          projection.allowsLiveCheckin(projection.stations.single),
          isFalse,
          reason: '$station 站不该有现场码',
        );
      }
    });
  });

  testWidgets('运行中的本站:「出示打卡码」点开就是现场码那条端点', (tester) async {
    final _FakeMerchantApi api = _FakeMerchantApi();
    await _pump(
      tester,
      api: api,
      projection: _projection('ACTIVE', playable: true),
    );

    expect(find.byKey(_liveCodeButton), findsOneWidget);
    // 位置钉在「本站运行」卡里、且在「暂停接待」之上 ——
    // 真源 wxml:140 的 wx:if 就在这张卡内、同一顺序,不是页脚浮一个游离按钮。
    expect(
      tester.getCenter(find.byKey(_liveCodeButton)).dy,
      greaterThan(tester.getCenter(find.text('本站运行')).dy),
    );
    expect(
      tester.getCenter(find.byKey(_liveCodeButton)).dy,
      lessThan(tester.getCenter(find.text('暂停接待')).dy),
    );
    // 海报码不在这页(真源把它留在 merchantinfo):两页两颗码,别在这页长出来。
    expect(find.text('店内海报码'), findsNothing);
    await tester.tap(find.byKey(_liveCodeButton));
    await tester.pumpAndSettle();

    expect(api.liveCalls, 1);
    expect(api.posterCalls, 0, reason: '两颗码两条端点,不许拿海报码顶现场码');
    expect(find.text('现场打卡码'), findsOneWidget);
  });

  testWidgets('★ 服务端没给 playable:按钮根本不出现,不是点了报错', (tester) async {
    final _FakeMerchantApi api = _FakeMerchantApi();
    await _pump(
      tester,
      api: api,
      projection: _projection('ACTIVE', playable: false),
    );

    expect(find.byKey(_liveCodeButton), findsNothing);
    expect(api.liveCalls, 0);
  });

  testWidgets('★ 局已结束:本站还在 ACTIVE 也不出示现场码', (tester) async {
    await _pump(
      tester,
      api: _FakeMerchantApi(),
      projection: _projection('ACTIVE', playable: true, status: 'FINISHED'),
    );

    expect(find.byKey(_liveCodeButton), findsNothing);
  });
}

// ─────────────────────────────────────────── 夹具

MerchantGameStation _station({
  bool playable = false,
  bool checklistChecked = true,
  int? capacity = 12,
  String serviceStartAt = '2099-01-01 09:00',
  String serviceEndAt = '2099-01-01 18:00',
  String status = 'ACTIVE',
}) => MerchantGameStation(
  stationId: 8,
  nodeId: 9,
  nodeName: '密码站',
  stationCode: 'A1',
  status: status,
  revision: 3,
  checklist: <GameChecklistItem>[
    GameChecklistItem(code: 'SIGN', label: '挂好门牌', checked: checklistChecked),
  ],
  pendingVerificationCount: 0,
  capacity: capacity,
  serviceStartAt: serviceStartAt,
  serviceEndAt: serviceEndAt,
  playable: playable,
);

MerchantGameProjection _projection(
  String station, {
  bool playable = false,
  String? status,
  MerchantGameStation? stationOverride,
}) => MerchantGameProjection(
  sessionId: 2,
  activityId: 7,
  status:
      status ??
      switch (station) {
        'INVITED' || 'ACCEPTED' => 'PREPARING',
        'READY' => 'READY',
        _ => 'RUNNING',
      },
  revision: 3,
  availableActions: const <String>{'STATION_PAUSE'},
  stations: <MerchantGameStation>[
    stationOverride ?? _station(playable: playable, status: station),
  ],
);

Future<void> _pump(
  WidgetTester tester, {
  required MerchantApi api,
  required MerchantGameProjection projection,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [merchantApiProvider.overrideWithValue(api)],
      child: CupertinoApp(
        home: MerchantGameNodePage(
          ownerMemberId: 41,
          activityId: 7,
          gateway: _Gateway(projection),
          pendingStore: MerchantGamePendingStore.memory(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Gateway implements GameSessionGateway {
  const _Gateway(this.projection);
  final MerchantGameProjection projection;
  @override
  Future<MerchantGameProjection> loadMerchantView({
    required int activityId,
  }) async => projection;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMerchantApi implements MerchantApi {
  int liveCalls = 0;
  int posterCalls = 0;

  @override
  Future<Map<String, dynamic>> chapterNodeLiveCheckinCode(int nodeId) async {
    liveCalls++;
    return <String, dynamic>{
      'qrcodeUrl': 'https://o/live.png',
      'code': 'L-1',
      'ttlMs': 60000,
    };
  }

  @override
  Future<Map<String, dynamic>> chapterNodePosterCode(int nodeId) async {
    posterCalls++;
    return <String, dynamic>{'qrcodeUrl': 'https://o/poster.png'};
  }

  @override
  Future<Uint8List> fetchImageBytes(String url) async =>
      Uint8List.fromList(<int>[1, 2, 3]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
