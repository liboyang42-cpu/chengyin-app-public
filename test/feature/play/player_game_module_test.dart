import 'package:chengyin_app/data/api/game_session_api.dart';
import 'package:chengyin_app/data/models/game_session.dart';
import 'package:chengyin_app/feature/play/player_game_module_controller.dart';
import 'package:chengyin_app/feature/play/player_game_module_views.dart';
import 'package:chengyin_app/feature/play/player_game_pending_store.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 玩家视角对局会话:进页拉一次投影;写先落存根、以回执为准;
/// 结果未知只收敛、不猜(对齐小程序 gameModule 的同一套状态机)。
void main() {
  test('进页拉一次玩家投影,身份胶囊显示服务端身份', () async {
    final _FakePlayerGateway gateway = _FakePlayerGateway();
    final ProviderContainer container = _container(gateway);
    addTearDown(container.dispose);

    final PlayerGameModuleController controller = container.read(
      playerGameModuleProvider(7).notifier,
    );
    await controller.load();

    expect(gateway.loadCount, 1);
    expect(controller.state.enabled, isTrue);
    expect(controller.state.projection?.role.name, '观察者');
    expect(controller.state.chipLabel, '观察者');
  });

  test('服务端说这一局没准备好:不显示也不是报错', () async {
    final _FakePlayerGateway gateway = _FakePlayerGateway(
      loadError: const GameSessionContractException(
        '本局玩家状态不可用',
        reasonCode: 'GAME_SESSION_NOT_PREPARED',
      ),
    );
    final ProviderContainer container = _container(gateway);
    addTearDown(container.dispose);

    final PlayerGameModuleController controller = container.read(
      playerGameModuleProvider(7).notifier,
    );
    await controller.load();

    expect(controller.state.enabled, isFalse);
    expect(controller.state.error, isEmpty);
    expect(controller.state.chipVisible, isFalse);
  });

  test('确认身份:命令带头(activityId/revision/requestId),APPLIED 后清存根并回读', () async {
    final _FakePlayerGateway gateway = _FakePlayerGateway();
    final PlayerGamePendingStore store = PlayerGamePendingStore.memory();
    final ProviderContainer container = _container(gateway, store: store);
    addTearDown(container.dispose);

    final PlayerGameModuleController controller = container.read(
      playerGameModuleProvider(7).notifier,
    );
    await controller.load();
    await controller.confirmRole();

    expect(gateway.commands, hasLength(1));
    final GameSessionCommand command = gateway.commands.single;
    expect(command.action, 'CONFIRM_ROLE');
    expect(command.activityId, 7);
    expect(command.nodeId, isNull);
    expect(command.expectedRevision, 12);
    expect(
      RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(command.requestId),
      isTrue,
    );
    expect(controller.state.writeStatus, PlayerGameWriteStatus.confirmed);
    expect(await store.read(7), isNull);
    expect(gateway.loadCount, 2);
  });

  test('网络断在中间:存根留着 + 未知态;核对结果用原 requestId 收敛', () async {
    final _FakePlayerGateway gateway = _FakePlayerGateway(submitThrows: true);
    final PlayerGamePendingStore store = PlayerGamePendingStore.memory();
    final ProviderContainer container = _container(gateway, store: store);
    addTearDown(container.dispose);

    final PlayerGameModuleController controller = container.read(
      playerGameModuleProvider(7).notifier,
    );
    await controller.load();
    await controller.confirmRole();

    expect(controller.state.writeStatus, PlayerGameWriteStatus.unknown);
    final PlayerGamePendingWrite? pending = await store.read(7);
    expect(pending, isNotNull);
    expect(pending!.action, 'CONFIRM_ROLE');

    gateway.receiptOutcome = GameReceiptOutcome.applied;
    await controller.reconcile();

    expect(gateway.readRequests.single.requestId, pending.requestId);
    expect(gateway.readRequests.single.expectedAction, 'CONFIRM_ROLE');
    expect(controller.state.writeStatus, PlayerGameWriteStatus.confirmed);
    expect(await store.read(7), isNull);
  });

  test('回执说 FAILED:清存根 + 原文进 error 态,不留在未知态', () async {
    final _FakePlayerGateway gateway = _FakePlayerGateway(
      rejectMessage: '身份确认未被接受',
    );
    final PlayerGamePendingStore store = PlayerGamePendingStore.memory();
    final ProviderContainer container = _container(gateway, store: store);
    addTearDown(container.dispose);

    final PlayerGameModuleController controller = container.read(
      playerGameModuleProvider(7).notifier,
    );
    await controller.load();
    await controller.confirmRole();

    expect(controller.state.writeStatus, PlayerGameWriteStatus.error);
    expect(controller.state.writeMessage, '身份确认未被接受');
    expect(await store.read(7), isNull);
  });

  test('任务凭证:三种采集都落成 evidenceUrls,提交带 taskCode + 原文 URL', () async {
    final _FakePlayerGateway gateway = _FakePlayerGateway();
    final ProviderContainer container = _container(gateway);
    addTearDown(container.dispose);

    final PlayerGameModuleController controller = container.read(
      playerGameModuleProvider(7).notifier,
    );
    await controller.load();
    controller.setEvidence(
      31,
      const PlayerTaskEvidence(
        type: 'TEXT',
        text: '看到青色门牌',
        evidenceUrls: <String>['text:%E9%9D%92%E8%89%B2'],
        statusText: '文字凭证已填写',
      ),
    );
    await controller.submitTask(31, 'TASK_A', <String>[
      'text:%E9%9D%92%E8%89%B2',
    ]);

    expect(gateway.commands, hasLength(1));
    final GameSessionCommand command = gateway.commands.single;
    expect(command.action, 'PLAYER_SUBMIT');
    expect(command.nodeId, 31);
    expect(command.payload['taskCode'], 'TASK_A');
    expect(command.payload['evidenceUrls'], <String>[
      'text:%E9%9D%92%E8%89%B2',
    ]);
    expect(controller.state.evidence[31]?.ready, isFalse);
  });

  testWidgets('章节卡身份胶囊点开「本局线索」半屏,并渲染本局节点', (tester) async {
    final _FakePlayerGateway gateway = _FakePlayerGateway();
    final ProviderContainer container = _container(gateway);
    addTearDown(container.dispose);
    await container.read(playerGameModuleProvider(7).notifier).load();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CupertinoApp(
          home: CupertinoPageScaffold(
            child: Center(child: PlayerGameRoleChip(activityId: 7)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('观察者'), findsOneWidget);
    await tester.tap(find.byKey(const Key('play-role-chip')));
    await tester.pumpAndSettle();

    expect(find.text('本局线索'), findsOneWidget);
    expect(find.text('我的身份'), findsOneWidget);
    expect(find.textContaining('节点 1'), findsOneWidget);
    expect(find.text('查看第 1 级提示'), findsOneWidget);
  });

  // 真源 index.wxml:1741-1762 vs :1771 —— 三种输入块不按 submission 收口,
  // 只有提交键要求「无提交或已被驳回」。核验期间仍看得见现场内容。
  testWidgets('已有待核验提交:凭证采集区与提交状态并存,提交键收起', (tester) async {
    final _FakePlayerGateway gateway = _FakePlayerGateway(
      projection: _projectionWithNode(
        const PlayerGameNode(
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
          submission: PlayerGameSubmission(
            submissionId: 41,
            nodeId: 31,
            taskCode: 'TASK_A',
            status: 'PENDING',
          ),
        ),
      ),
    );
    final ProviderContainer container = _container(gateway);
    addTearDown(container.dispose);
    await container.read(playerGameModuleProvider(7).notifier).load();

    await tester.pumpWidget(_pumpChip(container));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('play-role-chip')));
    await tester.pumpAndSettle();

    expect(find.text('填写文字凭证'), findsOneWidget, reason: '核验期间采集区不能消失');
    expect(find.text('待商家核验'), findsOneWidget);
    expect(find.text('核验编号 41'), findsOneWidget);
    expect(find.byKey(const Key('play-node-submit-31')), findsNothing);
  });

  // 真源 index.js:2257-2263 —— evidenceOnly 分支的写条文案。
  test('任务提交成功:写条文案与真源一致(普通 / 只收证据)', () async {
    final _FakePlayerGateway withTask = _FakePlayerGateway(
      projection: _projectionWithNode(_textTaskNode()),
    );
    final ProviderContainer first = _container(withTask);
    addTearDown(first.dispose);
    final PlayerGameModuleController plain = first.read(
      playerGameModuleProvider(7).notifier,
    );
    await plain.load();
    plain.setEvidence(
      31,
      const PlayerTaskEvidence(
        type: 'TEXT',
        text: '青色',
        evidenceUrls: <String>['text:%E9%9D%92%E8%89%B2'],
        statusText: '文字凭证已填写',
      ),
    );
    await plain.submitTask(31, 'TASK_A', <String>['text:%E9%9D%92%E8%89%B2']);
    expect(plain.state.writeMessage, '任务已由服务端记录');

    final _FakePlayerGateway evidenceOnly = _FakePlayerGateway(
      projection: _projectionWithNode(
        const PlayerGameNode(
          nodeId: 31,
          nodeName: '第一站',
          status: 'AVAILABLE',
          stationStatus: 'READY',
          clue: '',
          task: PlayerGameTask(
            taskCode: 'TASK_PHOTO',
            prompt: '拍下现场',
            inputType: 'PHOTO',
            verificationRequired: false,
            completionPolicy: 'EVIDENCE_ONLY',
          ),
          choices: <PlayerGameChoice>[],
        ),
      ),
    );
    final ProviderContainer second = _container(evidenceOnly);
    addTearDown(second.dispose);
    final PlayerGameModuleController photo = second.read(
      playerGameModuleProvider(7).notifier,
    );
    await photo.load();
    photo.setEvidence(
      31,
      const PlayerTaskEvidence(
        type: 'PHOTO',
        evidenceUrls: <String>['https://cdn.example.com/a.jpg'],
        statusText: '已上传 1 张现场照片',
      ),
    );
    await photo.submitTask(31, 'TASK_PHOTO', <String>[
      'https://cdn.example.com/a.jpg',
    ]);
    expect(photo.state.writeMessage, '证据已记录');
  });

  // 「命令提交后回执更新」:断在中间不猜,点「核对结果」用原 requestId 回读。
  testWidgets('提交断在中间:写条待核对,「核对结果」按原 requestId 收敛', (tester) async {
    final _FakePlayerGateway gateway = _FakePlayerGateway(
      submitThrows: true,
      projection: _projectionWithNode(_textTaskNode()),
    );
    final ProviderContainer container = _container(gateway);
    addTearDown(container.dispose);
    final PlayerGameModuleController controller = container.read(
      playerGameModuleProvider(7).notifier,
    );
    await controller.load();
    controller.setEvidence(
      31,
      const PlayerTaskEvidence(
        type: 'TEXT',
        text: '青色',
        evidenceUrls: <String>['text:%E9%9D%92%E8%89%B2'],
        statusText: '文字凭证已填写',
      ),
    );

    await tester.pumpWidget(_pumpChip(container));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('play-role-chip')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('play-node-submit-31')));
    await tester.pumpAndSettle();
    expect(find.text('提交结果待核对，请勿重复提交'), findsOneWidget);

    await tester.tap(find.byKey(const Key('play-game-module-reconcile')));
    await tester.pumpAndSettle();

    expect(find.text('操作已由服务端确认'), findsOneWidget);
    expect(gateway.readRequests, hasLength(1));
    expect(
      gateway.readRequests.single.requestId,
      gateway.commands.single.requestId,
      reason: '核对必须用原 requestId,不能新发一条命令',
    );
    expect(gateway.readRequests.single.expectedAction, 'PLAYER_SUBMIT');
  });
}

