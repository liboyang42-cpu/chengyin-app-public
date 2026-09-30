// 票域三条游客深链不再被路由静默弹回首页(b1-sim-club-2 N1)。
//
// 机制与券域 b1-sim-coupon P1-1 / roam #208 同型:`/tickets`、`/ticket/*`、
// `/participations` 从 `_loginRequiredPrefixes` 放行,页内登录门负责解释与
// 登入口。这里验证的是**路由那一半 + 门的可见性**:游客态必须落在票域页的
// 登录门上,而不是 kHomeRoute。
//
// 登录门用 StatusView key 定位(不靠文案子串顶包),文案单独断言 ——
// 「说人话、点名这是什么」回归时两样都跑不掉。

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/router/app_router.dart';
import 'package:chengyin_app/core/router/route_paths.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/participation/participation_page.dart';
import 'package:chengyin_app/feature/tickets/pass_page.dart';
import 'package:chengyin_app/feature/tickets/ticket_detail_page.dart';
import 'package:chengyin_app/feature/tickets/tickets_page.dart';
import 'package:chengyin_app/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _GuestAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

class _NoopApi implements ActivityApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> _pumpGuest(WidgetTester tester) async {
  final container = ProviderContainer(
    retry: (int _, Object _) => null,
    overrides: <dynamic>[
      authControllerProvider.overrideWith(_GuestAuth.new),
      activityApiProvider.overrideWithValue(_NoopApi()),
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
  testWidgets('游客 go(/tickets):落在票夹登录门,不回首页', (WidgetTester tester) async {
    final container = await _pumpGuest(tester);
    container.read(appRouterProvider).go('/tickets');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/tickets',
    );
    expect(find.byType(TicketsPage), findsOneWidget);
    expect(find.byKey(const Key('tickets-login-gate')), findsOneWidget);
    expect(find.text('登录后查看票夹'), findsOneWidget);
  });

  testWidgets('游客 go(/ticket/123):落在票券详情登录门,不回首页', (WidgetTester tester) async {
    final container = await _pumpGuest(tester);
    container.read(appRouterProvider).go('/ticket/123');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/ticket/123',
    );
    expect(find.byType(TicketDetailPage), findsOneWidget);
    expect(find.byKey(const Key('ticket-detail-login-gate')), findsOneWidget);
    expect(find.text('登录后查看票券详情'), findsOneWidget);
  });

  testWidgets('游客 go(/ticket/123/pass):落在出码登录门,不发签码请求', (
    WidgetTester tester,
  ) async {
    final container = await _pumpGuest(tester);
    container.read(appRouterProvider).go('/ticket/123/pass');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/ticket/123/pass',
    );
    expect(find.byType(PassPage), findsOneWidget);
    expect(find.byKey(const Key('ticket-pass-login-gate')), findsOneWidget);
    expect(find.text('登录后出示核销码'), findsOneWidget);
  });

  testWidgets('游客 go(/participations):落在我的参与登录门,不回首页', (
    WidgetTester tester,
  ) async {
    final container = await _pumpGuest(tester);
    container.read(appRouterProvider).go('/participations');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/participations',
    );
    expect(find.byType(ParticipationPage), findsOneWidget);
    expect(find.byKey(const Key('participation-login-gate')), findsOneWidget);
    expect(find.text('登录后查看我的参与'), findsOneWidget);
  });

  testWidgets('对照:/points(未收口的整页需登录域)仍兜底拦回首页', (WidgetTester tester) async {
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
