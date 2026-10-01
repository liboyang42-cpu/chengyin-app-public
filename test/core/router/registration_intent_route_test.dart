import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/core/merchant_access_provider.dart';
import 'package:chengyin_app/core/router/app_router.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/merchant/merchant_home_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
  void signIn(String role) => state = AuthState(initialized: true,
    user: User(id: 42, nickname: 'Original user', avatar: '', role: role));
}

void main() {
  for (final role in ['player', 'club', 'merchant']) {
    testWidgets('merchant intent routes $role through server access without granting a role', (tester) async {
      final auth = _Auth();
      var accessReads = 0;
      final container = ProviderContainer(retry: (_, _) => null, overrides: [
        authControllerProvider.overrideWith(() => auth),
        merchantAccessProvider.overrideWith((ref) async {
          accessReads++;
          return const MerchantAccess(active: false, merchantId: null,
            merchantName: null, merchantLogo: null, roleCode: null,
            permissions: <String>{});
        }),
        merchantUnreadProvider.overrideWith((ref) async => 0),
      ]);
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      addTearDown(router.dispose);
      router.go('/login?intent=merchant');
      await tester.pumpWidget(UncontrolledProviderScope(container: container,
        child: MaterialApp.router(routerConfig: router,
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates)));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.toString(), '/login?intent=merchant');
      auth.signIn(role);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/merchant');
      expect(container.read(authControllerProvider).user!.role, role);
      expect(accessReads, 1);
      expect(find.byType(MerchantHomePage), findsOneWidget);
      expect(find.text('Apply as a merchant'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
