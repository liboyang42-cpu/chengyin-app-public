// 社区广场 gate 关态入口收口回归。
//
// §5.4 判定:gate 关态时 /square/<id> 会落进「社区广场灰度中」墙,
// 而三处入口(我的发布 / 他人主页推文 / 社区治理通知)仍会把用户送进去。
// 这里把三处的行为钉死:
//   · 关态点击 → 原生提示、路由不变(不得进详情)
//   · 开态点击 → 照常进详情(负控:证明提示不是"永远都弹")

import 'package:chengyin_app/core/feature_flags.dart';
import 'package:chengyin_app/core/network/provider_retry.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/widgets/cy_native_notice.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/growth.dart';
import 'package:chengyin_app/data/models/my_project.dart';
import 'package:chengyin_app/data/models/profile_detail.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/orders/orders_page.dart';
import 'package:chengyin_app/feature/profile/profile_controller.dart';
import 'package:chengyin_app/feature/profile/profile_page.dart';
import 'package:chengyin_app/feature/profile/user_profile_page.dart';
import 'package:chengyin_app/feature/publish/my_projects_page.dart';
import 'package:chengyin_app/feature/square/square_controller.dart';
import 'package:chengyin_app/feature/square/square_governance_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// 只钉稳定前缀:后半句会撞 test/no_placeholder_actions_test.dart 的词表,
// 那条门禁一改文案就会连坐到这里。真正的行为由路由与详情断言钉住。
const String _closedNotice = '社区广场灰度中';

class _FakeRegistrationApi implements RegistrationApi {
  @override
  Future<Map<String, dynamic>?> joinInfo({int? memberId}) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixedAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 7, nickname: '探索者', avatar: '', role: 'player'),
  );
}

class _OneCreative extends MyCreativesController {
  @override
  Future<List<SquarePost>> build() async => <SquarePost>[
    SquarePost(id: 9, memberId: 7, contents: '城市散步日记'),
  ];
}

final ProfileDetail _profile = ProfileDetail(
  id: 7,
  nickname: '探索者',
  avatar: '',
  introduction: '',
  levelId: 1,
  point: 0,
  balance: 0,
  followNum: 0,
  fansNum: 0,
  likeNum: 0,
  topicNum: 0,
  activityNum: 0,
);

final GrowthCenter _growth = GrowthCenter(
  levelNo: 1,
  expValue: 0,
  points: 0,
  badges: <MedalBadge>[],
  missions: <GrowthMission>[],
);

