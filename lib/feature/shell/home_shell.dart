import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

import '../../core/router/route_paths.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';

typedef _ShellTab = ({
  String path,
  String label,
  IconData icon,
  IconData activeIcon,
  String sfSymbol,
  String activeSfSymbol,
});

/// 玩家主壳:一级导航与小程序保持同样的五个入口和顺序。
class HomeShell extends StatelessWidget {
  const HomeShell({
    super.key,
    required this.child,
    this.navigationShell,
    this.liquidGlassSupported,
    this.bottomNavigationBarVisible = true,
  });
  final Widget child;
  final StatefulNavigationShell? navigationShell;
  final bool? liquidGlassSupported;
  final bool bottomNavigationBarVisible;

  static const List<_ShellTab> _tabs = <_ShellTab>[
    (
      path: kHomeRoute,
      label: '首页',
      icon: CupertinoIcons.house,
      activeIcon: CupertinoIcons.house_fill,
      sfSymbol: 'house',
      activeSfSymbol: 'house.fill',
    ),
    (
      path: kRoamRoute,
      label: '漫游',
      icon: CupertinoIcons.compass,
      activeIcon: CupertinoIcons.compass_fill,
      sfSymbol: 'safari',
      activeSfSymbol: 'safari.fill',
    ),
    (
      path: kPublishRoute,
      label: '发布',
      icon: CupertinoIcons.folder,
      activeIcon: CupertinoIcons.folder_fill,
      sfSymbol: 'folder',
      activeSfSymbol: 'folder.fill',
    ),
    (
      path: kClubsRoute,
      label: '俱乐部',
      icon: CupertinoIcons.bubble_left_bubble_right,
      activeIcon: CupertinoIcons.bubble_left_bubble_right_fill,
      sfSymbol: 'bubble.left.and.bubble.right',
      activeSfSymbol: 'bubble.left.and.bubble.right.fill',
    ),
    (
      path: kProfileRoute,
      label: '我的',
      // 真源 icon_f5/icon_f01d 为裸人形(无圆环),crop.circle 会多一枚实心圆盘。
      icon: CupertinoIcons.person,
      activeIcon: CupertinoIcons.person_fill,
      sfSymbol: 'person',
      activeSfSymbol: 'person.fill',
    ),
  ];

  @override
  Widget build(BuildContext context) => _RootShell(
    tabs: _tabs,
    liquidGlassSupported: liquidGlassSupported,
    bottomNavigationBarVisible: bottomNavigationBarVisible,
    navigationShell: navigationShell,
    child: child,
  );
}

/// 商家主壳:与小程序商家视角保持独立五个一级入口。
class MerchantHomeShell extends StatelessWidget {
  const MerchantHomeShell({
    super.key,
    required this.child,
    this.navigationShell,
  });
  final Widget child;
  final StatefulNavigationShell? navigationShell;

  static const List<_ShellTab> _tabs = <_ShellTab>[
    (
      path: '/merchant',
      label: '工作台',
      icon: CupertinoIcons.rectangle_grid_2x2,
      activeIcon: CupertinoIcons.rectangle_grid_2x2_fill,
      sfSymbol: 'rectangle.grid.2x2',
      activeSfSymbol: 'rectangle.grid.2x2.fill',
    ),
    (
      path: '/merchant/marketing',
      label: '营销',
      icon: CupertinoIcons.speaker_2,
      activeIcon: CupertinoIcons.speaker_2_fill,
      sfSymbol: 'megaphone',
      activeSfSymbol: 'megaphone.fill',
    ),
    (
      path: '/merchant/templates',
      label: '模板',
      icon: CupertinoIcons.square_stack_3d_up,
      activeIcon: CupertinoIcons.square_stack_3d_up_fill,
      sfSymbol: 'square.stack.3d.up',
      activeSfSymbol: 'square.stack.3d.up.fill',
    ),
    (
      path: '/merchant/relations',
      label: '合作',
      icon: CupertinoIcons.person_2,
      activeIcon: CupertinoIcons.person_2_fill,
      sfSymbol: 'person.2',
      activeSfSymbol: 'person.2.fill',
    ),
    (
      path: '/merchant/profile',
      label: '我的',
      // 商家侧 icon_tab_mine 同为头+肩裸人形,不带圆环。
      icon: CupertinoIcons.person,
      activeIcon: CupertinoIcons.person_fill,
      sfSymbol: 'person',
      activeSfSymbol: 'person.fill',
    ),
  ];

  @override
  Widget build(BuildContext context) =>
      _RootShell(tabs: _tabs, navigationShell: navigationShell, child: child);
}

class _RootShell extends StatelessWidget {
  const _RootShell({
    required this.child,
    required this.tabs,
    this.liquidGlassSupported,
    this.bottomNavigationBarVisible = true,
    this.navigationShell,
  });

  final Widget child;
  final List<_ShellTab> tabs;
  final bool? liquidGlassSupported;
  final bool bottomNavigationBarVisible;
  final StatefulNavigationShell? navigationShell;

