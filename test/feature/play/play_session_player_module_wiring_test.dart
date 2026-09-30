import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/ai_npc_api.dart';
import 'package:chengyin_app/data/api/game_session_api.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/data/models/npc.dart';
import 'package:chengyin_app/feature/play/play_session_page.dart';
import 'package:chengyin_app/feature/play/player_game_module_controller.dart';
import 'package:chengyin_app/feature/play/player_game_pending_store.dart';

/// 主玩页「本局线索」三件的**接线守卫**:章节卡上的身份胶囊(点开面板)、
/// 首入的身份卡、节点上的本站任务。三件都在 `play_session_page` 的
/// 沉浸式章节布局里挂载 —— 谁把它们从页面上摘掉,这里就变红。
void main() {
  testWidgets('主玩页三件都在:身份卡 → 身份胶囊 → 本局线索(含本站任务)', (WidgetTester tester) async {
    final _StubPlayerGateway gateway = _StubPlayerGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playApiProvider.overrideWithValue(_StubPlayApi()),
          aiNpcApiProvider.overrideWithValue(_EmptyAiNpcApi()),
          playerGameSessionApiProvider.overrideWithValue(gateway),
          playerGamePendingStoreProvider.overrideWithValue(
            PlayerGamePendingStore.memory(),
          ),
          playerGameRoleSeenStoreProvider.overrideWithValue(
            PlayerGameRoleSeenStore.memory(),
          ),
        ],
        child: const MaterialApp(home: PlaySessionPage(activityId: 41)),
      ),
    );
    await tester.pumpAndSettle();

    // ① 身份卡:进页拉一次投影,首入本场弹一次「今晚的身份」。
    expect(find.text('今晚的身份'), findsOneWidget);
    expect(find.text('观察者'), findsWidgets);
    expect(find.byKey(const Key('play-role-card-cta')), findsOneWidget);
    // 卡片本体压在 scrim 正中,点 scrim 得点在卡片之外。
    final Rect scrim = tester.getRect(
      find.byKey(const Key('play-role-card-scrim')),
    );
    await tester.tapAt(scrim.topLeft + const Offset(6, 6));
    await tester.pumpAndSettle();
    expect(find.text('今晚的身份'), findsNothing);

    // ② 面板:章节卡上的身份胶囊,点开「本局线索」。
    expect(find.byKey(const Key('play-role-chip')), findsOneWidget);
    await tester.tap(find.byKey(const Key('play-role-chip')));
    await tester.pumpAndSettle();
    expect(find.text('本局线索'), findsOneWidget);
    expect(find.text('我的身份'), findsOneWidget);

    // ③ 任务凭证:节点上的本站任务 + 三种输入类型里的 TEXT 采集区。
    expect(find.text('本站任务'), findsOneWidget);
    expect(find.text('填写文字凭证'), findsOneWidget);
  });
}

class _StubPlayApi implements PlayApi {
  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async => PlayNodesResult(
    topicId: 71,
    mode: 1,
    playable: true,
    total: 1,
    doneCount: 0,
    chapters: const <PlayChapter>[PlayChapter(chapterId: 1, meta: '第一章')],
    nodes: const <PlayNode>[
      PlayNode(
        nodeId: 31,
        name: '第一站',
        address: '测试地点',
        sortId: 1,
        done: false,
      ),
    ],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubPlayerGateway implements PlayerGameSessionGateway {
  @override
  Future<PlayerGameProjection> loadPlayerView({
    required int activityId,
  }) async => const PlayerGameProjection(
    snapshotAt: '2026-09-17 21:30:00',
    sessionId: 88,
    activityId: 41,
    status: 'RUNNING',
    revision: 12,
    teamId: 3,
    role: PlayerGameRole(
      code: 'OBSERVER',
      name: '观察者',
      confirmed: false,
      publicBrief: '你负责看清现场。',
    ),
    availableActions: <String>{'CONFIRM_ROLE', 'PLAYER_SUBMIT'},
    nodes: <PlayerGameNode>[
      PlayerGameNode(
        nodeId: 31,
        nodeName: '第一站',
        status: 'AVAILABLE',
        stationStatus: 'READY',
        clue: '门口有一盏青色的灯。',
        task: PlayerGameTask(
          taskCode: 'TASK_A',
          prompt: '写下门牌颜色',
          inputType: 'TEXT',
          verificationRequired: true,
        ),
        choices: <PlayerGameChoice>[],
      ),
    ],
    visibleVariables: <String, Object?>{},
    teamActions: <PlayerGameTeamAction>[],
  );

  @override
  Future<GameSessionReceipt> submitPlayerCommand(
    GameSessionCommand command,
  ) async => throw UnimplementedError();

  @override
  Future<GameSessionReceipt> readPlayerReceipt({
    required int activityId,
    required String requestId,
    required String expectedAction,
  }) async => throw UnimplementedError();
}

class _EmptyAiNpcApi implements AiNpcApi {
  @override
  Future<List<NpcProfile>> fetchProfiles({
    String scope = 'global',
    int? activityId,
  }) async => const <NpcProfile>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
