import 'dart:ui' show SemanticsAction, SemanticsActionEvent;

import 'package:chengyin_app/core/widgets/cy_tabs.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/p3/badges/badge_detail_logic.dart';
import 'package:chengyin_app/feature/p3/badges/badge_detail_page.dart';
import 'package:chengyin_app/feature/p3/badges/badge_wall_controller.dart';
import 'package:chengyin_app/feature/p3/badges/badge_wall_logic.dart';
import 'package:chengyin_app/feature/p3/badges/badge_wall_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 勋章墙对游客是登录门(B1 报告 P1 修复),这组快照拍的是登录后的三态。
class _FixedAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 1, nickname: '阿兰', avatar: '', role: 'player'),
  );
}

const List<WallBadgeView> _badges = <WallBadgeView>[
  WallBadgeView(
    name: '开始在场',
    track: 0,
    tierKey: 'ID',
    tierZh: '探索',
    locked: false,
    timeText: '2026-08-23',
    source: '城市身份卡 · 探索',
    desc: '你第一次走进这座城市',
    cond: '完成第一次城市打卡',
    style: 'glow',
    iconUrl: '',
  ),
  WallBadgeView(
    name: '点亮全城',
    track: 4,
    tierKey: 'ID',
    tierZh: '共创',
    locked: true,
    timeText: '未点亮',
    source: '城市身份卡 · 共创',
    desc: '',
    cond: '点亮 10 个城市节点',
    style: 'glow',
    iconUrl: '',
  ),
];

Widget _host(
  Widget child, {
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
}) {
  return ProviderScope(
    overrides: <dynamic>[
      authControllerProvider.overrideWith(() => _FixedAuth()),
      badgeWallProvider.overrideWith(
        (_) async => const BadgeWallPageData(
          badges: _badges,
          legend: <WallLegendEntry>[
            WallLegendEntry(track: 0, zh: '探索', count: 1),
            WallLegendEntry(track: 4, zh: '共创', count: 1),
          ],
          unlockedCount: 1,
          lockedCount: 1,
          failure: null,
          failureDetail: '',
        ),
      ),
    ].cast(),
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: textScaler,
          disableAnimations: disableAnimations,
        ),
        child: child,
      ),
    ),
  );
}

void main() {
  testWidgets('勋章墙使用 iOS 原生导航与分段切换', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(_host(const BadgeWallPage()));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    expect(find.byType(CyTabs), findsOneWidget);
    expect(find.text('墙'), findsOneWidget);
    expect(find.text('列表'), findsOneWidget);

    // ★ 默认视图 = 列表(真源 badge-wall/index.js:178 viewMode:'list'),
    //   列表按三族分组带标题(index.wxml:30-43)。
    expect(find.text('城市身份卡'), findsOneWidget, reason: '默认应是带分组标题的列表');
    expect(find.text('查看条件'), findsOneWidget);

    await tester.tap(find.text('墙'));
    await tester.pumpAndSettle();
    expect(find.text('城市身份卡'), findsNothing, reason: '墙视图不分组');

    await tester.tap(find.text('列表'));
    await tester.pumpAndSettle();
    expect(find.text('城市身份卡'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('勋章详情使用 iOS 原生导航壳', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      _host(
        const BadgeDetailPage(
          params: BadgeDetailParams(
            name: '城墙勋章',
            sub: '城墙线 · 完成一程',
            img: '',
            style: 'enamel',
            rarity: 4,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    expect(find.text('徽章'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('勋章卡传达点亮与锁定语义，减弱动态时不做按压渐变', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      _host(const BadgeWallPage(), disableAnimations: true),
    );
    await tester.pumpAndSettle();

    final Finder unlocked = find.bySemanticsLabel('开始在场，已点亮，查看详情');
    expect(unlocked, findsOneWidget);
    expect(find.bySemanticsLabel('点亮全城，尚未点亮，查看条件'), findsOneWidget);

    final semanticsNode = tester.getSemantics(unlocked);
    expect(
      semanticsNode.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );

    final Finder cardButton = find.ancestor(
      of: find.text('开始在场'),
      matching: find.byType(CupertinoButton),
    );
    expect(cardButton, findsOneWidget);
    expect(tester.widget<CupertinoButton>(cardButton).pressedOpacity, 1);

    tester.platformDispatcher.onSemanticsActionEvent!(
      SemanticsActionEvent(
        type: SemanticsAction.tap,
        viewId: tester.view.viewId,
        nodeId: semanticsNode.id,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('获得时间'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('勋章墙在 200% 动态字号下不溢出且保留切换能力', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      _host(const BadgeWallPage(), textScaler: const TextScaler.linear(2)),
    );
    await tester.pumpAndSettle();

    expect(find.text('墙'), findsOneWidget);
    expect(find.text('列表'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('列表'));
    await tester.pumpAndSettle();
    expect(find.text('查看条件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('勋章详情在 200% 字号下可滚动且如实声明静态降级', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      _host(
        const BadgeDetailPage(
          params: BadgeDetailParams(
            name: '城墙勋章',
            sub: '城墙线 · 完成一程',
            img: '',
            style: 'enamel',
            rarity: 4,
          ),
        ),
        textScaler: const TextScaler.linear(2),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('珐琅样式'), findsOneWidget);
    expect(find.text('当前环境显示静态徽章预览'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
