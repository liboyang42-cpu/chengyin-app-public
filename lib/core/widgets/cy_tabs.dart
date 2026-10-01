import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

import '../theme/cy_palette.dart';
import '../theme/cy_tokens.dart';

/// 分段 / 标签栏。移植小程序 `components/cy/tabs`(components.wxss §5.2)。
///
/// **为什么值得单独一个组件**:App 这边 10 个页面各写了一套同样的东西 ——
/// 台账用 Material `ChoiceChip`(自带青色对勾,完全不是设计系统的东西)、
/// 商家关系用 Material `TabBar`(下划线粗细/颜色都是 Material 默认)、
/// 积分页自绘 `_TabBar` 包 `CyChip`。三种长相,同一个交互。
/// 页面之间对不上,和小程序更对不上。
///
/// ★ 强调色兜底是 [CyPalette.textPrimary](黑白基调),**不是品牌紫**。
///   小程序注释里记着:2026-07-31 全站扫描时发现 mylike/myproject/templatedetail
///   三处因为没显式传强调色,下划线吃到了默认紫。这里干脆不给紫色留默认口子。
enum CyTabsVariant {
  /// 默认:底部一条分隔线,选中项下方一根 36pt 短下划线。
  underline,

  /// 分段:整体一个药丸容器,选中项实心反色。
  segmented,

  /// 独立药丸,横向可滑。每个 item 各自成丸,item 间留间距。
  chip,
}

class CyTab {
  const CyTab({required this.key, required this.label, this.badge});

  final String key;
  final String label;

  /// 未读角标。null 或 0 都不显示 —— 「0 条未读」不该占一个红点。
  final int? badge;
}

class CyTabs extends StatelessWidget {
  const CyTabs({
    super.key,
    required this.tabs,
    required this.active,
    required this.onChanged,
    this.variant = CyTabsVariant.underline,
    this.compact = false,
    this.fill = false,
    this.hairline = true,
    this.liquidGlassSupported,
  });

  final List<CyTab> tabs;
  final String active;
  final ValueChanged<String> onChanged;
  final CyTabsVariant variant;

  /// 紧凑档(小程序 `--sm`):账期/筛选这类二级 tab。
  /// ★ 视觉高度降到 22pt,但**触达区仍补回 44pt** —— 与小程序同一手法
  ///   (它用透明 ::after 撑)。视觉紧凑不等于可以做成点不准的小目标。
  final bool compact;

  /// 内容切换 Tab 是页面主结构时等分可用宽度。
  final bool fill;

  /// underline 形态整条 border-bottom 画不画(真源 `hairline` 属性,
  /// tabs/index.js:27-30,2026-08-20:「只管整条底线,字号/指示条不动」——
  /// story 页用 `hairline:false`;a5-ios27-club-2 §四.1 登记的共用件缺口)。
  /// 默认 true = 既有调用零漂移。
  final bool hairline;

  /// 仅供能力分支测试；运行时使用系统版本探测。
  final bool? liquidGlassSupported;

  @override
  Widget build(BuildContext context) {
    switch (variant) {
      case CyTabsVariant.underline:
        return _buildUnderline(context);
      case CyTabsVariant.segmented:
        return _buildSegmented(context);
      case CyTabsVariant.chip:
        return _buildChip(context);
    }
  }

  Widget _buildUnderline(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final double visualHeight = _scaledHeight(
      context,
      minimum: compact ? 22 : 44,
      verticalRoom: compact ? 8 : 16,
    );
    return Container(
      decoration: BoxDecoration(
        border: hairline
            ? Border(bottom: BorderSide(color: p.borderSubtle, width: 1))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: tabs.map((CyTab t) {
          final bool on = t.key == active;
          final Widget item = _tap(
            context,
            t,
            selected: on,
            child: Container(
              height: visualHeight, // 默认仍为 88rpx / 44rpx，辅助字号下随文字增高
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Spacer(),
                  _label(context, t, on),
                  const Spacer(),
                  // 下划线 72rpx 宽 / 3rpx 高。★ 未选中时也占位(用透明),
                  // 否则选中切换会让文字上下跳 1.5px。
                  Container(
                    width: 36,
                    height: 1.5,
                    decoration: BoxDecoration(
                      color: on ? p.textPrimary : Colors.transparent,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ],
              ),
            ),
          );
          return fill ? Expanded(child: item) : item;
        }).toList(),
      ),
    );
  }

