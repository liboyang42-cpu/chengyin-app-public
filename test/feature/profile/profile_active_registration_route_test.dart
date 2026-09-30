import 'dart:async';

import 'package:chengyin_app/core/network/provider_retry.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/growth.dart';
import 'package:chengyin_app/data/models/my_project.dart';
import 'package:chengyin_app/data/models/profile_detail.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/orders/orders_page.dart';
import 'package:chengyin_app/feature/profile/profile_controller.dart';
import 'package:chengyin_app/feature/profile/profile_page.dart';
import 'package:chengyin_app/feature/publish/my_projects_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeRegistrationApi implements RegistrationApi {
  _FakeRegistrationApi(this.reply, {this.error, this.pending});

  final Map<String, dynamic>? reply;
  final Object? error;
  final Completer<Map<String, dynamic>?>? pending;
  int calls = 0;
  int? requestedMemberId;

  @override
  Future<Map<String, dynamic>?> joinInfo({int? memberId}) async {
    calls += 1;
    requestedMemberId = memberId;
    if (pending case final Completer<Map<String, dynamic>?> pending) {
      return pending.future;
    }
    if (error case final Object error) throw error;
    return reply;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixedAuth extends AuthController {
  _FixedAuth([this.role = 'player']);

  final String role;

  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 7, nickname: '探索者', avatar: '', role: role),
  );
}

