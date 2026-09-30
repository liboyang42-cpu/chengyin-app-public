import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/account_api.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/settings/about_page.dart';

class _FixedAuth extends AuthController {
  _FixedAuth(this.fixed);

  final AuthState fixed;

  @override
  AuthState build() => fixed;
}

class _PlayerCodeApi extends AccountApi {
  _PlayerCodeApi({this.error, this.result})
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  final String value = 'https://cdn.example/player.png';
  final Object? error;
  final Future<String>? result;
  int calls = 0;

  @override
  Future<String> playerCode() async {
    calls += 1;
    if (error != null) throw error!;
    if (result != null) return result!;
    return value;
  }
}

Widget _app({required AuthState auth, required AccountApi api}) {
  return ProviderScope(
    overrides: <dynamic>[
      authControllerProvider.overrideWith(() => _FixedAuth(auth)),
      accountApiProvider.overrideWithValue(api),
    ].cast(),
    child: const MaterialApp(home: AboutPage()),
  );
}

AuthState _loggedIn() => AuthState(
  user: User(id: 7, nickname: '玩家', avatar: '', role: 'player'),
  initialized: true,
);

void main() {
  testWidgets('guest sees login gate and never requests a player code', (
    WidgetTester tester,
  ) async {
    final _PlayerCodeApi api = _PlayerCodeApi();
    await tester.pumpWidget(
      _app(auth: const AuthState(initialized: true), api: api),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录后查看'), findsOneWidget);
    expect(find.byKey(const Key('player-code-image')), findsNothing);
    expect(api.calls, 0);
  });

  testWidgets('logged-in failure shows backend error and a retry control', (
    WidgetTester tester,
  ) async {
    final _PlayerCodeApi api = _PlayerCodeApi(
      error: Exception('个人码生成服务繁忙，请稍后重试'),
    );
    await tester.pumpWidget(_app(auth: _loggedIn(), api: api));
    await tester.pumpAndSettle();

    expect(find.text('个人码生成服务繁忙，请稍后重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(api.calls, 1);
  });

  testWidgets('logged-in request shows native loading feedback', (
    WidgetTester tester,
  ) async {
    final Completer<String> pending = Completer<String>();
    final _PlayerCodeApi api = _PlayerCodeApi(result: pending.future);
    await tester.pumpWidget(_app(auth: _loggedIn(), api: api));
    await tester.pump();

    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(api.calls, 1);

    pending.complete('https://cdn.example/player.png');
    await tester.pump();
  });

  testWidgets('logged-in user sees the real image and can refresh it', (
    WidgetTester tester,
  ) async {
    final _PlayerCodeApi api = _PlayerCodeApi();
    await tester.pumpWidget(_app(auth: _loggedIn(), api: api));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('player-code-image')), findsOneWidget);
    expect(find.text('刷新身份码'), findsOneWidget);
    expect(api.calls, 1);

    await tester.tap(find.text('刷新身份码'));
    await tester.pump();
    await tester.pump();
    expect(api.calls, 2);
  });
}
