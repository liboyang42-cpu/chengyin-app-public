import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/object_card_api.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/growth.dart';
import 'package:chengyin_app/data/models/my_project.dart';
import 'package:chengyin_app/data/models/object_card.dart';
import 'package:chengyin_app/data/models/profile_detail.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/p3/object_cards/object_cards_page.dart';
import 'package:chengyin_app/feature/profile/profile_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

final _user = ProfileDetail(
  id: 7, nickname: '原文名字', avatar: '', introduction: '原文介绍',
  levelId: 3, point: 88, balance: 12.5, followNum: 2, fansNum: 3,
  likeNum: 4, topicNum: 0, activityNum: 0,
);

Widget _profile(ValueChanged<ProfileDestination> onDestination) => ProfileRootView(
  user: _user,
  effectiveRole: 'player',
  orders: const AsyncData<List<MyRegistration>>([]),
  projects: const AsyncData<List<MyProject>>([]),
  posts: const AsyncData<List<SquarePost>>([]),
  growth: AsyncData(GrowthCenter(levelNo: 3, expValue: 88, points: 120,
      badges: [], missions: [])),
  playGrowth: const AsyncData(PlayGrowth(
      level: 3, totalCheckins: 9, totalMileage: 12, streakDays: 5)),
  onPost: (_) {}, onOrder: (_) {}, onProject: (_) {},
  onDestination: onDestination,
  onRetryOrders: () {}, onRetryProjects: () {}, onRetryPosts: () {}, onRetryGrowth: () {},
);

class _Auth extends AuthController {
  @override
  AuthState build() => AuthState(initialized: true,
      user: User(id: 7, nickname: '', avatar: '', role: 'player'));
}

class _Cards implements ObjectCardApi {
  int calls = 0;
  @override
  Future<ObjectCardCollection> list({String category = ''}) async {
    calls++;
    return const ObjectCardCollection(cards: [], total: 0);
  }
}

void main() {
  testWidgets('English profile preserves UGC and exposes tabs at large text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    try {
      final destinations = <ProfileDestination>[];
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: _profile(destinations.add),
      ));
      await tester.pumpAndSettle();
      expect(find.text('原文名字'), findsOneWidget);
      expect(find.text('原文介绍'), findsOneWidget);
      expect(find.text('My orders'), findsOneWidget);
      expect(find.bySemanticsLabel('Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final tab in ['posts', 'achievements', 'about', 'mine']) {
        final target = find.byKey(ValueKey('profile-tab-$tab'));
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (tab == 'posts') expect(find.text('No posts yet'), findsOneWidget);
        if (tab == 'about') expect(find.text('Introduction'), findsOneWidget);
      }
      final orders = find.byKey(const ValueKey('profile-orders'));
      await tester.ensureVisible(orders);
      await tester.tap(orders);
      expect(destinations, [ProfileDestination.orders]);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Collection profile entry navigates to object cards and calls list', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cards = _Cards();
    final router = GoRouter(initialLocation: '/profile', routes: [
      GoRoute(path: '/profile', builder: (context, _) => _profile((destination) {
        openProfileDestination(context, destination,
          isMerchantView: false,
          activeRegistration: const AsyncData(false),
          retryActiveRegistration: () {},
          ownedClubs: const AsyncData<List<Club>>([]),
          retryOwnedClubs: () {},
        );
      })),
      GoRoute(path: '/object-cards', builder: (_, _) => const ObjectCardsPage()),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_Auth.new),
        objectCardApiProvider.overrideWithValue(cards),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-tab-achievements')));
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('profile-object-cards'));
    await tester.scrollUntilVisible(entry, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/object-cards');
    expect(cards.calls, 1);
    expect(find.text('No objects collected yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