ProviderContainer _container(
  _FakePlayerGateway gateway, {
  PlayerGamePendingStore? store,
}) => ProviderContainer(
  overrides: [
    playerGameSessionApiProvider.overrideWithValue(gateway),
    playerGamePendingStoreProvider.overrideWithValue(
      store ?? PlayerGamePendingStore.memory(),
    ),
  ],
);

class _FakePlayerGateway implements PlayerGameSessionGateway {
  _FakePlayerGateway({
    this.loadError,
    this.submitThrows = false,
    this.rejectMessage,
    this.projection,
  });

  final GameSessionContractException? loadError;
  final PlayerGameProjection? projection;
  final bool submitThrows;
  final String? rejectMessage;
  int loadCount = 0;
  GameReceiptOutcome receiptOutcome = GameReceiptOutcome.applied;
  final List<GameSessionCommand> commands = <GameSessionCommand>[];
  final List<({int activityId, String requestId, String expectedAction})>
  readRequests =
      <({int activityId, String requestId, String expectedAction})>[];

  @override
  Future<PlayerGameProjection> loadPlayerView({required int activityId}) async {
    loadCount++;
    final GameSessionContractException? error = loadError;
    if (error != null) throw error;
    return projection ?? _projection();
  }

  @override
  Future<GameSessionReceipt> submitPlayerCommand(
    GameSessionCommand command,
  ) async {
    commands.add(command);
    if (submitThrows) throw Exception('network down');
    final String? rejected = rejectMessage;
    if (rejected != null) throw GameSessionRejectedException(rejected);
    return GameSessionReceipt(
      activityId: command.activityId,
      requestId: command.requestId,
      action: command.action,
      outcome: receiptOutcome,
      receiptId: 'receipt-1',
      revision: command.expectedRevision + 1,
    );
  }

