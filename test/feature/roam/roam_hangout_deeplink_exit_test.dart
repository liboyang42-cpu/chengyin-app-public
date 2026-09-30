// B1 二轮报告 N2:`/roam/nearby` 冷启动深链落「无返回键、无 Tab Bar」的
// 全地图页,边缘右滑是唯一出口 —— 用户不知道的手势不算出口。
//
// 口径照小程序 merchant/profile 那条:「回首页恒在,返回按栈深出」。
// 无栈直达 → 导航栏 leading 给「回首页」;从 /roam push 进来 → 系统返回钮,
// 不重复给回首页。

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/roam_api.dart';
import 'package:chengyin_app/data/models/roam.dart';
import 'package:chengyin_app/data/models/roam_social.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/roam/roam_hangout_page.dart';
import 'package:chengyin_app/feature/roam/roam_live_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fixed_auth.dart';

class _FakeLocation implements RoamLocationSource {
  @override
  Future<RoamLivePosition> current() async =>
      const RoamLivePosition(latitude: 31.2304, longitude: 121.4737);

  @override
  Stream<RoamLivePosition> watch() => const Stream<RoamLivePosition>.empty();
}

class _FakeRoamApi extends RoamApi {
  _FakeRoamApi() : super(DioClient(TokenStore(const FlutterSecureStorage())));

  @override
  Future<RoamHangoutNearby> hangoutNearby({
    required double lat,
    required double lng,
    int radiusM = 3000,
  }) async =>
      RoamHangoutNearby(items: const <RoamHangoutItem>[], radius: radiusM);

  @override
  Future<List<RoamRunner>> nearbyRunners({
    required double lat,
    required double lng,
    int radiusM = 3000,
  }) async => const <RoamRunner>[];

  @override
  Future<List<RoamPoi>> pois({
    required double lat,
    required double lng,
    int? radiusM,
  }) async => const <RoamPoi>[];
}

Future<GoRouter> _pump(WidgetTester tester, {required bool withStack}) async {
  final GoRouter router = GoRouter(
    initialLocation: withStack ? '/roam' : '/roam/nearby',
    routes: <RouteBase>[
      GoRoute(
        path: '/roam',
        builder: (BuildContext context, GoRouterState state) => CupertinoButton(
          child: const Text('go-nearby'),
          onPressed: () => context.push('/roam/nearby'),
        ),
      ),
      GoRoute(path: '/roam/nearby', builder: (_, _) => const RoamHangoutPage()),
      GoRoute(path: '/feed', builder: (_, _) => const Text('feed-home')),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          () => FixedAuth(signedInAuthState()),
        ),
        roamApiProvider.overrideWithValue(_FakeRoamApi()),
        roamLocationSourceProvider.overrideWithValue(_FakeLocation()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  if (withStack) {
    await tester.tap(find.text('go-nearby'));
    await tester.pumpAndSettle();
  }
  return router;
}

void main() {
  testWidgets('深链直达(栈底即本页):导航栏给「回首页」,点了真回首页', (WidgetTester tester) async {
    final GoRouter router = await _pump(tester, withStack: false);

    expect(find.byKey(const Key('hangout-home-exit')), findsOneWidget);
    expect(find.text('回首页'), findsOneWidget);

    await tester.tap(find.text('回首页'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/feed');
  });

  testWidgets('从 /roam 带栈进入:只有系统返回钮,不重复给回首页', (WidgetTester tester) async {
    await _pump(tester, withStack: true);

    expect(find.byKey(const Key('hangout-home-exit')), findsNothing);
    expect(find.byType(CupertinoNavigationBarBackButton), findsOneWidget);

    await tester.tap(find.byType(CupertinoNavigationBarBackButton));
    await tester.pumpAndSettle();
    expect(find.text('go-nearby'), findsOneWidget);
  });
}
