import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/tickets/pass_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth extends AuthController {
  @override
  AuthState build() => AuthState(initialized: true,
    user: User(id: 7, nickname: '玩家', avatar: '', role: 'player'));
}

class _Api extends ActivityApi {
  _Api({this.failure}) : super(DioClient(TokenStore(const FlutterSecureStorage())));
  final Object? failure;
  @override
  Future<DynCode> issueDynamicCode(int registrationId) async {
    if (failure != null) throw failure!;
    return DynCode(code: 'A0b-I1中', expiresAt: DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch);
  }
}

void main() {
  Future<void> pump(WidgetTester tester, _Api api) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [authControllerProvider.overrideWith(_Auth.new), activityApiProvider.overrideWithValue(api)],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PassPage(registrationId: 3),
      ),
    ));
    await tester.pump();
  }

  testWidgets('English QR fallback preserves the exact manual code', (tester) async {
    await pump(tester, _Api());
    expect(find.text('Could not load the QR code. Ask the merchant to enter this code:'), findsOneWidget);
    expect(find.text('A0b-I1中'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('issuance errors preserve API detail without showing raw parser errors', (tester) async {
    await pump(tester, _Api(failure: Exception('原始服务端原因')));
    expect(find.textContaining('原始服务端原因'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await pump(tester, _Api(failure: const FormatException('内部字段缺失')));
    expect(find.textContaining('内部字段缺失'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
