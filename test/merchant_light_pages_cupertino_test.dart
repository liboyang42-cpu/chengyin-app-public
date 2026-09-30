// 门禁:三个**页面级**商家浅色域(club / profile / template)必须跟路由层一样,
// Material `Theme` 与 Cupertino `CupertinoTheme` **两套一起换**。
//
// 为什么必须有这道闸:浅色域只包 Material `Theme` 是**不够的** ——
// `ThemeData.cupertinoOverrideTheme` 在 `CupertinoApp` 下不生效:Material
// `Theme.build` 只要发现祖先已有 CupertinoTheme(`lib/main.dart` 的根
// `CupertinoApp.router` 就是),就把**祖先那份数据**原样转发布出去
// (framework `material/theme.dart` `_inheritedCupertinoThemeData`),自己那份
// override 被丢掉。于是商家视角下这三页 Material 侧是浅的、Cupertino 侧仍是根暗色:
//   · `CupertinoButton` 前景取 `CupertinoTheme.primaryColor`(club 页多处);
//   · 没显式给底色的 `CupertinoPageScaffold` / `CupertinoNavigationBar` 取
//     `scaffoldBackgroundColor` / `barBackgroundColor`。
// 实测症状:B1 报告 P1 的商家域导航标题「白字压浅底」≈1.1:1。
//
// 路由层的三处包装器由 PR #198 收口;这三页是**页面内**按角色切浅色
// (同一条路由玩家看到暗色、商家看到浅色),不在路由层覆盖范围内,所以单独锁。
//
// ★ 断言的是**真根 `ChengyinApp` 树下渲出来的** CupertinoTheme 取值,不是
//   「包没包一层」—— 源码 grep 门禁(`merchant_routes_are_light_test.dart`)
//   对这条 bug 恒绿。
// 负控:把任一处 `CupertinoTheme(` 去掉(或只回退成 Material `Theme`),
//   本测试必须红(Brightness.dark / 导航标题亮度 > 0.5)。

import 'package:chengyin_app/core/router/app_router.dart';
import 'package:chengyin_app/core/theme/cy_palette.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_post.dart';
import 'package:chengyin_app/data/models/profile_detail.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_feed_page.dart';
import 'package:chengyin_app/feature/club/club_list_page.dart';
import 'package:chengyin_app/feature/profile/profile_controller.dart';
import 'package:chengyin_app/feature/profile/profile_page.dart';
import 'package:chengyin_app/feature/template/template_list_page.dart';
import 'package:chengyin_app/main.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _MerchantAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 7, nickname: '滨江骑行装备专卖', avatar: '', role: 'merchant'),
  );
}

final ProfileDetail _merchantProfile = ProfileDetail(
  id: 7,
  nickname: '滨江骑行装备专卖',
  avatar: '',
  introduction: '',
  levelId: 3,
  point: 88,
  balance: 12.5,
  followNum: 2,
  fansNum: 3,
  likeNum: 4,
  topicNum: 0,
  activityNum: 0,
);

/// 在**真根** `ChengyinApp`(CupertinoApp.router + 根暗色 CupertinoTheme +
/// `builder` 里那层 Material `Theme`)下把商家视角渲染到 [route]。
///
/// [router] 只在 club 那条用例上传:见文件末尾「为啥 club 要换路由表」。
Future<ProviderContainer> _pumpMerchant(
  WidgetTester tester, {
  required String route,
  GoRouter? router,
}) async {
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  final container = ProviderContainer(
    retry: (int _, Object _) => null,
    overrides: <dynamic>[
      authControllerProvider.overrideWith(_MerchantAuth.new),
      // 不给替身的话 detail / home / feed 会真发请求,页面停在 loading,
      // 这道闸就退化成「找不到页面」而不是「颜色不对」。
      profileDetailProvider.overrideWith((_) async => _merchantProfile),
      clubHomeProvider.overrideWith(
        (_) async => const ClubHome(
          owned: <Club>[],
          joined: <Club>[],
          nearby: <Club>[],
          events: <ClubHomeEvent>[],
        ),
      ),
      clubFeedProvider.overrideWith((_) async => const ClubFeed()),
      if (router != null) appRouterProvider.overrideWithValue(router),
    ].cast(),
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ChengyinApp()),
  );
  container.read(appRouterProvider).go(route);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

