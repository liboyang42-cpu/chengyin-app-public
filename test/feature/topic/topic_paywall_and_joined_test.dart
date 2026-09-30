// gap-spec-player #5:主题详情两态 —— 已购底栏「去票夹·查看我的票」(stype=0)
// + 故事付费墙(storyLocked && lockedChapterCount>0)。
//
// 真源:pages/topic/index/index.wxml:363-366(已购单按钮)、:462-468(付费墙卡),
//       index.js:1039(goMyOrders→订单)、:1284(goJoinedPlay→票夹路线票 tab)、
//       :1636-1641(lockedChapterCount)、:1665-1668(已购态取后端 isSignUp,不只信 URL is_join)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/feature/topic/topic_detail_controller.dart';
import 'package:chengyin_app/feature/topic/topic_detail_page.dart';

TopicDetail _topic({
  int? lifecycle,
  int? selfPlay,
  double? price,
  int? isSignUp,
  bool storyLocked = false,
  int totalChapterCount = 0,
  int? unlockedChapterCount,
  int chapters = 0,
}) => TopicDetail.fromJson(<String, dynamic>{
  'id': 1,
  'name': '静安微旅行',
  'description': '测试用',
  'lifecycle': ?lifecycle,
  'selfPlay': ?selfPlay,
  'selfPlayPrice': ?price,
  'isSignUp': ?isSignUp,
  'storyLocked': storyLocked,
  'totalChapterCount': totalChapterCount,
  'unlockedChapterCount': ?unlockedChapterCount,
  'chaptersList': <dynamic>[
    for (var i = 0; i < chapters; i++)
      <String, dynamic>{'id': i + 1, 'name': '第${i + 1}章'},
  ],
});

