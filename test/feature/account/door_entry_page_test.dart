import 'dart:async';

// 门口码落地页行为测(gap-spec-player #1):冷启动 `?scene` 分流、
// `?inviter` 归因补发、失败回落到首页并给出后端原文。
// 宿主用桩路由,只钉「/door 该去哪」,不拉起真 /play、/topic 页。
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/router/door_entry.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/data/models/scan_entry.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/account/door_entry_page.dart';
import 'package:chengyin_app/feature/account/inviter_cold_start.dart';
import 'package:chengyin_app/feature/account/pending_inviter.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fixed_auth.dart';

const String _code = '0123456789abcdef0123456789abcdef';

class _SwitchableAuth extends AuthController {
  @override
  AuthState build() => _player(42);
  void switchTo(int id) => state = _player(id);
}

class _FakePlayApi implements PlayApi {
  _FakePlayApi(this._result, [this._error]);
  final ScanEntryResult? _result;
  final Object? _error;
  final List<String> codes = <String>[];

  @override
  Future<ScanEntryResult> scanEntry(String code) async {
    codes.add(code);
    final Object? error = _error;
    if (error != null) throw error;
    return _result!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DeferredPlayApi implements PlayApi {
  final List<Completer<ScanEntryResult>> requests =
      <Completer<ScanEntryResult>>[];

  @override
  Future<ScanEntryResult> scanEntry(String code) {
    final request = Completer<ScanEntryResult>();
    requests.add(request);
    return request.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRegistrationApi implements RegistrationApi {
  final List<String> bound = <String>[];

  @override
  Future<void> setInviter(String inviterId) async => bound.add(inviterId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInviterFlags implements InviterFlagStore {
  _FakeInviterFlags({this.alreadyBound = false});
  final bool alreadyBound;
  bool marked = false;

  @override
  Future<bool> get bound async => alreadyBound;

  @override
  Future<void> markBound() async => marked = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AuthState _player(int id) => AuthState(
  initialized: true,
  user: User(id: id, nickname: '我', avatar: '', role: 'player'),
);

Future<GoRouter> _pump(
  WidgetTester tester, {
  required String initialLocation,
  required List<dynamic> overrides,
}) async {
  final memory = <String, String>{};
  final container = ProviderContainer(overrides: [
    ...overrides.cast(),
    pendingInviterProvider.overrideWith((ref) => PendingInviter(
      read: (key) async {
        if (key.startsWith('has_inviter_v1_')) {
          return await ref.read(inviterFlagStoreProvider).bound ? '1' : null;
        }
        return memory[key];
      },
      write: (key, value) async {
        memory[key] = value;
        if (key.startsWith('has_inviter_v1_')) {
          await ref.read(inviterFlagStoreProvider).markBound();
        }
      },
      remove: (key) async { memory.remove(key); },
      currentUserId: () => ref.read(authControllerProvider).user?.id,
      bind: (id) => ref.read(registrationApiProvider).setInviter(id),
    )),
  ]);
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: '/door',
        builder: (context, state) => DoorEntryPage(
          scene: state.uri.queryParameters['scene'],
          inviterId: readInviterId(state.uri.queryParameters),
        ),
      ),
      GoRoute(
        path: '/play/:activityId',
        builder: (context, state) => Text(
          'play:${state.pathParameters['activityId']}'
          '?topicId=${state.uri.queryParameters['topicId']}',
        ),
      ),
      GoRoute(
        path: '/topic/:id',
        builder: (context, state) =>
            Text('topic:${state.pathParameters['id']}'),
      ),
      GoRoute(path: '/feed', builder: (context, state) => const Text('home')),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('same code response from prior account cannot navigate current account', (tester) async {
    final auth = _SwitchableAuth();
    final play = _DeferredPlayApi();
    final router = await _pump(tester,
      initialLocation: '/door?scene=$_code',
      overrides: <Object>[
        authControllerProvider.overrideWith(() => auth),
        playApiProvider.overrideWithValue(play),
      ],
    );
    expect(play.requests, hasLength(1));
    auth.switchTo(43);
    await tester.pumpAndSettle();
    expect(play.requests, hasLength(2));
    play.requests[0].complete(const ScanEntryResult(action: 'purchase', topicId: 5));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/door');
    expect(find.text('topic:5'), findsNothing);
    play.requests[1].complete(const ScanEntryResult(action: 'purchase', topicId: 8));
    await tester.pumpAndSettle();
    expect(find.text('topic:8'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('离开未完成扫码页后同码重进,新请求完成正常导航', (tester) async {
    final play = _DeferredPlayApi();
    final router = await _pump(
      tester,
      initialLocation: '/door?scene=$_code',
      overrides: <Object>[
        authControllerProvider.overrideWith(() => FixedAuth(_player(42))),
        playApiProvider.overrideWithValue(play),
      ],
    );
    expect(play.requests, hasLength(1));
    router.go('/feed');
    await tester.pumpAndSettle();
    router.go('/door?scene=$_code');
    await tester.pumpAndSettle();
    expect(play.requests, hasLength(2));
    play.requests[1].complete(
      const ScanEntryResult(action: 'purchase', topicId: 8),
    );
    await tester.pumpAndSettle();
    expect(find.text('topic:8'), findsOneWidget);
    play.requests[0].complete(
      const ScanEntryResult(action: 'purchase', topicId: 5),
    );
    await tester.pumpAndSettle();
    expect(find.text('topic:8'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('同页切换扫码参数时过期响应不能覆盖新码', (tester) async {
    final play = _DeferredPlayApi();
    final router = await _pump(
      tester,
      initialLocation: '/door?scene=$_code',
      overrides: <Object>[
        authControllerProvider.overrideWith(() => FixedAuth(_player(42))),
        playApiProvider.overrideWithValue(play),
      ],
    );
    router.go('/door?scene=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    await tester.pumpAndSettle();
    expect(play.requests, hasLength(2));
    play.requests[0].complete(
      const ScanEntryResult(action: 'purchase', topicId: 5),
    );
    await tester.pumpAndSettle();
    expect(find.text('topic:5'), findsNothing);
    play.requests[1].complete(
      const ScanEntryResult(action: 'purchase', topicId: 8),
    );
    await tester.pumpAndSettle();
    expect(find.text('topic:8'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('门口码 action=play 带场次:冷启动直落游玩页', (WidgetTester tester) async {
    final fake = _FakePlayApi(
      const ScanEntryResult(
        action: 'play',
        topicId: 5,
        activityId: 9,
        nodeId: 3,
      ),
    );
    await _pump(
      tester,
      initialLocation: '/door?scene=$_code',
      overrides: <Object>[
        authControllerProvider.overrideWith(() => FixedAuth(_player(42))),
        playApiProvider.overrideWithValue(fake),
      ],
    );
    expect(fake.codes, <String>[_code]);
    expect(find.text('play:9?topicId=5'), findsOneWidget);
  });

  testWidgets('门口码没报名(非 play):落主题购买页', (WidgetTester tester) async {
    final fake = _FakePlayApi(
      const ScanEntryResult(action: 'purchase', topicId: 5),
    );
    await _pump(
      tester,
      initialLocation: '/door?scene=$_code',
      overrides: <Object>[
        authControllerProvider.overrideWith(() => FixedAuth(_player(42))),
        playApiProvider.overrideWithValue(fake),
      ],
    );
    expect(find.text('topic:5'), findsOneWidget);
  });

  testWidgets('★ 门口码带 inviter 冷启动归因:分流同时补发 setInviter 并打标记', (
    WidgetTester tester,
  ) async {
    final play = _FakePlayApi(
      const ScanEntryResult(action: 'play', topicId: 5, activityId: 9),
    );
    final reg = _FakeRegistrationApi();
    final flags = _FakeInviterFlags();
    await _pump(
      tester,
      initialLocation: '/door?scene=$_code&inviter=7',
      overrides: <Object>[
        authControllerProvider.overrideWith(() => FixedAuth(_player(42))),
        playApiProvider.overrideWithValue(play),
        registrationApiProvider.overrideWithValue(reg),
        inviterFlagStoreProvider.overrideWithValue(flags),
      ],
    );
    expect(find.text('play:9?topicId=5'), findsOneWidget);
    expect(reg.bound, <String>['7']);
    expect(flags.marked, isTrue);
  });

  testWidgets('自己点自己的分享码:归因闸挡下,不发请求', (WidgetTester tester) async {
    final play = _FakePlayApi(
      const ScanEntryResult(action: 'play', topicId: 5, activityId: 9),
    );
    final reg = _FakeRegistrationApi();
    await _pump(
      tester,
      initialLocation: '/door?scene=$_code&inviter=42',
      overrides: <Object>[
        authControllerProvider.overrideWith(() => FixedAuth(_player(42))),
        playApiProvider.overrideWithValue(play),
        registrationApiProvider.overrideWithValue(reg),
        inviterFlagStoreProvider.overrideWithValue(_FakeInviterFlags()),
      ],
    );
    expect(reg.bound, isEmpty);
  });

  testWidgets('票已绑过(has_inviter):不再重复绑', (WidgetTester tester) async {
    final play = _FakePlayApi(
      const ScanEntryResult(action: 'play', topicId: 5, activityId: 9),
    );
    final reg = _FakeRegistrationApi();
    await _pump(
      tester,
      initialLocation: '/door?scene=$_code&inviter=7',
      overrides: <Object>[
        authControllerProvider.overrideWith(() => FixedAuth(_player(42))),
        playApiProvider.overrideWithValue(play),
        registrationApiProvider.overrideWithValue(reg),
        inviterFlagStoreProvider.overrideWithValue(
          _FakeInviterFlags(alreadyBound: true),
        ),
      ],
    );
    expect(reg.bound, isEmpty);
  });

  testWidgets('码解析失败:提示后端原文并回首页,不打扰第二次', (WidgetTester tester) async {
    final play = _FakePlayApi(null, PlayException('请先登录'));
    await _pump(
      tester,
      initialLocation: '/door?scene=$_code',
      overrides: <Object>[
        authControllerProvider.overrideWith(() => FixedAuth(_player(42))),
        playApiProvider.overrideWithValue(play),
      ],
    );
    expect(find.text('home'), findsOneWidget);
    expect(find.text('请先登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scene 不是 32 位 hex:根本不发 scan-entry,直接落首页', (
    WidgetTester tester,
  ) async {
    final play = _FakePlayApi(
      const ScanEntryResult(action: 'play', topicId: 5),
    );
    await _pump(
      tester,
      initialLocation: '/door?scene=hello',
      overrides: <Object>[
        authControllerProvider.overrideWith(() => FixedAuth(_player(42))),
        playApiProvider.overrideWithValue(play),
      ],
    );
    expect(play.codes, isEmpty);
    expect(find.text('home'), findsOneWidget);
  });
}
