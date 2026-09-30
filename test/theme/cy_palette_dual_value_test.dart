// C4 双值守卫(手册 §3.6)。
//
// ★ 为什么需要:HIG 要求「即使只发一种外观,每个颜色也要有浅/深两个值」——
//   因为玻璃/材质要按背后的内容取色,缺一端就会在玻璃上露馅。仓里两端主题
//   是「暗端玩家 / 浅端商家」,最容易出的错不是漏字段(编译器管),而是**浅端
//   悄悄用了暗端的值而没人发现**:页面白底上戳一张黑卡、白字压白底,不抛错、
//   单测全绿(2026-08-19 一天撞三次)。这条闸把「两端必须不同」变成可执行断言。
//
// ★ 例外清单是**白名单式的**:两端同值必须在此处逐条写明理由;新增同值字段
//   会让本测试红,逼着人说明「为什么这个色两端可以一样」。
//
// ★ 负控:`identicalFields` 对被人为改成同值的调色板必须能报出来。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/theme/cy_palette.dart';
import 'package:chengyin_app/core/theme/cy_tokens.g.dart';

/// 两端**允许**相同的字段 → 理由。
const Map<String, String> kSameOnBothThemes = <String, String>{
  'overlay': '遮罩就是压暗层:rgba(0,0,0,.56),压黑底和白底都需要同一档暗度',
};

Map<String, Object> paletteFields(CyPalette p) => <String, Object>{
  'bgPage': p.bgPage,
  'bgSurface': p.bgSurface,
  'bgSurfaceSubtle': p.bgSurfaceSubtle,
  'bgSurfaceStrong': p.bgSurfaceStrong,
  'bgElevated': p.bgElevated,
  'textPrimary': p.textPrimary,
  'textSecondary': p.textSecondary,
  'textTertiary': p.textTertiary,
  'textPlaceholder': p.textPlaceholder,
  'textDisabled': p.textDisabled,
  'textInverse': p.textInverse,
  'borderSubtle': p.borderSubtle,
  'borderStrong': p.borderStrong,
  'overlay': p.overlay,
  'cardBorder': p.cardBorder,
  'bgSubtle': p.bgSubtle,
  'bgGlass': p.bgGlass,
  'actionPrimaryBg': p.actionPrimaryBg,
  'actionPrimaryFg': p.actionPrimaryFg,
  'actionSecondaryBg': p.actionSecondaryBg,
  'brand': p.brand,
  'brandSoft': p.brandSoft,
  'inputBgEmpty': p.inputBgEmpty,
  'inputBgFilled': p.inputBgFilled,
  'statePressed': p.statePressed,
  'statusInfo': p.statusInfo,
  'statusWarning': p.statusWarning,
  'statusSuccess': p.statusSuccess,
  'statusDanger': p.statusDanger,
  'inputPlaceholder': p.inputPlaceholder,
  'onCoverFg': p.onCoverFg,
};

/// 两端取值相同的字段名。
List<String> identicalFields(CyPalette a, CyPalette b) {
  final Map<String, Object> fa = paletteFields(a);
  final Map<String, Object> fb = paletteFields(b);
  return <String>[
    for (final String key in fa.keys)
      if (fa[key] == fb[key]) key,
  ];
}

void main() {
  test('★ 两端主题的每个语义色都必须有自己的值(例外逐条登记)', () {
    final List<String> identical = identicalFields(
      CyPalette.dark,
      CyPalette.light,
    );
    expect(
      identical.toSet(),
      kSameOnBothThemes.keys.toSet(),
      reason:
          '这些色在深浅两端取同一个值:${identical.join(', ')}。'
          '新增同值必须先在 kSameOnBothThemes 写明理由;'
          '若是漏给浅色值,请补 CyGeneratedLightTokens 映射。',
    );
  });

  test('卡片「描边 vs 投影」两端互斥,不许都空/都有', () {
    expect(CyPalette.dark.cardShadow, isEmpty, reason: '暗端黑底上投影不可见,卡片靠描边立起来');
    expect(
      CyPalette.light.cardShadow,
      isNotEmpty,
      reason: '浅端白卡贴白底,没有投影卡片就消失了',
    );
  });

  test('新增状态语义色直接来自生成物,不许手写字面量', () {
    expect(CyPalette.dark.statusDanger, CyGeneratedTokens.colorStatusDanger);
    expect(
      CyPalette.light.statusDanger,
      CyGeneratedLightTokens.colorStatusDanger,
    );
    expect(CyPalette.dark.statusSuccess, CyGeneratedTokens.colorStatusSuccess);
    expect(
      CyPalette.light.statusSuccess,
      CyGeneratedLightTokens.colorStatusSuccess,
    );
    expect(CyPalette.dark.statusWarning, CyGeneratedTokens.colorStatusWarning);
    expect(
      CyPalette.light.statusWarning,
      CyGeneratedLightTokens.colorStatusWarning,
    );
    expect(CyPalette.dark.statusInfo, CyGeneratedTokens.colorStatusInfo);
    expect(CyPalette.light.statusInfo, CyGeneratedLightTokens.colorStatusInfo);
    expect(CyPalette.dark.statePressed, CyGeneratedTokens.colorStatePressed);
    expect(
      CyPalette.light.statePressed,
      CyGeneratedLightTokens.colorStatePressed,
    );
    expect(
      CyPalette.dark.inputPlaceholder,
      CyGeneratedTokens.colorInputPlaceholder,
    );
    expect(
      CyPalette.light.inputPlaceholder,
      CyGeneratedLightTokens.colorInputPlaceholder,
    );
    expect(CyPalette.dark.onCoverFg, CyGeneratedTokens.colorActionPrimaryFg);
    expect(
      CyPalette.light.onCoverFg,
      CyGeneratedLightTokens.colorActionPrimaryFg,
    );
  });

  test('★ 状态色两端不同:浅端是 R1 调过对比度的深色原语', () {
    for (final String key in <String>[
      'statusInfo',
      'statusWarning',
      'statusSuccess',
      'statusDanger',
    ]) {
      expect(
        paletteFields(CyPalette.dark)[key],
        isNot(paletteFields(CyPalette.light)[key]),
        reason: '$key 两端同值 —— 暗端值压在商家白底上不达 AA',
      );
    }
  });

  test('负控:人为把浅端值塞回暗端,identicalFields 必须报出来', () {
    final CyPalette mutated = CyPalette.dark.copyWith(
      bgPage: CyPalette.light.bgPage,
      statusDanger: CyPalette.light.statusDanger,
    );
    expect(
      identicalFields(mutated, CyPalette.light),
      containsAll(<String>['bgPage', 'statusDanger']),
      reason: '守卫失效 = 两端同值会被静默放行',
    );
  });

  test('copyWith / lerp 覆盖新增字段', () {
    final CyPalette p = CyPalette.dark.copyWith(
      statusSuccess: CyPalette.light.statusSuccess,
      inputPlaceholder: CyPalette.light.inputPlaceholder,
    );
    expect(p.statusSuccess, CyPalette.light.statusSuccess);
    expect(p.inputPlaceholder, CyPalette.light.inputPlaceholder);
    final CyPalette mid = CyPalette.dark.lerp(CyPalette.light, 1);
    expect(mid.statusSuccess, CyPalette.light.statusSuccess);
    expect(mid.statePressed, CyPalette.light.statePressed);
  });
}