  @override
  Future<GameSessionReceipt> readPlayerReceipt({
    required int activityId,
    required String requestId,
    required String expectedAction,
  }) async {
    readRequests.add((
      activityId: activityId,
      requestId: requestId,
      expectedAction: expectedAction,
    ));
    return GameSessionReceipt(
      activityId: activityId,
      requestId: requestId,
      action: expectedAction,
      outcome: receiptOutcome,
      receiptId: 'receipt-1',
      revision: 13,
    );
  }
}

Widget _pumpChip(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: const CupertinoApp(
    home: CupertinoPageScaffold(
      child: Center(child: PlayerGameRoleChip(activityId: 7)),
    ),
  ),
);

PlayerGameNode _textTaskNode() => const PlayerGameNode(
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
);

PlayerGameProjection _projectionWithNode(PlayerGameNode node) =>
    PlayerGameProjection(
      snapshotAt: '2026-09-17 21:30:00',
      sessionId: 88,
      activityId: 7,
      status: 'RUNNING',
      revision: 12,
      teamId: 3,
      role: const PlayerGameRole(
        code: 'OBSERVER',
        name: '观察者',
        confirmed: false,
        publicBrief: '你负责看清现场。',
      ),
      availableActions: const <String>{'CONFIRM_ROLE', 'PLAYER_SUBMIT'},
      nodes: <PlayerGameNode>[node],
      visibleVariables: const <String, Object?>{},
      teamActions: const <PlayerGameTeamAction>[],
    );

