// P2–P4 共用层组件的 iOS 27 规则守卫。
//
// ★ 为什么单独一条:这一批改的全是**没有失败信号**的东西 —— 字重、字号出处、
//   底色材质、语义动作。改错了编译过、布局也不塌:golden 只会跟着截图走一遍,
//   基线一重录就「合法化」了。所以把规则锁在组件本身:
//     · T3  —— 不许 w800/w900 堆重(区块标题 / 页标题);
//     · T2  —— 字号必须来自 iOS 梯级(`CyType`),不是 rpx 换算的死数;
//     · M1  —— 内容层控件不许用玻璃底(`CyChip` 的 `bgGlass` 已退役);
//     · M8  —— 页底 CTA 是功能层:iOS 26+ 用真玻璃,旧系统回退实色;
//     · C4  —— 颜色走 `CyPalette` 双值,浅色页拿到的是浅端值;
//     · L3  —— 进下级页的 disclosure 用系统控件;
//     · L9  —— 命中区 ≥ 44pt;
//     · a11y —— section 标题进 rotor、角标可整体宣读、按钮有 tap 动作。
//   每条断言都对着 `docs/ios27-design-language.md` 的条目;改规则先改手册。

import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/core/theme/cy_palette.dart';
import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/core/theme/cy_tokens.g.dart';
import 'package:chengyin_app/core/widgets/cy_widgets.dart';

import '../support/source_text.dart';

Widget _host(Widget child, {ThemeData? theme}) {
  return MaterialApp(
    theme: theme ?? AppTheme.dark(),
    home: Scaffold(body: Center(child: child)),
  );
}

BoxDecoration _decorationOf(WidgetTester tester, Finder finder) {
  final Container container = tester.widget<Container>(finder);
  return container.decoration! as BoxDecoration;
}

