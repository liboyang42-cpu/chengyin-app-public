// Wave-B:漫游起始页(B01/B03/B04)· 据点核销码(B10/B11)· 定向玩法
// (B12 城市模式 / B14 手账 / B15 故事 / B16 通关)· 自由探索(B13 复用已有基线)·
// 城市实例缺参(B60)。
//
// 更新基准图:
//   flutter test --update-goldens test/golden/pages_wave_b_roam_play_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/ai_npc_api.dart';
import 'package:chengyin_app/data/models/club_lead.dart';
import 'package:chengyin_app/data/models/npc.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/api/roam_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/data/models/city_node_detail.dart';
import 'package:chengyin_app/data/models/roam.dart';
import 'package:chengyin_app/data/models/roam_session.dart';
import 'package:chengyin_app/data/models/roam_social.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/play/circle_theme_play_page.dart';
import 'package:chengyin_app/feature/play/classic_play_surfaces.dart';
import 'package:chengyin_app/feature/play/play_session_page.dart';
import 'package:chengyin_app/feature/play/team_lead_page.dart';
import 'package:chengyin_app/feature/roam/city_node_voucher_page.dart';
import 'package:chengyin_app/feature/roam/roam_history_page.dart';
import 'package:chengyin_app/feature/roam/roam_live_controller.dart';
import 'package:chengyin_app/feature/roam/roam_live_page.dart';

import 'golden_theme.dart';

class _FixedAuth extends AuthController {
  _FixedAuth(this._s);
  final AuthState _s;
  @override
  AuthState build() => _s;
}

class _Api implements PlayApi {
  _Api(this.payload);
  final Map<String, dynamic> payload;

  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async =>
      PlayNodesResult.fromJson(payload);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 定向玩法会拉 NPC 档案;不挡住这条就变成一次真网络 + 悬挂 timer。
class _NpcApi extends AiNpcApi {
  _NpcApi() : super(DioClient(TokenStore(const FlutterSecureStorage())));

  @override
  Future<List<NpcProfile>> fetchProfiles({
    String scope = 'global',
    int? activityId,
  }) async => const <NpcProfile>[];
}

/// 定向玩法会顺带拉「谁在这儿打过卡」;挡住它,别让基线依赖真网络。
class _RoamApi extends RoamApi {
  _RoamApi(super.client);

  @override
  Future<List<RoamShopVisitors>> shopVisitors({
    required int sourceType,
    required List<int> sourceIds,
  }) async => const <RoamShopVisitors>[];
}

/// 出码失败态用的假 RoamApi:只让 issueCityNodeCode 抛。
class _FailVoucherApi extends RoamApi {
  _FailVoucherApi(super.client);

