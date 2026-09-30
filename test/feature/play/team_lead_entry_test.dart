import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/ai_npc_api.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/data/models/club_lead.dart';
import 'package:chengyin_app/data/models/npc.dart';
import 'package:chengyin_app/feature/play/play_session_page.dart';
import 'package:chengyin_app/feature/play/team_lead_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

DioClient _client() => DioClient(TokenStore(const FlutterSecureStorage()));

class _PlayApi extends PlayApi {
  _PlayApi() : super(_client());

  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async =>
      const PlayNodesResult(
        topicId: 23,
        mode: 1,
        playable: true,
        total: 1,
        doneCount: 0,
        // 真源:一条节点都没有时整屏落「本场路线节点还在配置中」空态,
        // 带队工具条根本不渲染(`pages/play/index.js:2851`)。这一条测的是工具条。
        nodes: <PlayNode>[
          PlayNode(
            nodeId: 8,
            name: '定向第一站',
            address: '城瘾路 1 号',
            sortId: 1,
            done: false,
          ),
        ],
      );
}

class _NpcApi extends AiNpcApi {
  _NpcApi() : super(_client());

  @override
  Future<List<NpcProfile>> fetchProfiles({
    String scope = 'global',
    int? activityId,
  }) async => const <NpcProfile>[];
}

Widget _app({
  required TeamProgress progress,
  required bool liquidGlassSupported,
}) {
  final GoRouter router = GoRouter(
    initialLocation: '/play/7',
    routes: <RouteBase>[
      GoRoute(
        path: '/play/:id',
        builder: (_, _) => PlaySessionPage(
          activityId: 7,
          liquidGlassSupported: liquidGlassSupported,
        ),
      ),
      GoRoute(
        path: '/team-lead/:id',
        builder: (_, GoRouterState state) =>
            Scaffold(body: Text('带队场次 ${state.pathParameters['id']}')),
      ),
    ],
  );
  return ProviderScope(
    overrides: <dynamic>[
      playApiProvider.overrideWithValue(_PlayApi()),
      aiNpcApiProvider.overrideWithValue(_NpcApi()),
      teamProgressProvider(7).overrideWith((ref) async => progress),
    ].cast(),
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('带队场次在原游玩工具位置显示“更多 / 队伍位置”并进入本场', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(
        progress: const TeamProgress(exists: true, isLeader: false),
        liquidGlassSupported: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('play-more-tools')), findsOneWidget);
    expect(find.text('更多'), findsOneWidget);

    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    expect(find.text('队伍位置'), findsOneWidget);

    await tester.tap(find.text('队伍位置'));
    await tester.pumpAndSettle();
    expect(find.text('带队场次 7'), findsOneWidget);
  });

  testWidgets('没有带队场次时不显示入口，避免普通活动误进队长页', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(
        progress: const TeamProgress(exists: false, isLeader: true),
        liquidGlassSupported: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('play-more-tools')), findsNothing);
    expect(find.text('更多'), findsNothing);
  });

  testWidgets('iOS 26 使用单个原生 UIButton + UIMenu，保留 44pt 与 SF Symbol', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        progress: const TeamProgress(exists: true, isLeader: true),
        liquidGlassSupported: true,
      ),
    );
    await tester.pumpAndSettle();

    final LiquidGlassMenu menu = tester.widget<LiquidGlassMenu>(
      find.byType(LiquidGlassMenu),
    );
    expect(find.byType(LiquidGlassMenu), findsOneWidget);
    expect(menu.height, 44);
    expect(menu.label, '更多');
    expect(menu.menuTitle, '游玩工具');
    expect(menu.icon?.sfSymbolName, 'ellipsis.circle');
    expect(menu.items, hasLength(1));
    expect(menu.items.single.title, '队伍位置');
    expect(menu.items.single.icon?.sfSymbolName, 'person.3.fill');

    menu.onItemSelected('team-progress');
    await tester.pumpAndSettle();
    expect(find.text('带队场次 7'), findsOneWidget);
  });
}
