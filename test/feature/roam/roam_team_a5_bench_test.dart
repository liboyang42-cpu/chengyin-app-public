// A5 iOS 27 外观首遍复核(#295)对两块新落面的渲染取证(bench)截图。
//
// 覆盖:`4bac4940` 漫游地图队伍 marker 层(HUD 队伍行 RoamNearbyLayerRow)
//       与 `a3cf7bfb` /team/nearby 重写面(登录门 + 列表 + P2–P4 卡半屏 + P5 审批半屏)。
//
// 先例:#413 `advanced_configurator_bench_test.dart`、#356 `out/bench-blindtaste-*`。
// 默认只跑轻量断言(任何机器都绿,不进 golden 比对);出图:
//   BENCH_CAPTURE=1 flutter test test/feature/roam/roam_team_a5_bench_test.dart
// 产物写到 `out/bench_a5_team95_*.png`(复核留档,不当回归基准 —— 回归基准在
// test/golden/pages_team_golden_test.dart,已有同面三张)。
//
// ★ 磁盘守卫(本机 avail <20Gi 不起模拟器)下的降级取证通道:critic 读的是
//   这些 bench 图,不是模拟器画面;「回执 ≠ 观测」在这里靠图不靠测试名。

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/map/map_scene.dart';
import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/core/widgets/cy_widgets.dart';
import 'package:chengyin_app/data/api/team_map_api.dart';
import 'package:chengyin_app/data/models/roam_social.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/roam/roam_team_markers.dart';
import 'package:chengyin_app/feature/team/team_nearby_page.dart';

import '../../golden/golden_theme.dart';

const Key _benchKey = Key('bench-a5-team95');

bool get _capture => Platform.environment['BENCH_CAPTURE'] == '1';

// 多 worker 高负载机器上 pumpAndSettle 实测可挂满 10 分钟墙钟超时(#295 二轮
// list/gate 均 TimeoutException)。页面本身无永续动画,改为确定性帧数推进:
// 前几帧放 future 落地,后几帧把路由转场一次推到底,再补一帧收尾 rebuild。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.pump();
}

Future<void> _save(WidgetTester tester, String name) async {
  final Finder boundary = find.byKey(_benchKey);
  expect(boundary, findsOneWidget);
  if (!_capture) return;
  final RenderRepaintBoundary render =
      tester.renderObject<RenderRepaintBoundary>(boundary);
  final ui.Image image = await render.toImage(pixelRatio: 2);
  addTearDown(image.dispose);
  final ByteData bytes =
      (await image.toByteData(format: ui.ImageByteFormat.png))!;
  final Directory out = Directory('out')..createSync(recursive: true);
  File('${out.path}/bench_a5_team95_$name.png')
      .writeAsBytesSync(bytes.buffer.asUint8List());
}

class _FixedAuth extends AuthController {
  _FixedAuth(this.fixed);
  final AuthState fixed;

  @override
  AuthState build() => fixed;
}

AuthState get _guest => const AuthState(initialized: true);
AuthState get _player => AuthState(
      initialized: true,
      user: User(id: 1, nickname: '阿兰', avatar: '', role: 'player'),
    );

class _FakeTeamMapApi extends TeamMapApi {
  _FakeTeamMapApi() : super(DioClient(TokenStore(const FlutterSecureStorage())));

  List<Map<String, dynamic>> teams = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> applicants = <Map<String, dynamic>>[];
  Object? nearbyError;

  @override
  Future<List<Map<String, dynamic>>> nearby({
    required double lat,
    required double lng,
    int radiusM = 3000,
  }) async {
    if (nearbyError != null) throw nearbyError!;
    return teams;
  }

  @override
  Future<List<Map<String, dynamic>>> applications(int teamId) async =>
      applicants;

  @override
  Future<List<Map<String, dynamic>>> myTeams() async =>
      const <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> myApplications() async =>
      const <Map<String, dynamic>>[];
}

