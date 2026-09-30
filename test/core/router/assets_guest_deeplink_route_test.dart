// 资产域游客深链不再被路由静默弹回 /feed(#276 P1-1 / PR #379 真跑)。
//
// 机制与券域 b1-sim-coupon P1-1 / roam #208 同型:`/assets` 从
// `_loginRequiredPrefixes` 放行,页内登录门负责解释与登入口。
// 这里验证两半:路由必须把游客留在 /assets;页面短路掉注定 401 的流水请求。

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/role_provider.dart';
import 'package:chengyin_app/data/api/asset_api.dart';
import 'package:chengyin_app/feature/assets/assets_page.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/core/router/app_router.dart';
import 'package:chengyin_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _GuestAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

class _NoopAssetApi implements AssetApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> _pumpGuest(WidgetTester tester) async {
  final container = ProviderContainer(
    retry: (int _, Object _) => null,
    overrides: <dynamic>[
      authControllerProvider.overrideWith(_GuestAuth.new),
      assetApiProvider.overrideWithValue(_NoopAssetApi()),
    ].cast(),
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ChengyinApp()),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

void main() {
  testWidgets('游客 go(/assets):落在资产页登录门,不回首页', (WidgetTester tester) async {
    final container = await _pumpGuest(tester);
    container.read(appRouterProvider).go('/assets');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/assets',
      reason: '#276 P1-1 前症:游客被静默弹回 /feed,没有任何登录引导',
    );
    expect(find.byType(AssetsPage), findsOneWidget);
    expect(find.byKey(const Key('assets-login-gate')), findsOneWidget);
    expect(find.text('登录后查看资产明细'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
  });

  testWidgets('游客登录门不 watch 流水 provider:注定 401 的请求一个不发', (
    WidgetTester tester,
  ) async {
    int pointsLoads = 0;
    int balanceLoads = 0;
    int roleLoads = 0;
    final container = ProviderContainer(
      retry: (int _, Object _) => null,
      overrides: <dynamic>[
        authControllerProvider.overrideWith(_GuestAuth.new),
        assetApiProvider.overrideWithValue(_NoopAssetApi()),
        pointsListProvider.overrideWith((ref) {
          pointsLoads += 1;
          return const [];
        }),
        balanceListProvider.overrideWith((ref) {
          balanceLoads += 1;
          return const [];
        }),
        roleInfoProvider.overrideWith((ref) async {
          roleLoads += 1;
          throw UnimplementedError();
        }),
      ].cast(),
    );
    addTearDown(container.dispose);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AssetsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('assets-login-gate')), findsOneWidget);
    expect(pointsLoads, 0);
    expect(balanceLoads, 0);
    expect(roleLoads, 0, reason: '游客直达时那个必然 401 的 /api/role/info 不该发');
  });
}
