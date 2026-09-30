// 广场顶部「即将开始」横滑卡。
//
// 真源:
//   · 筛选 `pages/square/list/index.js:657-722`
//   · 倒计时 `pages/square/list/index.js:24-33`
//   · 卡片   `pages/square/list/index.wxml:20-38`
//
// ★ 筛选是**三个条件的与**,少一个就会把「已结束」「不在 24h 内」的
//   活动推给用户 —— 所以每个条件都有一条**只差那一个字段**的负控。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/data/api/square_api.dart';
import 'package:chengyin_app/data/models/official_event.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/square/square_controller.dart';
import 'package:chengyin_app/feature/square/square_list_page.dart';
import 'package:chengyin_app/feature/square/square_upcoming_events.dart';

OfficialEvent _event({
  int id = 1,
  String title = '城市夜跑',
  String? subtitle,
  String? city,
  int status = 2,
  bool bannerEnabled = true,
  DateTime? start,
  int participants = 0,
  List<String> avatars = const <String>[],
}) => OfficialEvent(
  id: id,
  title: title,
  subtitle: subtitle,
  city: city,
  status: status,
  bannerEnabled: bannerEnabled,
  activityStart: start,
  participants: participants,
  participantAvatars: avatars,
);

class _LoggedInAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

void main() {
  final DateTime now = DateTime(2026, 9, 17, 20, 0);

  test('筛选:三个条件全中才收', () {
    final List<OfficialEvent> picked = selectSquareUpcomingEvents(
      <OfficialEvent>[
        _event(id: 1, start: now.add(const Duration(hours: 3))),
        // 负控一:开关没开(运营没把它当推广位)。
        _event(
          id: 2,
          bannerEnabled: false,
          start: now.add(const Duration(hours: 3)),
        ),
        // 负控二:状态是「已结束」。
        _event(id: 3, status: 5, start: now.add(const Duration(hours: 3))),
        // 负控三:开始时刻已经过了。
        _event(id: 4, start: now.subtract(const Duration(minutes: 1))),
        // 负控四:刚好压在 24h 边界外。
        _event(id: 5, start: now.add(squareUpcomingWindow)),
        // 负控五:压根没有开始时刻。
        _event(id: 6),
      ],
      now,
    );

    expect(picked.map((OfficialEvent e) => e.id), <int>[1]);
  });

  test('筛选:按开始时刻升序,先开始的排前面', () {
    final List<OfficialEvent> picked =
        selectSquareUpcomingEvents(<OfficialEvent>[
          _event(id: 3, start: now.add(const Duration(hours: 9))),
          _event(id: 1, start: now.add(const Duration(hours: 1))),
          _event(id: 2, start: now.add(const Duration(hours: 5))),
        ], now);

    expect(picked.map((OfficialEvent e) => e.id), <int>[1, 2, 3]);
  });

  test('倒计时文案与真源逐字一致', () {
    expect(squareUpcomingCountdown(const Duration(minutes: 5)), '5 分钟后开始');
    expect(squareUpcomingCountdown(const Duration(hours: 3)), '3 小时后开始');
    expect(squareUpcomingCountdown(const Duration(hours: 26)), '1 天后开始');
    // 不足一分钟说「马上开始」—— kicker 已经写着「即将开始」,不重复。
    expect(squareUpcomingCountdown(const Duration(seconds: 40)), '马上开始');
    expect(squareUpcomingCountdown(const Duration(minutes: -5)), '马上开始');
  });

  test('卡片数据:头像最多三个,溢出按人数算', () {
    final List<SquareUpcomingCard> cards = squareUpcomingCards(<OfficialEvent>[
      _event(
        id: 9,
        title: '夜跑',
        subtitle: '静安线',
        city: '上海',
        start: now.add(const Duration(hours: 2)),
        participants: 12,
        avatars: <String>['a', 'b', 'c', 'd', 'e'],
      ),
      // 人数比头像还少:溢出必须是 0,不能算出负数。
      _event(
        id: 10,
        title: '早课',
        city: '上海',
        start: now.add(const Duration(hours: 4)),
        participants: 1,
        avatars: <String>['a', 'b'],
      ),
    ], now);

    expect(cards.length, 2);
    expect(cards.first.sub, '静安线');
    expect(cards.first.avatars, <String>['a', 'b', 'c']);
    expect(cards.first.overflow, 9);
    // 没有 subtitle 时退到 city。
    expect(cards.last.sub, '上海');
    expect(cards.last.overflow, 0);
  });

  testWidgets('横滑卡:点一张进对应活动,空列表整块不渲染', (WidgetTester tester) async {
    final List<int> opened = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SquareUpcomingTrack(
            cards: squareUpcomingCards(<OfficialEvent>[
              _event(
                id: 42,
                title: '城市夜跑',
                start: now.add(const Duration(hours: 2)),
              ),
            ], now),
            onOpen: (_, int id) => opened.add(id),
          ),
        ),
      ),
    );

    expect(find.text('即将开始'), findsOneWidget);
    expect(find.text('2 小时后开始'), findsOneWidget);
    await tester.tap(find.byKey(const Key('square-upcoming-card-42')));
    expect(opened, <int>[42]);

    // 负控:一条都没有 → 连轨道都不该出现。
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SquareUpcomingTrack(cards: <SquareUpcomingCard>[]),
        ),
      ),
    );
    expect(find.byKey(const Key('square-upcoming-track')), findsNothing);
  });

  testWidgets('列表页:横滑卡在第一张卡之前,信息流本身不受影响', (WidgetTester tester) async {
    // ★ 这条盯的是**索引位移**:横滑卡插进 ListView 头部后,
    //   第一张帖文卡不能被顶掉、也不许把「加载更多」提前。
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => const SquareListPage()),
        GoRoute(
          path: '/official/:id',
          builder: (_, GoRouterState s) =>
              Scaffold(body: Text('活动-${s.pathParameters['id']}')),
        ),
        GoRoute(
          path: '/square/:id',
          builder: (_, GoRouterState s) =>
              Scaffold(body: Text('详情-${s.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          squareFeedPageProvider.overrideWith(
            (Ref ref, SquareFeedMode mode) async => const SquareFeedPage(
              items: <SquarePost>[
                SquarePost(id: 5, memberId: 11, contents: '第一条动态'),
              ],
              hasMore: false,
            ),
          ),
          squareUpcomingCardsProvider.overrideWith(
            (Ref ref) async => <SquareUpcomingCard>[
              SquareUpcomingCard(
                eventId: 42,
                title: '城市夜跑',
                sub: '静安线',
                countdown: '2 小时后开始',
                avatars: const <String>[],
                overflow: 0,
              ),
            ],
          ),
        ].cast(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('square-upcoming-track')), findsOneWidget);
    expect(find.text('第一条动态'), findsOneWidget);
    expect(find.byKey(const Key('square-post-like-5')), findsOneWidget);

    await tester.tap(find.byKey(const Key('square-upcoming-card-42')));
    await tester.pumpAndSettle();
    expect(find.text('活动-42'), findsOneWidget);
  });

  testWidgets('列表页:没有即将开始的活动时,信息流照常从第一张开始', (WidgetTester tester) async {
    // 负控:provider 给空列表 → 轨道不渲染,帖子仍然是第一行。
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          squareFeedPageProvider.overrideWith(
            (Ref ref, SquareFeedMode mode) async => const SquareFeedPage(
              items: <SquarePost>[
                SquarePost(id: 5, memberId: 11, contents: '第一条动态'),
              ],
              hasMore: false,
            ),
          ),
          squareUpcomingCardsProvider.overrideWith(
            (Ref ref) async => const <SquareUpcomingCard>[],
          ),
        ].cast(),
        child: const MaterialApp(home: SquareListPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('square-upcoming-track')), findsNothing);
    expect(find.text('第一条动态'), findsOneWidget);
  });
}