void main() {
  testWidgets('CySectionTitle:Title3 + Semibold(T3/L2),并进无障碍 rotor', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(const CySectionTitle('我的票夹')));

    final Text text = tester.widget<Text>(find.text('我的票夹'));
    expect(text.style?.fontSize, CyType.title3.fontSize, reason: 'T2:字号走 iOS 梯级');
    expect(text.style?.fontWeight, FontWeight.w600);
    expect(
      text.style?.fontWeight!.value,
      lessThanOrEqualTo(FontWeight.w700.value),
      reason: 'T3:强调用 bold trait,不许 w800/w900 堆重',
    );
    expect(text.style?.color, CyPalette.dark.textPrimary);

    final SemanticsData data = tester
        .getSemantics(find.bySemanticsLabel('我的票夹'))
        .getSemanticsData();
    expect(
      data.flagsCollection.isHeader,
      isTrue,
      reason: 'section 标题要能被 VoiceOver 转子当标题跳转',
    );
  });

  testWidgets('CyPageTitle:字重按 T3(700),字号保留 58rpx(D10④)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(const CyPageTitle('我的票夹', subtitle: '探店日的票都在这里')),
    );

    final Text title = tester.widget<Text>(find.text('我的票夹'));
    expect(title.style?.fontWeight, FontWeight.w700);
    expect(title.style?.fontSize, CyTokens.typePageTitle);
    expect(title.style?.letterSpacing, 0, reason: 'T5:中文大字不加负字距');
  });

  testWidgets('CyTag:字号 Caption1、实色底(不是玻璃)', (WidgetTester tester) async {
    await tester.pumpWidget(_host(const CyTag(label: '探店日')));

    final Text text = tester.widget<Text>(find.text('探店日'));
    expect(text.style?.fontSize, CyType.caption1.fontSize);
    expect(text.style?.color, CyPalette.dark.textSecondary);

    final BoxDecoration decoration = _decorationOf(
      tester,
      find.ancestor(of: find.text('探店日'), matching: find.byType(Container)).first,
    );
    expect(decoration.color, CyPalette.dark.bgSubtle);
    expect(decoration.color, isNot(CyTokens.bgGlass), reason: 'M1:内容层不用玻璃底');
  });

  testWidgets('CyChip:未选中底是系统填充色、选中底是 brand(M1/C1)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Row(
          children: <Widget>[
            CyChip(label: '附近', selected: false, onTap: () {}),
            CyChip(label: '全部', selected: true, onTap: () {}),
          ],
        ),
      ),
    );

    final BoxDecoration idle = _decorationOf(
      tester,
      find.ancestor(of: find.text('附近'), matching: find.byType(Container)).first,
    );
    expect(
      idle.color,
      CupertinoColors.tertiarySystemFill.resolveFrom(
        tester.element(find.byType(CyChip).first),
      ),
      reason: 'M1:筛选片的未选中底是系统填充色,不再用 bgGlass',
    );
    expect(idle.color, isNot(CyTokens.bgGlass));

    final BoxDecoration selected = _decorationOf(
      tester,
      find.ancestor(of: find.text('全部'), matching: find.byType(Container)).first,
    );
    expect(selected.color, CyPalette.dark.brand);
  });

  testWidgets('CyChip:命中区 ≥44pt、VoiceOver 能激活、禁用态可感知(L9/a11y)', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await tester.pumpWidget(
      _host(
        Row(
          children: <Widget>[
            CyChip(label: '附近', selected: true, onTap: () => taps++),
            const CyChip(label: '禁用', selected: false),
          ],
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(CupertinoButton).first).height,
      greaterThanOrEqualTo(44),
    );

    final SemanticsData enabled = tester
        .getSemantics(find.bySemanticsLabel('附近'))
        .getSemanticsData();
    expect(
      enabled.hasAction(SemanticsAction.tap),
      isTrue,
      reason: '只给 button:true 不给动作,VoiceOver 双击没反应',
    );

    final SemanticsData disabled = tester
        .getSemantics(find.bySemanticsLabel('禁用'))
        .getSemanticsData();
    expect(
      disabled.flagsCollection.isEnabled,
      isNot(Tristate.none),
      reason: '禁用态要暴露「可禁用」,否则 VoiceOver 说不出「变暗」',
    );
    expect(disabled.flagsCollection.isEnabled, Tristate.isFalse);
    expect(disabled.hasAction(SemanticsAction.tap), isFalse);
    expect(taps, 0);
  });

  testWidgets('CyChip:Reduce Motion 下按压不做透明度变化(A2)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const Scaffold(
            body: Center(child: CyChip(label: '附近', selected: true, onTap: null)),
          ),
        ),
      ),
    );

    final CupertinoButton button = tester.widget<CupertinoButton>(
      find.byType(CupertinoButton),
    );
    expect(button.pressedOpacity, 1);
  });

  testWidgets('CyCell:系统列表行 + 系统 disclosure,命中区与语义都留给系统(L1/L3/L9)', (
    WidgetTester tester,
  ) async {
    bool tapped = false;
    await tester.pumpWidget(
      _host(
        CyCell(
          title: '订单',
          subtitle: '共 3 单',
          onTap: () => tapped = true,
        ),
      ),
    );

    expect(find.byType(CupertinoListTile), findsOneWidget);
    expect(
      find.byType(CupertinoListTileChevron),
      findsOneWidget,
      reason: 'L3:进下级页的箭头用系统 disclosure,不再用 Material 图标',
    );
    expect(
      tester.getSize(find.byType(CupertinoListTile)).height,
      greaterThanOrEqualTo(44),
      reason: 'L9:行高下限 44pt',
    );

    final Text title = tester.widget<Text>(find.text('订单'));
    expect(title.style?.fontSize, CyType.body.fontSize, reason: 'T2:行标题 = Body 17');
    final Text subtitle = tester.widget<Text>(find.text('共 3 单'));
    expect(
      subtitle.style?.fontSize,
      CyType.caption1.fontSize,
      reason: 'T2:行副标题 = Caption1 12',
    );

    await tester.tap(find.text('订单'));
    expect(tapped, isTrue);

    final SemanticsData data = tester
        .getSemantics(find.bySemanticsLabel('订单，共 3 单'))
        .getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue);
  });

  testWidgets('CyCell:只读行不加按钮语义、不吞 trailing 内的独立控件', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CyCell(
          title: '主理人',
          trailing: const CyChip(label: '编辑', selected: false, onTap: null),
        ),
      ),
    );

    final CupertinoListTile tile = tester.widget<CupertinoListTile>(
      find.byType(CupertinoListTile),
    );
    expect(tile.onTap, isNull);
    expect(find.bySemanticsLabel('编辑'), findsOneWidget);
  });

  testWidgets('CyField:label 走梯级 Caption1、次要色', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(const CyField(label: '活动名称', child: Text('占位'))),
    );

    final Text label = tester.widget<Text>(find.text('活动名称'));
    expect(label.style?.fontSize, CyType.caption1.fontSize);
    expect(label.style?.color, CyPalette.dark.textSecondary);
  });

  testWidgets('CyBadge:状态色走调色板双值(C4),可整体宣读(a11y)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(const CyBadge(count: 3, semanticsLabel: '3 条未读')),
    );

    final Text count = tester.widget<Text>(find.text('3'));
    expect(count.style?.color, CyTokens.onCoverFg, reason: '暗端前景不回归');
    expect(
      tester.getSemantics(find.bySemanticsLabel('3 条未读')),
      isNotNull,
    );
    expect(find.text('3'), findsOneWidget);

    // 浅色页(商家/主题编辑器)必须拿到浅端值 —— CyTokens 是暗色编译期常量。
    await tester.pumpWidget(
      _host(const CyBadge(count: 3), theme: AppTheme.merchantLight()),
    );
    // MaterialApp 用 AnimatedTheme 做主题过渡,一帧内还是旧主题 —— 等落定再断言。
    await tester.pumpAndSettle();
    final Text lightCount = tester.widget<Text>(find.text('3'));
    expect(lightCount.style?.color, CyGeneratedLightTokens.colorActionPrimaryFg);
    expect(lightCount.style?.color, isNot(CyTokens.onCoverFg));

    final BoxDecoration decoration = _decorationOf(
      tester,
      find.ancestor(of: find.text('3'), matching: find.byType(Container)).first,
    );
    expect(decoration.color, CyGeneratedLightTokens.colorStatusDanger);
  });

  testWidgets('CyBadge:红点不带数字、无条件语义时树外不产生节点', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(const CyBadge()));

    expect(find.byType(Text), findsNothing);
    final Container dot = tester.widget<Container>(
      find.descendant(of: find.byType(CyBadge), matching: find.byType(Container)),
    );
    expect((dot.decoration! as BoxDecoration).shape, BoxShape.circle);
  });

  testWidgets('CyFooterBar:回退实色 / 26+ 真玻璃,几何一致(M8/M9)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const CyFooterBar(
          primary: Text('报名'),
          secondary: Text('收藏'),
          liquidGlassSupported: false,
        ),
      ),
    );

    expect(find.byType(LiquidGlassContainer), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing, reason: 'M9:不许用 BackdropFilter 仿玻璃');
    final BoxDecoration fallback = _decorationOf(
      tester,
      find
          .descendant(of: find.byType(CyFooterBar), matching: find.byType(Container))
          .first,
    );
    expect(fallback.color, CyPalette.dark.bgSurface);
    expect(
      tester
          .widgetList<Expanded>(find.byType(Expanded))
          .map((Expanded e) => e.flex)
          .toList(),
      <int>[1, 2],
      reason: '比例规定死:次要 1、主动作 2',
    );

    await tester.pumpWidget(
      _host(
        const CyFooterBar(
          primary: Text('报名'),
          secondary: Text('收藏'),
          liquidGlassSupported: true,
        ),
      ),
    );

    expect(find.byType(LiquidGlassContainer), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('CyFooterBar:leading 信息区在左、主动作按自身宽度靠右(购物车合计条)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const CyFooterBar(
          leading: Text('合计'),
          primary: Text('去兑换'),
          secondary: Text('被忽略的次要动作'),
          liquidGlassSupported: false,
        ),
      ),
    );

    expect(find.text('被忽略的次要动作'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(CyFooterBar),
        matching: find.ancestor(
          of: find.text('去兑换'),
          matching: find.byType(Expanded),
        ),
      ),
      findsNothing,
      reason: 'leading 变体不做按钮分宽,主动作按自身宽度(Spacer 自带的 Expanded 除外)',
    );
    expect(find.byType(Spacer), findsOneWidget);
    expect(
      tester.getCenter(find.text('合计')).dx,
      lessThan(tester.getCenter(find.text('去兑换')).dx),
    );
    expect(find.byType(LiquidGlassContainer), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);

    await tester.pumpWidget(
      _host(
        const CyFooterBar(
          leading: Text('合计'),
          primary: Text('去兑换'),
          liquidGlassSupported: true,
        ),
      ),
    );
    expect(find.byType(LiquidGlassContainer), findsOneWidget);
  });

  testWidgets('Dynamic Type 2 倍下共用层不抛异常(T4)', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Column(
              children: <Widget>[
                const CySectionTitle('区块标题'),
                CyCell(title: '订单', subtitle: '共 3 单', onTap: () {}),
                const CyField(label: '活动名称', child: Text('占位')),
                CyChip(label: '附近', selected: true, onTap: () {}),
                const CyTag(label: '探店日'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('浅色主题下共用层取浅端值(C4 双值)', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        Column(
          children: <Widget>[
            const CySectionTitle('区块标题'),
            CyCell(title: '订单', subtitle: '共 3 单', onTap: () {}),
            const CyTag(label: '探店日'),
            const CyField(label: '活动名称', child: Text('占位')),
          ],
        ),
        theme: AppTheme.merchantLight(),
      ),
    );

    CyPalette paletteOf(Finder finder) =>
        CyPalette.of(tester.element(finder));

    final CyPalette light = CyPalette.light;
    expect(paletteOf(find.byType(CyTag)), light);
    expect(tester.widget<Text>(find.text('探店日')).style?.color, light.textSecondary);
    expect(
      tester.widget<Text>(find.text('区块标题')).style?.color,
      light.textPrimary,
    );
    expect(tester.widget<Text>(find.text('订单')).style?.color, light.textPrimary);
    expect(
      tester.widget<Text>(find.text('活动名称')).style?.color,
      light.textSecondary,
    );
    // 两端必须真的不同,否则「双值」是摆设。
    expect(light.textPrimary, isNot(CyPalette.dark.textPrimary));
    expect(light.textSecondary, isNot(CyPalette.dark.textSecondary));
  });

  test('★ 共用层不许再出现 w800/w900(T3)', () {
    final Iterable<File> files = Directory('lib/core/widgets')
        .listSync()
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'));
    expect(files, isNotEmpty, reason: '扫不到文件 = 门禁退化成恒绿');

    final List<String> offenders = <String>[];
    for (final File file in files) {
      final List<String> lines = codeOf(file.path).split('\n');
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('FontWeight.w800') ||
            lines[i].contains('FontWeight.w900')) {
          offenders.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'T3:强调用 bold trait(≤w700)。新增堆重会让各页自己的批次反复回改',
    );
  });
}
