// CyTabs 行为契约。
//
// ★ 为什么要有行为测试而不是只拍 golden:golden 只证明「长成什么样」,
//   证明不了「点下去会发生什么」。这个组件替换掉的三套自绘实现里,
//   有的把 index 当 key、有的把 key 当 label,换掉时最容易错的正是回调传什么。

import 'dart:ui' show SemanticsAction, SemanticsActionEvent;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/core/widgets/cy_tabs.dart';

const List<CyTab> _tabs = <CyTab>[
  CyTab(key: 'all', label: '全部'),
  CyTab(key: 'pending', label: '待结算', badge: 3),
  CyTab(key: 'settled', label: '已结算', badge: 0),
];

Future<String?> _tapTab(
  WidgetTester tester,
  String label, {
  CyTabsVariant variant = CyTabsVariant.chip,
}) async {
  String? got;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: CyTabs(
          variant: variant,
          tabs: _tabs,
          active: 'all',
          onChanged: (String k) => got = k,
        ),
      ),
    ),
  );
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
  return got;
}

void main() {
  testWidgets('iOS 26 segmented 用系统 Liquid Glass 分段控件', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: CyTabs(
            tabs: const <CyTab>[
              CyTab(key: 'mine', label: '我的'),
              CyTab(key: 'nearby', label: '附近'),
            ],
            active: 'mine',
            variant: CyTabsVariant.segmented,
            liquidGlassSupported: true,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    final LiquidGlassSegmentedControl native = tester.widget(
      find.byType(LiquidGlassSegmentedControl),
    );
    expect(native.labels, <String>['我的', '附近']);
    expect(native.height, 44);
  });

  testWidgets('iOS 26 segmented 在 200% Dynamic Type 下为原生文字增高', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: CyTabs(
            tabs: const <CyTab>[
              CyTab(key: 'mine', label: '我的'),
              CyTab(key: 'nearby', label: '附近'),
            ],
            active: 'mine',
            variant: CyTabsVariant.segmented,
            liquidGlassSupported: true,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    final LiquidGlassSegmentedControl native = tester.widget(
      find.byType(LiquidGlassSegmentedControl),
    );
    expect(native.height, greaterThan(44));
    // Widget tests 不在 iOS 平台上创建 UIKitView，因此高度契约要读
    // 传给原生控件的参数，实机截图再验证 PlatformView 布局。
    expect(native.height, 52);
  });

  testWidgets('最大辅助字号下三种 Tab 都不使用固定高度裁文字', (WidgetTester tester) async {
    for (final CyTabsVariant variant in CyTabsVariant.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(4)),
            child: child!,
          ),
          home: Scaffold(
            body: CyTabs(
              tabs: const <CyTab>[
                CyTab(key: 'mine', label: '我的活动'),
                CyTab(key: 'nearby', label: '附近活动'),
              ],
              active: 'mine',
              variant: variant,
              liquidGlassSupported: variant == CyTabsVariant.segmented,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull, reason: variant.name);
      if (variant == CyTabsVariant.segmented) {
        final LiquidGlassSegmentedControl native = tester.widget(
          find.byType(LiquidGlassSegmentedControl),
        );
        expect(native.height, greaterThan(72));
      } else {
        expect(
          tester.getSize(find.byType(CyTabs)).height,
          greaterThan(44),
          reason: variant.name,
        );
      }
    }
  });

  testWidgets('旧系统 segmented 使用 Cupertino 分段控件且不小于 44pt', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: CyTabs(
            tabs: const <CyTab>[
              CyTab(key: 'mine', label: '我的'),
              CyTab(key: 'nearby', label: '附近'),
            ],
            active: 'mine',
            variant: CyTabsVariant.segmented,
            liquidGlassSupported: false,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(
      find.byType(CupertinoSlidingSegmentedControl<String>),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byType(CyTabs)).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('Cupertino segmented 在 200% Dynamic Type 下不裁切', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: CyTabs(
            tabs: const <CyTab>[
              CyTab(key: 'mine', label: '我的'),
              CyTab(key: 'nearby', label: '附近'),
            ],
            active: 'mine',
            variant: CyTabsVariant.segmented,
            liquidGlassSupported: false,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('附近'), findsOneWidget);
  });

  testWidgets('CyTabs 小字角标使用 AA 对比度前景色', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: CyTabs(tabs: _tabs, active: 'all', onChanged: (_) {}),
        ),
      ),
    );

    final Text badge = tester.widget<Text>(find.text('3'));
    expect(badge.style?.color, CyTokens.onCoverFg);
    expect(badge.style?.color, isNot(Colors.white));
  });

  for (final CyTabsVariant v in CyTabsVariant.values) {
    testWidgets('${v.name}:回调拿到的是 key 不是 label 也不是下标', (
      WidgetTester tester,
    ) async {
      expect(await _tapTab(tester, '待结算', variant: v), 'pending');
    });
  }

  testWidgets('badge 为 0 不显示 —— 「0 条未读」不该占一个红点', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: CyTabs(tabs: _tabs, active: 'all', onChanged: (_) {}),
        ),
      ),
    );
    expect(find.text('3'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('badge 超过 99 显示 99+(对齐 cy-badge 的 max)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: CyTabs(
            tabs: const <CyTab>[CyTab(key: 'a', label: 'A', badge: 128)],
            active: 'a',
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('99+'), findsOneWidget);
    expect(find.text('128'), findsNothing);
  });

  testWidgets('紧凑标签仍用 Cupertino 按钮并保留 44pt 命中区', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: CyTabs(
            compact: true,
            tabs: _tabs,
            active: 'all',
            onChanged: (_) {},
          ),
        ),
      ),
    );

    final Finder button = find.ancestor(
      of: find.text('全部'),
      matching: find.byType(CupertinoButton),
    );
    expect(button, findsOneWidget);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('自绘 tab 的 VoiceOver 节点能真正激活回调', (WidgetTester tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: CyTabs(
            tabs: _tabs,
            active: 'all',
            onChanged: (String value) => selected = value,
          ),
        ),
      ),
    );

    final node = tester.getSemantics(find.bySemanticsLabel('待结算，3 条未读'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.tap,
        nodeId: node.id,
        viewId: tester.view.viewId,
      ),
    );
    await tester.pump();
    expect(selected, 'pending');
  });

  testWidgets('★ 选中态在浅色与暗色下都必须与未选中可分', (WidgetTester tester) async {
    // 这条测的是真撞过的 bug:chip 选中底原来读静态 `CyTokens.actionPrimaryBg`
    // (暗色端 = 近白 #F8F8F8),在浅色页上白底白丸,和未选中长得一模一样,
    // 而 golden 全绿、单测全绿 —— 只有把两个颜色取出来比才抓得到。
    for (final bool light in <bool>[false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: light ? AppTheme.merchantLight() : AppTheme.dark(),
          home: Scaffold(
            body: CyTabs(
              variant: CyTabsVariant.chip,
              tabs: _tabs,
              active: 'all',
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // ⚠️ 不能把「页面上所有带色 Container」拢在一起比 —— badge 是红色的
      //   (statusDanger),它一进集合就把亮度差撑到 0.8+,于是无论两个丸是不是
      //   同色,断言都过。第一版就是这么写的,负控注入静态色**没红**才发现。
      //   要比就精确比这两个丸:选中的「全部」和未选中的「待结算」。
      Color chipColor(String label) {
        final Container c = tester.widget<Container>(
          find
              .ancestor(of: find.text(label), matching: find.byType(Container))
              .first,
        );
        return (c.decoration! as BoxDecoration).color!;
      }

      final Color onColor = chipColor('全部');
      final Color offColor = chipColor('待结算');
      final String where = light ? '浅色' : '暗色';

      expect(
        onColor,
        isNot(offColor),
        reason: '$where下选中丸与未选中丸同色 —— 用户看不出选了哪一个',
      );

      // 不只是「不同色」,还得**差得够多**才看得出来。
      final double gap =
          (onColor.computeLuminance() - offColor.computeLuminance()).abs();
      expect(
        gap,
        greaterThan(0.3),
        reason: '$where下选中/未选中亮度差只有 ${gap.toStringAsFixed(3)},太接近了',
      );
    }
  });
}
