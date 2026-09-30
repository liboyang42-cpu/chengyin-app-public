import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/auth/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fixed_auth.dart';

void main() {
  for (final choice in <String, String>{
    '玩家注册': 'player',
    '商家注册': 'merchant',
    '已有账号，登录': 'existing',
  }.entries) {
    testWidgets('${choice.key}先选择意图再展示登录渠道，不授予角色', (tester) async {
      final container = ProviderContainer(overrides: [
        authControllerProvider.overrideWith(
          () => FixedAuth(const AuthState(initialized: true)),
        ),
      ]);
      addTearDown(container.dispose);
      final router = GoRouter(initialLocation: '/login', routes: [
        GoRoute(path: '/login', builder: (context, state) =>
          LoginPage(intent: state.uri.queryParameters['intent'])),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();
      expect(find.text('玩家注册'), findsOneWidget);
      expect(find.text('商家注册'), findsOneWidget);
      expect(find.text('已有账号，登录'), findsOneWidget);
      expect(find.text('微信登录'), findsNothing);
      await tester.tap(find.text(choice.key));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.queryParameters['intent'], choice.value);
      expect(find.text('微信登录'), findsOneWidget);
      expect(find.text('手机号登录'), findsOneWidget);
      expect(container.read(authControllerProvider).user, isNull);
      await tester.tap(find.text('重新选择'));
      await tester.pumpAndSettle();
      expect(find.text('玩家注册'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
