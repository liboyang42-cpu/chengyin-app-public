// 券域三条游客深链不再被路由静默弹回首页(b1-sim-coupon P1-1)。
//
// 机制与 roam #208 / 商家团队邀请门同型:`/coupons`、`/coupon/:id/code`、
// `/merchant/coupons` 从 `_loginRequiredPrefixes` 放行,页内登录门负责解释
// 与登入口。这里验证的是**路由那一半**:三条深链游客态必须落在券域页上。

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/router/app_router.dart';
import 'package:chengyin_app/core/router/route_paths.dart';
import 'package:chengyin_app/data/api/coupon_api.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/coupon/coupon_code_page.dart';
import 'package:chengyin_app/feature/coupon/my_coupons_page.dart';
import 'package:chengyin_app/feature/coupon/my_published_coupons_page.dart';
import 'package:chengyin_app/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _GuestAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

class _NoopApi implements CouponApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> _pumpGuest(WidgetTester tester) async {
  final container = ProviderContainer(
    retry: (int _, Object _) => null,
    overrides: <dynamic>[
      authControllerProvider.overrideWith(_GuestAuth.new),
      couponApiProvider.overrideWithValue(_NoopApi()),
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
  testWidgets('游客 go(/coupons):落在券包登录门,不回首页', (WidgetTester tester) async {
    final container = await _pumpGuest(tester);
    container.read(appRouterProvider).go('/coupons');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/coupons',
    );
    expect(find.byType(MyCouponsPage), findsOneWidget);
    expect(find.text('登录后查看优惠券'), findsOneWidget);
  });

  testWidgets('游客 go(/coupon/123/code):落在券码登录门,不回首页', (
    WidgetTester tester,
  ) async {
    final container = await _pumpGuest(tester);
    container.read(appRouterProvider).go('/coupon/123/code');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/coupon/123/code',
    );
    expect(find.byType(CouponCodePage), findsOneWidget);
    expect(find.text('登录后查看核销码'), findsOneWidget);
  });

  testWidgets('游客 go(/merchant/coupons):落在我发布的券登录门,不回首页', (
    WidgetTester tester,
  ) async {
    final container = await _pumpGuest(tester);
    container.read(appRouterProvider).go('/merchant/coupons');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/merchant/coupons',
    );
    expect(find.byType(MyPublishedCouponsPage), findsOneWidget);
    expect(find.text('登录后查看我发布的券'), findsOneWidget);
  });

  testWidgets('对照:/points(积分)仍按整前缀拦回首页 —— 本线只放行券域', (
    WidgetTester tester,
  ) async {
    final container = await _pumpGuest(tester);
    container.read(appRouterProvider).go('/points');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      kHomeRoute,
    );
  });
}