/// 带 GoRouter,能承接底栏/付费墙的 context.push 落点,把跳到的路径写进 [landed]。
/// [notices] 非空时注入 onShowNotice,拦截「立即解锁」点击(不拖进真实登录流)。
Future<void> _pump(
  WidgetTester tester,
  TopicDetail d, {
  List<String>? landed,
  List<String>? notices,
}) async {
  final router = GoRouter(
    initialLocation: '/topic/1',
    routes: <RouteBase>[
      GoRoute(
        path: '/topic/:id',
        builder: (_, _) => TopicDetailPage(
          topicId: 1,
          onShowNotice: notices == null
              ? null
              : (_, message) => notices.add(message),
        ),
      ),
      GoRoute(
        path: '/tickets',
        builder: (_, state) {
          landed?.add('/tickets?${state.uri.query}');
          return const Scaffold(body: Text('票夹'));
        },
      ),
      GoRoute(
        path: '/orders',
        builder: (_, _) {
          landed?.add('/orders');
          return const Scaffold(body: Text('我的订单'));
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        topicDetailProvider(1).overrideWith((ref) async => d),
      ].cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

/// 付费墙挂在主滚动列表末尾,默认在折叠线以下,懒建 → 先滚到它出现再断言。
Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('模型契约', () {
    test('isSignUp 回填 → 已购态(不只信 URL 参数)', () {
      expect(_topic(isSignUp: 1).isSignUp, isTrue);
      expect(_topic(isSignUp: 0).isSignUp, isFalse);
      expect(_topic().isSignUp, isFalse, reason: '缺失按未购');
    });

    test('lockedChapterCount = 总数 − 已解锁;没下发按已渲染章节兜底,下限 0', () {
      // 后端下发 unlocked。
      expect(
        _topic(
          totalChapterCount: 3,
          unlockedChapterCount: 1,
        ).lockedChapterCount,
        2,
      );
      // 未下发 unlocked → 退化 chaptersList.length(这里给了 2 章)。
      expect(_topic(totalChapterCount: 3, chapters: 2).lockedChapterCount, 1);
      // 解锁数 ≥ 总数 → 0,不出现负数。
      expect(
        _topic(
          totalChapterCount: 2,
          unlockedChapterCount: 5,
        ).lockedChapterCount,
        0,
      );
    });

    test('showStoryPaywall 要 storyLocked 且还有锁住章节', () {
      expect(
        _topic(
          storyLocked: true,
          totalChapterCount: 3,
          unlockedChapterCount: 1,
        ).showStoryPaywall,
        isTrue,
      );
      expect(
        _topic(
          storyLocked: true,
          totalChapterCount: 2,
          unlockedChapterCount: 2,
        ).showStoryPaywall,
        isFalse,
        reason: '全解锁了就不该再拦',
      );
      expect(
        _topic(
          storyLocked: false,
          totalChapterCount: 3,
          unlockedChapterCount: 1,
        ).showStoryPaywall,
        isFalse,
      );
    });
  });

  group('已购底栏', () {
    testWidgets('isSignUp=1 → 单按钮「去票夹 · 查看我的票」,盖过报名态', (tester) async {
      await _pump(tester, _topic(isSignUp: 1));
      expect(find.text('去票夹 · 查看我的票'), findsOneWidget);
      expect(find.text('去参加'), findsNothing);
    });

    testWidgets('★ 已购即使后端 lifecycle 停在招募中,也只给回票夹(裁决优先)', (tester) async {
      await _pump(tester, _topic(isSignUp: 1, lifecycle: 1));
      expect(find.text('去票夹 · 查看我的票'), findsOneWidget);
      expect(find.text('招募中 · 未开售'), findsNothing);
    });

    testWidgets('点击 → /tickets?stype=0(路线票 tab,不进 play)', (tester) async {
      final landed = <String>[];
      await _pump(tester, _topic(isSignUp: 1), landed: landed);
      await tester.tap(find.text('去票夹 · 查看我的票'));
      await tester.pumpAndSettle();
      expect(landed, <String>['/tickets?stype=0']);
    });
  });

  group('故事付费墙', () {
    testWidgets('storyLocked 且有锁住章节 → 渲染卡:文案 + 价格 + 双出口', (tester) async {
      await _pump(
        tester,
        _topic(
          storyLocked: true,
          totalChapterCount: 3,
          unlockedChapterCount: 1,
          price: 149,
        ),
      );
      await _reveal(tester, find.text('解锁完整体验'));
      expect(find.text('解锁完整体验'), findsOneWidget);
      expect(find.text('解锁后可看全部故事线、答题揭秘与到店权益'), findsOneWidget);
      expect(find.text('¥149.00'), findsOneWidget);
      expect(find.text('立即解锁'), findsOneWidget);
      expect(find.text('已购票？去「我的订单」找回'), findsOneWidget);
    });

    testWidgets('未锁 → 不渲染', (tester) async {
      await _pump(tester, _topic(storyLocked: false, totalChapterCount: 3));
      expect(find.text('解锁完整体验'), findsNothing);
    });

    testWidgets('已购票 → 去「我的订单」找回,落 /orders', (tester) async {
      final landed = <String>[];
      await _pump(
        tester,
        _topic(
          storyLocked: true,
          totalChapterCount: 3,
          unlockedChapterCount: 1,
        ),
        landed: landed,
      );
      await _reveal(tester, find.text('已购票？去「我的订单」找回'));
      await tester.tap(find.text('已购票？去「我的订单」找回'));
      await tester.pumpAndSettle();
      expect(landed, <String>['/orders']);
    });

    testWidgets('「立即解锁」点击走到解锁流(与底栏 selfPlayBuy 同口)', (tester) async {
      final notices = <String>[];
      await _pump(
        tester,
        _topic(
          storyLocked: true,
          totalChapterCount: 3,
          unlockedChapterCount: 1,
          price: 149,
        ),
        notices: notices,
      );
      await _reveal(tester, find.text('立即解锁'));
      await tester.tap(find.text('立即解锁'));
      await tester.pumpAndSettle();
      expect(notices, <String>[
        'unlock',
      ], reason: '非商家非游客 → 进入解锁流(测试拦下真实购买 sheet)');
    });
  });
}
