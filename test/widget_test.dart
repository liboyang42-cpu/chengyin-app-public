import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/main.dart';
import 'package:chengyin_app/core/router/app_router.dart';
import 'package:chengyin_app/core/router/route_paths.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/auth/login_page.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/club/club_apply_page.dart';
import 'package:chengyin_app/feature/club/club_create_page.dart';
import 'package:chengyin_app/feature/club/club_group_code_page.dart';
import 'package:chengyin_app/feature/club/club_list_page.dart';
import 'package:chengyin_app/feature/club/club_workbench_page.dart';
import 'package:chengyin_app/feature/feed/feed_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_home_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_public_home_page.dart';
import 'package:chengyin_app/feature/profile/profile_page.dart';
import 'package:chengyin_app/feature/roam/roam_live_page.dart';
import 'package:chengyin_app/feature/template/template_list_page.dart';

class _FixedAuth extends AuthController {
  _FixedAuth(this.fixed);
  final AuthState fixed;

  @override
  AuthState build() => fixed;
}

void main() {
  // flutter_secure_storage 在测试环境无原生 channel,会让 bootstrap().read() 永久挂起。
  // 注册内存 mock,让 read/write/delete 立即返回。
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  testWidgets('启动恢复未完成时停在 splash(不误跳登录)', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: ChengyinApp()));
    await tester.pump();

    // 未调 bootstrap → initialized=false → 停在 splash,显示品牌字与 Apple 加载件
    expect(find.text('城瘾'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('微信登录'), findsNothing);
  });

  // ★ 这条断言过去写的是「无 token 恢复完成后**落到登录页**」,而实际形态早已不是
  //   整页拦截:`app_router` 的 redirect 明确让「游客与登录用户都进主页」,需要登录的
  //   动作由 `login_gate` 在**动作发生时**弹窗要(`requireLogin`)。两处注释互证是有意
  //   设计,不是 redirect 被改坏 —— 所以该改的是这条测试,不是路由。
  //   断言用页面类型而不是页面上的某句文案:文案随时会改,改文案不该让这条红。
  testWidgets('无 token 恢复完成后进主页(游客可浏览,不被踢去登录页)', (WidgetTester tester) async {
    final container = ProviderContainer();
    // 模拟启动恢复:无 token → initialized=true 且未登录
    await container.read(authControllerProvider.notifier).bootstrap();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ChengyinApp(),
      ),
    );
    // 有界 pump 让 go_router redirect 落定到一级首页。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(FeedPage), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);

    container.dispose();
  });

  testWidgets('真实路由表的五个 Tab 均落到对应一级页', (WidgetTester tester) async {
    final container = ProviderContainer();
    await container.read(authControllerProvider.notifier).bootstrap();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ChengyinApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    for (final (String label, Type pageType) in <(String, Type)>[
      ('首页', FeedPage),
      ('漫游', RoamLivePage),
      ('发布', TemplateListPage),
      ('俱乐部', ClubListPage),
      ('我的', ProfilePage),
    ]) {
      final tab = find.descendant(
        of: find.byType(CupertinoTabBar),
        matching: find.bySemanticsLabel(label),
      );
      await tester.tap(tab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(pageType), findsOneWidget, reason: '$label 落点错误');
    }

    container.dispose();
  });

  testWidgets('游客深链落到集邮册/相机/p3 成长三页时见到登录门,不被静默弹回首页', (
    WidgetTester tester,
  ) async {
    final container = ProviderContainer();
    await container.read(authControllerProvider.notifier).bootstrap();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ChengyinApp(),
      ),
    );
    await tester.pump();

    // B1 模拟器报告 P1:静默重定向让用户以为链接坏了。现在页面落地并解释,
    // 但仍不给游客看任何内容(接口请求在游客态直接不发)。
    for (final (String path, Key gate) in <(String, Key)>[
      ('/roam/stamp-camera', Key('stamp-camera-login-gate')),
      ('/roam/stamp-album', Key('stamp-album-login-gate')),
      // p3 成长域三页(REPORT-sim-p3 P1-1):原来登记在 _loginRequiredPrefixes,
      // 游客深链一律静默弹回 /feed;现在落到页内登录门。
      ('/growth', Key('growth-login-gate')),
      ('/growth/leaderboard', Key('leaderboard-login-gate')),
      ('/badges', Key('badge-wall-login-gate')),
    ]) {
      container.read(appRouterProvider).go(path);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(gate), findsOneWidget, reason: '$path 缺少登录门');
      // 停在深链本身(而不是被静默重定向回首页);FeedPage 在壳的
      // IndexedStack 里一直活着,不能用它判落点。
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        path,
        reason: '$path 仍被弹回首页',
      );
    }

    container.dispose();
  });

  testWidgets('游客深链不能绕过新建模板登录门禁', (WidgetTester tester) async {
    final container = ProviderContainer();
    await container.read(authControllerProvider.notifier).bootstrap();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ChengyinApp(),
      ),
    );
    await tester.pump();

    for (final String path in <String>['/template/new', '/template/edit']) {
      container.read(appRouterProvider).go(path);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(FeedPage), findsOneWidget, reason: '$path 未拦截游客');
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        kHomeRoute,
        reason: '$path 仍留在受保护深链',
      );
    }

    container.dispose();
  });

  testWidgets('游客可直接打开商家公开主页', (WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: <dynamic>[
        merchantPublicHomeByIdProvider(7).overrideWith(
          (ref) async => <String, dynamic>{'id': 7, 'name': '静安咖啡'},
        ),
      ].cast(),
    );
    await container.read(authControllerProvider.notifier).bootstrap();
    final router = container.read(appRouterProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ChengyinApp(),
      ),
    );
    await tester.pump();
    router.go('/merchant/public-home/7');
    await tester.pumpAndSettle();
    expect(find.byType(MerchantPublicHomePage), findsOneWidget);
    expect(find.text('静安咖啡'), findsOneWidget);
    expect(
      router.routeInformationProvider.value.uri.path,
      '/merchant/public-home/7',
    );
    container.dispose();
  });

  testWidgets('俱乐部静态二级路由不会被 :id 详情吞掉', (tester) async {
    final container = ProviderContainer();
    await container.read(authControllerProvider.notifier).bootstrap();
    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ChengyinApp(),
      ),
    );
    await tester.pump();

    for (final (String path, Type pageType) in <(String, Type)>[
      ('/club/apply', ClubApplyPage),
      ('/club/create', ClubCreatePage),
      ('/club/group-code', ClubGroupCodePage),
      ('/club/workbench', ClubWorkbenchPage),
    ]) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(
        find.byType(pageType),
        findsOneWidget,
        reason: '$path 落点错误; uri=${router.routeInformationProvider.value.uri}',
      );
    }

    container.dispose();
  });

  testWidgets('商家冷启动落到商家工作台并显示独立五根导航', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => _FixedAuth(
            AuthState(
              initialized: true,
              user: User(id: 2, nickname: '商家', avatar: '', role: 'merchant'),
            ),
          ),
        ),
        merchantDashboardProvider.overrideWith(
          (_) async => throw StateError('fixture'),
        ),
        merchantUnreadProvider.overrideWith((_) async => null),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ChengyinApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(MerchantHomePage), findsOneWidget);
    final CupertinoTabBar tabBar = tester.widget(find.byType(CupertinoTabBar));
    expect(tabBar.items.map((item) => item.label), <String>[
      '工作台',
      '营销',
      '模板',
      '合作',
      '我的',
    ]);

    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      kMerchantHomeRoute,
    );

    container.dispose();
  });

  test('真实路由解析器读取续编 id', () {
    expect(publishEditTopicId(Uri.parse('/publish/pro?id=11')), 11);
    expect(publishEditTopicId(Uri.parse('/publish/pro?topicId=11')), isNull);
  });
}