  int _indexFor(String location) {
    // `/merchant` 是其余商家根路由的前缀，必须先选最长的具体匹配。
    final ordered = tabs.indexed.toList()
      ..sort((a, b) => b.$2.path.length.compareTo(a.$2.path.length));
    for (final (int index, _ShellTab tab) in ordered) {
      if (location == tab.path || location.startsWith('${tab.path}/')) {
        return index;
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    if (!bottomNavigationBarVisible) {
      return Scaffold(body: child);
    }
    final location = GoRouterState.of(context).matchedLocation;
    final index = _indexFor(location);
    final palette = CyPalette.of(context);
    final bool detectedLiquidGlass = NativeLiquidGlassUtils.supportsLiquidGlass;
    final bool supportsLiquidGlass =
        liquidGlassSupported ?? detectedLiquidGlass;
    // 真机原生 Tab 自带 UIAccessibility label/selected 状态，不再叠加
    // Flutter 透明语义层，否则 VoiceOver 会对同一个 Tab 聚焦两次。
    // Widget 测试强制开启能力时仍用 overlay 验证公开合同。
    final bool needsLiquidGlassSemanticsOverlay =
        supportsLiquidGlass &&
        !(liquidGlassSupported == null && detectedLiquidGlass);
    final double safeBottom = MediaQuery.paddingOf(context).bottom;
    // 回退栏带文字标签后,大字号档要给 label 让位(真机 UITabBar 同此行为);
    // 标准档 scale(10)=10,增量 0,几何不变。
    final double labelSlack = MediaQuery.textScalerOf(
      context,
    ).scale(10) - 10;
    final double barHeight = supportsLiquidGlass
        ? CyTokens.iosLiquidTabBarHeight +
              CyTokens.iosLiquidTabBarOverflow +
              safeBottom
        : CyTokens.iosLegacyTabBarHeight +
              (labelSlack > 0 ? labelSlack : 0) +
              safeBottom;
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final CupertinoTabBar fallback = _fallbackTabBar(
      context,
      palette,
      index,
      reduceMotion: reduceMotion,
    );
    // 布局原语例外(二轮判定):玻璃 TabBar 悬浮需 extendBody + 底栏等高
    // MediaQuery 避让,CupertinoPageScaffold 无等价物;Scaffold 非交互控件,
    // 不在 no_material_* 门禁范围(依据与测试断言见 home_shell_test.dart)。
    return Scaffold(
      extendBody: supportsLiquidGlass,
      body: child,
      bottomNavigationBar: SizedBox(
        height: barHeight,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Offstage(offstage: supportsLiquidGlass, child: fallback),
            Offstage(
              offstage: !supportsLiquidGlass,
              child: LiquidGlassTabBar(
                items: <LiquidGlassTabItem>[
                  for (final _ShellTab tab in tabs)
                    LiquidGlassTabItem(
                      label: tab.label,
                      icon: NativeLiquidGlassIcon.sfSymbol(tab.sfSymbol),
                      selectedIcon: NativeLiquidGlassIcon.sfSymbol(
                        tab.activeSfSymbol,
                      ),
                    ),
                ],
                currentIndex: index,
                onTabSelected: (int i) => _selectTab(context, index, i),
                selectedItemColor: palette.textPrimary,
                height: CyTokens.iosLiquidTabBarHeight,
                // N5:原生 UITabBar 同档带文字标签(真源 app.json tabBar.text)。
                showLabels: true,
              ),
            ),
            Offstage(
              offstage: !needsLiquidGlassSemanticsOverlay,
              child: Row(
                children: <Widget>[
                  for (final (int tabIndex, _ShellTab tab) in tabs.indexed)
                    Expanded(
                      child: Semantics(
                        key: ValueKey<String>('liquid-shell-tab-${tab.path}'),
                        container: true,
                        label: tab.label,
                        button: true,
                        selected: tabIndex == index,
                        onTap: () => _selectTab(context, index, tabIndex),
                        child: const SizedBox.expand(),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  CupertinoTabBar _fallbackTabBar(
    BuildContext context,
    CyPalette palette,
    int index, {
    required bool reduceMotion,
  }) {
    final bool increaseContrast = MediaQuery.highContrastOf(context);
    return CupertinoTabBar(
      currentIndex: index,
      activeColor: palette.textPrimary,
      inactiveColor: increaseContrast
          ? palette.textPrimary
          : palette.textSecondary,
      backgroundColor: palette.bgSurface,
      border: Border(
        top: BorderSide(
          color: increaseContrast ? palette.borderStrong : palette.borderSubtle,
        ),
      ),
      onTap: (int i) => _selectTab(context, index, i),
      items: <BottomNavigationBarItem>[
        for (final (int tabIndex, _ShellTab tab) in tabs.indexed)
          _fallbackTabItem(
            tab,
            selected: tabIndex == index,
            reduceMotion: reduceMotion,
          ),
      ],
    );
  }

  BottomNavigationBarItem _fallbackTabItem(
    _ShellTab tab, {
    required bool selected,
    required bool reduceMotion,
  }) {
    final Widget icon = Semantics(
      key: ValueKey<String>('shell-tab-${tab.path}'),
      label: tab.label,
      button: true,
      selected: selected,
      child: ExcludeSemantics(
        child: AnimatedScale(
          scale: selected ? 1.08 : 1,
          duration: reduceMotion
              ? Duration.zero
              : CyMotion.fast,
          curve: Curves.easeOutCubic,
          child: Icon(selected ? tab.activeIcon : tab.icon),
        ),
      ),
    );
    // N5(规则手册):Tab Bar 带文字标签,真源 app.json tabBar.text 同名。
    // 语义仍由图标节点承载,label 文本置空语义,避免 VoiceOver 同档读两遍。
    return BottomNavigationBarItem(
      icon: icon,
      activeIcon: icon,
      label: tab.label,
      semanticsLabel: '',
    );
  }

  void _selectTab(BuildContext context, int currentIndex, int nextIndex) {
    if (nextIndex == currentIndex) return;
    HapticFeedback.selectionClick();
    final StatefulNavigationShell? shell = navigationShell;
    if (shell != null) {
      shell.goBranch(nextIndex);
    } else {
      context.go(tabs[nextIndex].path);
    }
  }
}
