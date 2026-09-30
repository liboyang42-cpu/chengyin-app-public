import 'package:chengyin_app/feature/roam/roam_history_page.dart';
import 'package:chengyin_app/feature/roam/roam_live_controller.dart';
import 'package:chengyin_app/feature/roam/roam_team_markers.dart';
import 'package:chengyin_app/feature/roam/roam_live_page.dart';
import 'package:chengyin_app/core/map/apple_scene_view.dart';
import 'package:chengyin_app/core/map/map_scene.dart';
import 'package:chengyin_app/data/models/roam.dart';
import 'package:chengyin_app/data/models/roam_session.dart' hide RoamPoi;
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fixed_auth.dart';

void main() {
  testWidgets('游客点 GO 先走登录门禁,不先索取定位再打 401', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roamHistoryProvider.overrideWith((_) async => const <RoamSession>[]),
          roamIntroTopicsProvider.overrideWith(
            (_) async => const <RoamIntroTopic>[],
          ),
        ],
        child: const MaterialApp(home: RoamLivePage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('roam-go')));
    await tester.pumpAndSettle();

    expect(find.text('登录城瘾'), findsOneWidget);
    expect(find.text('开启实时定位'), findsNothing);
  });

  testWidgets('漫游历史有实时入口，并进入 /roam 开始页', (tester) async {
    final GoRouter router = GoRouter(
      initialLocation: '/roam/history',
      routes: <RouteBase>[
        GoRoute(
          path: '/roam/history',
          builder: (_, _) => const RoamHistoryPage(),
        ),
        GoRoute(path: '/roam', builder: (_, _) => const RoamLivePage()),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roamHistoryProvider.overrideWith((_) async => const <RoamSession>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('roam-live-entry')));
    await tester.pumpAndSettle();

    expect(find.text('漫游'), findsOneWidget);
  });

  testWidgets('自由漫游玩法使用 Cupertino Sheet 并保留小程序文案顺序', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roamHistoryProvider.overrideWith((_) async => const <RoamSession>[]),
          roamIntroTopicsProvider.overrideWith(
            (_) async => const <RoamIntroTopic>[],
          ),
        ],
        child: const MaterialApp(home: RoamLivePage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('roam-intro-card-free')));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.text('自由漫游怎么玩'), findsOneWidget);
    expect(find.text('不绑定路线，随走随发现城市。'), findsOneWidget);
    expect(find.text('开始'), findsOneWidget);
    expect(find.text('点“开启定位并出发”后，地图才会回到你身边。'), findsOneWidget);
    expect(find.text('探索'), findsOneWidget);
    expect(find.text('走近街区可点亮迷雾；附近内容会在地图上出现。'), findsOneWidget);
    expect(find.text('记录'), findsOneWidget);
    expect(find.text('本次足迹保存在本机；演示点只供浏览，不能打卡。'), findsOneWidget);
  });

  testWidgets('200% Dynamic Type 下玩法 Sheet 仍可滚动且无溢出', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roamHistoryProvider.overrideWith((_) async => const <RoamSession>[]),
          roamIntroTopicsProvider.overrideWith(
            (_) async => const <RoamIntroTopic>[],
          ),
        ],
        child: MaterialApp(
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const RoamLivePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('roam-intro-card-free')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(CupertinoPageScaffold),
        matching: find.byType(Scrollable),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('200% Dynamic Type/减少动态/高对比下漫游在 SE/390 屏可操作', (
    WidgetTester tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final Size viewport in const <Size>[Size(320, 568), Size(390, 844)]) {
      bool started = false;
      bool openedRules = false;
      bool openedHistory = false;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport;

      await tester.pumpWidget(
        MaterialApp(
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
              highContrast: true,
            ),
            child: child!,
          ),
          home: RoamIntroView(
            key: ValueKey<Size>(viewport),
            sessions: const <RoamSession>[],
            topics: const <RoamIntroTopic>[],
            onStart: () => started = true,
            onStartAndShoot: () {},
            onOpenRules: () => openedRules = true,
            onOpenHistory: () => openedHistory = true,
            onOpenStampAlbum: () {},
            onOpenBadges: () {},
            onOpenTopic: (_) {},
            onOpenOfficialEvents: () {},
            onDiscoverShops: () {},
            onOpenProfile: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '$viewport 开始页不应溢出');
      expect(find.byKey(const Key('roam-intro-card-free')), findsOneWidget);
      expect(find.byKey(const Key('roam-go')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('roam-go'))).height,
        greaterThanOrEqualTo(44),
      );

      await tester.tap(find.byKey(const Key('roam-intro-card-free')));
      await tester.tap(find.byKey(const Key('roam-go')));
      expect(openedRules, isTrue);
      expect(started, isTrue);

      await tester.tap(find.text('漫游护照'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '$viewport 护照页不应溢出');
      expect(find.byKey(const Key('roam-passport-history')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('roam-passport-history'))).height,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(find.byKey(const Key('roam-passport-history')));
      expect(openedHistory, isTrue);
    }
  });

  testWidgets('200% Dynamic Type 下实时漫游状态与结束 CTA 不溢出', (
    WidgetTester tester,
  ) async {
    const Size viewport = Size(320, 568);
    const RoamLiveState roamingState = RoamLiveState(
      phase: RoamLivePhase.roaming,
      location: RoamLivePosition(latitude: 31.2304, longitude: 121.4737),
      distanceM: 123456,
      newlyRevealed: 999,
      shops: 888,
    );
    await tester.binding.setSurfaceSize(viewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roamLiveControllerProvider.overrideWith(
            () => _PresetRoamLiveController(roamingState),
          ),
          roamNearbyLayerProvider.overrideWith(_StubNearbyLayer.new),
          roamHistoryProvider.overrideWith((_) async => const <RoamSession>[]),
        ],
        child: MaterialApp(
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              size: viewport,
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
              highContrast: true,
            ),
            child: child!,
          ),
          home: const RoamLivePage(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('实时探索'), findsOneWidget);
    expect(find.text('结束漫游'), findsOneWidget);
    expect(
      tester.getSize(find.widgetWithText(CyNativeButton, '结束漫游')).height,
      greaterThanOrEqualTo(44),
    );
    expect(tester.takeException(), isNull);
  });

  // B1 二轮报告 N3:护照瓷贴「勋章墙 / 发现附近店铺」是整页需登录路由,
  // 游客直 push 会被路由静默弹回首页(roam2-22b/23 实拍)—— 入口必须先就地
  // 弹登录,登完接着进目标页。
  Future<GoRouter> pumpPassport(
    WidgetTester tester, {
    bool signedIn = false,
  }) async {
    final GoRouter router = GoRouter(
      initialLocation: '/roam',
      routes: <RouteBase>[
        GoRoute(path: '/roam', builder: (_, _) => const RoamLivePage()),
        GoRoute(
          path: '/badges',
          builder: (_, _) => const Text('badges-landed'),
        ),
        GoRoute(
          path: '/merchant/discover',
          builder: (_, _) => const Text('discover-landed'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (signedIn)
            authControllerProvider.overrideWith(
              () => FixedAuth(signedInAuthState()),
            ),
          roamHistoryProvider.overrideWith((_) async => const <RoamSession>[]),
          roamIntroTopicsProvider.overrideWith(
            (_) async => const <RoamIntroTopic>[],
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('漫游护照'));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('游客点护照瓷贴:就地弹登录,不落进需登录目标页', (WidgetTester tester) async {
    await pumpPassport(tester);

    await tester.tap(find.byKey(const Key('roam-passport-badges')));
    await tester.pumpAndSettle();

    expect(find.text('登录城瘾'), findsOneWidget);
    expect(find.text('badges-landed'), findsNothing);
  });

  testWidgets('登录态点护照瓷贴:直达勋章墙 / 发现店铺', (WidgetTester tester) async {
    await pumpPassport(tester, signedIn: true);

    await tester.tap(find.byKey(const Key('roam-passport-badges')));
    await tester.pumpAndSettle();
    expect(find.text('badges-landed'), findsOneWidget);
  });

  testWidgets('★ 点地图针接线:onPointTap 已传,城市针走 checkin、扫码针跳据点详情', (
    WidgetTester tester,
  ) async {
    const RoamLiveState roamingState = RoamLiveState(
      phase: RoamLivePhase.roaming,
      location: RoamLivePosition(latitude: 31.2304, longitude: 121.4737),
      revealedTiles: <String>{'pin-tile'},
      pois: <RoamPoi>[
        RoamPoi(id: 9, name: '老钟楼', lat: 31.231, lng: 121.4745),
        RoamPoi(id: 11, name: '河畔咖啡', lat: 31.232, lng: 121.475, type: 2),
      ],
    );
    final _PinTapRoamController controller = _PinTapRoamController(
      roamingState,
      const RoamCheckinResult(
        outcome: RoamCheckinOutcome.needsScan,
        message: '这是参与据点,去扫码核销',
        poiId: 77,
      ),
    );
    final GoRouter router = GoRouter(
      initialLocation: '/roam',
      routes: <RouteBase>[
        GoRoute(path: '/roam', builder: (_, _) => const RoamLivePage()),
        GoRoute(
          path: '/roam/poi/:poiId',
          builder: (_, GoRouterState s) => CupertinoPageScaffold(
            child: Text('据点详情-${s.pathParameters['poiId']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roamLiveControllerProvider.overrideWith(() => controller),
          roamHistoryProvider.overrideWith((_) async => const <RoamSession>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    final AppleSceneView view = tester.widget<AppleSceneView>(
      find.byType(AppleSceneView),
    );
    expect(
      view.onPointTap,
      isNotNull,
      reason: 'gap-spec-roam P0-3:不传 onPointTap 时 checkin 整条是死代码',
    );

    // 城市地点针 → checkin;回执 needsScan → 按服务端 poiId 跳据点详情。
    view.onPointTap!(
      const MapPoint(
        id: 'roam-poi-9',
        latitude: 31.231,
        longitude: 121.4745,
        title: '老钟楼',
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.checkinPins.single.name, '老钟楼');
    expect(find.text('据点详情-77'), findsOneWidget);
  });

  testWidgets('★ 商户针点开进据点详情(源 onMarkerTap:isCityNode → roam-poi-detail)', (
    WidgetTester tester,
  ) async {
    const RoamLiveState roamingState = RoamLiveState(
      phase: RoamLivePhase.roaming,
      location: RoamLivePosition(latitude: 31.2304, longitude: 121.4737),
      revealedTiles: <String>{'pin-tile'},
      pois: <RoamPoi>[
        RoamPoi(id: 11, name: '河畔咖啡', lat: 31.232, lng: 121.475, type: 2),
      ],
    );
    final _PinTapRoamController controller = _PinTapRoamController(
      roamingState,
      const RoamCheckinResult(outcome: RoamCheckinOutcome.lit, message: '已点亮'),
    );
    final GoRouter router = GoRouter(
      initialLocation: '/roam',
      routes: <RouteBase>[
        GoRoute(path: '/roam', builder: (_, _) => const RoamLivePage()),
        GoRoute(
          path: '/roam/poi/:poiId',
          builder: (_, GoRouterState s) => CupertinoPageScaffold(
            child: Text('据点详情-${s.pathParameters['poiId']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roamLiveControllerProvider.overrideWith(() => controller),
          roamHistoryProvider.overrideWith((_) async => const <RoamSession>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    final AppleSceneView view = tester.widget<AppleSceneView>(
      find.byType(AppleSceneView),
    );
    view.onPointTap!(
      const MapPoint(
        id: 'roam-poi-11',
        latitude: 31.232,
        longitude: 121.475,
        title: '河畔咖啡',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('据点详情-11'), findsOneWidget);
    expect(
      controller.checkinPins,
      isEmpty,
      reason: '商户打卡走 shop/visit,不由 checkin 代发',
    );
  });
}

class _PresetRoamLiveController extends RoamLiveController {
  _PresetRoamLiveController(this.initialState);

  final RoamLiveState initialState;

  @override
  RoamLiveState build() => initialState;
}

/// 漫游地图上的队伍层会去拉 `/api/team/nearby` —— 这几条用例只看版式,
/// 用空图层顶掉网络(2026-09-18 A3 地图组队 marker 层接入后新增)。
class _StubNearbyLayer extends RoamNearbyLayerController {
  @override
  Future<RoamNearbyLayer> build() async => const RoamNearbyLayer();
}

class _PinTapRoamController extends RoamLiveController {
  _PinTapRoamController(this.initialState, this.checkinReply);

  final RoamLiveState initialState;
  final RoamCheckinResult checkinReply;
  final List<({String name, double poiLat, double poiLng})> checkinPins =
      <({String name, double poiLat, double poiLng})>[];

  @override
  RoamLiveState build() => initialState;

  @override
  Future<RoamCheckinResult?> checkinPin({
    required String name,
    required double poiLat,
    required double poiLng,
  }) async {
    checkinPins.add((name: name, poiLat: poiLat, poiLng: poiLng));
    return checkinReply;
  }
}
