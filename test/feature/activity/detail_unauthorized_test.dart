// 游客点进活动详情时,后端 401 必须变成「去登录」而不是通用错误态。
//
// ★ 这条来自对生产后端的实测,不是推测:
//   `POST https://api.example.invalid/prod-api/api/activity/info` 无 token 时返回
//   {"code":401,"msg":"登录状态已失效，请重新登录"}。
//   而 app_router 的设计是让游客直接浏览(注释:「浏览类页面(地图/活动/…)」)。
//   两者对不上 —— 小程序不会撞上,因为那边人人都被微信静默登录、不存在"游客"。
//
// 通用错误态在这里是**误导**:游客从没登录过却被告知"登录状态已失效",
// 而且「重试」按多少次都还是 401 —— 是条死路,审核员正是以游客身份点进来的。
//
// 同时守住反面:网络故障**不能**也被当成要登录,否则断网的用户会被反复推去登录页。
//
// 文案「没能打开这个活动」是 2026-08-18 从「活动拉取失败(后端未连接或不存在)」改来的
// ——「后端」是内部构件名,不该出现在用户/审核员眼前(见 test/no_dev_strings_in_ui_test.dart)。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/activity/activity_controller.dart';
import 'package:chengyin_app/feature/activity/activity_detail_page.dart';

Widget _app(Object error) {
  return ProviderScope(
    // 不写 List<Override> 的显式类型:Riverpod 3 把它导出在另一处,
    // 这里靠推断即可(与 test/golden 里的写法一致)。
    overrides: <dynamic>[
      activityDetailProvider(7).overrideWith((ref) async => throw error),
    ].cast(),
    child: const MaterialApp(home: ActivityDetailPage(activityId: 7)),
  );
}

DioException _http(int status) => DioException(
  requestOptions: RequestOptions(path: '/api/activity/info'),
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: '/api/activity/info'),
    statusCode: status,
  ),
);

void main() {
  testWidgets('401 → 登录引导(不是「拉取失败」)', (WidgetTester tester) async {
    await tester.pumpWidget(_app(_http(401)));
    await tester.pumpAndSettle();

    expect(find.text('登录后查看活动详情'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    expect(find.textContaining('没能打开这个活动'), findsNothing);
  });

  testWidgets('网络故障 → 通用错误态(别把断网也推去登录)', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(
        DioException(
          requestOptions: RequestOptions(path: '/api/activity/info'),
          type: DioExceptionType.connectionError,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('没能打开这个活动'), findsOneWidget);
    expect(find.text('登录后查看活动详情'), findsNothing);
  });

  testWidgets('其它 HTTP 错误(500)也走通用错误态', (WidgetTester tester) async {
    await tester.pumpWidget(_app(_http(500)));
    await tester.pumpAndSettle();

    expect(find.textContaining('没能打开这个活动'), findsOneWidget);
    expect(find.text('登录后查看活动详情'), findsNothing);
  });
}
