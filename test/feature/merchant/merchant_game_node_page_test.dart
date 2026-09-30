import 'dart:async';

import 'package:chengyin_app/data/api/game_session_api.dart';
import 'package:chengyin_app/data/models/merchant_apply.dart';
import 'package:chengyin_app/data/models/my_project.dart';
import 'package:chengyin_app/feature/merchant/merchant_game_node_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_game_pending_store.dart';
import 'package:chengyin_app/core/widgets/status_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('工作台分开展示承接与主办项目，并用真实 ID 进正确详情', (tester) async {
    final router = GoRouter(
      initialLocation: '/merchant',
      routes: <RouteBase>[
        GoRoute(
          path: '/merchant',
          builder: (_, _) => const CupertinoPageScaffold(
            child: SingleChildScrollView(child: MerchantGameEntriesSection()),
          ),
        ),
        GoRoute(
          path: '/merchant/registration/:id/edit',
          builder: (_, state) => CupertinoPageScaffold(
            child: Text(
              'registration-${state.pathParameters['id']}-'
              '${state.uri.queryParameters['topicId']}-'
              '${state.uri.queryParameters['scope']}',
            ),
          ),
        ),
        GoRoute(
          path: '/project/home/:topicId',
          builder: (_, state) => CupertinoPageScaffold(
            child: Text('project-${state.pathParameters['topicId']}'),
          ),
        ),
        GoRoute(
          path: '/activity/:id',
          builder: (_, state) => CupertinoPageScaffold(
            child: Text('activity-${state.pathParameters['id']}'),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantJoinedProjectsProvider.overrideWith(
            (ref) async => const <TopicRegistration>[
              TopicRegistration(
                id: 410,
                topicId: 91,
                topicName: '我承接的夜游',
                status: 1,
              ),
            ],
          ),
          merchantHostedProjectsProvider.overrideWith(
            (ref) async => const <MyProject>[
              MyProject(id: 52, bizType: 'topic', title: '我主办的主题'),
              MyProject(id: 37, bizType: 'activity', title: '我主办的活动'),
            ],
          ),
          gameSessionApiProvider.overrideWithValue(
            _Gateway(<MerchantGameProjection>[]),
          ),
        ],
        child: CupertinoApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('我承接的'), findsNothing, reason: '小程序已从卡面移除角色 pill');
    expect(find.text('我主办的'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Semantics && widget.properties.label == '打开我承接的项目我承接的夜游',
      ),
      findsOneWidget,
      reason: '角色语义保留在辅助功能中',
    );
    expect(find.byKey(const Key('merchant-project-join-410')), findsOneWidget);
    expect(find.byKey(const Key('merchant-project-topic-52')), findsOneWidget);
    expect(
      find.byKey(const Key('merchant-project-activity-37')),
      findsOneWidget,
    );

    await tester.tap(find.text('我承接的夜游'));
    await tester.pumpAndSettle();
    expect(
      find.text('registration-410-91-MERCHANT'),
      findsOneWidget,
      reason: '承接项目用真实报名 id 进既有报名详情链路',
    );

    router.go('/merchant');
    await tester.pumpAndSettle();
    await tester.tap(find.text('我主办的主题'));
    await tester.pumpAndSettle();
    expect(find.text('project-52'), findsOneWidget, reason: '主办主题进主办方项目主页');

    router.go('/merchant');
    await tester.pumpAndSettle();
    await tester.tap(find.text('我主办的活动'));
    await tester.pumpAndSettle();
    expect(find.text('activity-37'), findsOneWidget, reason: '主办活动仍进活动详情');
  });

  testWidgets('本站深层页复用统一加载与错误状态', (tester) async {
    final pending = Completer<MerchantGameProjection>();
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: MerchantGameNodePage(
            ownerMemberId: 41,
            activityId: 7,
            gateway: _NodeGateway(() => pending.future),
            pendingStore: MerchantGamePendingStore.memory(),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(LoadingView), findsOneWidget);

    pending.completeError(Exception('本站状态失败'));
    await tester.pumpAndSettle();
    expect(find.byType(StatusView), findsOneWidget);
    expect(find.text('本站状态失败'), findsOneWidget);
  });

  testWidgets('没有站点邀请时显示与小程序一致的邀请空态', (tester) async {
    final gateway = _Gateway(<MerchantGameProjection>[
      const MerchantGameProjection(
        sessionId: 2,
        activityId: 7,
        status: 'PREPARING',
        revision: 3,
        availableActions: <String>{},
        stations: <MerchantGameStation>[],
      ),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: MerchantGameNodePage(
            ownerMemberId: 41,
            activityId: 7,
            gateway: gateway,
            pendingStore: MerchantGamePendingStore.memory(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无本站任务'), findsOneWidget);
    expect(find.text('俱乐部或主办方发出站点邀请后，会显示在这里'), findsOneWidget);
  });

  testWidgets('本站执行卡始终存在，主办方未配置任务时明确禁止引导玩家', (tester) async {
    final gateway = _Gateway(<MerchantGameProjection>[
      _projection(
        'INVITED',
        playerTaskPrompt: '',
        merchantInstruction: '',
        hiddenInfoReminder: '',
      ),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: MerchantGameNodePage(
            ownerMemberId: 41,
            activityId: 7,
            gateway: gateway,
            pendingStore: MerchantGamePendingStore.memory(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('本站执行卡'), findsOneWidget);
    expect(find.text('无需猜剧情，只按公开步骤接待玩家'), findsOneWidget);
    expect(find.text('主办方尚未配置本站任务，当前不要引导玩家开始。'), findsOneWidget);
  });

  testWidgets('已配置任务只展示公开执行信息，缺省说明使用小程序安全文案', (tester) async {
    final gateway = _Gateway(<MerchantGameProjection>[
      _projection(
        'INVITED',
        playerTaskPrompt: '向店员展示玩家页的公开核验编号',
        merchantInstruction: '',
        hiddenInfoReminder: '',
      ),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: MerchantGameNodePage(
            ownerMemberId: 41,
            activityId: 7,
            gateway: gateway,
            pendingStore: MerchantGamePendingStore.memory(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('玩家会做什么'), findsOneWidget);
    expect(find.text('向店员展示玩家页的公开核验编号'), findsOneWidget);
    expect(find.text('商家只需做什么'), findsOneWidget);
    expect(find.text('按核验编号确认玩家已完成公开任务；不代替玩家解题。'), findsOneWidget);
    expect(find.text('不能透露什么'), findsOneWidget);
    expect(find.text('不要透露答案、其他角色线索或后台剧情条件。'), findsOneWidget);
  });

  testWidgets('站点邀请与准备条件按小程序卡片顺序呈现', (tester) async {
    final gateway = _Gateway(<MerchantGameProjection>[_projection('INVITED')]);
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: MerchantGameNodePage(
            ownerMemberId: 41,
            activityId: 7,
            gateway: gateway,
            pendingStore: MerchantGamePendingStore.memory(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('站点邀请'), findsOneWidget);
    expect(find.text('接受后才能填写准备清单并开放本站'), findsOneWidget);
    expect(find.text('拒绝邀请'), findsOneWidget);
    expect(find.text('接受邀请'), findsOneWidget);
  });

  testWidgets('准备入口说明全部条件，Sheet 保留准备备注的原文案', (tester) async {
    final gateway = _Gateway(<MerchantGameProjection>[
      _projection(
        'ACCEPTED',
        actions: const <String>{'STATION_READY'},
        checklist: const <GameChecklistItem>[
          GameChecklistItem(code: 'power', label: '确认现场电源', checked: false),
        ],
      ),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: MerchantGameNodePage(
            ownerMemberId: 41,
            activityId: 7,
            gateway: gateway,
            pendingStore: MerchantGamePendingStore.memory(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('准备清单'), findsOneWidget);
    expect(find.text('全部完成后，本站才可进入准备完成状态'), findsOneWidget);
    expect(find.text('确认准备完成'), findsOneWidget);

    await tester.tap(find.text('确认准备完成'));
    await tester.pumpAndSettle();
    expect(find.text('准备备注（选填）'), findsOneWidget);
    expect(
      find.widgetWithText(CupertinoTextField, '给主办方留一句现场说明'),
      findsOneWidget,
    );
  });

  testWidgets('复盘完整显示服务端下发的公开授权内容计数', (tester) async {
    final gateway = _Gateway(<MerchantGameProjection>[
      _projection(
        'CLOSED',
        actions: const <String>{},
        recap: const MerchantStationRecap(
          arrivedPlayers: 8,
          submissionCount: 6,
          approvedCount: 5,
          rejectedCount: 1,
          recordedCount: 6,
          normalCompletedCount: 4,
          fallbackCompletedCount: 1,
          pauseEventCount: 2,
          authorizedContentCount: 0,
        ),
      ),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: MerchantGameNodePage(
            ownerMemberId: 41,
            activityId: 7,
            gateway: gateway,
            pendingStore: MerchantGamePendingStore.memory(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('公开授权内容'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('仅显示本站安全聚合，不公开玩家内容。'), findsOneWidget);
  });

  testWidgets('多个站点用 Apple Action Sheet 切换，不使用页面 segmented', (tester) async {
    final first = _projection('INVITED');
    final gateway = _Gateway(<MerchantGameProjection>[
      MerchantGameProjection(
        sessionId: first.sessionId,
        activityId: first.activityId,
        status: first.status,
        revision: first.revision,
        availableActions: first.availableActions,
        stations: <MerchantGameStation>[
          first.stations.single,
          const MerchantGameStation(
            stationId: 10,
            nodeId: 11,
            nodeName: '终点站',
            stationCode: 'B2',
            status: 'INVITED',
            revision: 3,
            checklist: <GameChecklistItem>[],
            pendingVerificationCount: 0,
          ),
        ],
      ),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: MerchantGameNodePage(
            ownerMemberId: 41,
            activityId: 7,
            gateway: gateway,
            pendingStore: MerchantGamePendingStore.memory(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsNothing);
    await tester.tap(find.byKey(const Key('merchant-game-station-picker')));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    await tester.tap(find.text('终点站'));
    await tester.pumpAndSettle();
    expect(find.text('B2'), findsOneWidget, reason: '英雄区已切换到第二个站点');
  });

  testWidgets('接受邀请只在 APPLIED 回执后回读最新投影', (tester) async {
    final gateway = _Gateway(<MerchantGameProjection>[
      _projection('INVITED'),
      _projection('ACCEPTED'),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: MerchantGameNodePage(
            ownerMemberId: 41,
            activityId: 7,
            gateway: gateway,
            pendingStore: MerchantGamePendingStore.memory(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('待接受邀请'), findsOneWidget);
    expect(find.text('接受邀请'), findsOneWidget);

    await tester.tap(find.text('接受邀请'));
    await tester.pumpAndSettle();

    expect(gateway.commands.single.action, 'STATION_ACCEPT');
    expect(gateway.loadCount, 2, reason: '写入后必须重新读服务端投影');
    expect(find.text('已接受 · 待准备'), findsOneWidget);
  });

  testWidgets('本站准备清单使用可执行的 Apple 原生开关', (tester) async {
    final gateway = _Gateway(<MerchantGameProjection>[
      _projection(
        'ACCEPTED',
        actions: const <String>{'STATION_READY'},
        checklist: const <GameChecklistItem>[
          GameChecklistItem(code: 'power', label: '确认现场电源', checked: false),
        ],
      ),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: MerchantGameNodePage(
            ownerMemberId: 41,
            activityId: 7,
            gateway: gateway,
            pendingStore: MerchantGamePendingStore.memory(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('merchant-game-ready-action')));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoSwitch), findsOneWidget);
    expect(find.bySemanticsLabel('确认现场电源'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('确认现场电源'));
    await tester.pump();
    expect(
      tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
      isTrue,
    );
  });

  testWidgets('拒绝理由用 Cupertino Action Sheet，不是自制弹窗', (tester) async {
    final gateway = _Gateway(<MerchantGameProjection>[_projection('INVITED')]);
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: MerchantGameNodePage(
            ownerMemberId: 41,
            activityId: 7,
            gateway: gateway,
            pendingStore: MerchantGamePendingStore.memory(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('拒绝邀请'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    expect(find.text('档期冲突'), findsOneWidget);
    expect(find.text('现场资源不足'), findsOneWidget);
  });

  testWidgets('工作台只展示服务端授权的本站入口', (tester) async {
    final gateway = _Gateway(<MerchantGameProjection>[_projection('INVITED')])
      ..entries = const <MerchantGameEntry>[
        MerchantGameEntry(
          activityId: 7,
          topicId: 3,
          activityName: '夜游任务',
          stationCount: 1,
        ),
      ];
    int? opened;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantJoinedProjectsProvider.overrideWith(
            (ref) async => const <TopicRegistration>[],
          ),
          merchantHostedProjectsProvider.overrideWith(
            (ref) async => const <MyProject>[
              MyProject(
                id: 7,
                bizType: 'activity',
                title: '夜游任务',
                stateText: '进行中',
              ),
            ],
          ),
        ],
        child: CupertinoApp(
          home: CupertinoPageScaffold(
            child: MerchantGameEntriesSection(
              gateway: gateway,
              onOpen: (value) => opened = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('项目'), findsOneWidget);
    expect(find.text('本站准备与运行'), findsNothing, reason: '本站入口必须归属项目卡，不能自成一级卡');
    expect(find.text('夜游任务'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('merchant-project-activity-7')),
        matching: find.byKey(const Key('merchant-game-entry-7')),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('merchant-game-entry-7')));
    expect(opened, 7);
  });

  testWidgets('两类项目都为空时显示真实空态，不冒充 0 个项目', (tester) async {
    final gateway = _Gateway(<MerchantGameProjection>[_projection('INVITED')]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantJoinedProjectsProvider.overrideWith(
            (ref) async => const <TopicRegistration>[],
          ),
          merchantHostedProjectsProvider.overrideWith(
            (ref) async => const <MyProject>[],
          ),
        ],
        child: CupertinoApp(
          home: CupertinoPageScaffold(
            child: Column(
              children: <Widget>[
                const Text('before'),
                MerchantGameEntriesSection(gateway: gateway),
                const Text('after'),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('项目'), findsOneWidget);
    expect(find.text('还没有项目'), findsOneWidget);
    expect(find.text('去发起'), findsOneWidget);
    expect(find.textContaining('0 个项目'), findsNothing);
  });

  testWidgets('项目与本站入口加载中时明确表达加载态', (tester) async {
    final pending = Completer<List<MerchantGameEntry>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantJoinedProjectsProvider.overrideWith(
            (ref) async => const <TopicRegistration>[],
          ),
          merchantHostedProjectsProvider.overrideWith(
            (ref) async => const <MyProject>[],
          ),
        ],
        child: CupertinoApp(
          home: CupertinoPageScaffold(
            child: MerchantGameEntriesSection(
              gateway: _PendingGateway(pending.future),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('项目加载中…'), findsOneWidget);
    pending.complete(const <MerchantGameEntry>[]);
    await tester.pumpAndSettle();
  });

  testWidgets('一类项目已返回、另一类仍在读取时保留真实卡并提示更新中', (tester) async {
    final hosted = Completer<List<MyProject>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantJoinedProjectsProvider.overrideWith(
            (ref) async => const <TopicRegistration>[
              TopicRegistration(id: 410, topicId: 91, topicName: '已返回的承接'),
            ],
          ),
          merchantHostedProjectsProvider.overrideWith((ref) => hosted.future),
        ],
        child: CupertinoApp(
          home: CupertinoPageScaffold(
            child: MerchantGameEntriesSection(
              gateway: _Gateway(<MerchantGameProjection>[]),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('已返回的承接'), findsOneWidget);
    expect(find.text('正在更新项目…'), findsOneWidget);

    hosted.complete(const <MyProject>[]);
    await tester.pumpAndSettle();
    expect(find.text('正在更新项目…'), findsNothing);
  });

  testWidgets('项目读取失败时显式报错并可重试', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantJoinedProjectsProvider.overrideWith(
            (ref) async => throw Exception('项目失败'),
          ),
          merchantHostedProjectsProvider.overrideWith(
            (ref) async => throw Exception('项目失败'),
          ),
        ],
        child: const CupertinoApp(
          home: CupertinoPageScaffold(
            child: MerchantGameEntriesSection(gateway: _ErrorGateway()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('项目没取到'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('点击项目卡内本站入口进入对应游戏节点页', (tester) async {
    final gateway = _Gateway(<MerchantGameProjection>[_projection('INVITED')])
      ..entries = const <MerchantGameEntry>[
        MerchantGameEntry(
          activityId: 7,
          topicId: 3,
          activityName: '夜游任务',
          stationCount: 1,
        ),
      ];
    final router = GoRouter(
      initialLocation: '/merchant',
      routes: <RouteBase>[
        GoRoute(
          path: '/merchant',
          builder: (_, _) =>
              const CupertinoPageScaffold(child: MerchantGameEntriesSection()),
        ),
        GoRoute(
          path: '/merchant/game-node/:activityId',
          builder: (_, state) => CupertinoPageScaffold(
            child: Text('game-${state.pathParameters['activityId']}'),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameSessionApiProvider.overrideWithValue(gateway),
          merchantJoinedProjectsProvider.overrideWith(
            (ref) async => const <TopicRegistration>[],
          ),
          merchantHostedProjectsProvider.overrideWith(
            (ref) async => const <MyProject>[
              MyProject(id: 7, bizType: 'activity', title: '夜游任务'),
            ],
          ),
        ],
        child: CupertinoApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('merchant-game-entry-7')));
    await tester.pumpAndSettle();
    expect(find.text('game-7'), findsOneWidget);
  });

  testWidgets('冷启动深链会先根据本地请求编号读服务端回执', (tester) async {
    final store = MerchantGamePendingStore.memory();
    await store.write(
      const MerchantGamePendingWrite(
        ownerMemberId: 41,
        activityId: 7,
        nodeId: 9,
        requestId: 'req_12345678',
        expectedRevision: 3,
        action: 'STATION_ACCEPT',
        payload: <String, dynamic>{},
      ),
    );
    final gateway = _Gateway(<MerchantGameProjection>[_projection('ACCEPTED')]);
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: MerchantGameNodePage(
            ownerMemberId: 41,
            activityId: 7,
            gateway: gateway,
            pendingStore: store,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(gateway.receiptReadCount, 1);
    expect(await store.read(7, ownerMemberId: 41), isNull);
    expect(find.text('已接受 · 待准备'), findsOneWidget);
  });

  testWidgets('回执未确认时可用完整原命令和同一幂等键重试', (tester) async {
    final store = MerchantGamePendingStore.memory();
    await store.write(
      const MerchantGamePendingWrite(
        ownerMemberId: 41,
        activityId: 7,
        nodeId: 9,
        requestId: 'req_retry_12345678',
        expectedRevision: 3,
        action: 'STATION_DECLINE',
        payload: <String, dynamic>{
          'reasonCode': 'SCHEDULE_CONFLICT',
          'reason': '档期冲突',
        },
      ),
    );
    final gateway = _RecoverablePendingGateway(<MerchantGameProjection>[
      _projection('INVITED'),
      _projection('INVITED'),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: MerchantGameNodePage(
            ownerMemberId: 41,
            activityId: 7,
            gateway: gateway,
            pendingStore: store,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('使用原请求重试'), findsOneWidget);
    await tester.tap(find.text('使用原请求重试'));
    await tester.pumpAndSettle();

    expect(gateway.commands, hasLength(1));
    expect(gateway.commands.single.requestId, 'req_retry_12345678');
    expect(gateway.commands.single.nodeId, 9);
    expect(gateway.commands.single.expectedRevision, 3);
    expect(gateway.commands.single.action, 'STATION_DECLINE');
    expect(gateway.commands.single.payload, <String, dynamic>{
      'reasonCode': 'SCHEDULE_CONFLICT',
      'reason': '档期冲突',
    });
    expect(await store.read(7, ownerMemberId: 41), isNull);
    expect(find.text('操作结果待确认'), findsNothing);
  });

  test('待确认命令按登录用户隔离', () async {
    final store = MerchantGamePendingStore.memory();
    await store.write(
      const MerchantGamePendingWrite(
        ownerMemberId: 41,
        activityId: 7,
        nodeId: 9,
        requestId: 'req_owner_12345678',
        expectedRevision: 3,
        action: 'STATION_ACCEPT',
        payload: <String, dynamic>{},
      ),
    );

    expect(await store.read(7, ownerMemberId: 42), isNull);
    expect(await store.read(7, ownerMemberId: 41), isNotNull);
    await store.clear(7, ownerMemberId: 42);
    expect(await store.read(7, ownerMemberId: 41), isNotNull);
  });

  testWidgets('旧 v1 待确认记录只对账不重放', (tester) async {
    final store = MerchantGamePendingStore.memory();
    await store.writeLegacyForTest(
      const MerchantGameLegacyPendingWrite(
        activityId: 7,
        requestId: 'req_legacy_12345678',
        action: 'STATION_ACCEPT',
      ),
    );
    final gateway = _RecoverablePendingGateway(<MerchantGameProjection>[
      _projection('INVITED'),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: MerchantGameNodePage(
            ownerMemberId: 41,
            activityId: 7,
            gateway: gateway,
            pendingStore: store,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final replayButton = tester.widget<CupertinoButton>(
      find.widgetWithText(CupertinoButton, '使用原请求重试'),
    );
    expect(replayButton.onPressed, isNull);
    expect(find.textContaining('旧版记录信息不完整'), findsOneWidget);
    expect(gateway.commands, isEmpty);
    expect(await store.readLegacy(7), isNotNull);
  });

  testWidgets('本地安全存储失败时不发送服务端命令', (tester) async {
    final gateway = _Gateway(<MerchantGameProjection>[_projection('INVITED')]);
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: MerchantGameNodePage(
            ownerMemberId: 41,
            activityId: 7,
            gateway: gateway,
            pendingStore: _FailingPendingStore(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('接受邀请'));
    await tester.pumpAndSettle();

    expect(gateway.commands, isEmpty);
    expect(find.text('无法安全保存本次操作，请重试'), findsOneWidget);
    expect(find.text('操作结果待确认'), findsNothing);
  });

  testWidgets('冷启动游戏站点深链返回商家工作台', (tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    final gateway = _Gateway(<MerchantGameProjection>[_projection('INVITED')]);
    final router = GoRouter(
      initialLocation: '/merchant/game-node/7',
      routes: <RouteBase>[
        GoRoute(
          path: '/merchant',
          builder: (_, _) =>
              const CupertinoPageScaffold(child: Text('商家工作台根页')),
        ),
        GoRoute(
          path: '/merchant/game-node/:activityId',
          builder: (_, state) => MerchantGameNodePage(
            ownerMemberId: 41,
            activityId: int.parse(state.pathParameters['activityId']!),
            gateway: gateway,
            pendingStore: MerchantGamePendingStore.memory(),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(child: CupertinoApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();
    final Finder back = find.bySemanticsLabel('返回商家中心');
    expect(back, findsOneWidget);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.text('商家工作台根页'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('准备 Sheet 系统时间选择取消不改值不关闭，确认后才提交', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const MethodChannel channel = MethodChannel(
      'com.chengyin.app/native_date_picker',
    );
    final DateTime selectedStart = DateTime.now().add(
      const Duration(days: 1, hours: 1),
    );
    final DateTime cancelledEnd = selectedStart.add(const Duration(hours: 1));
    final DateTime selectedEnd = selectedStart.add(const Duration(hours: 2));
    final List<int?> results = <int?>[
      null,
      selectedStart.millisecondsSinceEpoch,
      null,
      selectedEnd.millisecondsSinceEpoch,
    ];
    final List<MethodCall> calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall call,
    ) async {
      calls.add(call);
      return results.removeAt(0);
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _Gateway(<MerchantGameProjection>[
      _projection('ACCEPTED', actions: const <String>{'STATION_READY'}),
      _projection('READY'),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: MerchantGameNodePage(
            ownerMemberId: 41,
            activityId: 7,
            gateway: gateway,
            pendingStore: MerchantGamePendingStore.memory(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('merchant-game-ready-action')));
    await tester.pumpAndSettle();

    final Finder readySheetTitle = find.descendant(
      of: find.byType(CupertinoPopupSurface),
      matching: find.text('完成本站准备'),
    );
    await tester.tap(find.text('服务开始'));
    await tester.pumpAndSettle();
    expect(readySheetTitle, findsOneWidget);
    expect(gateway.commands, isEmpty);
    expect(find.text(_formatted(selectedStart)), findsNothing);

    await tester.tap(find.text('服务开始'));
    await tester.pumpAndSettle();
    expect(readySheetTitle, findsOneWidget);
    expect(find.text(_formatted(selectedStart)), findsOneWidget);

    await tester.tap(find.text('服务结束'));
    await tester.pumpAndSettle();
    expect(readySheetTitle, findsOneWidget);
    expect(find.text(_formatted(cancelledEnd)), findsNothing);

    await tester.tap(find.text('服务结束'));
    await tester.pumpAndSettle();
    expect(find.text(_formatted(selectedEnd)), findsOneWidget);
    await _completeSheet(tester);
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;

    expect(readySheetTitle, findsNothing);
    expect(calls, hasLength(4));
    expect(gateway.commands.single.action, 'STATION_READY');
    expect(
      gateway.commands.single.payload['serviceStartAt'],
      _formatted(selectedStart),
    );
    expect(
      gateway.commands.single.payload['serviceEndAt'],
      _formatted(selectedEnd),
    );
  });

  testWidgets('准备 Sheet 仍拒绝过去时间与结束早于开始', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const MethodChannel channel = MethodChannel(
      'com.chengyin.app/native_date_picker',
    );
    final DateTime now = DateTime.now();
    final DateTime pastStart = now.subtract(const Duration(hours: 2));
    final DateTime pastEnd = now.subtract(const Duration(hours: 1));
    final DateTime futureStart = now.add(const Duration(days: 2, hours: 2));
    final DateTime invalidEnd = now.add(const Duration(days: 2, hours: 1));
    final DateTime validEnd = futureStart.add(const Duration(hours: 1));
    final List<int> results = <int>[
      pastStart.millisecondsSinceEpoch,
      pastEnd.millisecondsSinceEpoch,
      futureStart.millisecondsSinceEpoch,
      invalidEnd.millisecondsSinceEpoch,
      validEnd.millisecondsSinceEpoch,
    ];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall call) async => results.removeAt(0),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final gateway = _Gateway(<MerchantGameProjection>[
      _projection('ACCEPTED', actions: const <String>{'STATION_READY'}),
      _projection('READY'),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: MerchantGameNodePage(
            ownerMemberId: 41,
            activityId: 7,
            gateway: gateway,
            pendingStore: MerchantGamePendingStore.memory(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('merchant-game-ready-action')));
    await tester.pumpAndSettle();
    final Finder readySheetTitle = find.descendant(
      of: find.byType(CupertinoPopupSurface),
      matching: find.text('完成本站准备'),
    );

    await tester.tap(find.text('服务开始'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('服务结束'));
    await tester.pumpAndSettle();
    await _completeSheet(tester);
    expect(readySheetTitle, findsOneWidget);
    expect(gateway.commands, isEmpty);

    await tester.tap(find.text('服务开始'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('服务结束'));
    await tester.pumpAndSettle();
    await _completeSheet(tester);
    expect(readySheetTitle, findsOneWidget);
    expect(gateway.commands, isEmpty);

    await tester.tap(find.text('服务结束'));
    await tester.pumpAndSettle();
    await _completeSheet(tester);
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;

    expect(readySheetTitle, findsNothing);
    expect(gateway.commands.single.action, 'STATION_READY');
    expect(
      gateway.commands.single.payload['serviceStartAt'],
      _formatted(futureStart),
    );
    expect(
      gateway.commands.single.payload['serviceEndAt'],
      _formatted(validEnd),
    );
  });

  testWidgets('暂停 Sheet 系统恢复时间取消不关闭，确认后才提交', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const MethodChannel channel = MethodChannel(
      'com.chengyin.app/native_date_picker',
    );
    final DateTime selectedResume = DateTime.now().add(const Duration(days: 1));
    final List<int?> results = <int?>[
      null,
      selectedResume.millisecondsSinceEpoch,
    ];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall call) async => results.removeAt(0),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final gateway = _Gateway(<MerchantGameProjection>[
      _projection(
        'ACTIVE',
        actions: const <String>{'STATION_PAUSE'},
        fallbackOptions: const <MerchantGameFallback>[
          MerchantGameFallback(
            sourceNodeId: 9,
            planCode: 'BACKUP_A',
            planVersion: 1,
            nodeId: 10,
            nodeName: '备援站',
            playerMessage: '请前往备援站继续探索',
          ),
          MerchantGameFallback(
            sourceNodeId: 9,
            planCode: 'BACKUP_B',
            planVersion: 1,
            nodeId: 11,
            nodeName: '等待区',
            playerMessage: '请在等待区留意现场通知',
          ),
        ],
      ),
      _projection('PAUSED'),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: MerchantGameNodePage(
            ownerMemberId: 41,
            activityId: 7,
            gateway: gateway,
            pendingStore: MerchantGamePendingStore.memory(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('暂停接待'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('现场满员'));
    await tester.pumpAndSettle();

    final Finder pauseSheetTitle = find.text('预计恢复与备援预案');
    expect(pauseSheetTitle, findsOneWidget);
    await tester.tap(find.text('预计恢复时间'));
    await tester.pumpAndSettle();
    expect(pauseSheetTitle, findsOneWidget);
    expect(gateway.commands, isEmpty);
    expect(find.text(_formatted(selectedResume)), findsNothing);

    await tester.tap(find.text('预计恢复时间'));
    await tester.pumpAndSettle();
    expect(pauseSheetTitle, findsOneWidget);
    expect(find.text(_formatted(selectedResume)), findsOneWidget);
    await _completeSheet(tester);
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;

    expect(pauseSheetTitle, findsNothing);
    expect(gateway.commands.single.action, 'STATION_PAUSE');
    expect(
      gateway.commands.single.payload['resumeEta'],
      _formatted(selectedResume),
    );
  });

  testWidgets('READY 站点即使收到全局 STATION_PAUSE 也不展示暂停动作', (
    WidgetTester tester,
  ) async {
    final gateway = _Gateway(<MerchantGameProjection>[
      _projection('READY', actions: const <String>{'STATION_PAUSE'}),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: MerchantGameNodePage(
            ownerMemberId: 41,
            activityId: 7,
            gateway: gateway,
            pendingStore: MerchantGamePendingStore.memory(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂停接待'), findsNothing);
    expect(gateway.commands, isEmpty);
  });

  testWidgets('核验 Sheet 无效提交 ID 不关闭不提交，合法 ID 才关闭', (tester) async {
    final gateway = _Gateway(<MerchantGameProjection>[
      _projection(
        'ACTIVE',
        actions: const <String>{'VERIFY_SUBMISSION'},
        pendingVerificationCount: 1,
      ),
      _projection('ACTIVE'),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: MerchantGameNodePage(
            ownerMemberId: 41,
            activityId: 7,
            gateway: gateway,
            pendingStore: MerchantGamePendingStore.memory(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('核验玩家提交'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(CupertinoTextField), '0');
    await _completeSheet(tester);
    await tester.pump();
    final Finder verifySheetTitle = find.descendant(
      of: find.byType(CupertinoPopupSurface),
      matching: find.text('核验玩家提交'),
    );
    expect(verifySheetTitle, findsOneWidget);
    expect(gateway.commands, isEmpty);

    await tester.enterText(find.byType(CupertinoTextField), '42');
    await _completeSheet(tester);
    await tester.pumpAndSettle();

    expect(verifySheetTitle, findsNothing);
    expect(gateway.commands.single.action, 'VERIFY_SUBMISSION');
    expect(gateway.commands.single.payload['submissionId'], '42');
  });
}

Future<void> _completeSheet(WidgetTester tester) async {
  final CupertinoButton done = tester.widget<CupertinoButton>(
    find.widgetWithText(CupertinoButton, '完成'),
  );
  done.onPressed!();
  await tester.pumpAndSettle();
}

String _formatted(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

MerchantGameProjection _projection(
  String stationStatus, {
  Set<String>? actions,
  int pendingVerificationCount = 0,
  List<MerchantGameFallback> fallbackOptions = const <MerchantGameFallback>[],
  List<GameChecklistItem> checklist = const <GameChecklistItem>[],
  String playerTaskPrompt = '',
  String merchantInstruction = '核对暗号后放行',
  String hiddenInfoReminder = '不要公开答案',
  MerchantStationRecap? recap,
}) => MerchantGameProjection(
  sessionId: 2,
  activityId: 7,
  status: switch (stationStatus) {
    'INVITED' || 'ACCEPTED' => 'PREPARING',
    'READY' => 'READY',
    _ => 'RUNNING',
  },
  revision: 3,
  availableActions:
      actions ?? const <String>{'STATION_ACCEPT', 'STATION_DECLINE'},
  fallbackOptions: fallbackOptions,
  stations: <MerchantGameStation>[
    MerchantGameStation(
      stationId: 8,
      nodeId: 9,
      nodeName: '密码站',
      stationCode: 'A1',
      status: stationStatus,
      revision: 3,
      checklist: checklist,
      pendingVerificationCount: pendingVerificationCount,
      merchantInstruction: merchantInstruction,
      hiddenInfoReminder: hiddenInfoReminder,
      playerTaskPrompt: playerTaskPrompt,
      recap: recap,
    ),
  ],
);

class _Gateway implements GameSessionGateway {
  _Gateway(this.views);
  final List<MerchantGameProjection> views;
  final List<GameSessionCommand> commands = <GameSessionCommand>[];
  int loadCount = 0;
  int receiptReadCount = 0;
  List<MerchantGameEntry> entries = const <MerchantGameEntry>[];
  @override
  Future<List<MerchantGameEntry>> loadMerchantEntries() async => entries;
  @override
  Future<MerchantGameProjection> loadMerchantView({
    required int activityId,
  }) async => views[loadCount++];
  @override
  Future<GameSessionReceipt> submitAndReadReceipt(
    GameSessionCommand command,
  ) async {
    commands.add(command);
    return GameSessionReceipt(
      activityId: command.activityId,
      requestId: command.requestId,
      action: command.action,
      outcome: GameReceiptOutcome.applied,
      receiptId: 'r1',
      revision: 4,
    );
  }

  @override
  Future<GameSessionReceipt> readReceipt({
    required int activityId,
    required String requestId,
    required String expectedAction,
  }) async {
    receiptReadCount += 1;
    return GameSessionReceipt(
      activityId: activityId,
      requestId: requestId,
      action: expectedAction,
      outcome: GameReceiptOutcome.applied,
      receiptId: 'r1',
      revision: 4,
    );
  }
}

class _RecoverablePendingGateway extends _Gateway {
  _RecoverablePendingGateway(super.views);

  @override
  Future<GameSessionReceipt> readReceipt({
    required int activityId,
    required String requestId,
    required String expectedAction,
  }) async => throw const GameSessionContractException('操作结果尚未确认');
}

class _FailingPendingStore extends MerchantGamePendingStore {
  _FailingPendingStore() : super.memory();

  @override
  Future<void> write(MerchantGamePendingWrite value) async {
    throw StateError('secure storage unavailable');
  }
}

class _PendingGateway implements GameSessionGateway {
  const _PendingGateway(this.entries);
  final Future<List<MerchantGameEntry>> entries;
  @override
  Future<List<MerchantGameEntry>> loadMerchantEntries() => entries;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NodeGateway implements GameSessionGateway {
  const _NodeGateway(this.load);
  final Future<MerchantGameProjection> Function() load;
  @override
  Future<MerchantGameProjection> loadMerchantView({required int activityId}) =>
      load();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ErrorGateway implements GameSessionGateway {
  const _ErrorGateway();
  @override
  Future<List<MerchantGameEntry>> loadMerchantEntries() async =>
      throw Exception('本站入口失败');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
