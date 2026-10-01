import 'package:chengyin_app/l10n/app_localizations.dart';
import 'dart:ui' as ui;

import 'package:chengyin_app/feature/shell/home_shell.dart';
import 'package:chengyin_app/core/theme/cy_palette.dart';
import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

void main() {
  for (final merchant in [false, true]) {
    testWidgets('English ${merchant ? 'merchant' : 'player'} tabs update with language and keep routes', (tester) async {
      final router = merchant ? _merchantRouter() : _testRouter(liquidGlassSupported: false);
      addTearDown(router.dispose);
      Future<void> render(String language) async {
        await tester.pumpWidget(MaterialApp.router(
          routerConfig: router,
          locale: Locale(language),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
        ));
        await tester.pumpAndSettle();
      }
      await render('en');
      final expected = merchant
        ? ['Workspace', 'Marketing', 'Templates', 'Cooperation', 'Profile']
        : ['Home', 'Roam', 'Publish', 'Clubs', 'Profile'];
      final native = tester.widget<LiquidGlassTabBar>(find.byType(LiquidGlassTabBar, skipOffstage: false));
      expect(native.items.map((item) => item.label), expected);
      final fallback = tester.widget<CupertinoTabBar>(find.byType(CupertinoTabBar));
      expect(fallback.items.map((item) => item.label), expected);
      fallback.onTap!(1);
      await tester.pumpAndSettle();
      final destination = merchant ? '/merchant/marketing' : '/roam';
      expect(router.routeInformationProvider.value.uri.path, destination);
      await render('zh');
      expect(router.routeInformationProvider.value.uri.path, destination);
      final chinese = tester.widget<CupertinoTabBar>(find.byType(CupertinoTabBar));
      expect(chinese.items.first.label, merchant ? '工作台' : '首页');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Liquid Glass 五个 Tab 仍分别暴露 VoiceOver 名称与动作', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final GoRouter router = _testRouter(liquidGlassSupported: true);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    for (final String label in <String>['首页', '漫游', '发布', '俱乐部', '我的']) {
      final Finder tab = find.bySemanticsLabel(label);
      expect(
        tab,
        findsOneWidget,
        reason: '$label 在 Liquid Glass 模式下不可被 VoiceOver 找到',
      );
      final data = tester.getSemantics(tab).getSemanticsData();
      expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
      expect(tester.getSize(tab).height, greaterThanOrEqualTo(44));
    }
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('首页'))
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
    handle.dispose();
  });

  testWidgets('玩家一级导航与小程序一致:首页/漫游/发布/俱乐部/我的', (WidgetTester tester) async {
    final GoRouter router = _testRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final LiquidGlassTabBar nativeBar = tester.widget(
      find.byType(LiquidGlassTabBar, skipOffstage: false),
    );
    expect(
      nativeBar.items.map((LiquidGlassTabItem item) => item.label),
      <String>['首页', '漫游', '发布', '俱乐部', '我的'],
    );
    // N5:Tab Bar 带文字标签(真源 app.json tabBar.text)。
    expect(nativeBar.showLabels, isTrue);
    final CupertinoTabBar tabBar = tester.widget(find.byType(CupertinoTabBar));
    expect(
      tabBar.items.map((BottomNavigationBarItem item) => item.label),
      <String>['首页', '漫游', '发布', '俱乐部', '我的'],
    );
    for (final (String path, IconData icon) in <(String, IconData)>[
      ('/feed', CupertinoIcons.house_fill),
      ('/roam', CupertinoIcons.compass),
      ('/template-square', CupertinoIcons.folder),
      ('/clubs', CupertinoIcons.bubble_left_bubble_right),
      ('/profile', CupertinoIcons.person),
    ]) {
      expect(
        tester
            .widget<Icon>(
              find.descendant(
                of: find.byKey(ValueKey<String>('shell-tab-$path')),
                matching: find.byType(Icon),
              ),
            )
            .icon,
        icon,
      );
    }
    // N5 契约(二轮改):五个标签必须可见,不再是纯图标。
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('漫游'), findsOneWidget);
    expect(find.text('发布'), findsOneWidget);
    expect(find.text('俱乐部'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    for (final String label in <String>['首页', '漫游', '发布', '俱乐部', '我的']) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
  });

  testWidgets('点击五个 Tab 分别打开对应一级页面', (WidgetTester tester) async {
    final GoRouter router = _testRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    for (final (String label, String page) in <(String, String)>[
      ('首页', '首页页'),
      ('漫游', '漫游页'),
      ('发布', '发布页'),
      ('俱乐部', '俱乐部页'),
      ('我的', '我的页'),
    ]) {
      await tester.tap(find.bySemanticsLabel(label));
      await tester.pumpAndSettle();
      expect(find.text(page), findsOneWidget, reason: '$label 没有打开$page');
    }
  });

  testWidgets('只有系统 Liquid Glass Tab 才让内容延伸到底栏后方', (WidgetTester tester) async {
    final GoRouter router = _testRouter(liquidGlassSupported: true);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final Finder shellScaffold = find.ancestor(
      of: find.byType(LiquidGlassTabBar, skipOffstage: false),
      matching: find.byType(Scaffold),
    );
    expect(shellScaffold, findsOneWidget);
    expect(tester.widget<Scaffold>(shellScaffold).extendBody, isTrue);
  });

  testWidgets('Liquid Glass 壳向五个分支注入与原生底栏等高的内容避让', (WidgetTester tester) async {
    final GoRouter router = _insetRouter(liquidGlassSupported: true);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(bottom: 34)),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final BuildContext branchContext = tester.element(
      find.byKey(const Key('shell-inset-probe')),
    );
    expect(
      MediaQuery.paddingOf(branchContext).bottom,
      CyTokens.iosLiquidTabBarHeight + CyTokens.iosLiquidTabBarOverflow + 34,
    );
  });

  testWidgets('旧系统 fallback 不改变页面原有底部几何', (WidgetTester tester) async {
    final GoRouter router = _testRouter(liquidGlassSupported: false);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final Finder shellScaffold = find.ancestor(
      of: find.byType(CupertinoTabBar),
      matching: find.byType(Scaffold),
    );
    expect(shellScaffold, findsOneWidget);
    expect(tester.widget<Scaffold>(shellScaffold).extendBody, isFalse);
  });

  testWidgets('漫游运行态隐藏整个一级底栏且内容不再延伸到底栏后', (WidgetTester tester) async {
    final GoRouter router = _testRouter(
      liquidGlassSupported: true,
      bottomNavigationBarVisible: false,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.byType(LiquidGlassTabBar, skipOffstage: false), findsNothing);
    expect(find.byType(CupertinoTabBar, skipOffstage: false), findsNothing);
    final Scaffold shellScaffold = tester.widget(find.byType(Scaffold).first);
    expect(shellScaffold.bottomNavigationBar, isNull);
    expect(shellScaffold.extendBody, isFalse);
  });

  testWidgets('商家一级导航与小程序一致:工作台/营销/模板/合作/我的', (WidgetTester tester) async {
    final GoRouter router = _merchantRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final CupertinoTabBar tabBar = tester.widget(find.byType(CupertinoTabBar));
    expect(
      tabBar.items.map((BottomNavigationBarItem item) => item.label),
      <String>['工作台', '营销', '模板', '合作', '我的'],
    );

    for (final (String label, String page) in <(String, String)>[
      ('工作台', '商家工作台'),
      ('营销', '商家营销'),
      ('模板', '商家模板'),
      ('合作', '商家合作'),
      ('我的', '商家我的'),
    ]) {
      await tester.tap(find.bySemanticsLabel(label));
      await tester.pumpAndSettle();
      expect(find.text(page), findsOneWidget, reason: '$label 没有打开$page');
    }
  });

  testWidgets('商家五个 Tab 切换后保留各自页面状态', (WidgetTester tester) async {
    final GoRouter router = _merchantRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('模板'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开启商家模板页内状态'));
    await tester.pump();
    expect(find.text('商家模板页内状态已开启'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('模板'));
    await tester.pumpAndSettle();

    expect(find.text('商家模板页内状态已开启'), findsOneWidget);
  });

  testWidgets('非减少动态模式下 Tab 图标使用轻量选中过渡', (WidgetTester tester) async {
    final GoRouter router = _testRouter(liquidGlassSupported: false);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final Iterable<AnimatedScale> animations = tester.widgetList<AnimatedScale>(
      find.byType(AnimatedScale),
    );
    expect(animations, isNotEmpty);
    expect(
      animations.every(
        (AnimatedScale animation) => animation.duration > Duration.zero,
      ),
      isTrue,
    );
  });

  testWidgets('系统开启减少动态时 Tab 缩放过渡自动关闭', (WidgetTester tester) async {
    final GoRouter router = _testRouter(liquidGlassSupported: false);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final Iterable<AnimatedScale> animations = tester.widgetList<AnimatedScale>(
      find.byType(AnimatedScale),
    );
    expect(animations, isNotEmpty);
    expect(
      animations.every(
        (AnimatedScale animation) => animation.duration == Duration.zero,
      ),
      isTrue,
    );
  });

  testWidgets('Increase Contrast 下 fallback Tab 提升未选中图标与分隔线对比', (
    WidgetTester tester,
  ) async {
    final GoRouter router = _testRouter(liquidGlassSupported: false);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(highContrast: true),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final CupertinoTabBar tabBar = tester.widget(find.byType(CupertinoTabBar));
    expect(tabBar.inactiveColor, CyPalette.dark.textPrimary);
    expect(tabBar.border!.top.color, CyPalette.dark.borderStrong);
  });

  testWidgets('320x568、200% 字号下玩家与商家五 Tab 都保留 44pt 可访问入口', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final ({GoRouter router, List<String> labels}) testCase
        in <({GoRouter router, List<String> labels})>[
          (
            router: _testRouter(liquidGlassSupported: false),
            labels: <String>['首页', '漫游', '发布', '俱乐部', '我的'],
          ),
          (
            router: _merchantRouter(),
            labels: <String>['工作台', '营销', '模板', '合作', '我的'],
          ),
        ]) {
      addTearDown(testCase.router.dispose);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
            highContrast: true,
          ),
          child: MaterialApp.router(routerConfig: testCase.router),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      for (final String label in testCase.labels) {
        final Finder tab = find.bySemanticsLabel(label);
        expect(tab, findsOneWidget);
        expect(tester.getSize(tab).height, greaterThanOrEqualTo(44));
      }
    }
  });

  testWidgets('五个 Tab 切换后保留各自页面状态', (WidgetTester tester) async {
    final GoRouter router = _testRouter(liquidGlassSupported: false);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('俱乐部'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开启俱乐部页内状态'));
    await tester.pump();
    expect(find.text('俱乐部页内状态已开启'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('俱乐部'));
    await tester.pumpAndSettle();

    expect(find.text('俱乐部页内状态已开启'), findsOneWidget);
  });
}

GoRouter _testRouter({
  bool? liquidGlassSupported,
  bool bottomNavigationBarVisible = true,
}) => GoRouter(
  initialLocation: '/feed',
  routes: <RouteBase>[
    StatefulShellRoute.indexedStack(
      builder: (_, _, StatefulNavigationShell navigationShell) => HomeShell(
        liquidGlassSupported: liquidGlassSupported,
        bottomNavigationBarVisible: bottomNavigationBarVisible,
        navigationShell: navigationShell,
        child: navigationShell,
      ),
      branches: <StatefulShellBranch>[
        StatefulShellBranch(routes: <RouteBase>[_root('/feed', '首页页')]),
        StatefulShellBranch(routes: <RouteBase>[_root('/roam', '漫游页')]),
        StatefulShellBranch(
          routes: <RouteBase>[_root('/template-square', '发布页')],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/clubs',
              builder: (_, _) => const _StatefulClubMarker(),
            ),
          ],
        ),
        StatefulShellBranch(routes: <RouteBase>[_root('/profile', '我的页')]),
      ],
    ),
  ],
);

