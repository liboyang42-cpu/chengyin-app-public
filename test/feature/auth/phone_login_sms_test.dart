import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/data/api/auth_api.dart';
import 'package:chengyin_app/feature/auth/phone_login_sheet.dart';

class _SmsAuthApi extends AuthApi {
  _SmsAuthApi({this.error})
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  final Object? error;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> sendSmsCode(String phone) async {
    calls += 1;
    if (error != null) throw error!;
    return <String, dynamic>{'code': 200, 'msg': '验证码已发送'};
  }
}

Widget _host(AuthApi api, {ThemeData? theme}) {
  return ProviderScope(
    overrides: <dynamic>[authApiProvider.overrideWithValue(api)].cast(),
    child: MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => CupertinoButton(
            onPressed: () => showPhoneLoginSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openAndEnterPhone(WidgetTester tester, AuthApi api) async {
  await tester.pumpWidget(_host(api));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(CupertinoTextField).first, '13800138000');
}

double _contrast(Color foreground, Color background) {
  final double lighter = foreground.computeLuminance() + 0.05;
  final double darker = background.computeLuminance() + 0.05;
  return lighter > darker ? lighter / darker : darker / lighter;
}

void main() {
  testWidgets('iOS 登录表单接入系统手机号与短信验证码自动填充', (WidgetTester tester) async {
    await _openAndEnterPhone(tester, _SmsAuthApi());

    expect(find.byType(AutofillGroup), findsOneWidget);
    final List<CupertinoTextField> fields = tester
        .widgetList<CupertinoTextField>(find.byType(CupertinoTextField))
        .toList();
    expect(fields[0].autofillHints, contains(AutofillHints.telephoneNumber));
    expect(fields[1].autofillHints, contains(AutofillHints.oneTimeCode));
  });

  testWidgets(
    'SMS failure shows the backend channel error and never fake-successes',
    (WidgetTester tester) async {
      final _SmsAuthApi api = _SmsAuthApi(error: Exception('短信服务未配置'));
      await _openAndEnterPhone(tester, api);

      await tester.tap(find.text('获取验证码'));
      await tester.pump();

      expect(api.calls, 1);
      expect(find.text('短信服务未配置'), findsOneWidget);
      expect(find.text('验证码已发送'), findsNothing);
    },
  );

  testWidgets('SMS success is acknowledged and stale pending copy is gone', (
    WidgetTester tester,
  ) async {
    final _SmsAuthApi api = _SmsAuthApi();
    await _openAndEnterPhone(tester, api);

    expect(find.text('短信验证码功能即将开放'), findsNothing);
    expect(find.text('验证码 5 分钟内有效'), findsOneWidget);

    await tester.tap(find.text('获取验证码'));
    await tester.pump();
    expect(find.text('验证码已发送'), findsOneWidget);
  });

  testWidgets('浅色模式登录反馈文字对比度不低于 4.5:1', (WidgetTester tester) async {
    final _SmsAuthApi api = _SmsAuthApi(error: Exception('短信服务未配置'));
    await tester.pumpWidget(_host(api, theme: AppTheme.merchantLight()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(CupertinoTextField).first,
      '13800138000',
    );
    await tester.tap(find.text('获取验证码'));
    await tester.pump();

    final Text feedback = tester.widget<Text>(
      find.byKey(const Key('phone-login-feedback')),
    );
    expect(
      _contrast(feedback.style!.color!, Colors.white),
      greaterThanOrEqualTo(4.5),
    );
  });
}
