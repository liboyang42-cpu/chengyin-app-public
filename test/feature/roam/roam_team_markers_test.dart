// 漫游地图 · 队伍 marker 层(地图组队 P 方案,地图侧)的门禁。
//
// 判据(线卡 A3)四条,各有着落:
//   ① 点位编码与真源一致(`utils/map-team.js:12` 队伍 …4 / `roam-hangout.js:81` 活动 …2 主题 …3);
//   ② 只画队伍 + 主题/活动,**局(kind=hangout)一律不画**(9-15 裁决,搭子局 A 已下架);
//   ③ 点 marker 开的半屏 = `/team/nearby` 列表页那一份(`showTeamMarkerSheet`),不复制状态机;
//   ④ 无定位 / 无队伍 / 接口失败 / 401 四档各有着落。
//
// ★ 真源:`subpackageRoam/nearby/index.js`(接线)、`utils/map-team.js`、`utils/roam-hangout.js`。

import 'dart:async';

import 'package:chengyin_app/core/map/map_scene.dart';
import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/data/api/roam_api.dart';
import 'package:chengyin_app/data/api/team_map_api.dart';
import 'package:chengyin_app/data/models/roam_social.dart';
import 'package:chengyin_app/feature/roam/roam_live_controller.dart';
import 'package:chengyin_app/feature/roam/roam_team_markers.dart';
import 'package:chengyin_app/feature/team/team_nearby_page.dart'
    show showTeamMarkerSheet, teamMapApiProvider;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _team({
  int teamId = 7,
  String viewerStatus = 'NONE',
  bool viewerHasTicket = true,
  int joinedCount = 3,
  int maxMembers = 4,
  double? latitude = 31.2,
  double? longitude = 121.4,
}) => <String, dynamic>{
  'teamId': teamId,
  'title': '外滩夜行',
  'activityId': 11,
  'activityName': '外滩夜行路线 · 周五 19:30 场',
  'productType': 1,
  'addressName': '外滩源',
  'latitude': latitude,
  'longitude': longitude,
  'distance': 600,
  'leaderName': '小周',
  'joinedCount': joinedCount,
  'maxMembers': maxMembers,
  'memberAvatars': const <String>['a.png'],
  'viewerStatus': viewerStatus,
  'viewerHasTicket': viewerHasTicket,
};

RoamHangoutItem _place({
  required String kind,
  required int id,
  double? latitude = 31.21,
  double? longitude = 121.41,
}) => RoamHangoutItem.fromJson(<String, dynamic>{
  'kind': kind,
  'id': id,
  'name': '人民广场夜跑',
  'latitude': latitude,
  'longitude': longitude,
});

class _FakeTeamMapApi extends TeamMapApi {
  _FakeTeamMapApi() : super(DioClient(TokenStore(const FlutterSecureStorage())));

  List<Map<String, dynamic>> teams = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> applicants = <Map<String, dynamic>>[];
  Object? nearbyError;
  Object? withdrawError;

  final List<int> radii = <int>[];
  final List<int> withdrawn = <int>[];

  @override
  Future<List<Map<String, dynamic>>> nearby({
    required double lat,
    required double lng,
    int radiusM = 3000,
  }) async {
    radii.add(radiusM);
    if (nearbyError != null) throw nearbyError!;
    return teams;
  }

  @override
  Future<void> withdraw(int teamId) async {
    if (withdrawError != null) throw withdrawError!;
    withdrawn.add(teamId);
  }

  @override
  Future<List<Map<String, dynamic>>> applications(int teamId) async =>
      applicants;
}

class _FakeRoamApi extends RoamApi {
  _FakeRoamApi() : super(DioClient(TokenStore(const FlutterSecureStorage())));

  List<RoamHangoutItem> items = <RoamHangoutItem>[];
  Object? error;
  int calls = 0;

  @override
  Future<RoamHangoutNearby> hangoutNearby({
    required double lat,
    required double lng,
    int radiusM = 3000,
  }) async {
    calls += 1;
    if (error != null) throw error!;
    return RoamHangoutNearby(items: items);
  }
}

