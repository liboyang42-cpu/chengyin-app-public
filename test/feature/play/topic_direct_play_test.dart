import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/ai_npc_api.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/data/models/npc.dart';
import 'package:chengyin_app/feature/npc/npc_controller.dart';
import 'package:chengyin_app/feature/play/play_session_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

DioClient _client() => DioClient(TokenStore(const FlutterSecureStorage()));

class _TopicPlayApi extends PlayApi {
  _TopicPlayApi() : super(_client());

  final List<int> requestedTopics = <int>[];
  final List<int> requestedActivities = <int>[];
  final List<int> answeredTopics = <int>[];

  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async {
    requestedActivities.add(activityId);
    return const PlayNodesResult(
      topicId: 23,
      mode: 1,
      playable: true,
      total: 1,
      doneCount: 0,
      // 节点为空的场次在真源整屏落空态、不渲染游玩工具(`pages/play/index.js:2851`),
      // 下面几条测的是工具条上的入场码入口,所以回包得真有一条站。
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

  @override
  Future<PlayNodesResult> fetchTopicNodes(int topicId) async {
    requestedTopics.add(topicId);
    return PlayNodesResult(
      topicId: topicId,
      mode: 1,
      playable: true,
      total: 0,
      doneCount: 0,
      nodes: const <PlayNode>[
        PlayNode(
          nodeId: 7,
          name: '主题问答站',
          address: '',
          sortId: 1,
          done: false,
          validationMethod: 1,
          needAnswer: true,
          question: '城瘾的答案是什么？',
        ),
      ],
    );
  }

  @override
  Future<CheckinReward> submitTopicAnswer({
    required int topicId,
    required int nodeId,
    required String answer,
    RouteAdvanceToken? routeAdvance,
  }) async {
    answeredTopics.add(topicId);
    return const CheckinReward(
      nodeId: 7,
      firstTime: true,
      doneCount: 1,
      total: 1,
      completed: false,
      newBadges: <PlayBadge>[],
    );
  }
}

class _RecordingNpcApi extends AiNpcApi {
  _RecordingNpcApi() : super(_client());

  final List<int?> requestedActivities = <int?>[];
  final List<String> requestedEvents = <String>[];

  @override
  Future<List<NpcProfile>> fetchProfiles({
    String scope = 'global',
    int? activityId,
  }) async {
    requestedActivities.add(activityId);
    return const <NpcProfile>[
      NpcProfile(profileId: 9, name: '活动 NPC', scopeType: 1),
    ];
  }

  @override
  Future<NpcLine> fetchEventLine({
    required int profileId,
    required String eventType,
    int? nodeId,
  }) async {
    requestedEvents.add(eventType);
    return const NpcLine(profileId: 9, line: '活动话术');
  }
}

void main() {
  testWidgets('topicId 直玩只加载主题节点，不请求 activityId=0 的 NPC', (
    WidgetTester tester,
  ) async {
    final playApi = _TopicPlayApi();
    final npcApi = _RecordingNpcApi();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          playApiProvider.overrideWithValue(playApi),
          aiNpcApiProvider.overrideWithValue(npcApi),
        ].cast(),
        child: const MaterialApp(
          home: PlaySessionPage(activityId: 0, topicId: 23),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(playApi.requestedTopics, <int>[23]);
    expect(find.text('游玩打卡'), findsOneWidget);
    expect(
      npcApi.requestedActivities,
      isEmpty,
      reason: '主题直玩没有活动场次，不得访问 activityId=0 的活动 NPC',
    );
  });

  testWidgets('主题答题成功不发送活动 NPC 事件', (WidgetTester tester) async {
    final playApi = _TopicPlayApi();
    final npcApi = _RecordingNpcApi();
    final container = ProviderContainer(
      overrides: <dynamic>[
        playApiProvider.overrideWithValue(playApi),
        aiNpcApiProvider.overrideWithValue(npcApi),
      ].cast(),
    );
    addTearDown(container.dispose);

    // 预热错误的 activityId=0 会话，让残留的无条件 onEvent 真能访问边界。
    await container.read(npcSessionProvider(0).notifier).loadProfiles();
    npcApi.requestedActivities.clear();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PlaySessionPage(activityId: 0, topicId: 23),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('主题问答站'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('play-answer-text-input')),
      '城市与人',
    );
    expect(find.byType(CupertinoTextField), findsOneWidget);
    // 提交按钮跟着输入框内容解禁:先让 onChanged 引发的重建落地,再点。
    await tester.pump();
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    expect(playApi.answeredTopics, <int>[23]);
    expect(npcApi.requestedActivities, isEmpty);
    expect(npcApi.requestedEvents, isEmpty, reason: '主题直玩的节点回执不得进入活动 NPC 事件链');
  });

  testWidgets('活动与主题参数同时存在时优先加载活动场次', (WidgetTester tester) async {
    final playApi = _TopicPlayApi();
    final npcApi = _RecordingNpcApi();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          playApiProvider.overrideWithValue(playApi),
          aiNpcApiProvider.overrideWithValue(npcApi),
        ].cast(),
        child: const MaterialApp(
          home: PlaySessionPage(activityId: 77, topicId: 23),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(playApi.requestedActivities, <int>[77]);
    expect(playApi.requestedTopics, isEmpty);
  });

  testWidgets('游玩页作为根路由打开时，返回落到票夹', (WidgetTester tester) async {
    final playApi = _TopicPlayApi();
    final npcApi = _RecordingNpcApi();
    final router = GoRouter(
      initialLocation: '/play/77',
      routes: <RouteBase>[
        GoRoute(
          path: '/play/:id',
          builder: (_, _) => const PlaySessionPage(activityId: 77),
        ),
        GoRoute(
          path: '/tickets',
          builder: (_, _) => const Scaffold(body: Text('我的票夹')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          playApiProvider.overrideWithValue(playApi),
          aiNpcApiProvider.overrideWithValue(npcApi),
        ].cast(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('play-back')));
    await tester.pumpAndSettle();

    expect(find.text('我的票夹'), findsOneWidget);
  });

  testWidgets('registrationId 在城市定向游玩页保留为入场码入口', (WidgetTester tester) async {
    final playApi = _TopicPlayApi();
    final npcApi = _RecordingNpcApi();
    final router = GoRouter(
      initialLocation: '/play/77',
      routes: <RouteBase>[
        GoRoute(
          path: '/play/:id',
          builder: (_, _) =>
              const PlaySessionPage(activityId: 77, registrationId: 91),
        ),
        GoRoute(
          path: '/ticket/:id/pass',
          builder: (_, state) =>
              Scaffold(body: Text('入场码 ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          playApiProvider.overrideWithValue(playApi),
          aiNpcApiProvider.overrideWithValue(npcApi),
        ].cast(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('play-entry-pass')));
    await tester.pumpAndSettle();

    expect(find.text('入场码 91'), findsOneWidget);
  });
}
