// 工作台项目区断线(缺口盘点 2592/2594 · Top1)。
//
// ★ 这一块的三样东西此前全是**空的**:`todo`/`events` 两个参数根本没传,
//   于是卡上永远没有待办签、铃铛永远是 0、卡底那颗动作整行不存在
//   (真源 utils/merchant-workbench.js 的 `cardAction`)。
//   商家在项目卡上看不到「这一单有几张券没核」,也点不进扫码。
//
// 三态必须分清(真源 makeProjectCard 的注释原话:猜错的代价不对称):
//   · 有待核销 → 「去核销」,而且必须真的进扫码(#814 删过一个说核销、
//     实际跳台账的假入口);
//   · 没待核销 → 「承接进度」,落点与整卡一致;
//   · 待办**没读到** → 卡上那一格留空(既不谎报「今日无待办」,
//     也不在每张卡上刷一句报错),动作给「承接进度」。

import 'package:chengyin_app/data/api/game_session_api.dart';
import 'package:chengyin_app/data/models/merchant_apply.dart';
import 'package:chengyin_app/data/models/merchant_dashboard.dart';
import 'package:chengyin_app/data/models/my_project.dart';
import 'package:chengyin_app/feature/merchant/merchant_game_node_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _OfflineGateway implements GameSessionGateway {
  @override
  Future<List<MerchantGameEntry>> loadMerchantEntries() async =>
      const <MerchantGameEntry>[];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('这一区不碰对局接口');
}

const TopicRegistration _joined = TopicRegistration(
  id: 410,
  topicId: 91,
  topicName: '我承接的夜游',
  status: 1,
);

/// 档期已过的承接行 —— 真源 index.js:305-314/806:先滤掉已结束再切片计数。
const TopicRegistration _over = TopicRegistration(
  id: 411,
  topicId: 92,
  topicName: '去年那场夜游',
  status: 1,
  startDate: '2025-01-01 00:00:00',
  endDate: '2025-01-02 00:00:00',
);

/// 只登记这一区会跳的两条落点 —— 跳错路由当场就能看出来。
GoRouter _router(Widget section) => GoRouter(
  initialLocation: '/merchant',
  routes: <RouteBase>[
    GoRoute(path: '/merchant', builder: (_, _) => section),
    GoRoute(
      path: '/merchant/scan',
      builder: (_, _) => const Text('扫码核销页'),
    ),
    GoRoute(
      path: '/merchant/registration/410/edit',
      builder: (_, _) => const Text('承接进度页'),
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  GoRouter router, {
  List<TopicRegistration> joined = const <TopicRegistration>[_joined],
  List<MyProject> hosted = const <MyProject>[],
}) async {
  addTearDown(router.dispose);
  await tester.binding.setSurfaceSize(const Size(390, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        merchantJoinedProjectsProvider.overrideWith((_) async => joined),
        merchantHostedProjectsProvider.overrideWith((_) async => hosted),
      ].cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

MerchantGameEntriesSection _section({
  required MerchantTodo? todo,
  List<Map<String, dynamic>>? events,
}) => MerchantGameEntriesSection(
  gateway: _OfflineGateway(),
  todo: todo,
  events: events,
);

MerchantTodo _todo({int pendingVerify = 0, bool available = true}) =>
    MerchantTodo.fromJson(<String, dynamic>{
      if (available)
        'byProject': <dynamic>[
          <String, dynamic>{
            'ownerType': 1,
            'ownerId': 91,
            'pendingVerify': pendingVerify,
          },
        ],
    });

void main() {
  testWidgets('★ 有值:待办签上卡 + 卡底「去核销」,点了真的进扫码', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      _router(
        _section(
          todo: _todo(pendingVerify: 2),
          events: <Map<String, dynamic>>[
            <String, dynamic>{
              'ownerType': 1,
              'ownerId': 91,
              'content': '核销 1 张',
            },
          ],
        ),
      ),
    );

    expect(find.text('待核销 2'), findsOneWidget);
    // 铃铛按项目计数:events 的 ownerType/ownerId 对上这一张卡才算它的一条。
    expect(find.text('1'), findsOneWidget);

    final Finder action = find.byKey(
      const Key('merchant-project-action-verify-join-410'),
    );
    expect(action, findsOneWidget);
    expect(find.text('去核销'), findsOneWidget);
    expect(tester.getSize(action).height, greaterThanOrEqualTo(44));

    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('扫码核销页'), findsOneWidget);
    expect(find.text('承接进度页'), findsNothing);
  });

  testWidgets('★ 皆空:没有待核销 → 「今日无待办」+「承接进度」,落点与整卡一致', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      _router(_section(todo: _todo(), events: const <Map<String, dynamic>>[])),
    );

    expect(find.text('今日无待办'), findsOneWidget);
    expect(find.text('去核销'), findsNothing);
    expect(find.text('待核销 0'), findsNothing);

    await tester.tap(
      find.byKey(const Key('merchant-project-action-progress-join-410')),
    );
    await tester.pumpAndSettle();
    expect(find.text('承接进度页'), findsOneWidget);
  });

  testWidgets('★ 待办没读到:那一格留空(不谎报「今日无待办」),动作退回「承接进度」', (
    WidgetTester tester,
  ) async {
    // 后端是旧版:整个 byProject 字段缺席,只有全局 pendingVerify=9。
    await _pump(
      tester,
      _router(
        _section(
          todo: MerchantTodo.fromJson(<String, dynamic>{'pendingVerify': 9}),
          events: const <Map<String, dynamic>>[],
        ),
      ),
    );

    expect(find.text('今日无待办'), findsNothing);
    expect(find.text('待核销 9'), findsNothing);
    expect(
      find.byKey(const Key('merchant-project-action-progress-join-410')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('merchant-project-action-verify-join-410')),
      findsNothing,
    );
  });

  testWidgets('主办卡没有卡底动作;已结束的项目不进这一区', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      _router(
        _section(
          todo: _todo(pendingVerify: 3),
          events: const <Map<String, dynamic>>[],
        ),
      ),
      joined: const <TopicRegistration>[_over],
      hosted: const <MyProject>[
        MyProject(id: 52, bizType: 'topic', title: '我主办的主题'),
      ],
    );

    expect(find.text('我主办的主题'), findsOneWidget);
    // 真源:主办卡底行只有「N 报名 · N 浏览」,没有动作(稿 260:277)。
    expect(find.text('去核销'), findsNothing);
    expect(find.text('承接进度'), findsNothing);
    // 已结束那张根本不进这一区(先滤再切片,「全部 N」也不该数它)。
    expect(find.text('去年那场夜游'), findsNothing);
  });
}
