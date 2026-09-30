// 结局信的分发链(G1762 / §5):`PlayEndingPage` 与 `/api/play/ending` 早就在,
// 但全仓没有一个入口 —— 探店日跑完之后那封信玩家永远看不到。
//
// 真源:通关收尾 `openFinish()`(`pages/play/index.js:5065`)第一件事就是 `loadEnding()`
// (`:5050`),而 `loadEnding` 的门是 `mode !== 2` 直接 return —— 结局信只属于探店日;
// 拉回来之后以 `ending.show` 全屏叠在通关卡之上(`index.wxml:1379`),关掉退回卡上。
// 参数照 `_sessionParams()`(`:488`):活动会话只带 activityId,自玩会话才带 topicId。

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/router/app_router.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/data/models/play_ending.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/play/play_ending_page.dart';
import 'package:chengyin_app/feature/play/play_session_controller.dart';
import 'package:chengyin_app/feature/play/play_session_page.dart';
import 'package:chengyin_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

DioClient _client() => DioClient(TokenStore(const FlutterSecureStorage()));

/// 首屏按次返回不同回包(模拟「打完最后一站」),结局记录请求参数。
class _StubPlayApi extends PlayApi {
  _StubPlayApi({required this.results, this.letter, this.endingFailure})
    : super(_client());

  final List<PlayNodesResult> results;
  final PlayEnding? letter;
  Object? endingFailure;

  final List<int?> nodesTopicIds = <int?>[];
  final List<PlayEndingKey> endingRequests = <PlayEndingKey>[];

  int get nodesCalls => nodesTopicIds.length;

  /// 第 N 次首屏返回第 N 个回包,发完就用最后一个(测「打完最后一站」的两次回包)。
  PlayNodesResult _next() {
    final int i = nodesCalls - 1;
    return results[i < results.length ? i : results.length - 1];
  }

  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async {
    nodesTopicIds.add(null);
    return _next();
  }

  @override
  Future<PlayNodesResult> fetchTopicNodes(int topicId) async {
    nodesTopicIds.add(topicId);
    return _next();
  }

  @override
  Future<PlayEnding> ending({int? activityId, int? topicId}) async {
    endingRequests.add((activityId: activityId, topicId: topicId));
    if (endingFailure != null) throw endingFailure!;
    return letter!;
  }
}

PlayNodesResult _session({
  required int mode,
  required bool done,
  int topicId = 73,
}) => PlayNodesResult(
  topicId: topicId,
  mode: mode,
  playable: true,
  total: 1,
  doneCount: done ? 1 : 0,
  registered: true,
  chapters: const <PlayChapter>[
    PlayChapter(chapterId: 5, meta: '第一章', title: '城南旧货'),
  ],
  nodes: <PlayNode>[
    PlayNode(nodeId: 7, name: '第一站', address: '城瘾路 1 号', sortId: 1, done: done),
  ],
);

const PlayEnding _letter = PlayEnding(
  opener: '你把城南走成了一封信',
  fragments: <EndingFragment>[
    EndingFragment(step: 1, name: '第一站', nodeId: 7, text: '门口那棵树底下有人等过你。'),
  ],
);

class _LoggedInAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    user: User(id: 99, nickname: '测试玩家', avatar: '', role: 'player'),
    initialized: true,
  );
}

