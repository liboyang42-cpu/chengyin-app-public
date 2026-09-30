import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../widgets/cy_tabs.dart';
import 'app_colors.dart';
import 'cy_palette.dart';
import 'cy_tokens.dart';
import 'cy_tokens.g.dart';

/// 城瘾主题。feature 层一律用 `Theme.of(context)` / `CyPalette.of(context)` 取值,
/// 不硬编码颜色/间距。
///
/// **两套**:`dark()` 是 C 端(小程序 tokens.wxss 默认块),`merchantLight()` 是
/// 商家工作台(小程序 `.theme-light`,36 个商家页 @import merchant-light.wxss)。
/// 此前 App 只有暗色一套,商家页全渲成黑底,与小程序并排看是两个产品。
/// 主题编辑器(`.theme-topic-editor`)见 [topicEditorLight]。
abstract final class AppTheme {
  static ThemeData dark() => _build(CyPalette.dark, Brightness.dark);

  /// 商家工作台浅色主题。挂在商家路由外层,不是全局切换 ——
  /// 小程序侧同样是**逐页 @import**,离开商家页就回暗色。
  static ThemeData merchantLight() => _build(CyPalette.light, Brightness.light);

  /// 主题编辑器 / 创建域浅色主题(决策 D10⑥)。
  ///
  /// 与 [merchantLight] **同底色、白卡、正文**,只有**卡片起层手段**不同 ——
  /// 真源 tokens.wxss 把这件事写成一条「二选一」规范(商家块 980-986):
  /// 「投影与描边同时出现 = 一张卡两条外沿 … 本域选投影,所以描边必须同步关掉;
  ///  白底细线域(theme-topic-editor)则相反 —— 那边零投影、留描边」。
  ///
  /// * `.theme-merchant`:`--cy-comp-card-shadow-day: 0 2rpx 8rpx rgba(15,23,43,.48)`
  ///   + `--cy-comp-card-border: transparent` → **投影起层**。
  /// * `.theme-topic-editor`(1136-1138 行):`--cy-comp-card-shadow-day: 0 0 0 0
  ///   transparent`,而 `.cy-card` 的描边读的是 `--cy-border-card`
  ///   = `var(--cy-color-border-subtle)` = `#E8E8E8` → **细线起层**。
  ///
  /// App 侧 `.cy-card` 的两种长相都由 [_build] 从 `cardShadow` / `cardBorder`
  /// 推出来(`cardShadow.isEmpty ? elevation 0 : 2`、`cardBorder` 决定描边有无),
  /// 所以这里只换这两个值即可,**不另起一套主题族** —— 两域其余 20 处 token 差异
  /// (status-*/bgGlass/skeleton/text-placeholder)在 `lib/feature/publish`、
  /// `lib/feature/template` 里**没有消费端**(已 grep 核实),等 P0 统一收敛。
  static ThemeData topicEditorLight() => _build(
    CyPalette.light.copyWith(
      cardShadow: const <BoxShadow>[],
      cardBorder: CyGeneratedLightTokens.colorBorderSubtle,
    ),
    Brightness.light,
  );

