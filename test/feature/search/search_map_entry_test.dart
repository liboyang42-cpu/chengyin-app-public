import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/data/models/roam_session.dart';
import 'package:chengyin_app/data/models/category.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/data/api/square_api.dart';
import 'package:chengyin_app/feature/roam/roam_live_page.dart';
import 'package:chengyin_app/feature/search/city_node_search_page.dart';
import 'package:chengyin_app/feature/search/search_controller.dart';
import 'package:chengyin_app/feature/search/search_page.dart';
import 'package:chengyin_app/feature/square/square_controller.dart';
import 'package:chengyin_app/feature/square/square_list_page.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  test('地图搜索路由保留关键词与分类', () {
    expect(
      searchMapLocation(keyword: '咖啡 馆', categoryId: 6),
      '/search/map?keyword=%E5%92%96%E5%95%A1+%E9%A6%86&categoryId=6',
    );
    expect(searchMapLocation(), '/search/map');
  });

  testWidgets('搜索页地图入口可达搜索地图', (WidgetTester tester) async {
    final GoRouter router = GoRouter(
      initialLocation: '/search',
      routes: <RouteBase>[
        GoRoute(path: '/search', builder: (_, _) => const SearchPage()),
        GoRoute(
          path: '/search/map',
          builder: (_, _) => const Scaffold(body: Text('搜索地图已打开')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          searchCategoriesProvider.overrideWith((ref) async => <Category>[]),
        ].cast(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    await tester.tap(find.text('在地图上搜城市节点'));
    await tester.pumpAndSettle();
    expect(find.text('搜索地图已打开'), findsOneWidget);
  });

  testWidgets('广场地图入口可达搜索地图', (WidgetTester tester) async {
    final GoRouter router = GoRouter(
      initialLocation: '/square',
      routes: <RouteBase>[
        GoRoute(path: '/square', builder: (_, _) => const SquareListPage()),
        GoRoute(
          path: '/search/map',
          builder: (_, _) => const Scaffold(body: Text('搜索地图已打开')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          squareFeedPageProvider.overrideWith(
            (ref, mode) async =>
                const SquareFeedPage(items: <SquarePost>[], hasMore: false),
          ),
        ].cast(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('square-search-map')));
    await tester.pumpAndSettle();
    expect(find.text('搜索地图已打开'), findsOneWidget);
  });

  testWidgets('漫游地图入口交付公开点击回调', (WidgetTester tester) async {
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoamIntroView(
            sessions: const <RoamSession>[],
            topics: const <RoamIntroTopic>[],
            onStart: () {},
            onStartAndShoot: () {},
            onOpenRules: () {},
            onOpenHistory: () {},
            onOpenStampAlbum: () {},
            onOpenBadges: () {},
            onOpenTopic: (_) {},
            onOpenOfficialEvents: () {},
            onDiscoverShops: () {},
            onOpenProfile: () {},
            onOpenSearchMap: () => opens += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('roam-search-map')));
    expect(opens, 1);
  });
}
