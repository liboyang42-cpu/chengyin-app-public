// 游客点设置 →「我走过的」:后端 401 必须变成「去登录」,不能是整屏英文异常堆栈。
//
// ★ 生产实测(2026-09-18,无 token):
//     HTTP 401 {"msg":"登录状态已失效，请重新登录","code":401}
//   而 app_router 的 `_loginRequiredPrefixes` **不含 /my-plays** —— 路由对游客开放,
//   页面又原样把 dio 异常塞进 StatusView.sub,于是整屏英文埋栈 + MDN 链接
//   (b1-sim-play 实拍 p2-my-plays)。
//
// 同时守住反面:断网 / 500 **不能**也被当成要登录,否则断网的人被反复推去登录页。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/play/my_plays_page.dart';

const String _path = '/api/play/my-completed';

DioException _http(int status, {Object? body}) => DioException(
  requestOptions: RequestOptions(path: _path),
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: _path),
    statusCode: status,
    data: body,
  ),
);

DioException _offline() => DioException(
  requestOptions: RequestOptions(path: _path),
  type: DioExceptionType.connectionError,
);

Widget _page(Object error) => ProviderScope(
  overrides: [
    myCompletedPlaysProvider.overrideWith((_) async => throw error),
  ],
  child: const MaterialApp(home: MyPlaysPage()),
);

void main() {
  testWidgets('401(游客)→ 登录引导,不画 dio 异常原文', (WidgetTester tester) async {
    await tester.pumpWidget(
      _page(
        _http(
          401,
          body: <String, dynamic>{'msg': '登录状态已失效，请重新登录', 'code': 401},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录后查看走过的路线'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.textContaining('我的参与没能加载出来'), findsNothing);
  });

  testWidgets('500 → 用后端中文原话,不画 dio 异常原文', (WidgetTester tester) async {
    await tester.pumpWidget(
      _page(_http(500, body: <String, dynamic>{'msg': '服务器开小差了'})),
    );
    await tester.pumpAndSettle();

    expect(find.text('服务器开小差了'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.text('登录后查看走过的路线'), findsNothing);
  });

  testWidgets('断网 → 通用错误态(别把断网也推去登录)', (WidgetTester tester) async {
    await tester.pumpWidget(_page(_offline()));
    await tester.pumpAndSettle();

    expect(find.text('网络开了点小差'), findsOneWidget);
    expect(find.text('登录后查看走过的路线'), findsNothing);
  });
}