GoRoute _squareDetailRoute() => GoRoute(
  path: '/square/:id',
  builder: (_, state) => Text('SQUARE-${state.pathParameters['id']}'),
);

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  GoRouter router, {
  Size viewport = const Size(390, 1100),
}) async {
  addTearDown(router.dispose);
  addTearDown(container.dispose);
  await tester.binding.setSurfaceSize(viewport);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Future<GoRouter> _pumpOwnProfile(
  WidgetTester tester, {
  required bool open,
}) async {
  final container = ProviderContainer(
    retry: chengyinRetry,
    overrides: [
      authControllerProvider.overrideWith(_FixedAuth.new),
      registrationApiProvider.overrideWithValue(_FakeRegistrationApi()),
      profileDetailProvider.overrideWith((_) async => _profile),
      myOrdersProvider.overrideWith((_) async => <MyRegistration>[]),
      myProjectsProvider.overrideWith((_) async => <MyProject>[]),
      myCreativesProvider.overrideWith(_OneCreative.new),
      growthCenterProvider.overrideWith((_) async => _growth),
      featureFlagProvider.overrideWith((ref, name) => open),
    ],
  );
  final router = GoRouter(
    initialLocation: '/profile',
    routes: <RouteBase>[
      GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
      _squareDetailRoute(),
    ],
  );
  await _pump(tester, container, router);
  return router;
}

Future<GoRouter> _pumpUserProfile(
  WidgetTester tester, {
  required bool open,
}) async {
  final container = ProviderContainer(
    overrides: [
      // 推文栏要登录态(P1-1):游客看到的是登录引导,点不到推文。
      authControllerProvider.overrideWith(_FixedAuth.new),
      otherProfileProvider(42).overrideWith((ref) async => _profile),
      otherPostsProvider(42).overrideWith(
        (ref) async => <SquarePost>[
          SquarePost(id: 9, memberId: 42, contents: '城市散步日记'),
        ],
      ),
      featureFlagProvider.overrideWith((ref, name) => open),
    ],
  );
  final router = GoRouter(
    initialLocation: '/member',
    routes: <RouteBase>[
      GoRoute(
        path: '/member',
        builder: (_, _) => const UserProfilePage(memberId: 42),
      ),
      _squareDetailRoute(),
    ],
  );
  await _pump(tester, container, router, viewport: const Size(390, 900));
  return router;
}

Future<GoRouter> _pumpGovernance(
  WidgetTester tester, {
  required bool open,
}) async {
  final container = ProviderContainer(
    overrides: [
      squareEnforcementsProvider.overrideWith(
        (ref) async => <Map<String, dynamic>>[],
      ),
      squareNotificationsProvider.overrideWith(
        (ref) async => <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 5,
            'post_id': 9,
            'read_at': '2026-09-17T00:00:00Z',
            'payload_json': <String, dynamic>{'action': 'LIKE'},
          },
        ],
      ),
      squareNotificationPreferencesProvider.overrideWith(
        (ref) async => <String, dynamic>{
          'interactionEnabled': false,
          'mentionEnabled': false,
          'socialEnabled': false,
        },
      ),
      featureFlagProvider.overrideWith((ref, name) => open),
    ],
  );
  final router = GoRouter(
    initialLocation: '/governance',
    routes: <RouteBase>[
      GoRoute(
        path: '/governance',
        builder: (_, _) => const SquareGovernancePage(),
      ),
      _squareDetailRoute(),
    ],
  );
  await _pump(tester, container, router, viewport: const Size(390, 1200));
  return router;
}

/// 关态断言:提示已在、路由没动、详情没渲染。收尾隐藏提示,清掉它的计时器。
Future<void> _expectClosedNotice(
  WidgetTester tester,
  GoRouter router, {
  required String location,
}) async {
  expect(find.textContaining(_closedNotice), findsOneWidget);
  expect(router.state.matchedLocation, location);
  expect(find.text('SQUARE-9'), findsNothing);
  CyNativeNotice.hide();
  await tester.pump();
}

void main() {
  tearDown(CyNativeNotice.hide);

  testWidgets('关态:我的发布点击只提示,不进详情', (WidgetTester tester) async {
    final router = await _pumpOwnProfile(tester, open: false);

    await tester.tap(find.text('推文'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('城市散步日记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await _expectClosedNotice(tester, router, location: '/profile');
  });

  testWidgets('负控:开态我的发布照常进详情', (WidgetTester tester) async {
    final router = await _pumpOwnProfile(tester, open: true);

    await tester.tap(find.text('推文'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('城市散步日记'));
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, '/square/9');
    expect(find.text('SQUARE-9'), findsOneWidget);
    expect(find.textContaining(_closedNotice), findsNothing);
  });

  testWidgets('关态:他人主页推文点击只提示,不进详情', (WidgetTester tester) async {
    final router = await _pumpUserProfile(tester, open: false);

    await tester.tap(find.text('城市散步日记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await _expectClosedNotice(tester, router, location: '/member');
  });

  testWidgets('负控:开态他人主页推文照常进详情', (WidgetTester tester) async {
    final router = await _pumpUserProfile(tester, open: true);

    await tester.tap(find.text('城市散步日记'));
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, '/square/9');
    expect(find.text('SQUARE-9'), findsOneWidget);
  });

  testWidgets('关态:治理通知点击只提示,不进详情', (WidgetTester tester) async {
    final router = await _pumpGovernance(tester, open: false);

    await tester.tap(find.text('有人喜欢了你的帖文'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await _expectClosedNotice(tester, router, location: '/governance');
  });

  testWidgets('负控:开态治理通知照常进详情', (WidgetTester tester) async {
    final router = await _pumpGovernance(tester, open: true);

    await tester.tap(find.text('有人喜欢了你的帖文'));
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, '/square/9');
    expect(find.text('SQUARE-9'), findsOneWidget);
  });
}