  @override
  Future<CityNodeVoucher> issueCityNodeCode(int poiId) async =>
      throw Exception('服务端开小差了');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PresetRoam extends RoamLiveController {
  _PresetRoam(this._initial);
  final RoamLiveState _initial;
  @override
  RoamLiveState build() => _initial;
}

AuthState _auth() => AuthState(
  user: User(id: 7, nickname: '阿兰', avatar: '', role: 'player'),
  initialized: true,
);

Widget _app(List<dynamic> overrides, Widget home) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: goldenTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

Future<void> _shot(WidgetTester tester, String path) async {
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(path));
}

RoamSession _session() => const RoamSession(
  ts: 1783000000000,
  zone: '静安',
  date: '2026-07-12',
  dateLine: '7月12日',
  distance: 3.1,
  explorePct: 48,
  shops: 3,
  time: '42:10',
);

/// 经典定向(mode 1)一份可玩数据:两章四点,首点已完成。
Map<String, dynamic> _cityPayload() => <String, dynamic>{
  'topicId': 9,
  'mode': 1,
  'playable': true,
  'total': 4,
  'doneCount': 1,
  'chapters': <dynamic>[
    <String, dynamic>{'chapterId': 100, 'name': '晨间烘焙'},
    <String, dynamic>{'chapterId': 200, 'name': '旧书与唱片'},
  ],
  'nodes': <dynamic>[
    <String, dynamic>{
      'nodeId': 11,
      'name': 'Bakehouse 巨鹿路店',
      'address': '巨鹿路 88 号',
      'sortId': 1,
      'done': true,
      'chapterId': 100,
      'latitude': 31.21,
      'longitude': 121.45,
    },
    <String, dynamic>{
      'nodeId': 12,
      'name': '长乐路旧物店',
      'address': '长乐路 88 号',
      'sortId': 2,
      'done': false,
      'chapterId': 200,
      'latitude': 31.22,
      'longitude': 121.46,
    },
  ],
};

void main() {
  // PlaySessionPage(城市模式)进页会读一次 secure storage 里没收敛的写
  // (PlayerGamePendingStore.read);单测环境没有插件实现,不挡这条会抛
  // MissingPluginException,把整页拍成失败态。仓库统一用这个 channel 假实现。
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  // ── 漫游起始页 pages/roam/index ────────────────────────────────────────
  testWidgets('B01 漫游 · 常态(话题卡 + 足迹记录 + GO)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        authControllerProvider.overrideWith(() => _FixedAuth(_auth())),
        roamHistoryProvider.overrideWith(
          (ref) async => <RoamSession>[_session()],
        ),
        roamIntroTopicsProvider.overrideWith(
          (ref) async => const <RoamIntroTopic>[
            RoamIntroTopic(
              title: '老建筑年份线索',
              subtitle: '跟着门牌走一条线',
              route: '/topic/9',
              freeExplore: false,
            ),
          ],
        ),
      ], const RoamLivePage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('漫游'), findsOneWidget);
    await _shot(tester, 'goldens/page_roam_intro_normal.png');
  });

  testWidgets('B03 漫游 · 定位未授权(红字说明 + 仍然可以重开)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        authControllerProvider.overrideWith(() => _FixedAuth(_auth())),
        roamLiveControllerProvider.overrideWith(
          () => _PresetRoam(
            const RoamLiveState(error: '请在系统设置中开启位置权限，以便继续使用位置功能'),
          ),
        ),
        roamHistoryProvider.overrideWith((ref) async => const <RoamSession>[]),
        roamIntroTopicsProvider.overrideWith(
          (ref) async => const <RoamIntroTopic>[],
        ),
      ], const RoamLivePage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('请在系统设置中开启位置权限，以便继续使用位置功能'), findsOneWidget);
    await _shot(tester, 'goldens/page_roam_intro_permission.png');
  });

  testWidgets('B04 漫游 · 结算态(没有轨迹)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 900));
    await tester.pumpWidget(
      _app(<dynamic>[
        authControllerProvider.overrideWith(() => _FixedAuth(_auth())),
        roamLiveControllerProvider.overrideWith(
          () => _PresetRoam(
            RoamLiveState(
              phase: RoamLivePhase.finished,
              track: const <RoamLivePosition>[],
              distanceM: 0,
              finishResult: const RoamFinishResult(
                totalXp: 0,
                newTiles: 0,
                newPois: 0,
                sessionShops: 0,
              ),
            ),
          ),
        ),
        roamHistoryProvider.overrideWith((ref) async => const <RoamSession>[]),
      ], const RoamLivePage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('漫游完成'), findsOneWidget);
    await _shot(tester, 'goldens/page_roam_settle_no_track.png');
  });

  // ── 据点核销码 subpackageRoam/citynode-code ────────────────────────────
  testWidgets('B10 据点核销码 · 缺参(只给返回,零重试)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        authControllerProvider.overrideWith(() => _FixedAuth(_auth())),
      ], const CityNodeVoucherPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('这个核销码打不开'), findsOneWidget);
    await _shot(tester, 'goldens/page_city_node_voucher_missing.png');
  });

  testWidgets('B11 据点核销码 · 出码失败(说清原因 + 可重试)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        authControllerProvider.overrideWith(() => _FixedAuth(_auth())),
        roamApiProvider.overrideWithValue(
          _FailVoucherApi(DioClient(TokenStore(const FlutterSecureStorage()))),
        ),
      ], const CityNodeVoucherPage(poiId: 701, name: '老码头咖啡')),
    );
    await tester.pumpAndSettle();

    // 文案有意不暴露后端原文:说清「哪一步失败 + 下一步做什么」。
    expect(find.text('暂时无法生成核销码，请稍后重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    await _shot(tester, 'goldens/page_city_node_voucher_error.png');
  });

  // ── 定向玩法 pages/play/index ─────────────────────────────────────────
  testWidgets('B12 定向玩法 · 城市模式常态', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        authControllerProvider.overrideWith(() => _FixedAuth(_auth())),
        playApiProvider.overrideWithValue(_Api(_cityPayload())),
        aiNpcApiProvider.overrideWithValue(_NpcApi()),
        teamProgressProvider(
          41,
        ).overrideWith((ref) async => const TeamProgress()),
        roamApiProvider.overrideWithValue(
          _RoamApi(DioClient(TokenStore(const FlutterSecureStorage()))),
        ),
      ], const PlaySessionPage(activityId: 41)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    await _shot(tester, 'goldens/page_play_city_normal.png');
  });

  testWidgets('B14 定向玩法 · 手账(章节 + 站点列表)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    final PlayNodesResult result = PlayNodesResult.fromJson(_cityPayload());
    await tester.pumpWidget(
      _app(
        <dynamic>[
          authControllerProvider.overrideWith(() => _FixedAuth(_auth())),
        ],
        ClassicPlayJournalPage(
          chapter: result.chapters.first,
          nodes: result.nodes,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _shot(tester, 'goldens/page_play_journal.png');
  });

  testWidgets('B15 定向玩法 · 故事流(第 N 站)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    final PlayNodesResult result = PlayNodesResult.fromJson(_cityPayload());
    final ScrollController controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        <dynamic>[
          authControllerProvider.overrideWith(() => _FixedAuth(_auth())),
        ],
        Scaffold(
          body: ClassicPlayStorySurface(
            node: result.nodes.last,
            step: 2,
            scrollController: controller,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    await _shot(tester, 'goldens/page_play_story.png');
  });

  testWidgets('B16 定向玩法 · 通关(里程碑 + 探索值)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    final PlayNodesResult result = PlayNodesResult.fromJson(<String, dynamic>{
      ..._cityPayload(),
      'doneCount': 2,
    });
    final ScrollController controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        <dynamic>[
          authControllerProvider.overrideWith(() => _FixedAuth(_auth())),
        ],
        Scaffold(
          body: ClassicPlayFinishSurface(
            result: result,
            scrollController: controller,
            onContinue: () {},
            onJournal: () {},
            onLeaderboard: () {},
            onShare: () {},
            onSave: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    await _shot(tester, 'goldens/page_play_finish.png');
  });

  // ── 城市实例 pages/play/circle/index ──────────────────────────────────
  testWidgets('B60 城市实例 · 缺参(明确说明,不停在 loading)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        authControllerProvider.overrideWith(() => _FixedAuth(_auth())),
      ], const CircleThemePlayPage(topicId: 0)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('circle-missing-info')), findsOneWidget);
    await _shot(tester, 'goldens/page_circle_missing_param.png');
  });
}