GoRouter _merchantRouter() => GoRouter(
  initialLocation: '/merchant',
  routes: <RouteBase>[
    StatefulShellRoute.indexedStack(
      builder: (_, _, StatefulNavigationShell navigationShell) =>
          MerchantHomeShell(
            navigationShell: navigationShell,
            child: navigationShell,
          ),
      branches: <StatefulShellBranch>[
        StatefulShellBranch(routes: <RouteBase>[_root('/merchant', '商家工作台')]),
        StatefulShellBranch(
          routes: <RouteBase>[_root('/merchant/marketing', '商家营销')],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/merchant/templates',
              builder: (_, _) => const _StatefulMerchantTemplateMarker(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[_root('/merchant/relations', '商家合作')],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[_root('/merchant/profile', '商家我的')],
        ),
      ],
    ),
  ],
);

GoRouter _insetRouter({required bool liquidGlassSupported}) => GoRouter(
  initialLocation: '/feed',
  routes: <RouteBase>[
    StatefulShellRoute.indexedStack(
      builder: (_, _, StatefulNavigationShell navigationShell) => HomeShell(
        liquidGlassSupported: liquidGlassSupported,
        navigationShell: navigationShell,
        child: navigationShell,
      ),
      branches: <StatefulShellBranch>[
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/feed',
              builder: (_, _) =>
                  const SizedBox(key: Key('shell-inset-probe'), height: 1),
            ),
          ],
        ),
        StatefulShellBranch(routes: <RouteBase>[_root('/roam', '漫游页')]),
        StatefulShellBranch(
          routes: <RouteBase>[_root('/template-square', '发布页')],
        ),
        StatefulShellBranch(routes: <RouteBase>[_root('/clubs', '俱乐部页')]),
        StatefulShellBranch(routes: <RouteBase>[_root('/profile', '我的页')]),
      ],
    ),
  ],
);

