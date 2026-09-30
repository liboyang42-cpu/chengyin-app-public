import 'package:chengyin_app/core/router/app_router.dart';
import 'package:chengyin_app/core/router/route_paths.dart';
import 'package:chengyin_app/core/theme/cy_palette.dart';
import 'package:chengyin_app/data/api/merchant_operator_api.dart';
import 'package:chengyin_app/data/models/merchant_operator.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/merchant/merchant_operator_page.dart';
import 'package:chengyin_app/main.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MutableAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);

  void signIn() {
    state = AuthState(
      initialized: true,
      user: User(id: 7, nickname: '探索者', avatar: '', role: 'player'),
    );
  }
}

class _TeamApi implements MerchantOperatorGateway {
  @override
  Future<MerchantOperatorAccess> access() async => const MerchantOperatorAccess(
    active: false,
    merchantId: null,
    merchantName: null,
    merchantLogo: null,
    roleCode: null,
    permissions: <String>{},
    canManageOperators: false,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const String token = 'merchant-invite-token-123456';

  testWidgets('游客团队邀请保留完整深链，登录后仍以原 token 处理', (WidgetTester tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('zh')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final container = ProviderContainer(
      retry: (int _, Object _) => null,
      overrides: <dynamic>[
        authControllerProvider.overrideWith(_MutableAuth.new),
        merchantOperatorApiProvider.overrideWithValue(_TeamApi()),
      ].cast(),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ChengyinApp(),
      ),
    );
    container.read(appRouterProvider).go('/merchant/team?invite=$token');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container
          .read(appRouterProvider)
          .routeInformationProvider
          .value
          .uri
          .toString(),
      '/merchant/team?invite=$token',
    );
    expect(find.text('登录后处理团队邀请'), findsOneWidget);
    expect(find.byType(MerchantOperatorPage), findsNothing);

    await tester.tap(find.text('去登录'));
    // #213 起 showLoginSheet 先 async 探原生承载、无插件再回退 Cupertino 转场,
    // 单帧 pump 赶不上,必须 settle。
    await tester.pumpAndSettle();
    expect(find.text('登录城瘾'), findsOneWidget);
    Navigator.of(tester.element(find.text('登录城瘾'))).pop();
    await tester.pumpAndSettle();

    (container.read(authControllerProvider.notifier) as _MutableAuth).signIn();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final MerchantOperatorPage page = tester.widget<MerchantOperatorPage>(
      find.byType(MerchantOperatorPage),
    );
    expect(page.incomingInviteToken, token);
    expect(find.text('加入经营团队'), findsOneWidget);
  });

  testWidgets('普通经营团队深链对游客仍需登录', (WidgetTester tester) async {
    final container = ProviderContainer(
      retry: (int _, Object _) => null,
      overrides: <dynamic>[
        authControllerProvider.overrideWith(_MutableAuth.new),
        merchantOperatorApiProvider.overrideWithValue(_TeamApi()),
      ].cast(),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ChengyinApp(),
      ),
    );
    container.read(appRouterProvider).go('/merchant/team');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      kHomeRoute,
    );
    expect(find.byType(MerchantOperatorPage), findsNothing);
  });

  // 商家域 = **恒浅**(D10①)。而浅色只包 Material `Theme` 是**不够的** ——
  // `ThemeData.cupertinoOverrideTheme` 在 `CupertinoApp` 下是死的:Material
  // `Theme.build` 只要发现祖先已有 CupertinoTheme(`main.dart` 的根
  // `CupertinoApp.router`),就把**祖先那份数据**原样转发布出去,自己那份被丢掉
  // ⇒ `CupertinoNavigationBar` 标题、`CupertinoPageScaffold` 底色仍是根暗色。
  //
  // 这条断言的是**渲出来的颜色**,不是「包没包一层」—— 源码 grep 那道闸
  // (`merchant_routes_are_light_test.dart`)对这条 bug 恒绿,必须有测颜色的用例。
  testWidgets('★★ 商家邀请门落在**浅色** Cupertino 主题里(不是只包 Material Theme)', (
    WidgetTester tester,
  ) async {
    final container = ProviderContainer(
      retry: (int _, Object _) => null,
      overrides: <dynamic>[
        authControllerProvider.overrideWith(_MutableAuth.new),
        merchantOperatorApiProvider.overrideWithValue(_TeamApi()),
      ].cast(),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ChengyinApp(),
      ),
    );
    container.read(appRouterProvider).go('/merchant/team?invite=$token');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final BuildContext context = tester.element(find.text('登录后处理团队邀请'));
    final CupertinoThemeData cupertino = CupertinoTheme.of(context);
    expect(
      cupertino.brightness,
      Brightness.light,
      reason: '商家页拿到根暗色的 CupertinoTheme ⇒ 导航标题白字、整页黑底',
    );
    expect(
      cupertino.scaffoldBackgroundColor,
      CyPalette.light.bgPage,
      reason:
          'CupertinoPageScaffold 没给 backgroundColor 时会落到这里(2026-09-17 实拍整帧纯黑)',
    );
    expect(
      cupertino.barBackgroundColor,
      CyPalette.light.bgPage,
      reason: '导航栏底色必须跟商家浅色页底一致',
    );
    final Color title = CupertinoDynamicColor.resolve(
      cupertino.textTheme.navTitleTextStyle.color!,
      context,
    );
    expect(
      title.computeLuminance(),
      lessThan(0.5),
      reason: '导航标题实际画出来的颜色必须是深字(改前是 254 白字压 243 浅底,≈1.1:1)',
    );
  });
}