class _PresetRoamLiveController extends RoamLiveController {
  _PresetRoamLiveController(this.initialState);

  final RoamLiveState initialState;

  @override
  RoamLiveState build() => initialState;
}

const RoamLiveState _roaming = RoamLiveState(
  phase: RoamLivePhase.roaming,
  location: RoamLivePosition(latitude: 31.2304, longitude: 121.4737),
);

ProviderContainer _container({
  required _FakeTeamMapApi teamApi,
  required _FakeRoamApi roamApi,
  RoamLiveState state = _roaming,
}) {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      roamLiveControllerProvider.overrideWith(
        () => _PresetRoamLiveController(state),
      ),
      teamMapApiProvider.overrideWithValue(teamApi),
      roamApiProvider.overrideWithValue(roamApi),
    ],
  );
  addTearDown(container.dispose);
  // autoDispose 的 provider 在没人监听时会被回收 —— 用例里保持一个监听,
  // 否则「错误也要能读出来」这条会先撞上 disposal 而不是接口异常。
  final ProviderSubscription<AsyncValue<RoamNearbyLayer>> keep = container
      .listen(
        roamNearbyLayerProvider,
        (AsyncValue<RoamNearbyLayer>? previous, AsyncValue<RoamNearbyLayer> next) {},
        fireImmediately: true,
      );
  addTearDown(keep.close);
  return container;
}

