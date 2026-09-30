// a2-club-entry 条目14:圈子动态的引用卡(真源 utils/feed-play-card.js +
// components/cy/feed-play-card)。判据在模型层(见 club_post_test.dart),
// 这里钉「渲染出来 + 点得到 + 落点对」:
//   - 卡本体 → 主题详情 /topic/<sportTopicId>;
//   - 「试玩」→ 自玩会话 /play/0?topicId=<sportTopicId>;
//   - 没引用/对象被删/拿不到 sportTopicId → 不出卡或卡点不动。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/data/models/club_post.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/club/club_feed_page.dart';

import '../../support/fixed_auth.dart';

ClubPost _post(Map<String, dynamic> m) =>
    ClubPost.fromJson(<String, dynamic>{'id': 66, 'content': '今晚的记录', ...m});

Future<GoRouter> _pump(WidgetTester tester, ClubPost post) async {
  await tester.binding.setSurfaceSize(const Size(390, 900));
  final router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) => ClubPostTile(post: post),
      ),
      GoRoute(
        path: '/topic/:id',
        builder: (_, state) =>
            Scaffold(body: Text('topic-${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/play/:key',
        builder: (_, state) => Scaffold(
          body: Text(
            'play-${state.pathParameters['key']}-${state.uri.queryParameters['topicId']}',
          ),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(
          () => FixedAuth(signedInAuthState()),
        ),
      ].cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('模板引用卡:封面+名字+「主题模板」,点卡进主题、点试玩进自玩会话', (WidgetTester tester) async {
    final router = await _pump(
      tester,
      _post(<String, dynamic>{
        'refType': 2,
        'refId': 77,
        'sportName': '静安夜跑',
        'sportCover': 'https://example.com/cover.jpg',
        'sportTopicId': 77,
        'isTopicTemplate': true,
      }),
    );
    expect(find.text('主题模板'), findsOneWidget);
    await tester.tap(find.byKey(const Key('club-post-ref-card-66')));
    await tester.pumpAndSettle();
    expect(find.text('topic-77'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('club-post-ref-play-66')));
    await tester.pumpAndSettle();
    expect(
      find.text('play-0-77'),
      findsOneWidget,
      reason: '自玩会话:activityId=0+topicId',
    );
    router.dispose();
  });

  testWidgets('完赛分享:成绩卡顶掉普通图廊,但卡仍可点回主题', (WidgetTester tester) async {
    final router = await _pump(
      tester,
      _post(<String, dynamic>{
        'refType': 1,
        'refId': 501,
        'sportName': '周六场',
        'sportCover': 'https://example.com/a.jpg',
        'sportTopicId': 77,
        'images': 'https://example.com/x.jpg',
      }),
    );
    expect(find.text('游玩记录'), findsOneWidget);
    // 「试玩」只属于模板卡;完赛卡不给。
    expect(find.byKey(const Key('club-post-ref-play-66')), findsNothing);
    await tester.tap(find.byKey(const Key('club-post-ref-card-66')));
    await tester.pumpAndSettle();
    expect(find.text('topic-77'), findsOneWidget);
    router.dispose();
  });

  testWidgets('普通帖(无引用)不出卡', (WidgetTester tester) async {
    final router = await _pump(tester, _post(<String, dynamic>{}));
    expect(find.byKey(const Key('club-post-ref-card-66')), findsNothing);
    expect(find.text('游玩记录'), findsNothing);
    expect(find.text('主题模板'), findsNothing);
    router.dispose();
  });

  testWidgets('被引对象已删(名字空)→ 不渲染卡', (WidgetTester tester) async {
    final router = await _pump(
      tester,
      _post(<String, dynamic>{
        'refType': 2,
        'sportName': '',
        'sportCover': 'https://example.com/cover.jpg',
        'sportTopicId': 77,
      }),
    );
    expect(find.byKey(const Key('club-post-ref-card-66')), findsNothing);
    expect(find.text('主题模板'), findsNothing);
    router.dispose();
  });

  testWidgets('拿不到 sportTopicId:卡照出,但不给点(没有死链接入口)', (
    WidgetTester tester,
  ) async {
    final router = await _pump(
      tester,
      _post(<String, dynamic>{
        'refType': 2,
        'sportName': '静安夜跑',
        'sportCover': 'https://example.com/cover.jpg',
        'isTopicTemplate': true,
      }),
    );
    expect(find.text('静安夜跑'), findsOneWidget);
    expect(find.byKey(const Key('club-post-ref-card-66')), findsNothing);
    expect(find.byKey(const Key('club-post-ref-play-66')), findsNothing);
    router.dispose();
  });
}