PlayerGameProjection _projection() => const PlayerGameProjection(
  snapshotAt: '2026-09-17 21:30:00',
  sessionId: 88,
  activityId: 7,
  status: 'RUNNING',
  revision: 12,
  teamId: 3,
  role: PlayerGameRole(
    code: 'OBSERVER',
    name: '观察者',
    confirmed: false,
    publicBrief: '你负责看清现场。',
  ),
  availableActions: <String>{
    'CONFIRM_ROLE',
    'PLAYER_CHOICE',
    'PLAYER_SUBMIT',
    'PLAYER_HINT',
    'PLAYER_REVEAL',
  },
  nodes: <PlayerGameNode>[
    PlayerGameNode(
      nodeId: 31,
      nodeName: '第一站',
      status: 'AVAILABLE',
      stationStatus: 'READY',
      clue: '门口有一盏青色的灯。',
      task: PlayerGameTask(
        taskCode: 'TASK_A',
        prompt: '拍下青色门牌',
        inputType: 'TEXT',
        verificationRequired: true,
      ),
      hint: PlayerGameHint(
        currentLevel: 0,
        revealedTexts: <PlayerGameHintText>[],
        nextLevel: 1,
        nextImpactLabel: '扣 5 分',
        revealAvailable: false,
        revealImpactLabel: '',
      ),
      choices: <PlayerGameChoice>[],
    ),
  ],
  visibleVariables: <String, Object?>{},
  teamActions: <PlayerGameTeamAction>[],
);
