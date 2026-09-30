import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/data/api/square_api.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/square/square_controller.dart';
import 'package:chengyin_app/feature/square/square_compose_page.dart';
import 'package:chengyin_app/feature/square/square_detail_page.dart';
import 'package:chengyin_app/feature/square/square_list_page.dart';

class _LoggedInAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    user: User(id: 99, nickname: '测试用户', avatar: '', role: 'player'),
    initialized: true,
  );
}

void main() {
  test('发布快捷目标只接受受支持的显式值', () {
    expect(squareComposeIntentFromValue('photo'), SquareComposeIntent.photo);
    expect(
      squareComposeIntentFromValue('location'),
      SquareComposeIntent.location,
    );
    expect(squareComposeIntentFromValue('route'), SquareComposeIntent.route);
    expect(squareComposeIntentFromValue('unknown'), isNull);
    expect(squareComposeIntentFromValue(null), isNull);
  });

  testWidgets('广场公开入口包含话题社群且暂不暴露未成熟推荐流', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          squareFeedPageProvider.overrideWith(
            (ref, mode) async =>
                const SquareFeedPage(items: <SquarePost>[], hasMore: false),
          ),
        ].cast(),
        child: const MaterialApp(home: SquareListPage()),
      ),
    );
    await tester.pumpAndSettle();

    for (final String label in <String>['最新', '关注', '附近', '话题', '社群', '精选']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('热门'), findsNothing);
    expect(find.text('推荐'), findsNothing);
    expect(find.byKey(const Key('square-governance-entry')), findsOneWidget);

    await tester.tap(find.text('关注'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('square-governance-entry')), findsOneWidget);
  });

  testWidgets('小程序基线：动态页在信息流前提供完整发布区并保留治理入口', (WidgetTester tester) async {
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => const SquareListPage()),
        GoRoute(
          path: '/square/compose',
          builder: (_, GoRouterState state) => Scaffold(
            body: Text(
              '发布目标-${state.uri.queryParameters['intent'] ?? 'basic'}',
            ),
          ),
        ),
        GoRoute(
          path: '/square/governance',
          builder: (_, _) => const Scaffold(body: Text('治理页')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          squareFeedPageProvider.overrideWith(
            (ref, mode) async => const SquareFeedPage(
              items: <SquarePost>[
                SquarePost(id: 8, memberId: 11, contents: '第一条动态'),
              ],
              hasMore: false,
            ),
          ),
        ].cast(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('动态'), findsOneWidget);
    expect(find.byKey(const Key('square-compose-entry')), findsOneWidget);
    expect(find.byKey(const Key('square-compose-media')), findsOneWidget);
    expect(find.byKey(const Key('square-compose-location')), findsOneWidget);
    expect(find.byKey(const Key('square-compose-route')), findsOneWidget);
    expect(find.byKey(const Key('square-compose-submit')), findsOneWidget);
    expect(find.byKey(const Key('square-governance-entry')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('square-compose-entry'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('square-thread-item-8'))).dy,
      ),
    );

    await tester.tap(find.byKey(const Key('square-compose-entry')));
    await tester.pumpAndSettle();
    expect(find.text('发布目标-basic'), findsOneWidget);
  });

  testWidgets('发布区图片地点路线进入各自编辑目标', (WidgetTester tester) async {
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => const SquareListPage()),
        GoRoute(
          path: '/square/compose',
          builder: (_, GoRouterState state) => Scaffold(
            body: Text(
              '发布目标-${state.uri.queryParameters['intent'] ?? 'basic'}',
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          squareFeedPageProvider.overrideWith(
            (ref, mode) async =>
                const SquareFeedPage(items: <SquarePost>[], hasMore: false),
          ),
        ].cast(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    for (final ({String key, String intent}) target
        in <({String key, String intent})>[
          (key: 'square-compose-media', intent: 'photo'),
          (key: 'square-compose-location', intent: 'location'),
          (key: 'square-compose-route', intent: 'route'),
        ]) {
      await tester.tap(find.byKey(Key(target.key)));
      await tester.pumpAndSettle();
      expect(find.text('发布目标-${target.intent}'), findsOneWidget);
      router.go('/');
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Threads 式时间线保留城瘾路线附件和四个帖文动作', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          squareFeedPageProvider.overrideWith(
            (ref, mode) async => SquareFeedPage(
              items: <SquarePost>[
                SquarePost.fromJson(<String, dynamic>{
                  'id': 1,
                  'memberId': 11,
                  'memberNickname': '阿兰',
                  'contents': '今晚沿苏州河走到昌平路，风比昨天轻。',
                  'sportName': '苏州河夜行路线',
                  'nodeDoneCount': 4,
                  'nodeTotal': 6,
                  'address': '昌平路桥',
                  'likeNum': 12,
                  'commentCount': 3,
                }),
              ],
              hasMore: false,
            ),
          ),
        ].cast(),
        child: const MaterialApp(home: SquareListPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('square-thread-item-1')), findsOneWidget);
    expect(find.byKey(const Key('square-thread-rail-1')), findsOneWidget);
    expect(find.text('苏州河夜行路线'), findsOneWidget);
    expect(find.text('附近'), findsOneWidget);
    expect(find.text('4/6 个节点'), findsOneWidget);
    for (final String action in <String>['reply', 'like', 'share', 'more']) {
      expect(find.byKey(Key('square-post-$action-1')), findsOneWidget);
    }
  });

  // 真源 pages/square/list/index.js:627-638 `goPlay`:关联的是活动 →
  // 直达开局页(`/pages/play/index?activityId=`),不是活动详情。
  testWidgets('★ 关联活动附件条点进开局页 /play/:activityId,不是活动详情', (
    WidgetTester tester,
  ) async {
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => const SquareListPage()),
        GoRoute(
          path: '/activity/:id',
          builder: (_, _) => const Scaffold(body: Text('活动详情')),
        ),
        GoRoute(
          path: '/play/:activityId',
          builder: (_, GoRouterState state) =>
              Scaffold(body: Text('开局-${state.pathParameters['activityId']}')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          squareFeedPageProvider.overrideWith(
            (ref, mode) async => SquareFeedPage(
              items: <SquarePost>[
                SquarePost.fromJson(<String, dynamic>{
                  'id': 2,
                  'memberId': 11,
                  'contents': '今晚这场一起走。',
                  'sportName': '夜行路线',
                  'references': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'reference_type': 'ACTIVITY',
                      'reference_id': 77,
                    },
                  ],
                }),
              ],
              hasMore: false,
            ),
          ),
        ].cast(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('夜行路线'));
    await tester.pumpAndSettle();
    expect(find.text('开局-77'), findsOneWidget);
    expect(find.text('活动详情'), findsNothing);
  });

  // 真源 H050 三合一弹层(编辑/删除):components/cy/post-actions/index.wxml。
  // App 列表侧原来本人帖「···」只有删除,编辑唯一入口在详情页 —— 从列表改帖断链。
  testWidgets('★ 本人帖「···」有「编辑动态」,进发布面板的编辑态', (WidgetTester tester) async {
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => const SquareListPage()),
        GoRoute(
          path: '/square/compose',
          builder: (_, GoRouterState state) =>
              Scaffold(body: Text('编辑-${(state.extra as SquarePost).id}')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          squareFeedPageProvider.overrideWith(
            (ref, mode) async => const SquareFeedPage(
              items: <SquarePost>[
                SquarePost(id: 5, memberId: 99, contents: '我自己发的动态'),
              ],
              hasMore: false,
            ),
          ),
        ].cast(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('square-post-more-5')));
    await tester.pumpAndSettle();
    expect(find.text('编辑动态'), findsOneWidget);
    expect(find.text('删除动态'), findsOneWidget);

    await tester.tap(find.text('编辑动态'));
    await tester.pumpAndSettle();
    expect(find.text('编辑-5'), findsOneWidget);
  });

  testWidgets('动态页不占用系统返回位并回到原入口', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          squareFeedPageProvider.overrideWith(
            (ref, mode) async =>
                const SquareFeedPage(items: <SquarePost>[], hasMore: false),
          ),
        ].cast(),
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: CupertinoButton(
                onPressed: () => Navigator.of(context).push<void>(
                  CupertinoPageRoute<void>(
                    builder: (_) => const SquareListPage(),
                  ),
                ),
                child: const Text('打开动态'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开动态'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoNavigationBarBackButton), findsOneWidget);

    await tester.tap(find.byType(CupertinoNavigationBarBackButton));
    await tester.pumpAndSettle();
    expect(find.text('打开动态'), findsOneWidget);
  });

  testWidgets('窄屏大字体下发布区可换行且不溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          squareFeedPageProvider.overrideWith(
            (ref, mode) async =>
                const SquareFeedPage(items: <SquarePost>[], hasMore: false),
          ),
        ].cast(),
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const SquareListPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('square-compose-route')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('小程序基线：列表作者行后先展示 16:10 媒体再展示正文', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          squareFeedPageProvider.overrideWith(
            (ref, mode) async => SquareFeedPage(
              items: <SquarePost>[
                SquarePost.fromJson(<String, dynamic>{
                  'id': 9,
                  'memberId': 11,
                  'memberNickname': '阿兰',
                  'contents': '图片之后的正文',
                  'pics': <String>['https://example.invalid/post.jpg'],
                }),
              ],
              hasMore: false,
            ),
          ),
        ].cast(),
        child: const MaterialApp(home: SquareListPage()),
      ),
    );
    await tester.pumpAndSettle();

    final Finder media = find.byKey(const Key('square-post-media-9'));
    final Finder content = find.byKey(const Key('square-post-content-9'));
    expect(media, findsOneWidget);
    expect(content, findsOneWidget);
    expect(
      tester.getTopLeft(media).dy,
      lessThan(tester.getTopLeft(content).dy),
    );
    expect(
      tester
          .widget<AspectRatio>(
            find.descendant(of: media, matching: find.byType(AspectRatio)),
          )
          .aspectRatio,
      16 / 10,
    );
  });

  testWidgets('小程序基线：详情模块顺序与显式评论发送目标稳定', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          squareDetailProvider(21).overrideWith(
            (ref) async => SquarePost.fromJson(<String, dynamic>{
              'id': 21,
              'memberId': 11,
              'memberNickname': '阿兰',
              'contents': '详情正文',
              'pics': <String>['https://example.invalid/detail.jpg'],
              'likeNum': 2,
              'commentCount': 0,
              'viewerCanComment': true,
            }),
          ),
          squareCommentsProvider(
            21,
          ).overrideWith((ref) async => const <Comment>[]),
        ].cast(),
        child: const MaterialApp(home: SquareDetailPage(postId: 21)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('动态详情'), findsOneWidget);
    final Finder media = find.byKey(const Key('square-detail-media'));
    final Finder actions = find.byKey(const Key('square-detail-actions'));
    final Finder author = find.byKey(const Key('square-detail-author'));
    final Finder content = find.byKey(const Key('square-detail-content'));
    final Finder comments = find.byKey(const Key('square-detail-comments'));
    for (final Finder finder in <Finder>[
      media,
      actions,
      author,
      content,
      comments,
    ]) {
      expect(finder, findsOneWidget);
    }
    expect(tester.getTopLeft(author).dy, lessThan(tester.getTopLeft(media).dy));
    expect(
      tester.getTopLeft(media).dy,
      lessThan(tester.getTopLeft(actions).dy),
    );
    expect(
      tester.getTopLeft(actions).dy,
      lessThan(tester.getTopLeft(content).dy),
    );
    expect(
      tester.getTopLeft(content).dy,
      lessThan(tester.getTopLeft(comments).dy),
    );
    expect(find.byKey(const Key('square-comment-input')), findsOneWidget);
    expect(find.byKey(const Key('square-comment-send')), findsOneWidget);
    await tester.tap(find.byKey(const Key('square-detail-comment-action')));
    await tester.pump();
    expect(
      tester
          .widget<CupertinoTextField>(
            find.byKey(const Key('square-comment-input')),
          )
          .focusNode
          ?.hasFocus,
      isTrue,
    );
  });

  testWidgets('最新与关注切换读取两条不同的真实 Feed', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          squareFeedPageProvider.overrideWith(
            (ref, mode) async => SquareFeedPage(
              items: <SquarePost>[
                mode == SquareFeedMode.following
                    ? const SquarePost(id: 2, memberId: 12, contents: '关注动态')
                    : const SquarePost(id: 1, memberId: 11, contents: '最新动态'),
              ],
              hasMore: false,
            ),
          ),
        ].cast(),
        child: const MaterialApp(home: SquareListPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('最新动态'), findsOneWidget);
    expect(find.text('关注动态'), findsNothing);

    await tester.tap(find.text('关注'));
    await tester.pumpAndSettle();

    expect(find.text('最新动态'), findsNothing);
    expect(find.text('关注动态'), findsOneWidget);
  });

  testWidgets('评论动作通过真实 GoRouter 进入帖文对话', (WidgetTester tester) async {
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => const SquareListPage()),
        GoRoute(
          path: '/square/:id',
          builder: (_, GoRouterState state) =>
              Scaffold(body: Text('帖文详情-${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          squareFeedPageProvider.overrideWith(
            (ref, mode) async => const SquareFeedPage(
              items: <SquarePost>[
                SquarePost(id: 7, memberId: 11, contents: '可继续的城市对话'),
              ],
              hasMore: false,
            ),
          ),
        ].cast(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final CupertinoButton replyButton = tester.widget<CupertinoButton>(
      find.descendant(
        of: find.byKey(const Key('square-post-reply-7')),
        matching: find.byType(CupertinoButton),
      ),
    );
    replyButton.onPressed!();
    await tester.pumpAndSettle();

    expect(find.text('帖文详情-7'), findsOneWidget);
  });
}
