import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

import '../theme/cy_palette.dart';
import '../theme/cy_tokens.dart';

/// 与小程序 `style/components.wxss` 全局类一一对应的基础件。
///
/// ★ 单一真源仍是那份 wxss。这里只做忠实映射,尺寸都按 1rpx = 0.5pt 换算并
///   在注释里保留原始 rpx 值。要改设计先改 wxss 再同步过来。
///
/// 为什么不逐页手写:同一个「标签」在 24 个页面里各写各的,必然漂移 ——
/// 小程序侧就吃过这个亏(secondary 按钮在组件版和全局 class 版长成两个样)。

/// `.cy-tag` 标签:高 44rpx、药丸角、caption 字号、bg-subtle 底。
class CyTag extends StatelessWidget {
  const CyTag({super.key, required this.label, this.brand = false, this.tone});

  final String label;

  /// `.cy-tag--brand`:brand 色字 + brand-soft 底。
  /// ⚠️ 黑白系里 brand 就是白色,不是彩色。
  final bool brand;

  /// 状态色字(对应 `cy-badge type=status variant=…`)。底仍是中性 bg-subtle
  /// —— 真源的状态徽标也只染字,不给整块上色底。
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    // ★ 垂直居中用行高而不是 Container.alignment:alignment 会在 Wrap 等
    //   **有界**约束下把药丸撑满整行宽(b1-sim-search P1-4:8 个热词各占一行)。
    //   行高 (22/12) 的半leading居中与 Align 居中同一落点,像素不变。
    return Container(
      height: 22, // 44rpx
      padding: EdgeInsets.symmetric(horizontal: CyTokens.space2_5),
      decoration: BoxDecoration(
        color: brand
            ? CyPalette.of(context).brandSoft
            : CyPalette.of(context).bgSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusPill),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        // 字号走 iOS 梯级(T2):胶囊标签是小字,对应 Caption1(12)。
        // 不再从 `typeCaption`(22rpx=11,梯级上是 Caption2)取 —— 梯级之外的
        // 字号会让 Dynamic Type 的缩放档位与粗细层次对不上系统。
        style: CyType.caption1.copyWith(
          height: 22 / 12,
          color: brand
              ? CyPalette.of(context).brand
              : (tone ?? CyPalette.of(context).textSecondary),
        ),
      ),
    );
  }
}

