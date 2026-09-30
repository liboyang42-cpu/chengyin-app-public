import 'package:chengyin_app/data/models/growth.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/p3/badges/badge_wall_controller.dart';
import 'package:chengyin_app/feature/p3/badges/badge_wall_logic.dart';
import 'package:chengyin_app/feature/p3/badges/badge_wall_page.dart';
import 'package:chengyin_app/feature/p3/growth/leaderboard_controller.dart';
import 'package:chengyin_app/feature/p3/growth/leaderboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// 这三页对游客是登录门(B1 报告 P1 修复),拍的是登录后的落点。
class _FixedAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 1, nickname: '阿兰', avatar: '', role: 'player'),
  );
}

Future<GoRouter> _pumpRoute(
  WidgetTester tester, {
  required String initialLocation,
  required Widget page,
  required List<dynamic> overrides,
}) async {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(path: initialLocation, builder: (_, _) => page),
      GoRoute(
        path: '/feed',
        builder: (_, _) =>
            const Text('/feed', textDirection: TextDirection.ltr),
      ),
      GoRoute(
        path: '/map',
        builder: (_, _) => const Text('/map', textDirection: TextDirection.ltr),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('成长榜空态去探索回 Mini 真源首页', (WidgetTester tester) async {
    final board = GrowthLeaderboard.fromJson(<String, dynamic>{
      'metric': 'point',
      'period': 'total',
      'list': <dynamic>[],
      'me': <String, dynamic>{'score': 0},
    });
    final router = await _pumpRoute(
      tester,
      initialLocation: '/leaderboard',
      page: const LeaderboardPage(),
      overrides: <dynamic>[
        authControllerProvider.overrideWith(() => _FixedAuth()),
        leaderboardProvider.overrideWith(
          (ref, query) async =>
              LeaderboardResult(data: buildLeaderboardData(board)),
        ),
      ],
    );

    await tester.tap(find.text('去探索'));
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, '/feed');
  });

  testWidgets('徽章墙空态去探索回 Mini 真源首页', (WidgetTester tester) async {
    final router = await _pumpRoute(
      tester,
      initialLocation: '/badges',
      page: const BadgeWallPage(),
      overrides: <dynamic>[
        authControllerProvider.overrideWith(() => _FixedAuth()),
        badgeWallProvider.overrideWith(
          (ref) async => const BadgeWallPageData(
            badges: <WallBadgeView>[],
            legend: <WallLegendEntry>[],
            unlockedCount: 0,
            lockedCount: 0,
            failure: null,
            failureDetail: '',
          ),
        ),
      ],
    );

    await tester.tap(find.text('去探索'));
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, '/feed');
  });
}
