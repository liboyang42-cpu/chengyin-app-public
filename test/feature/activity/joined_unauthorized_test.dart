// 「我的」档游客 401 必须变成「去登录」,而不是通用错误态。
//
// ★ 生产实测(2026-09-18):
//   `POST https://api.example.invalid/prod-api/api/registration/my-joined`
//   无 token 返回 {"code":401,"msg":"登录状态已失效，请重新登录"}。
//   而 /activities 是游客可直接浏览的路由 —— 通用错误态的「重试」按多少次
//   都还是 401,是条死路。同 App 内对照:活动详情页对同类 401 已有登录门。
//
// 同时守住反面:网络故障**不能**也被当成要登录,否则断网用户被反复推去登录页。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/feature/activity/activity_controller.dart';
import 'package:chengyin_app/feature/activity/activity_list_page.dart';

import '../../golden/golden_theme.dart';

const String _path = '/api/registration/my-joined';

DioException _http(int status) => DioException(
  requestOptions: RequestOptions(path: _path),
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: _path),
    statusCode: status,
  ),
);

Future<void> _openMineTab(WidgetTester tester, Object error) async {
  await tester.pumpWidget(
    ProviderScope(
      // 不写 List<Override> 的显式类型:与 test/golden 里的写法一致。
      overrides: <dynamic>[
        activityListProvider.overrideWith((ref) async => <Activity>[]),
        myJoinedActivitiesProvider.overrideWith((ref) async => throw error),
      ].cast(),
      child: MaterialApp(
        theme: goldenTheme(),
        debugShowCheckedModeBanner: false,
        home: const ActivityListPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('我的'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('401 → 登录引导(不是「没能加载报名记录」)', (WidgetTester tester) async {
    await _openMineTab(tester, _http(401));

    expect(find.text('登录后查看报名记录'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    expect(find.textContaining('没能加载报名记录'), findsNothing);
  });

  testWidgets('「去登录」就地弹登录弹窗', (WidgetTester tester) async {
    await _openMineTab(tester, _http(401));

    await tester.tap(find.text('去登录'));
    await tester.pumpAndSettle();

    expect(find.text('登录城瘾'), findsOneWidget);
  });

  testWidgets('网络故障 → 通用错误态(别把断网也推去登录)', (WidgetTester tester) async {
    await _openMineTab(
      tester,
      DioException(
        requestOptions: RequestOptions(path: _path),
        type: DioExceptionType.connectionError,
      ),
    );

    expect(find.textContaining('没能加载报名记录'), findsOneWidget);
    expect(find.text('登录后查看报名记录'), findsNothing);
  });
}