void main() {
  test('marker 身份:队伍 …4 / 活动 …2 / 主题 …3;局与漫游自己的点都不认', () {
    expect(roamTeamMarkerId(7), '74');
    expect(parseRoamMarkerId('74'), const RoamMarkerHit(RoamMarkerKind.team, 7));
    expect(
      parseRoamMarkerId('133'),
      const RoamMarkerHit(RoamMarkerKind.topic, 13),
    );
    expect(
      parseRoamMarkerId('122'),
      const RoamMarkerHit(RoamMarkerKind.activity, 12),
    );
    // 局(…1):9-15 裁决下架,地图上不存在「局」
    expect(parseRoamMarkerId('121'), isNull);
    // 漫游自己的点(poi / 附近的人)与自己的 marker(9)不是本层点位
    expect(parseRoamMarkerId('roam-poi-3'), isNull);
    expect(parseRoamMarkerId('runner-9'), isNull);
    expect(parseRoamMarkerId('9'), isNull);
  });

  test('点位映射:队伍 + 主题 + 活动画上,局不画,没坐标的跳过', () {
    final List<MapPoint> points = roamNearbyMarkerPoints(
      teams: <Map<String, dynamic>>[
        _team(teamId: 7, viewerStatus: 'JOINED'),
        _team(teamId: 8, latitude: null, longitude: null),
      ],
      items: <RoamHangoutItem>[
        _place(kind: 'topic', id: 13),
        _place(kind: 'activity', id: 12),
        _place(kind: 'hangout', id: 14),
        _place(kind: 'topic', id: 15, latitude: null, longitude: null),
      ],
    );

    expect(
      points.map((MapPoint p) => p.id).toList(),
      <String>['74', '133', '122'],
    );
    // 坐标原样交给 MapKit(GCJ-02 直通,`apple_scene_view.dart` 的约定)
    expect(points.first.latitude, 31.2);
    expect(points.first.longitude, 121.4);
    // 队名 + 场次,与列表页同一份 `decorateTeam` 输出
    expect(points.first.title, '外滩夜行');
    expect(points.first.subtitle, '外滩夜行路线 · 周五 19:30 场');
    // 我已在队里 → 高亮档(真源 teamMarkerSpec 的 state=joined)
    expect(points.first.state, MapPointState.active);
    expect(points[1].state, MapPointState.normal);
    expect(points[1].subtitle, '主题');
    expect(points[2].subtitle, '限时活动');
  });

  test('无定位:不取数、不画点(还没进入漫游就没有这一层)', () async {
    final _FakeTeamMapApi teamApi = _FakeTeamMapApi();
    final _FakeRoamApi roamApi = _FakeRoamApi();
    final ProviderContainer container = _container(
      teamApi: teamApi,
      roamApi: roamApi,
      state: const RoamLiveState(phase: RoamLivePhase.idle),
    );

    final RoamNearbyLayer layer = await container.read(
      roamNearbyLayerProvider.future,
    );
    expect(layer.teams, isEmpty);
    expect(teamApi.radii, isEmpty);
    expect(roamApi.calls, 0);
  });

  test('取数:半径按小程序默认 1 km,队伍 + 主题/活动都进来', () async {
    final _FakeTeamMapApi teamApi = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[_team()];
    final _FakeRoamApi roamApi = _FakeRoamApi()
      ..items = <RoamHangoutItem>[
        _place(kind: 'topic', id: 13),
        _place(kind: 'hangout', id: 14),
      ];
    final ProviderContainer container = _container(
      teamApi: teamApi,
      roamApi: roamApi,
    );

    final RoamNearbyLayer layer = await container.read(
      roamNearbyLayerProvider.future,
    );
    expect(teamApi.radii, <int>[1000]);
    expect(layer.teams, hasLength(1));
    expect(layer.items, hasLength(2));
    // 局在画的时候被滤掉(点位断言在映射用例里)
    expect(
      roamNearbyMarkerPoints(teams: layer.teams, items: layer.items)
          .map((MapPoint p) => p.id),
      <String>['74', '133'],
    );
  });

  test('队伍层失败:整层报错(不给假点位);主题层失败只少一层点', () async {
    final _FakeTeamMapApi teamApi = _FakeTeamMapApi()
      ..nearbyError = const TeamMapApiException('登录状态已失效');
    final _FakeRoamApi roamApi = _FakeRoamApi();
    final ProviderContainer container = _container(
      teamApi: teamApi,
      roamApi: roamApi,
    );

    await pumpEventQueue();
    expect(container.read(roamNearbyLayerProvider).hasError, isTrue);
    expect(
      container.read(roamNearbyLayerProvider).error,
      isA<TeamMapApiException>(),
    );

    final _FakeTeamMapApi okTeamApi = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[_team()];
    final ProviderContainer other = _container(
      teamApi: okTeamApi,
      roamApi: _FakeRoamApi()..error = RoamApiException('主题层没读到'),
    );
    final RoamNearbyLayer layer = await other.read(
      roamNearbyLayerProvider.future,
    );
    expect(layer.teams, hasLength(1));
    expect(layer.items, isEmpty);
  });

  test('半屏动作后的本地补丁:申请成功改状态 / 满员撤下点位', () async {
    final _FakeTeamMapApi teamApi = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[_team()];
    final ProviderContainer container = _container(
      teamApi: teamApi,
      roamApi: _FakeRoamApi(),
    );
    await container.read(roamNearbyLayerProvider.future);
    final RoamNearbyLayerController controller = container.read(
      roamNearbyLayerProvider.notifier,
    );

    controller.patchTeam(7, <String, Object?>{'viewerStatus': 'PENDING'});
    expect(
      container.read(roamNearbyLayerProvider).value!.rowOf(7)!['viewerStatus'],
      'PENDING',
    );

    controller.dropTeam(7);
    expect(container.read(roamNearbyLayerProvider).value!.rowOf(7), isNull);
    expect(
      roamNearbyMarkerPoints(
        teams: container.read(roamNearbyLayerProvider).value!.teams,
        items: const <RoamHangoutItem>[],
      ),
      isEmpty,
    );
  });

  testWidgets('顶部条三态:读取中 / N 支在招募 / 读不到 + 去登录(401)', (
    WidgetTester tester,
  ) async {
    Future<void> pump(
      RoamNearbyLayerController Function() create, {
      bool settle = true,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          // 每次 pump 换一把 key:同一个 ProviderScope 复用元素时不会用新 override。
          key: ValueKey<int>(_hudSeq++),
          overrides: [roamNearbyLayerProvider.overrideWith(create)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: RoamNearbyLayerRow()),
          ),
        ),
      );
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
      }
    }

    // 读取中
    await pump(_NeverNearbyLayer.new, settle: false);
    expect(find.text('附近的队伍 · 读取中'), findsOneWidget);

    // 有队伍(计数文案取自真源 `map-team.js:105`)
    await pump(
      () => _FixedNearbyLayer(
        RoamNearbyLayer(teams: <Map<String, dynamic>>[_team()]),
      ),
    );
    expect(find.text('附近的队伍 · 1 支在招募'), findsOneWidget);

    // 这一片没有队伍:计数为 0,不编「有队伍」
    await pump(() => _FixedNearbyLayer(const RoamNearbyLayer()));
    expect(find.text('附近的队伍 · 0 支在招募'), findsOneWidget);

    // 失败 + 未登录(401 走登录引导,不说「检查网络」)
    await pump(_FailingNearbyLayer.new);
    // 失败档计数条不谎称「读取中」:真源失败时顶部条保持 `headerText(上次结果)`。
    expect(find.text('附近的队伍 · 读取中'), findsNothing);
    expect(find.text('附近的队伍 · 0 支在招募'), findsOneWidget);
    expect(find.text('附近的队伍没能读到'), findsOneWidget);
    expect(find.text('登录状态已失效,登录后接着看'), findsOneWidget);
    expect(find.widgetWithText(CupertinoButton, '去登录'), findsOneWidget);
    expect(find.text('检查网络'), findsNothing);
  });

  testWidgets('点 marker 开的半屏 = 列表页那一份:PENDING 能撤回', (
    WidgetTester tester,
  ) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi();
    final List<Map<String, Object?>> patches = <Map<String, Object?>>[];
    await _pumpMarkerSheet(
      tester,
      api: api,
      row: _team(viewerStatus: 'PENDING'),
      onPatch: patches.add,
    );

    expect(find.text('◷ 已申请 · 等队长同意'), findsOneWidget);
    await tester.tap(find.text('撤回申请'));
    await tester.pumpAndSettle();
    expect(api.withdrawn, <int>[7]);
    expect(patches.single['viewerStatus'], 'NONE');
  });

  testWidgets('队长 marker 开的是审批半屏(与列表页同一条出口)', (
    WidgetTester tester,
  ) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..applicants = <Map<String, dynamic>>[
        <String, dynamic>{
          'memberId': 5,
          'memberName': '阿彪',
          'appliedAt': '2026-09-18 10:00:00',
          'applyExpireTime': '2026-09-19 10:00:00',
        },
      ];
    await _pumpMarkerSheet(
      tester,
      api: api,
      row: _team(teamId: 9, viewerStatus: 'LEADER'),
    );

    expect(find.text('你是队长 · 已组 3/4 · 还能再加 1 人'), findsOneWidget);
    expect(find.text('阿彪'), findsOneWidget);
    expect(find.text('拒绝'), findsOneWidget);
    expect(find.text('同意'), findsOneWidget);
  });
}

