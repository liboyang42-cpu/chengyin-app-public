// 游客进「承接邀约」:后端 401 必须变成「去登录」,不是把 Dio 原始异常铺在正文里。
//
// ★ 来自模拟器实测(见 coordinator/out/b1-sim-legal.md / REPORT-sim-legal.md):
//   `GET /api/official/v2/party-inbox` 对无 token 的请求返回 401,而页面是
//   游客可达的(官方活动页有入口)。原实现 `sub: e.toString()` 把整段英文异常
//   (`DioException [bad response] ... status code of 401 ... developer.mozilla.org`)
//   渲染给用户,还把鉴权失败说成「加载失败」,「重试」按多少次都还是 401。
//
// ★ 小程序不会撞上:那边人人都被微信静默登录,不存在「游客」。
//
// 反面同样要守:网络故障**不能**被当成要登录,否则断网用户被反复推去登录。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/official/official_controller.dart';
import 'package:chengyin_app/feature/official/official_inbox_page.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';

/// 游客(已初始化、无 user)。避开真 keychain,只测页面行为。
class _GuestAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

Widget _app(Object error) {
  return ProviderScope(
    overrides: <dynamic>[
      authControllerProvider.overrideWith(_GuestAuth.new),
      partyInboxProvider.overrideWith((ref) async => throw error),
    ].cast(),
    child: const MaterialApp(home: OfficialInboxPage()),
  );
}

DioException _http(int status) => DioException(
  requestOptions: RequestOptions(path: '/api/official/v2/party-inbox'),
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: '/api/official/v2/party-inbox'),
    statusCode: status,
  ),
);

void main() {
  testWidgets('401 → 登录引导(不是「加载失败」,也没有异常原文)', (WidgetTester tester) async {
    await tester.pumpWidget(_app(_http(401)));
    await tester.pumpAndSettle();

    expect(find.text('登录后查看承接邀约'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('网络故障 → 通用错误态(别把断网也推去登录)', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(
        DioException(
          requestOptions: RequestOptions(path: '/api/official/v2/party-inbox'),
          type: DioExceptionType.connectionError,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('承接邀约没能加载出来'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('登录后查看承接邀约'), findsNothing);
  });

  testWidgets('500 也走通用错误态', (WidgetTester tester) async {
    await tester.pumpWidget(_app(_http(500)));
    await tester.pumpAndSettle();

    expect(find.text('承接邀约没能加载出来'), findsOneWidget);
    expect(find.text('登录后查看承接邀约'), findsNothing);
  });

  testWidgets('「去登录」打开登录弹窗(不是死按钮)', (WidgetTester tester) async {
    await tester.pumpWidget(_app(_http(401)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('去登录'));
    await tester.pumpAndSettle();

    expect(find.text('登录城瘾'), findsOneWidget);
  });
}