GoRoute _root(String path, String marker) => GoRoute(
  path: path,
  builder: (_, _) => Scaffold(body: Center(child: Text(marker))),
);

class _StatefulClubMarker extends StatefulWidget {
  const _StatefulClubMarker();

  @override
  State<_StatefulClubMarker> createState() => _StatefulClubMarkerState();
}

class _StatefulClubMarkerState extends State<_StatefulClubMarker> {
  bool enabled = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('俱乐部页'),
          CupertinoButton(
            onPressed: () => setState(() => enabled = true),
            child: Text(enabled ? '俱乐部页内状态已开启' : '开启俱乐部页内状态'),
          ),
        ],
      ),
    ),
  );
}

class _StatefulMerchantTemplateMarker extends StatefulWidget {
  const _StatefulMerchantTemplateMarker();

  @override
  State<_StatefulMerchantTemplateMarker> createState() =>
      _StatefulMerchantTemplateMarkerState();
}

class _StatefulMerchantTemplateMarkerState
    extends State<_StatefulMerchantTemplateMarker> {
  bool enabled = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('商家模板'),
          CupertinoButton(
            onPressed: () => setState(() => enabled = true),
            child: Text(enabled ? '商家模板页内状态已开启' : '开启商家模板页内状态'),
          ),
        ],
      ),
    ),
  );
}