/// 用 `showTeamMarkerSheet` 真开一次半屏(漫游地图 marker 走的就是这条出口)。
Future<void> _pumpMarkerSheet(
  WidgetTester tester, {
  required _FakeTeamMapApi api,
  required Map<String, dynamic> row,
  void Function(Map<String, Object?> patch)? onPatch,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (BuildContext context) => CupertinoButton(
            onPressed: () => showTeamMarkerSheet(
              context: context,
              api: api,
              row: row,
              onPatch: onPatch ?? (Map<String, Object?> _) {},
              onDrop: () {},
              onOpenTeam: (int _) {},
              onOpenActivity: (int _) {},
            ),
            child: const Text('marker'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('marker'));
  await tester.pumpAndSettle();
}

/// 永远读不完:只为断言「读取中」这一档。
int _hudSeq = 0;

class _NeverNearbyLayer extends RoamNearbyLayerController {
  @override
  Future<RoamNearbyLayer> build() => Completer<RoamNearbyLayer>().future;
}

class _FixedNearbyLayer extends RoamNearbyLayerController {
  _FixedNearbyLayer(this.layer);

  final RoamNearbyLayer layer;

  @override
  Future<RoamNearbyLayer> build() async => layer;
}

class _FailingNearbyLayer extends RoamNearbyLayerController {
  @override
  Future<RoamNearbyLayer> build() async =>
      throw const TeamMapApiException('登录状态已失效');
}