/// 从 [pageType] **内部**(那层浅色包装之后)回读 CupertinoTheme 的实际取值。
/// 页面内容(Scaffold)一定在包装层里面 —— 拿它的 context 才是「这一页渲成了什么」,
/// 而不是「根主题是什么」。
void _expectLightCupertino(
  WidgetTester tester, {
  required Type pageType,
  required String where,
}) {
  final Finder scopes = find.descendant(
    of: find.byType(pageType),
    matching: find.byType(Scaffold),
  );
  expect(scopes, findsWidgets, reason: '$where 没渲出 $pageType 的内容');
  final BuildContext context = tester.element(scopes.first);
  final CupertinoThemeData cupertino = CupertinoTheme.of(context);

  expect(
    cupertino.brightness,
    Brightness.light,
    reason: '$where 拿到根暗色 CupertinoTheme ⇒ 深色前景压在浅底上',
  );
  expect(
    cupertino.scaffoldBackgroundColor,
    CyPalette.light.bgPage,
    reason: '$where 没显式给底色的 CupertinoPageScaffold 会落到这里',
  );
  expect(
    cupertino.barBackgroundColor,
    CyPalette.light.bgPage,
    reason: '$where 的 Cupertino 导航栏底色必须跟商家浅色页底一致',
  );
  expect(
    cupertino.primaryColor,
    CyPalette.light.textPrimary,
    reason: '$where 的 CupertinoButton 前景色取的就是 primaryColor(改前是根暗色的浅色值)',
  );
  final Color navTitle = CupertinoDynamicColor.resolve(
    cupertino.textTheme.navTitleTextStyle.color!,
    context,
  );
  expect(
    navTitle.computeLuminance(),
    lessThan(0.5),
    reason: '$where 的 Cupertino 导航标题必须是深字(改前取根暗色 = 浅字压浅底)',
  );
}

/// 真 app 树会打接口,收尾把挂起的定时器排空(写法同
/// mini_carrier_runtime_smoke_test.dart),否则 teardown 报 "Timer is still pending"。
Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  testWidgets('商家视角 /profile 在浅色 Cupertino 主题里', (WidgetTester tester) async {
    final container = await _pumpMerchant(tester, route: '/profile');
    // 商家根页被重定向到商家落点,同一个 `ProfilePage` 类的另一份实例 ——
    // 浅色包装在**页面内**,这一行把「确实落在商家落点」钉住。
    expect(
      container
          .read(appRouterProvider)
          .routeInformationProvider
          .value
          .uri
          .toString(),
      '/merchant/profile',
    );
    _expectLightCupertino(
      tester,
      pageType: ProfileRootView,
      where: '商家视角 /profile',
    );
    await _drain(tester);
  });

  testWidgets('商家视角 /template-square 在浅色 Cupertino 主题里', (
    WidgetTester tester,
  ) async {
    final container = await _pumpMerchant(tester, route: '/template-square');
    expect(
      container
          .read(appRouterProvider)
          .routeInformationProvider
          .value
          .uri
          .toString(),
      '/merchant/templates',
    );
    _expectLightCupertino(
      tester,
      pageType: TemplateListPage,
      where: '商家视角 /template-square',
    );
    await _drain(tester);
  });

  testWidgets('商家视角 club 根页在浅色 Cupertino 主题里', (WidgetTester tester) async {
    // ★ 为啥 club 这条要换路由表:`/clubs` 在商家视角被 `_merchantRootRedirects`
    //   (app_router.dart)整条送去 `/merchant/relations`,所以 `ClubListPage` 里
    //   `isMerchantViewer: true` 那一支在**真路由下到不了**。这里只换路由表,
    //   把真 `ClubListPage` 挂到真根 `ChengyinApp` 下 —— 根主题、Material `Theme`
    //   的发布链、页面自己的包装层全是真的,只有「怎么走到这一页」是替身。
    //   上面 `商家视角 /clubs 被重定向` 那条把这个前提也钉住了。
    final GoRouter router = GoRouter(
      initialLocation: '/clubs',
      routes: <RouteBase>[
        GoRoute(path: '/clubs', builder: (_, _) => const ClubListPage()),
      ],
    );
    addTearDown(router.dispose);
    await _pumpMerchant(tester, route: '/clubs', router: router);
    _expectLightCupertino(
      tester,
      pageType: ClubListPage,
      where: '商家视角 /clubs(页面级商家分支)',
    );
    await _drain(tester);
  });

  testWidgets('商家视角 /clubs 被重定向 —— club 页面级分支在真路由下不可达', (
    WidgetTester tester,
  ) async {
    final container = await _pumpMerchant(tester, route: '/clubs');
    expect(
      container
          .read(appRouterProvider)
          .routeInformationProvider
          .value
          .uri
          .toString(),
      '/merchant/relations',
    );
    // 页面级那一支不是「到不了就白改」:它是 `ClubRootView` 的公开 seam,
    // 路由表一旦不再兜这一跳,商家就会直接落在这页上。上一条用例锁的就是它。
    expect(find.byType(ClubListPage), findsNothing);
    await _drain(tester);
  });
}