  static ThemeData _build(CyPalette p, Brightness brightness) {
    final light = brightness == Brightness.light;
    final base = light
        ? ThemeData.light(useMaterial3: true)
        : ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[p],
      scaffoldBackgroundColor: p.bgPage,
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: p.textPrimary,
        scaffoldBackgroundColor: p.bgPage,
        barBackgroundColor: p.bgPage,
      ),
      // ★ 参数必须传进**构造器**,不能 `ColorScheme.dark().copyWith(...)` ——
      //   ColorScheme 的一批派生色(surfaceTint / onSurfaceVariant / outline …)
      //   是按构造入参算的;先默认构造再 copyWith,派生色仍停留在默认 surface/primary
      //   算出来的值上。实测差异:半屏表单里的图标与必填星号从 #F8F8F8 变成纯白
      //   (account_phone_sheet 基准图 2995px)。语义没变、颜色悄悄变了,最难查的一类。
      colorScheme: light
          ? ColorScheme.light(
              primary: p.textPrimary,
              secondary: p.textPrimary,
              surface: p.bgSurface,
              error: AppColors.danger,
              onPrimary: p.textInverse,
              onSurface: p.textPrimary,
            )
          : const ColorScheme.dark(
              primary: AppColors.primary,
              secondary: AppColors.nodeGlow,
              surface: AppColors.bgSurface,
              error: AppColors.danger,
              onPrimary: AppColors.onPrimary,
              onSurface: AppColors.textPrimary,
            ),
      // ⚠️ 手册 P0 要求「textTheme 对齐 T2」尚未接线:这里只换色,字号仍走
      //   Material 基座默认。改基座字号会整体改变已录的 golden 基线,而本机
      //   Flutter 3.47.4 ≠ CI 门禁的 3.44.2,无法本地可靠重录 —— 留下一批在
      //   CI runner 环境做。新代码的字号请直接取 `CyType`(iOS 阶梯)。
      textTheme: base.textTheme.apply(
        bodyColor: p.textPrimary,
        displayColor: p.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.bgPage,
        foregroundColor: p.textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      // ★ --cy-shadow-card: none —— 深色下卡片无阴影,elevation 必须显式为 0。
      // .cy-card = bg-card + **2rpx 描边** + radius-md + padding space-3。
      // ★ 描边是小程序卡片的识别特征,Flutter Card 默认没有,漏了整体观感就散。
      // ★ 浅色端**没有描边、只有投影**(tokens.wxss:663-665 把 card-border 和
      //   顶缘高光都置 transparent);暗色端反过来。两个都给 = 两端都不对。
      cardTheme: CardThemeData(
        color: p.bgSurface,
        // ★ 浅色端卡片**靠投影**立起来(tokens.wxss:664
        //   `0 2rpx 8rpx rgba(15,23,43,.48)`),暗色端 elevation 恒 0 靠描边。
        //   两端都给 elevation 0 的话,浅色页就是「白卡贴白底」,卡界消失。
        elevation: p.cardShadow.isEmpty ? CyTokens.cardElevation : 2,
        shadowColor: p.cardShadow.isEmpty ? null : p.cardShadow.first.color,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          side: BorderSide(
            color: p.cardBorder,
            width: p.cardBorder == Colors.transparent ? 0 : 1,
          ),
        ),
      ),
      // .cy-btn:高 btn-h(88rpx)、圆角 **radius-lg**(不是 md)、
      // 字号 font-subtitle=card-title、weight 700、横 padding btn-pad-x。
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: light ? p.textPrimary : AppColors.primary,
          foregroundColor: light ? p.textInverse : AppColors.onPrimary,
          // ★ 禁用态换色不换透明度。小程序注释写明:opacity:.4 会把已调过
          //   对比度的文字整体压暗到 4.5:1 以下,且全站出现两套禁用视觉。
          disabledBackgroundColor: p.bgSubtle,
          disabledForegroundColor: p.textPlaceholder,
          minimumSize: const Size.fromHeight(CyTokens.btnH),
          padding: EdgeInsets.symmetric(horizontal: CyTokens.btnPadX),
          textStyle: const TextStyle(
            fontSize: CyTokens.typeCardTitle,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
            // ★ 有意偏离小程序的 `.cy-btn[disabled] { border: none }`:
            //   bg-subtle 是 rgba(255,255,255,.04),叠在**纯黑页面底**上 ≈ #0A0A0A,
            //   与背景几乎无差 ⇒ 禁用按钮整个隐形(golden 快照里一眼看出)。
            //   小程序那个值能用,是因为它的按钮多在 #0A0A0B 的卡片内,有底色差。
            //   这里给禁用态加一道描边保证任何底色上都有边界,不改底色本身。
            side: BorderSide(color: p.borderSubtle, width: 1),
          ),
        ),
      ),
      // .cy-btn--secondary:★**只有填充没有描边**(小程序侧 2026-08-05 用户定,
      // 当时组件版改了、全局 class 版漏改,同一个 secondary 出现两种长相)。
      // Flutter 的 OutlinedButton 默认带 side,必须显式置 none。
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: light ? p.textPrimary : CyTokens.actionSecondaryFg,
          // .theme-light:681 --cy-color-action-secondary-bg: #F4F4F4
          backgroundColor: light
              ? const Color(0xFFF4F4F4)
              : CyTokens.actionSecondaryBg,
          disabledBackgroundColor: p.bgSubtle,
          disabledForegroundColor: p.textPlaceholder,
          minimumSize: const Size.fromHeight(CyTokens.btnH),
          padding: EdgeInsets.symmetric(horizontal: CyTokens.btnPadX),
          side: BorderSide.none,
          textStyle: const TextStyle(
            fontSize: CyTokens.typeCardTitle,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
          ),
        ),
      ),
      // 小程序 components/tabBar 是 **monochrome 黑白态**(默认开),
      // 选中差异交给字重与滤镜,不用彩色图标 —— 换底后本就是白/灰,
      // 这里补上字重差异,否则选中态只有明度差,弱视场景下不好分辨。
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.bgSurface,
        selectedItemColor: p.textPrimary,
        unselectedItemColor: p.textSecondary,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(
          fontSize: CyTokens.typeMicro,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: CyTokens.typeMicro,
          fontWeight: FontWeight.w400,
        ),
      ),
      // .cy-input / .cy-textarea:bg-card-2 底 + 2rpx border-line 描边
      // + radius-sm + padding 24rpx→12 + font-body,placeholder 用 text-secondary。
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.bgSurfaceSubtle,
        contentPadding: EdgeInsets.all(CyTokens.space3),
        hintStyle: TextStyle(
          color: p.textSecondary,
          fontSize: CyTokens.typeBody,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CyTokens.radiusSm),
          borderSide: BorderSide(color: p.borderStrong, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CyTokens.radiusSm),
          borderSide: BorderSide(color: p.borderStrong, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CyTokens.radiusSm),
          // 聚焦用主文字色描边 —— 黑白系里没有"主题色高亮",靠加重描边表达。
          borderSide: BorderSide(color: p.textPrimary, width: 1),
        ),
      ),
      // .cy-sheet:bg-card + 上两角 radius-lg。
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.bgSurface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(CyTokens.radiusLg),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.bgSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          side: BorderSide(color: p.borderSubtle, width: 1),
        ),
      ),
      // Material TabBar 默认是**满格 3px 粗线 + primary 色**,和小程序的
      // 定宽 36pt 圆角细线完全两回事。4 个页面用 TabBar+TabBarView
      // (结构上合理,不必拆),所以在主题层统一皮肤,而不是逐页改。
      tabBarTheme: TabBarThemeData(
        indicator: CyTabIndicator(color: p.textPrimary),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: p.textPrimary,
        unselectedLabelColor: p.textSecondary,
        labelStyle: const TextStyle(
          fontSize: CyTokens.typeBody,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: CyTokens.typeBody,
          fontWeight: FontWeight.w600,
        ),
        dividerColor: p.borderSubtle,
        dividerHeight: 1, // 2rpx
        // 小程序没有水波纹,点下去只有颜色过渡
        overlayColor: WidgetStatePropertyAll<Color>(Colors.transparent),
      ),
      dividerColor: p.borderSubtle,
    );
  }
}