/// 游玩页 → 结局信,用与 `app_router` 相同的路由形状(结局信从 query 收 topicId)。
Future<ProviderContainer> _pumpPlay(
  WidgetTester tester, {
  required _StubPlayApi api,
  required int activityId,
  int? topicId,
}) async {
  final ProviderContainer container = ProviderContainer(
    retry: (int _, Object _) => null,
    overrides: <dynamic>[
      playApiProvider.overrideWithValue(api),
      authControllerProvider.overrideWith(_LoggedInAuth.new),
    ].cast(),
  );
  addTearDown(container.dispose);

  final String playLocation =
      '/play/$activityId${topicId == null ? '' : '?topicId=$topicId'}';
  final GoRouter router = GoRouter(
    initialLocation: playLocation,
    routes: <RouteBase>[
      GoRoute(
        path: '/play/:activityId',
        builder: (BuildContext context, GoRouterState state) => PlaySessionPage(
          activityId:
              int.tryParse(state.pathParameters['activityId'] ?? '') ?? 0,
          topicId: int.tryParse(state.uri.queryParameters['topicId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/play/:activityId/ending',
        builder: (BuildContext context, GoRouterState state) => PlayEndingPage(
          activityId:
              int.tryParse(state.pathParameters['activityId'] ?? '') ?? 0,
          topicId: int.tryParse(state.uri.queryParameters['topicId'] ?? ''),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      // 减动效:mode2 进场的开卡包 Rive 在 widget test 里起不了原生解码
      // (`pack_opening_intro.dart:88` 就是为这条路径留的开关)。
      child: MaterialApp.router(
        routerConfig: router,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// 打完整场:再拉一次首屏,回包里全部完成 ⇒ 走 `openFinish` 那条收尾链。
Future<void> _finishSession(
  WidgetTester tester,
  ProviderContainer container, {
  required int? activityId,
  required int? topicId,
}) async {
  await container
      .read(
        playSessionProvider((
          activityId: activityId,
          topicId: topicId,
        )).notifier,
      )
      .load();
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('★ 通关收尾把结局信送到位(真源 openFinish → loadEnding)', () {
    testWidgets('探店日(mode2)通关:结局信压上来,自玩会话按 topicId 取', (
      WidgetTester tester,
    ) async {
      final _StubPlayApi api = _StubPlayApi(
        results: <PlayNodesResult>[
          _session(mode: 2, done: false),
          _session(mode: 2, done: true),
        ],
        letter: _letter,
      );
      final ProviderContainer container = await _pumpPlay(
        tester,
        api: api,
        activityId: 0,
        topicId: 73,
      );
      expect(api.nodesTopicIds, <int?>[73], reason: '自玩会话首屏只按 topicId 拉');

      await _finishSession(tester, container, activityId: null, topicId: 73);

      expect(api.endingRequests, <PlayEndingKey>[
        (activityId: null, topicId: 73),
      ], reason: '参数照 _sessionParams():自玩没有 activityId');
      expect(find.text('你把城南走成了一封信'), findsOneWidget);
      expect(find.text('门口那棵树底下有人等过你。'), findsOneWidget);

      // 关掉结局信 = 真源 `closeEnding()`:人退回探店日那一屏,不是退出游玩。
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('你把城南走成了一封信'), findsNothing);
      expect(find.text('1/1 已核销'), findsOneWidget);
    });

    testWidgets('重进一趟早已打完的探店日:不重放结局信', (WidgetTester tester) async {
      final _StubPlayApi api = _StubPlayApi(
        results: <PlayNodesResult>[_session(mode: 2, done: true)],
        letter: _letter,
      );
      await _pumpPlay(tester, api: api, activityId: 0, topicId: 73);
      await tester.pumpAndSettle();

      expect(
        api.endingRequests,
        isEmpty,
        reason: '真源 index.js:3228 —— 重进一个早已完成的主题不重放仪式',
      );
      expect(find.text('你把城南走成了一封信'), findsNothing);
    });

    testWidgets('城市定向(mode1)通关:根本不问 /api/play/ending', (
      WidgetTester tester,
    ) async {
      final _StubPlayApi api = _StubPlayApi(
        results: <PlayNodesResult>[
          _session(mode: 1, done: false, topicId: 21),
          _session(mode: 1, done: true, topicId: 21),
        ],
        letter: _letter,
      );
      final ProviderContainer container = await _pumpPlay(
        tester,
        api: api,
        activityId: 41,
      );

      await _finishSession(tester, container, activityId: 41, topicId: null);

      expect(
        find.byKey(const Key('classic-play-finish')),
        findsOneWidget,
        reason: '定向照样有通关卡',
      );
      expect(
        api.endingRequests,
        isEmpty,
        reason: '真源 loadEnding 第一行 mode!==2 就 return,定向没有这封信',
      );
      expect(find.text('你把城南走成了一封信'), findsNothing);
    });

    testWidgets('活动会话的结局信按 activityId 取,不带 topicId', (
      WidgetTester tester,
    ) async {
      final _StubPlayApi api = _StubPlayApi(
        results: <PlayNodesResult>[
          _session(mode: 2, done: false, topicId: 21),
          _session(mode: 2, done: true, topicId: 21),
        ],
        letter: _letter,
      );
      final ProviderContainer container = await _pumpPlay(
        tester,
        api: api,
        activityId: 41,
        topicId: 21,
      );

      await _finishSession(tester, container, activityId: 41, topicId: null);

      expect(api.endingRequests, <PlayEndingKey>[
        (activityId: 41, topicId: null),
      ], reason: '同时有活动与主题时 activityId 优先(同 _sessionParams)');
      expect(find.text('你把城南走成了一封信'), findsOneWidget);
    });

    testWidgets('结局信拉不到:点名是城市故事没加载,给重新加载且真重发', (WidgetTester tester) async {
      final _StubPlayApi api = _StubPlayApi(
        results: <PlayNodesResult>[
          _session(mode: 2, done: false),
          _session(mode: 2, done: true),
        ],
        letter: _letter,
        endingFailure: PlayException('结局信暂时没写好'),
      );
      final ProviderContainer container = await _pumpPlay(
        tester,
        api: api,
        activityId: 0,
        topicId: 73,
      );

      await _finishSession(tester, container, activityId: null, topicId: 73);

      expect(find.text('城市故事暂未加载，不影响本次足迹。'), findsOneWidget);
      expect(find.text('你把城南走成了一封信'), findsNothing);

      api.endingFailure = null;
      await tester.tap(find.text('重新加载'));
      await tester.pumpAndSettle();

      expect(api.endingRequests.length, 2, reason: '重试必须真再问一次');
      expect(find.text('你把城南走成了一封信'), findsOneWidget);
    });
  });

  group('★ 路由落点(deeplink / 分享链直落) 用真实 app_router', () {
    Future<ProviderContainer> pumpApp(
      WidgetTester tester,
      _StubPlayApi api,
    ) async {
      final ProviderContainer container = ProviderContainer(
        retry: (int _, Object _) => null,
        overrides: <dynamic>[
          playApiProvider.overrideWithValue(api),
          authControllerProvider.overrideWith(_LoggedInAuth.new),
        ].cast(),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ChengyinApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      return container;
    }

    testWidgets('/play/0/ending?topicId=73 把 topicId 交到页上', (
      WidgetTester tester,
    ) async {
      final _StubPlayApi api = _StubPlayApi(
        results: const <PlayNodesResult>[],
        letter: _letter,
      );
      final ProviderContainer container = await pumpApp(tester, api);

      container.read(appRouterProvider).go('/play/0/ending?topicId=73');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(PlayEndingPage), findsOneWidget);
      expect(api.endingRequests, <PlayEndingKey>[
        (activityId: null, topicId: 73),
      ]);
      expect(find.text('你把城南走成了一封信'), findsOneWidget);
    });

    testWidgets('/play/41/ending 按活动会话取信', (WidgetTester tester) async {
      final _StubPlayApi api = _StubPlayApi(
        results: const <PlayNodesResult>[],
        letter: _letter,
      );
      final ProviderContainer container = await pumpApp(tester, api);

      container.read(appRouterProvider).go('/play/41/ending');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.endingRequests, <PlayEndingKey>[
        (activityId: 41, topicId: null),
      ]);
    });
  });
}
