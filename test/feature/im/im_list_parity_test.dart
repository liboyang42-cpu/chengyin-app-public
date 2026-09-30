import 'dart:async';

import 'package:chengyin_app/data/models/im.dart';
import 'package:chengyin_app/feature/im/im_controller.dart';
import 'package:chengyin_app/feature/im/im_list_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  Conversation conversation() => Conversation(
    conversationId: 7,
    type: kImTypeSingle,
    counterparty: ImCounterparty(id: 8, nickname: '阿林', avatar: ''),
    lastMsgText: '周六见',
  );

  Future<void> pumpPage(
    WidgetTester tester, {
    required Future<List<Conversation>> Function() loadConversations,
    VoidCallback? onOpenCoopPool,
    VoidCallback? onOpenSquare,
  }) async {
    final GoRouter router = GoRouter(
      initialLocation: '/im',
      routes: <RouteBase>[
        GoRoute(
          path: '/im',
          builder: (_, _) => ImListPage(
            onOpenCoopPool: onOpenCoopPool,
            onOpenSquare: onOpenSquare,
          ),
        ),
        GoRoute(
          path: '/coop-pool',
          builder: (_, _) => const Scaffold(body: Text('ROUTE /coop-pool')),
        ),
        GoRoute(
          path: '/square',
          builder: (_, _) => const Scaffold(body: Text('ROUTE /square')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imConversationsProvider.overrideWith((_) => loadConversations()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
  }

  /// 分段控件内的 tab 文字。不能拿全页 `find.text` 的位置当 tab ——
  /// 「私信」同时是 tab 标签和列表分组头，谁先渲染取决于会话数据。
  Finder scopeTab(String label) {
    return find.descendant(
      of: find.byWidgetPredicate(
        (Widget w) => w.runtimeType.toString().startsWith(
          'CupertinoSlidingSegmentedControl',
        ),
      ),
      matching: find.text(label),
    );
  }

  group('合作池入口常驻', () {
    final List<({String name, Future<List<Conversation>> Function() load})>
    states = <({String name, Future<List<Conversation>> Function() load})>[
      (name: 'loading', load: () => Completer<List<Conversation>>().future),
      (
        name: 'error',
        load: () => Future<List<Conversation>>.error(Exception('网络异常')),
      ),
      (name: 'empty', load: () async => <Conversation>[]),
      (name: 'data', load: () async => <Conversation>[conversation()]),
    ];

    for (final state in states) {
      testWidgets('${state.name} 态可见且打开 /coop-pool', (tester) async {
        await pumpPage(tester, loadConversations: state.load);

        expect(find.text('合作池'), findsOneWidget);
        expect(find.text('看开放给俱乐部承接的主题'), findsOneWidget);

        await tester.tap(find.text('合作池'));
        await tester.pumpAndSettle();
        expect(find.text('ROUTE /coop-pool'), findsOneWidget);
      });
    }
  });

  testWidgets('私信空态 CTA 文案与小程序一致并打开 /square', (tester) async {
    await pumpPage(tester, loadConversations: () async => <Conversation>[]);
    await tester.pumpAndSettle();

    expect(find.text('还没有私信'), findsOneWidget);
    // 空态图标是系统符号(Cupertino),不是 Material 图形(iOS 27 原生化)。
    expect(find.byIcon(CupertinoIcons.chat_bubble), findsOneWidget);
    expect(find.text('去广场认识几个同路的人,聊起来就在这儿了'), findsOneWidget);
    expect(find.text('去广场找人'), findsOneWidget);

    await tester.tap(find.text('去广场找人'));
    await tester.pumpAndSettle();
    expect(find.text('ROUTE /square'), findsOneWidget);
  });

  testWidgets('公开导航缝可接管两个入口且不触发默认路由', (tester) async {
    var coopPoolOpened = false;
    var squareOpened = false;
    await pumpPage(
      tester,
      loadConversations: () async => <Conversation>[],
      onOpenCoopPool: () => coopPoolOpened = true,
      onOpenSquare: () => squareOpened = true,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('合作池'));
    await tester.tap(find.text('去广场找人'));

    expect(coopPoolOpened, isTrue);
    expect(squareOpened, isTrue);
    expect(find.text('ROUTE /coop-pool'), findsNothing);
    expect(find.text('ROUTE /square'), findsNothing);
  });

  testWidgets('群会话按业务键显示为频道且可筛选', (tester) async {
    final Conversation group = Conversation.fromJson(<String, dynamic>{
      'conversationId': 9,
      'type': 4,
      'counterparty': <String, dynamic>{
        'nickname': '夜行俱乐部',
        'bizKey': 'club_7',
      },
    });
    await pumpPage(
      tester,
      loadConversations: () async => <Conversation>[conversation(), group],
    );
    await tester.pumpAndSettle();

    expect(find.text('俱乐部频道'), findsOneWidget);
    expect(find.text('私信'), findsWidgets);
    await tester.tap(scopeTab('频道'));
    await tester.pumpAndSettle();
    expect(find.text('夜行俱乐部'), findsOneWidget);
    expect(find.text('阿林'), findsNothing);
  });

  testWidgets('私信筛选:系统通知不混入,客服按真源决策 2 归私信', (tester) async {
    final Conversation system = Conversation(
      conversationId: 10,
      type: kImTypeSystem,
      counterparty: ImCounterparty(id: 0, nickname: '系统通知', avatar: ''),
    );
    final Conversation merchant = Conversation(
      conversationId: 11,
      type: kImTypeMerchant,
      counterparty: ImCounterparty(id: 0, nickname: '城瘾客服', avatar: ''),
    );
    await pumpPage(
      tester,
      loadConversations: () async => <Conversation>[
        conversation(),
        system,
        merchant,
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(scopeTab('私信'));
    await tester.pumpAndSettle();
    expect(find.text('阿林'), findsOneWidget);
    expect(find.text('城瘾客服'), findsOneWidget);
    expect(find.text('系统通知'), findsNothing);
  });

  testWidgets('频道 tab 空态说频道来路,不给「去广场找人」假下一步', (tester) async {
    await pumpPage(
      tester,
      loadConversations: () async => <Conversation>[conversation()],
    );
    await tester.pumpAndSettle();

    await tester.tap(scopeTab('频道'));
    await tester.pumpAndSettle();
    expect(find.text('还没有频道'), findsOneWidget);
    expect(find.text('从主题、俱乐部或队伍进入讨论后,频道会出现在这里'), findsOneWidget);
    expect(find.text('去广场找人'), findsNothing);
    expect(find.text('没有匹配的会话'), findsNothing);
  });

  testWidgets('关键词没搜到仍报「没有匹配的会话」,不与 tab 空态混用', (tester) async {
    await pumpPage(
      tester,
      loadConversations: () async => <Conversation>[conversation()],
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(CupertinoTextField).first, '不存在的人');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的会话'), findsOneWidget);
    expect(find.text('还没有私信'), findsNothing);
  });
}