Map<String, dynamic> _team({
  required int teamId,
  required String activityName,
  String viewerStatus = 'NONE',
  bool viewerHasTicket = false,
  int joinedCount = 3,
  int maxMembers = 4,
  int? pendingCount,
  int distance = 600,
}) =>
    <String, dynamic>{
      'teamId': teamId,
      'title': '外滩夜行',
      'activityId': 11,
      'activityName': activityName,
      'productType': 1,
      'addressName': '外滩源',
      'coordSource': 'GATHER',
      'latitude': 31.2,
      'longitude': 121.4,
      'distance': distance,
      'leaderName': '小周',
      'joinedCount': joinedCount,
      'maxMembers': maxMembers,
      'memberAvatars': const <String>[],
      'viewerStatus': viewerStatus,
      'viewerHasTicket': viewerHasTicket,
      'pendingCount': pendingCount,
    };

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeTeamMapApi api,
  required AuthState auth,
}) async {
  setGoldenViewport(tester, const Size(390, 844));
  final ThemeData theme = goldenTheme();
  await tester.pumpWidget(
    RepaintBoundary(
      key: _benchKey,
      child: ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => _FixedAuth(auth)),
          teamMapApiProvider.overrideWithValue(api),
        ],
        child: MaterialApp(
          theme: theme,
          debugShowCheckedModeBanner: false,
          home: CupertinoTheme(
            data: CupertinoThemeData(
              brightness: Brightness.dark,
              primaryColor: theme.colorScheme.primary,
              primaryContrastingColor: theme.colorScheme.onPrimary,
              scaffoldBackgroundColor: theme.scaffoldBackgroundColor,
              barBackgroundColor: theme.scaffoldBackgroundColor,
            ),
            child: TeamNearbyPage(
              api: api,
              locate: () async =>
                  const MapCoordinate(latitude: 31.2304, longitude: 121.4737),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}

// ── HUD 队伍行:复刻 _RoamHud 的玻璃卡壳(同款 bgGlass/borderSubtle/radiusLg
//    与上下相邻行),让 critic 看到 marker 层那一行在卡里的真实上下文。 ──

class _ReadyLayer extends RoamNearbyLayerController {
  _ReadyLayer(this.layer);
  final RoamNearbyLayer layer;

  @override
  Future<RoamNearbyLayer> build() async => layer;
}

class _FailLayer extends RoamNearbyLayerController {
  @override
  Future<RoamNearbyLayer> build() async =>
      throw Exception('DioException [bad response]: 401 Unauthorized');
}

class _BusyLayer extends RoamNearbyLayerController {
  @override
  Future<RoamNearbyLayer> build() => Completer<RoamNearbyLayer>().future;
}

Future<void> _pumpHud(WidgetTester tester, Widget layer) async {
  setGoldenViewport(tester, const Size(390, 420));
  await tester.pumpWidget(
    RepaintBoundary(
      key: _benchKey,
      child: MaterialApp(
        theme: AppTheme.dark(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          // 地图页底近似:HUD 卡浮在深色地图上。
          backgroundColor: const Color(0xFF0B0E13),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.all(CyTokens.space3),
                child: Container(
                  padding: const EdgeInsets.all(CyTokens.space3),
                  decoration: BoxDecoration(
                    color: CyTokens.bgGlass,
                    border: Border.all(color: CyTokens.borderSubtle),
                    borderRadius: BorderRadius.circular(CyTokens.radiusLg),
                  ),
                  child: Builder(
                    builder: (BuildContext context) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const CyTag(label: '实时探索', brand: true),
                            const SizedBox(width: CyTokens.space2),
                            Expanded(
                              child: Text(
                                '863 m · 新点亮 4 · 到店 2',
                                textAlign: TextAlign.end,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: CyTokens.textSecondary),
                              ),
                            ),
                          ],
                        ),
                        layer,
                        const SizedBox(height: CyTokens.space2),
                        Row(
                          children: <Widget>[
                            const Icon(
                              CupertinoIcons.person_2,
                              size: 14,
                              color: CyTokens.textSecondary,
                            ),
                            const SizedBox(width: CyTokens.space1),
                            Expanded(
                              child: Text(
                                '附近 5 人在走',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            CupertinoButton(
                              minimumSize: const Size(44, 44),
                              padding: EdgeInsets.zero,
                              onPressed: () {},
                              child: const Text('看看'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

RoamHangoutItem _place({required String kind, required int id}) =>
    RoamHangoutItem.fromJson(<String, dynamic>{
      'kind': kind,
      'id': id,
      'name': kind == 'topic' ? '城市漫步主题' : '限时活动 · 夜光跑',
      'latitude': 31.231,
      'longitude': 121.475,
    });

void main() {
  final List<Map<String, dynamic>> teams = <Map<String, dynamic>>[
    _team(teamId: 7, activityName: '外滩夜行路线 · 周五 19:30 场', viewerHasTicket: true),
    _team(teamId: 8, activityName: '苏河湾探店日 · 周六 14:00 场', viewerStatus: 'PENDING', distance: 1500),
    _team(teamId: 9, activityName: '辰山夜观星 · 周日 20:00 场', viewerHasTicket: false, joinedCount: 2),
  ];

  testWidgets('列表页(登录态):计数条 + 两枚角控件 + 三行队伍', (WidgetTester tester) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi()..teams = teams;
    await _pumpPage(tester, api: api, auth: _player);
    expect(find.text('附近的队伍'), findsOneWidget);
    expect(find.text('外滩夜行 · 3/4'), findsNothing); // 行标题是队名
    await _save(tester, 'list');
  });

  testWidgets('登录门(游客): Cupertino 锁图标 + 去登录出口', (WidgetTester tester) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi();
    await _pumpPage(tester, api: api, auth: _guest);
    expect(find.text('登录后查看附近的队伍'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    await _save(tester, 'gate');
  });

  testWidgets('P3 有票卡半屏(点第一行打开)', (WidgetTester tester) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi()..teams = teams;
    await _pumpPage(tester, api: api, auth: _player);
    await tester.tap(find.text('外滩夜行路线 · 周五 19:30 场'));
    await _settle(tester);
    expect(find.text('申请加入'), findsOneWidget);
    await _save(tester, 'card_sheet');
  });

  testWidgets('P5 队长审批半屏:拒绝在左、同意在右', (WidgetTester tester) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[
        _team(teamId: 7, activityName: '外滩夜行路线 · 周五 19:30 场', viewerStatus: 'LEADER', pendingCount: 2),
      ]
      ..applicants = <Map<String, dynamic>>[
        <String, dynamic>{'memberId': 5, 'memberName': '阿杰'},
        <String, dynamic>{'memberId': 6, 'memberName': 'Mia'},
      ];
    await _pumpPage(tester, api: api, auth: _player);
    await tester.tap(find.text('外滩夜行路线 · 周五 19:30 场'));
    await _settle(tester);
    expect(find.text('拒绝'), findsNWidgets(2));
    await _save(tester, 'leader_sheet');
  });

  testWidgets('HUD 队伍行 · 有队伍(点层含主题/活动)', (WidgetTester tester) async {
    await _pumpHud(
      tester,
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => _FixedAuth(_player)),
          roamNearbyLayerProvider.overrideWith(
            () => _ReadyLayer(RoamNearbyLayer(
              teams: teams,
              items: <RoamHangoutItem>[
                _place(kind: 'topic', id: 21),
                _place(kind: 'activity', id: 33),
              ],
            )),
          ),
        ],
        child: const RoamNearbyLayerRow(),
      ),
    );
    await _settle(tester);
    expect(find.text('附近的队伍 · 3 支在招募'), findsOneWidget);
    await _save(tester, 'hud_normal');
  });

  testWidgets('HUD 队伍行 · 读取中', (WidgetTester tester) async {
    await _pumpHud(
      tester,
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => _FixedAuth(_player)),
          roamNearbyLayerProvider.overrideWith(() => _BusyLayer()),
        ],
        child: const RoamNearbyLayerRow(),
      ),
    );
    await tester.pump();
    expect(find.text('附近的队伍 · 读取中'), findsOneWidget);
    await _save(tester, 'hud_loading');
  });

  testWidgets('HUD 队伍行 · 读不到(登录态给重试)', (WidgetTester tester) async {
    await _pumpHud(
      tester,
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => _FixedAuth(_player)),
          roamNearbyLayerProvider.overrideWith(() => _FailLayer()),
        ],
        child: const RoamNearbyLayerRow(),
      ),
    );
    await _settle(tester);
    expect(find.text('重试'), findsOneWidget);
    await _save(tester, 'hud_error_retry');
  });

  testWidgets('HUD 队伍行 · 401(游客给去登录)', (WidgetTester tester) async {
    await _pumpHud(
      tester,
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => _FixedAuth(_guest)),
          roamNearbyLayerProvider.overrideWith(() => _FailLayer()),
        ],
        child: const RoamNearbyLayerRow(),
      ),
    );
    await _settle(tester);
    expect(find.text('去登录'), findsOneWidget);
    await _save(tester, 'hud_error_401');
  });
}
