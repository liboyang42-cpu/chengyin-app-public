// 游客打开 /my-projects 时,三个 tab(主题 / 活动 / 模板)都不能把**原始 Dio 异常**
// 糊上屏 —— 那条异常是英文的,还带 pub.dev/MDN 链接,而屏幕前面是游客和审核员。
//
// ★ 这一条来自对生产后端的实测,不是推测(B1 报告 pb-07/08/09):
//   `POST /api/project/my`、`POST /api/template/my-list` 无 token 时返回
//   {"code":401,"msg":"登录状态已失效，请重新登录"}。
//   而 /my-projects 对游客是开放的(不在 `_loginRequiredPrefixes` 里),
//   小程序那边撞不上 —— 人人都被微信静默登录,不存在"游客"。
//
// 通用错误态在这里**两头都不对**:文案是后端的"登录状态已失效"(游客从没登录过),
// 而「重试」按多少次都还是 401,是条死路。改成可恢复的登录引导。
//
// 反面同样守住:断网 / 500 **不能**也被当成要登录 —— 那会让只是没网的用户
// 被反复推去登录页,登完还是失败。
//
// 标题口径按真源(subpackageA/pages/myproject/index.wxml):
//   主题/活动面板 title="项目暂时没能加载" sub=<后端 msg,兜底「项目加载失败，请稍后重试」>;
//   模板面板 title=<后端 msg,兜底「节点玩法加载失败」> sub=""。两格本就不同,不硬拉平。

import 'package:chengyin_app/data/models/my_project.dart';
import 'package:chengyin_app/data/models/template.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/core/network/provider_retry.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/publish/my_projects_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _http(int status, {String? msg}) => DioException(
  requestOptions: RequestOptions(path: '/api/project/my'),
  response: Response<Map<String, dynamic>>(
    requestOptions: RequestOptions(path: '/api/project/my'),
    statusCode: status,
    data: msg == null ? null : <String, dynamic>{'code': status, 'msg': msg},
  ),
);

DioException _offline() => DioException(
  requestOptions: RequestOptions(path: '/api/project/my'),
  type: DioExceptionType.connectionError,
);

MyProject _project({required int id, required String title}) =>
    MyProject.fromJson(<String, dynamic>{
      'id': id,
      'bizType': 'topic',
      'title': title,
      'state': 'draft',
      'stateText': '草稿',
      'ownerType': 'member',
    });

/// 已经登录(但服务端会话可能已失效)。用来验证「去登录」登录成功后就地重取。
class _LoggedIn extends AuthController {
  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 1, nickname: '我', avatar: '', role: 'player'),
  );
}

Widget _app({
  required Future<List<MyProject>> Function() projects,
  required Future<List<PlayTemplate>> Function() templates,
  AuthController Function()? auth,
}) {
  return ProviderScope(
    // 与 lib/main.dart 同一套重试策略:Riverpod 3 默认会把失败的 provider
    // 自动重试 10 次(30 秒),4xx/5xx 这种服务端明确答复不该重试 ——
    // 否则错误态要转圈半分钟才出来,401 也会被反复重打。
    retry: chengyinRetry,
    // 不写 List<Override> 的显式类型:Riverpod 3 把它导出在另一处,
    // 这里靠推断即可(与 test/feature/activity/detail_unauthorized_test.dart 一致)。
    overrides: <dynamic>[
      myProjectsProvider.overrideWith((_) => projects()),
      myProjectTemplatesProvider.overrideWith((_) => templates()),
      if (auth != null) authControllerProvider.overrideWith(auth),
    ].cast(),
    child: const MaterialApp(home: MyProjectsPage(liquidGlassSupported: false)),
  );
}

void main() {
  testWidgets('三个 tab 的游客 401 都是登录引导(不吐异常原文、不重复发请求)', (
    WidgetTester tester,
  ) async {
    int projectCalls = 0;
    int templateCalls = 0;
    await tester.pumpWidget(
      _app(
        projects: () async {
          projectCalls += 1;
          throw _http(401, msg: '登录状态已失效，请重新登录');
        },
        templates: () async {
          templateCalls += 1;
          throw _http(401, msg: '登录状态已失效，请重新登录');
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录后查看我的项目'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.textContaining('http'), findsNothing);

    // 活动与主题共用同一个 provider:切过去不该再发一次请求。
    await tester.tap(find.text('活动'));
    await tester.pumpAndSettle();
    expect(find.text('登录后查看我的项目'), findsOneWidget);
    expect(projectCalls, 1);

    await tester.tap(find.text('模板'));
    await tester.pumpAndSettle();
    expect(find.text('登录后查看节点玩法'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
    expect(templateCalls, 1);

    // 停在错误态不会自己反复重发。
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(projectCalls, 1);
    expect(templateCalls, 1);
  });

  testWidgets('登录成功后点「去登录」就地重取', (WidgetTester tester) async {
    int projectCalls = 0;
    await tester.pumpWidget(
      _app(
        auth: _LoggedIn.new,
        projects: () async {
          projectCalls += 1;
          if (projectCalls == 1) throw _http(401);
          return <MyProject>[_project(id: 1, title: '路线草稿')];
        },
        templates: () async => const <PlayTemplate>[],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('登录后查看我的项目'), findsOneWidget);

    await tester.tap(find.text('去登录'));
    await tester.pumpAndSettle();

    expect(projectCalls, 2);
    expect(find.text('路线草稿'), findsOneWidget);
    expect(find.text('登录后查看我的项目'), findsNothing);
  });

  testWidgets('断网 / 500 / 非 Dio 异常都走通用错误态,不推去登录', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        projects: () async => throw _http(500, msg: '系统开小差了，请稍后重试'),
        templates: () async => throw _offline(),
      ),
    );
    await tester.pumpAndSettle();

    // 主题/活动:真源标题 + 后端中文 msg 兜到 sub。
    expect(find.text('项目暂时没能加载'), findsOneWidget);
    expect(find.text('系统开小差了，请稍后重试'), findsOneWidget);
    expect(find.text('去登录'), findsNothing);

    await tester.tap(find.text('模板'));
    await tester.pumpAndSettle();
    // 模板:真源那一格 sub 为空,断网没有 msg 可给。
    expect(find.text('节点玩法加载失败'), findsOneWidget);
    expect(find.text('去登录'), findsNothing);
    expect(find.textContaining('DioException'), findsNothing);
  });

  testWidgets('500 但没有可用的后端 msg 时退回真源兜底,不吐异常原文', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        projects: () async => throw _http(500),
        templates: () async => throw _http(500, msg: 'https://pub.dev/x'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('项目加载失败，请稍后重试'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);

    await tester.tap(find.text('模板'));
    await tester.pumpAndSettle();
    // 带链接的 msg 属于诊断原文,照样不许上屏。
    expect(find.text('节点玩法加载失败'), findsOneWidget);
    expect(find.textContaining('pub.dev'), findsNothing);
  });
}