class _EmptyCreatives extends MyCreativesController {
  @override
  Future<List<SquarePost>> build() async => <SquarePost>[];
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

Future<({GoRouter router, ProviderContainer container})> _pumpProfile(
  WidgetTester tester,
  _FakeRegistrationApi api, {
  String role = 'player',
  List<Club> ownedClubs = const <Club>[],
  List<MyProject> projects = const <MyProject>[],
}) async {
  final container = ProviderContainer(
    retry: chengyinRetry,
    overrides: [
      authControllerProvider.overrideWith(() => _FixedAuth(role)),
      clubMyProvider.overrideWith((_) async => ownedClubs),
      registrationApiProvider.overrideWithValue(api),
      profileDetailProvider.overrideWith((_) async => _profile),
      myOrdersProvider.overrideWith((_) async => <MyRegistration>[]),
      myProjectsProvider.overrideWith((_) async => projects),
      myCreativesProvider.overrideWith(_EmptyCreatives.new),
      growthCenterProvider.overrideWith(
        (_) async => GrowthCenter(
          levelNo: 1,
          expValue: 0,
          points: 0,
          badges: <MedalBadge>[],
          missions: <GrowthMission>[],
        ),
      ),
    ],
  );
  final router = GoRouter(
    initialLocation: '/profile',
    routes: <RouteBase>[
      ShellRoute(
        builder: (_, _, Widget child) => child,
        routes: <RouteBase>[
          GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
          GoRoute(
            path: '/roam',
            builder: (_, _) =>
                const Text('/roam', textDirection: TextDirection.ltr),
          ),
          GoRoute(
            path: '/feed',
            builder: (_, _) =>
                const Text('/feed', textDirection: TextDirection.ltr),
          ),
          GoRoute(
            path: '/club/create',
            builder: (_, _) =>
                const Text('/club/create', textDirection: TextDirection.ltr),
          ),
          GoRoute(
            path: '/club/:id',
            builder: (_, state) => Text(
              '/club/${state.pathParameters['id']}',
              textDirection: TextDirection.ltr,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/tickets',
        builder: (_, _) =>
            const Text('/tickets', textDirection: TextDirection.ltr),
      ),
    ],
  );
  addTearDown(router.dispose);
  addTearDown(container.dispose);
  await tester.binding.setSurfaceSize(const Size(390, 1100));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return (router: router, container: container);
}

void main() {
  test('我的开始探索读取本人进行中报名', () async {
    final api = _FakeRegistrationApi(<String, dynamic>{'id': 37});
    final container = ProviderContainer(
      overrides: [registrationApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    expect(await container.read(hasActiveRegistrationProvider.future), isTrue);
    expect(api.calls, 1);
    expect(api.requestedMemberId, isNull, reason: '本人查询不传 member_id');
  });

  test('报名状态网络失败保持 error，不能伪装成没有进行中报名', () async {
    final container = ProviderContainer(
      retry: chengyinRetry,
      overrides: [
        registrationApiProvider.overrideWithValue(
          _FakeRegistrationApi(<String, dynamic>{}, error: Exception('网络连接超时')),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      hasActiveRegistrationProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(hasActiveRegistrationProvider).hasError, isTrue);
    expect(container.read(hasActiveRegistrationProvider).value, isNull);
  });

  for (final (:reply, :target, :canPop)
      in <({Map<String, dynamic>? reply, String target, bool canPop})>[
        (reply: null, target: '/roam', canPop: false),
        (reply: <String, dynamic>{'id': 37}, target: '/roam', canPop: false),
      ]) {
    testWidgets('真实我的页开始探索 ${reply == null ? '无报名' : '有报名'}都进漫游且不留返回栈', (
      WidgetTester tester,
    ) async {
      final (:router, :container) = await _pumpProfile(
        tester,
        _FakeRegistrationApi(reply),
      );
      await tester.tap(find.text('开始探索'));
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, target);
      expect(router.canPop(), canPop);
      expect(container.read(hasActiveRegistrationProvider).hasError, isFalse);
    });
  }

  testWidgets('票夹是独立入口，不与开始探索合并', (WidgetTester tester) async {
    final api = _FakeRegistrationApi(<String, dynamic>{'id': 37});
    final (:router, container: _) = await _pumpProfile(tester, api);

    await tester.tap(find.text('票夹'));
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, '/tickets');
    expect(api.calls, 1);

    router.pop();
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, '/profile');
    expect(api.calls, 1);
  });

  for (final (:owned, :label, :target)
      in <({List<Club> owned, String label, String target})>[
        (
          owned: <Club>[Club(id: 23, name: '夜行者俱乐部', isOwner: true)],
          label: '俱乐部',
          target: '/club/23',
        ),
        (owned: <Club>[], label: '创建俱乐部', target: '/club/create'),
      ]) {
    testWidgets('真实我的页主理人${owned.isEmpty ? '无' : '有'} owned club 进 $target', (
      WidgetTester tester,
    ) async {
      final (:router, container: _) = await _pumpProfile(
        tester,
        _FakeRegistrationApi(null),
        role: 'club',
        ownedClubs: owned,
      );

      await tester.tap(find.text('关于'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, target);
    });
  }

  testWidgets('真实我的页报名状态 loading 时禁用开始探索', (WidgetTester tester) async {
    final pending = Completer<Map<String, dynamic>?>();
    await _pumpProfile(tester, _FakeRegistrationApi(null, pending: pending));

    final CupertinoButton button = tester.widget<CupertinoButton>(
      find.ancestor(
        of: find.text('开始探索'),
        matching: find.byType(CupertinoButton),
      ),
    );
    expect(button.onPressed, isNull);

    pending.complete(null);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CupertinoButton>(
            find.ancestor(
              of: find.text('开始探索'),
              matching: find.byType(CupertinoButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('真实我的页报名状态 error 时只重试，不跳到首页或票夹', (WidgetTester tester) async {
    final api = _FakeRegistrationApi(null, error: Exception('网络连接超时'));
    final (:router, :container) = await _pumpProfile(tester, api);
    expect(container.read(hasActiveRegistrationProvider).hasError, isTrue);

    await tester.tap(find.text('开始探索'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(router.state.matchedLocation, '/profile');
    expect(router.canPop(), isFalse);
    expect(api.calls, greaterThanOrEqualTo(2));
  });

  testWidgets('未同步类型的项目点开只轻提示不弹 alert，也不跳路由(#412 S7)', (
    WidgetTester tester,
  ) async {
    final (:router, container: _) = await _pumpProfile(
      tester,
      _FakeRegistrationApi(null),
      projects: const <MyProject>[
        MyProject(id: 61, bizType: 'unknown', title: '未同步项目'),
      ],
    );

    await tester.ensureVisible(find.text('未同步项目'));
    await tester.tap(find.text('未同步项目'));
    await tester.pumpAndSettle();

    expect(find.text('暂时无法打开这个项目：项目类型还未同步，请稍后再试。'), findsOneWidget);
    expect(
      find.byType(CupertinoAlertDialog),
      findsNothing,
      reason: '纯告知弹 alert 会被 S7 判违规 —— 页内轻提示即可',
    );
    expect(router.state.matchedLocation, '/profile');
  });
}
