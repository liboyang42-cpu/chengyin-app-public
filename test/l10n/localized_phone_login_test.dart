import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/auth_api.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/auth/phone_login_sheet.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixed_auth.dart';

class _SmsApi extends AuthApi {
  _SmsApi() : super(DioClient(TokenStore(const FlutterSecureStorage())));
  int calls = 0;
  @override
  Future<Map<String, dynamic>> sendSmsCode(String phone) async {
    calls++;
    throw Exception('短信服务未配置');
  }
}

void main() {
  testWidgets('English SMS form keeps validation and server failure distinct', (tester) async {
    final api = _SmsApi();
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => FixedAuth(guestAuthState)),
        authApiProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(body: SingleChildScrollView(
          child: CyPhoneLoginView(onLoggedIn: () {}),
        )),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Get code'));
    await tester.tap(find.text('Get code'));
    await tester.pump();
    expect(api.calls, 0);
    expect(find.text('Enter an 11-digit phone number'), findsWidgets);
    await tester.enterText(find.byType(CupertinoTextField).first, '13800138000');
    await tester.ensureVisible(find.text('Get code'));
    await tester.tap(find.text('Get code'));
    await tester.pump();
    expect(api.calls, 1);
    expect(find.text('短信服务未配置'), findsOneWidget);
    expect(find.text('Verification code sent'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