  Widget _buildSegmented(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final int selectedIndex = tabs.indexWhere((CyTab tab) => tab.key == active);
    final bool supportsNative =
        liquidGlassSupported ?? NativeLiquidGlassUtils.supportsLiquidGlass;
    final bool hasBadges = tabs.any((CyTab tab) => (tab.badge ?? 0) > 0);
    if (supportsNative && !hasBadges) {
      // SwiftUI Picker 会随 Dynamic Type 放大文字。宿主高度也必须同步增长，
      // 否则原生文字虽放大了，PlatformView 仍会在 44pt 裁切。
      final double scaledLabelHeight = MediaQuery.textScalerOf(
        context,
      ).scale(CyTokens.typeBody);
      final double nativeHeight = scaledLabelHeight + 24 < 44
          ? 44
          : scaledLabelHeight + 24;
      return LiquidGlassSegmentedControl(
        labels: tabs.map((CyTab tab) => tab.label).toList(growable: false),
        selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
        onValueChanged: (int index) => onChanged(tabs[index].key),
        color: p.textPrimary,
        height: nativeHeight,
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: CupertinoSlidingSegmentedControl<String>(
        groupValue: selectedIndex < 0 ? tabs.first.key : active,
        backgroundColor: p.bgSurfaceSubtle,
        thumbColor: p.actionPrimaryBg,
        padding: const EdgeInsets.all(3),
        children: <String, Widget>{
          for (final CyTab tab in tabs)
            tab.key: Padding(
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
              child: _label(
                context,
                tab,
                tab.key == active,
                inverseColor: tab.key == active ? p.actionPrimaryFg : null,
              ),
            ),
        },
        onValueChanged: (String? value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }

  Widget _buildChip(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final double controlHeight = _scaledHeight(
      context,
      minimum: 44,
      verticalRoom: 16,
    );
    // ★ 几何按真源 2026-08-20 画板04 定稿(components/cy/tabs/index.wxss
    //   `.cy-tabs--chip .cy-tabs__item`):竖距 14rpx=7pt、横距 space-3-5=14pt、
    //   字号 type-label=12、未选 Regular/选中 Medium 反色 —— 视觉高约 62rpx=31pt。
    //   旧实现吃的是 08-20 之前的「药丸高 = space-7(40pt)+ subhead 15 字」旧量图,
    //   在筛选行里比页面主结构还抢眼(a5-ios27-search-2 critic 点名)。
    //   高度不再定死:由 padding + 文字自然长出,Dynamic Type 放大时随行增高,
    //   触达区靠 CupertinoButton(minimumSize 44) 上下外扩(= 真源透明 ::after 手法)。
    return SizedBox(
      height: controlHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: CyTokens.space2),
        itemBuilder: (BuildContext context, int i) {
          final CyTab t = tabs[i];
          final bool on = t.key == active;
          return _tap(
            context,
            t,
            selected: on,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: CyTokens.space3_5,
                vertical: 7, // 14rpx,量表无半步 token(与真源同一注记)
              ),
              // ★ 不能给 alignment:那会让 Container 吃满 ListView 行高,
              //   药丸被拉成整条(实测 60pt)。高度由 padding+文字长出,
              //   垂直居中交给 CupertinoButton 内部的 Align(触达 ≥44)。
              decoration: BoxDecoration(
                // 选中 = 反色中性(action-primary),**不是品牌紫**。
                color: on ? p.actionPrimaryBg : p.bgElevated,
                borderRadius: BorderRadius.circular(CyTokens.radiusPill),
              ),
              child: _label(
                context,
                t,
                on,
                style: CyType.caption1,
                weight: on ? FontWeight.w500 : FontWeight.w400,
                // 真源未选字色是 text-primary(不是其它变体的 secondary)。
                color: on ? p.actionPrimaryFg : p.textPrimary,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _label(
    BuildContext context,
    CyTab t,
    bool on, {
    bool inverse = false,
    Color? inverseColor,
    Color? color,
    TextStyle? style,
    FontWeight? weight,
  }) {
    final CyPalette p = CyPalette.of(context);
    final Color resolvedColor =
        color ??
        inverseColor ??
        (inverse ? p.textInverse : (on ? p.textPrimary : p.textSecondary));
    final Widget text = Text(
      t.label,
      style:
          (style ??
                  TextStyle(
                    // 字号走 iOS 梯级(T2):紧凑档 = Caption1(12,与旧 typeLabel 同值),
                    // 常规档 = Subhead(15,旧 typeBody 是 14,不在梯级上)。
                    fontSize: compact
                        ? CyType.caption1.fontSize
                        : CyType.subhead.fontSize,
                  ))
              .copyWith(
                color: resolvedColor,
                fontWeight: weight ?? (on ? FontWeight.w700 : FontWeight.w600),
              ),
    );
    final int? badge = t.badge;
    if (badge == null || badge <= 0) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        text,
        const SizedBox(width: 4), // 8rpx
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            // 状态色/前景从调色板取(C4 双值):tab 上的未读角标是「状态」用色
            // (C1 允许),浅色页(商家)也要跟着走浅端值。
            color: p.statusDanger,
            borderRadius: BorderRadius.circular(CyTokens.radiusPill),
          ),
          child: Text(
            // cy-badge 自带 max=99
            badge > 99 ? '99+' : '$badge',
            style: TextStyle(
              color: p.onCoverFg,
              fontSize: CyTokens.typeMicro,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  double _scaledHeight(
    BuildContext context, {
    required double minimum,
    required double verticalRoom,
  }) {
    final double fontSize = compact ? CyTokens.typeLabel : CyTokens.typeBody;
    final double needed =
        MediaQuery.textScalerOf(context).scale(fontSize) + verticalRoom;
    return needed < minimum ? minimum : needed;
  }

  Widget _tap(
    BuildContext context,
    CyTab t, {
    required bool selected,
    required Widget child,
  }) {
    // ★ 紧凑档视觉 22pt,触达区补回 44pt。小程序用透明 ::after 撑,
    //   Flutter 这边靠 MaterialTapTargetSize —— 两边都是同一个理由:
    //   视觉紧凑不能牺牲最小可点尺寸。
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: t.badge != null && t.badge! > 0
          ? stringsOf(context).sharedUnreadTabLabel(t.label, t.badge!)
          : t.label,
      onTap: () => onChanged(t.key),
      child: ExcludeSemantics(
        child: CupertinoButton(
          onPressed: () => onChanged(t.key),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          pressedOpacity: MediaQuery.disableAnimationsOf(context) ? 1 : 0.4,
          child: child,
        ),
      ),
    );
  }
}

/// Material `TabBar` 的城瘾指示器 —— 固定 36pt 宽的圆角短线。
///
/// **为什么不用 `TabBarIndicatorSize.label`**:小程序的下划线是**定宽 72rpx**
/// (tabs/index.wxss:`width: 72rpx` + 注释「2026-07-31 用户定:下划线加长」),
/// 不随标签长短变。跟着标签走的话,「已建立」和「发现」两个 tab 的下划线会一长一短,
/// 和小程序并排看差别很明显。
///
/// 用在 [ThemeData.tabBarTheme],覆盖 Material 默认那条**满格 3px** 的粗线。
class CyTabIndicator extends Decoration {
  const CyTabIndicator({required this.color});

  final Color color;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _CyTabIndicatorPainter(color);
}

class _CyTabIndicatorPainter extends BoxPainter {
  _CyTabIndicatorPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final Size size = cfg.size ?? Size.zero;
    const double w = 36; // 72rpx
    const double h = 1.5; // 3rpx
    final Rect rect = Rect.fromLTWH(
      offset.dx + (size.width - w) / 2,
      offset.dy + size.height - h,
      w,
      h,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(h)),
      Paint()..color = color,
    );
  }
}