/// `.cy-chip` 筛选片:高 64rpx、药丸角、label 字号、玻璃底 + 描边。
/// 选中态 `.cy-chip--on` 是**实心反色**(brand 底 + text-inverse 字)。
class CyChip extends StatelessWidget {
  const CyChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // onTap 为 null 即禁用。禁用态**换色不降透明度** —— 与 .cy-btn 同一纪律:
    // opacity 会把已调过对比度的文字整体压暗,且全站出现两套禁用视觉。
    final bool disabled = onTap == null;
    // ★ selected 与 disabled 是**正交**的两维,不能互相吞掉:
    //   底色由 selected 决定(选中=实心反色),disabled 只影响前景对比度。
    //   此前 disabled 分支写在最外层,导致「选中但不可点」的项渲染成灰底,
    //   当前选中项看起来像未选中 —— golden 快照里一眼看出来的。
    final CyPalette palette = CyPalette.of(context);
    // ★ 未选中底是**系统填充色**,不是 `bgGlass`(M1):筛选片是内容层控件,
    //   玻璃只给功能层(导航/工具栏/sheet/菜单/浮动控件)。`tertiarySystemFill`
    //   是 iOS 给内容层控件用的填充色,随浅/深自动解析(C4 不需要两套值)。
    final Color bg = selected
        ? palette.brand
        : (disabled
              ? palette.bgSubtle
              : CupertinoColors.tertiarySystemFill.resolveFrom(context));
    final Color fg = selected
        // 选中是白底 ⇒ 字必须反色成黑,否则白底白字。
        // 选中且禁用时压成中灰:仍在白底上可读(对比度足),又能看出不可点。
        ? (disabled ? const Color(0xFF6B6B6B) : palette.textInverse)
        : (disabled ? palette.textPlaceholder : palette.textSecondary);
    return Semantics(
      container: true,
      button: true,
      enabled: !disabled,
      selected: selected,
      label: label,
      // ★ 动作必须挂在这一层:子树的语义被 ExcludeSemantics 摘掉了,
      //   只给 `button: true` 不给 `onTap`,VoiceOver 会念「按钮」但双击没反应。
      onTap: disabled ? null : () => onTap?.call(),
      child: ExcludeSemantics(
        child: IgnorePointer(
          ignoring: disabled,
          child: CupertinoButton(
            onPressed: () => onTap?.call(),
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
            pressedOpacity: MediaQuery.disableAnimationsOf(context) ? 1 : 0.4,
            child: Container(
              height: 32, // 64rpx 可视高度；按钮命中区保持 44pt。
              padding: const EdgeInsets.symmetric(horizontal: 13), // 26rpx
              // 同 CyTag:垂直居中走行高,不用 alignment —— alignment 在
              // Wrap 的有界约束下会把筛选片撑满整行(b1-sim-search P1-4)。
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                border: Border.all(
                  color: selected
                      ? CyPalette.of(context).brand
                      : CyPalette.of(context).borderSubtle,
                  width: 1,
                ),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CyType.caption1.copyWith(
                  height: 32 / 12,
                  // 选中是白底 ⇒ 字必须反色成黑,否则白底白字。
                  color: fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.cy-sec-title` 区块标题。
///
/// ★ 外观按手册 L2/T3 走 iOS 分组列表 section header:**Title3(20)+ Semibold**。
///   旧实现是 36rpx(18)+ `FontWeight.w800` —— w800 属「堆重」,T3 全仓退役;
///   字号也必须落在 iOS 梯级上,否则 Dynamic Type 的档位与系统对不上。
///   `Semantics(header: true)` 让 VoiceOver 的转子能按标题跳(此前缺失)。
class CySectionTitle extends StatelessWidget {
  const CySectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final Widget title = Semantics(
      header: true,
      child: Text(
        text,
        style: CyType.title3.copyWith(
          fontWeight: FontWeight.w600,
          color: CyPalette.of(context).textPrimary,
        ),
      ),
    );
    if (trailing == null) return title;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[title, trailing!],
    );
  }
}

/// `cy-page-title` 页标题:大字(58rpx)+ 可选副标。
///
/// 小程序每页是「沉浸导航栏 + 页内大标题」,不是 Material 那种居中小标题的
/// AppBar。用法:AppBar 只留返回键(title 置空),内容顶部放本组件。
///
/// ★ letterSpacing 显式为 0 —— 小程序注释写明「中文大字不加负字距」,
///   而 Flutter 的大字号 TextStyle 默认带负字距,不置零中文会挤在一起。
class CyPageTitle extends StatelessWidget {
  const CyPageTitle(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        // .pt:margin-top space-5 / margin-bottom space-2 / padding 0 page-x
        padding: EdgeInsets.fromLTRB(
          CyTokens.pageX,
          CyTokens.space5,
          CyTokens.pageX,
          CyTokens.space2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontSize: CyTokens.typePageTitle,
                height: 1.22,
                // T3:强调用 bold(700)。w800 属堆重,已全仓退役。
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                color: CyPalette.of(context).textPrimary,
              ),
            ),
            if (subtitle != null)
              Padding(
                padding: EdgeInsets.only(top: CyTokens.space1),
                child: Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: CyTokens.typeBody,
                    height: CyTokens.leadingNormal,
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// `.cy-sheet__grab` 半屏抓手:72rpx × 8rpx,居中。
class CySheetGrab extends StatelessWidget {
  const CySheetGrab({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36, // 72rpx
      height: 4, // 8rpx
      margin: EdgeInsets.only(bottom: CyTokens.space3),
      decoration: BoxDecoration(
        color: CyPalette.of(context).borderStrong,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// `.cy-field` + `.cy-label`:表单一项。
/// label 是 flex space-between,右侧可放行内动作(小程序那里放「✨AI 帮我写」)。
///
/// ★ 手册 P3 要求「进 inset grouped section;label 规则 T2」。分段容器
///   (`CupertinoFormSection.insetGrouped`)是**页面级**结构,由各页在 P3 批次
///   自行接线 —— 本组件只保证 label 走 iOS 梯级(Caption1,12pt,与旧
///   `typeLabel` 同值,零视觉漂移),字号从此有梯级出处。
class CyField extends StatelessWidget {
  const CyField({
    super.key,
    required this.label,
    required this.child,
    this.trailing,
  });

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: CyTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(bottom: CyTokens.space1_5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  label,
                  style: CyType.caption1.copyWith(
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// `cy-avatar` 头像:圆形,可选 2rpx 描边。
class CyAvatar extends StatelessWidget {
  const CyAvatar({
    super.key,
    this.url,
    this.fallback,
    this.fallbackImageProvider,
    this.fallbackAsset,
    this.size = 40,
    this.bordered = true,
  });

  final String? url;

  /// 无图时显示的文字(通常取名称首字)。
  final String? fallback;

  /// 默认头像的可注入图像源，供离线快照使用。
  final ImageProvider<Object>? fallbackImageProvider;

  /// 无图时优先显示的本地默认头像。
  final String? fallbackAsset;
  final double size;

  /// `.av__inner--bordered`:2rpx borderSubtle。深色底上没有描边会与背景糊在一起。
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final has = url != null && url!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: CyPalette.of(context).bgElevated,
        border: bordered
            ? Border.all(color: CyPalette.of(context).borderSubtle, width: 1)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: has
          ? Image.network(
              url!,
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (_, _, _) => _AvatarFallback(
                text: fallback,
                imageProvider: fallbackImageProvider,
                asset: fallbackAsset,
                size: size,
              ),
            )
          : _AvatarFallback(
              text: fallback,
              imageProvider: fallbackImageProvider,
              asset: fallbackAsset,
              size: size,
            ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({
    this.text,
    this.imageProvider,
    this.asset,
    required this.size,
  });
  final String? text;
  final ImageProvider<Object>? imageProvider;
  final String? asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (imageProvider != null) {
      return Image(
        image: imageProvider!,
        width: size,
        height: size,
        fit: BoxFit.cover,
      );
    }
    if (asset != null && asset!.isNotEmpty) {
      return Image.asset(asset!, width: size, height: size, fit: BoxFit.cover);
    }
    final t = (text ?? '').trim();
    if (t.isEmpty) {
      return Icon(
        // 全 App 恒暗/恒浅两态都在用这个兜底 —— 不留 Material 字形,
        // 用 Cupertino 人形剪影(圆底已由外层容器给出,不再套 person_crop_circle)。
        CupertinoIcons.person,
        size: size * 0.5,
        color: CyPalette.of(context).textTertiary,
      );
    }
    return Text(
      t.characters.first,
      style: TextStyle(
        fontSize: size * 0.4,
        fontWeight: FontWeight.w700,
        color: CyPalette.of(context).textSecondary,
      ),
    );
  }
}

/// `cy-badge` 徽标:红点或数字角标。
///
/// `.bd--dot` 是 16rpx 圆点 + 2rpx bgSurface 描边 —— 描边是为了压在头像/图标上
/// 时能与底下的内容分开,别省。
class CyBadge extends StatelessWidget {
  const CyBadge({super.key, this.count, this.semanticsLabel});

  /// null 或 0 显示为红点;>0 显示数字(超过 99 显示 99+)。
  final int? count;

  /// 无障碍标签(如「3 条未读」)。给定时角标作为**一个**元素宣读 ——
  /// 否则 VoiceOver 只会念一个孤立的数字,离了上下文没有意义。
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final n = count ?? 0;
    final Widget badge;
    if (n <= 0) {
      badge = Container(
        width: 8, // 16rpx
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // 状态色从调色板取(C4 双值):`CyTokens.statusDanger` 是暗色编译期
          // 常量,浅色页(商家/主题编辑器)拿到的是暗端值。
          color: palette.statusDanger,
          border: Border.all(color: palette.bgSurface, width: 1),
        ),
      );
    } else {
      badge = Container(
        constraints: const BoxConstraints(minWidth: 16),
        height: 16,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.statusDanger,
          borderRadius: BorderRadius.circular(CyTokens.radiusPill),
          border: Border.all(color: palette.bgSurface, width: 1),
        ),
        child: Text(
          n > 99 ? '99+' : '$n',
          // ★ 深色而不是白色 —— 对齐小程序 `components/cy/badge/index.wxss:16`
          //   (`.bd__count { color: var(--cy-comp-oncover-fg) }`),并且实测更好:
          //   danger 底 #E5484D 上,白字对比度 3.91(低于 AA 正文 4.5),深字 5.06。
          //   badge 用的是 micro 字号,小字比正文更吃亏,不该用不达标的那个。
          //   别凭「彩色底配白字」的常理改回 Colors.white —— 同样的坑在状态色上
          //   已经踩过一次,见 test/theme/contrast_test.dart。
          //   前景同样走调色板(C4):浅端状态色是压深的 R1 原语,配白字才达标。
          style: TextStyle(
            fontSize: CyTokens.typeMicro,
            fontWeight: FontWeight.w600,
            color: palette.onCoverFg,
            height: 1,
          ),
        ),
      );
    }
    if (semanticsLabel == null) return badge;
    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(child: badge),
    );
  }
}

/// `cy-cell` 列表项:左图标/右箭头 + 主副文案。
class CyCell extends StatelessWidget {
  const CyCell({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.showChevron = true,
    this.minHeight,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;

  /// 行高钩子:对齐小程序 `--cy-comp-cell-min-h`(如设置页 112rpx)。
  /// 缺省时双行 128rpx→64pt、单行按 btn-h(88rpx→44pt)。
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final bool twoline = subtitle != null && subtitle!.isNotEmpty;
    final double effectiveMinHeight =
        minHeight ?? (twoline ? 64 : CyTokens.btnH);
    final bool enabled = onTap != null;

    // iOS 列表行(L1/L3):行本体交给系统 `CupertinoListTile` —— 按压高亮、
    // 行高下限(44/48)、一行截断规则全部走系统实现,不再自绘。
    //   ① 标题/副标题字号走 iOS 梯级(Body 17 / Caption1 12),不再是小程序
    //      的 rpx 换算值(14/12);副标题天然与系统列表一致。
    //   ② 进下级页的 disclosure 用系统 `CupertinoListTileChevron`,不再用
    //      Material 的 `Icons.chevron_right`(L3:箭头交给系统语义色)。
    //   ③ 按压反馈用调色板 `statePressed`(C4 双值蒙层)。系统默认的
    //      `systemGrey4` 是不透明实色,会把卡片自己的底色盖掉。
    // ★ leading 不能交给 CupertinoListTile 的 `leading`:它会被塞进
    //   `leadingSize`(默认 28pt)的方框,而本组件 20 处调用点的图标/头像
    //   尺寸各不相同,塞进去会缩水 —— 所以行内容整体由 `title` 承载。
    final Widget tile = CupertinoListTile(
      padding: EdgeInsets.symmetric(
        horizontal: CyTokens.space3,
        vertical: CyTokens.space2,
      ),
      backgroundColorActivated: palette.statePressed,
      // ★ 不要 `() => onTap!()`:那会把消费者返回的 Future 交回框架,
      //   `CupertinoListTile` 的内部实现是 `await widget.onTap!()` —— 行会一直
      //   停在按下态,直到消费者的整条异步链(load+play)结束才复位。
      onTap: enabled
          ? () {
              onTap!();
            }
          : null,
      title: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading!,
            SizedBox(width: CyTokens.space3),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: CyType.body.copyWith(color: palette.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (twoline) ...<Widget>[
                  SizedBox(height: CyTokens.space1),
                  Text(
                    subtitle!,
                    style: CyType.caption1.copyWith(
                      color: palette.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            SizedBox(width: CyTokens.space2),
            trailing!,
          ],
          if (showChevron && enabled)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: CupertinoListTileChevron(),
            ),
        ],
      ),
    );

    final Widget content = ConstrainedBox(
      // .cell--twoline min-height 128rpx→64;单行按 btn-h(88rpx→44)。
      // minHeight 钩子只做上界放大,不压回默认档以下。
      constraints: BoxConstraints(minHeight: effectiveMinHeight),
      child: tile,
    );

    // A display-only cell may still contain independent trailing controls
    // (for example edit/delete). Do not disable or merge those descendants
    // merely because the row itself has no navigation action.
    if (!enabled) return content;

    return Semantics(
      container: true,
      button: true,
      enabled: true,
      label: twoline ? '$title，$subtitle' : title,
      // 同 CyChip:动作挂在语义层(VoiceOver 双击可导航)。
      onTap: onTap,
      child: ExcludeSemantics(child: content),
    );
  }
}

/// `cy-footer-bar` 底部操作条(活动详情的报名条一类)。
///
/// ★ 比例是规定死的:次要动作 flex 1、主动作 flex 2。
///   两个按钮等宽会让用户分不清哪个是主行动。
///
/// ★ 材质(手册 M8 / 对照表行 28):页底固定 CTA 属**功能层**,iOS 26+ 用真
///   玻璃(`LiquidGlassContainer`),iOS 13–25 回退实色条。两条路径的几何完全
///   一致 —— 只换材质,不换布局,页面不会因系统版本重排。
///   ⚠️ 不许用 `BackdropFilter` 仿玻璃:门禁 `test/no_fake_glass_test.dart` 会红,
///   而且仿不像(M9)。
class CyFooterBar extends StatelessWidget {
  const CyFooterBar({
    super.key,
    required this.primary,
    this.secondary,
    this.leading,
    this.liquidGlassSupported,
  });

  final Widget primary;
  final Widget? secondary;

  /// 左侧信息区(如购物车「合计」),右侧放 [primary] 按钮(按自身宽度)。
  /// 传了它就当「说明在左、动作在右」排,[secondary] 不再生效;
  /// 不传时保持原「双按钮分宽」布局,既有调用方零改动。
  final Widget? leading;

  /// 仅供能力分支测试;运行时用系统版本探测(与 `CyNativeButton` 同口径)。
  final bool? liquidGlassSupported;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final bool useNative =
        liquidGlassSupported ?? NativeLiquidGlassUtils.supportsLiquidGlass;
    final Widget row = SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          CyTokens.pageX,
          CyTokens.space3,
          CyTokens.pageX,
          CyTokens.space3,
        ),
        child: leading != null
            ? Row(
                children: <Widget>[
                  leading!,
                  const Spacer(),
                  SizedBox(width: CyTokens.space3),
                  primary,
                ],
              )
            : Row(
                children: <Widget>[
                  if (secondary != null) ...<Widget>[
                    Expanded(flex: 1, child: secondary!),
                    SizedBox(width: CyTokens.space3),
                  ],
                  Expanded(flex: 2, child: primary),
                ],
              ),
      ),
    );

    if (useNative) {
      return LiquidGlassContainer(
        config: const LiquidGlassConfig(shape: LiquidGlassEffectShape.rect),
        child: row,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: palette.bgSurface,
        border: Border(top: BorderSide(color: palette.borderSubtle, width: 1)),
      ),
      child: row,
    );
  }
}
