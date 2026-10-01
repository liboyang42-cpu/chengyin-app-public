import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chengyin_app/core/merchant_access_provider.dart';
import 'package:chengyin_app/data/models/merchant_application.dart';
import 'package:chengyin_app/feature/merchant/merchant_home_page.dart';

import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/feature/merchant/merchant_error_view.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

Widget _host(WidgetBuilder builder, {Locale locale = const Locale('en')}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Builder(builder: builder)),
    );

void main() {
  testWidgets('English workbench localizes model states and preserves reasons', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            merchantAccessProvider.overrideWith(
              (ref) async => const MerchantAccess(
                active: false,
                merchantId: 1,
                merchantName: '店主命名',
                merchantLogo: null,
                roleCode: 'MERCHANT_OWNER',
                permissions: <String>{},
                application: MerchantApplication(
                  id: 1,
                  status: 2,
                  accountStatus: 2,
                  disableReason: '平台原始原因',
                  rejectReason: '历史驳回原因',
                ),
              ),
            ),
            merchantUnreadProvider.overrideWith((ref) async => 2),
          ],
          child: _host((_) => const MerchantHomePage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Merchant workbench'), findsOneWidget);
      expect(find.text('Account disabled'), findsOneWidget);
      expect(find.text('View application progress'), findsOneWidget);
      expect(find.text('店主命名'), findsOneWidget);
      expect(find.textContaining('平台原始原因'), findsOneWidget);
      expect(find.textContaining('历史驳回原因'), findsNothing);
      expect(find.bySemanticsLabel('2 unread messages'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('English network error has localized retry and action works', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      _host(
        (context) => merchantErrorView(
          context,
          DioException(requestOptions: RequestOptions(path: '/merchant')),
          onRetry: () => retries++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load Content'), findsOneWidget);
    expect(
      find.text('Network error. Check your connection and try again.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('English review state retains error triage without apply action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        (context) => merchantErrorView(
          context,
          MerchantApiException('仅启用且审核通过的商家可查看客户名册'),
          onRetry: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Merchant credentials under review'), findsOneWidget);
    expect(find.text('Apply as a merchant'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('English generic errors preserve original backend text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        (context) => merchantErrorView(
          context,
          MerchantApiException('后端原话'),
          onRetry: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load Content'), findsOneWidget);
    expect(find.text('后端原话'), findsOneWidget);
  });

  testWidgets('permission defaults follow the host locale', (tester) async {
    await tester.pumpWidget(
      _host(
        (_) => merchantDeniedView(title: 'Finance access required', onRetry: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Contact the store owner to enable access'), findsOneWidget);
    expect(find.text('Check again'), findsOneWidget);
    await tester.pumpWidget(
      _host(
        (_) => merchantDeniedView(title: '财务权限', onRetry: () {}),
        locale: const Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('请联系店主开通'), findsOneWidget);
    expect(find.text('重新确认'), findsOneWidget);
  });
}
