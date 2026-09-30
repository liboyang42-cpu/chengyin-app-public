import 'package:flutter/cupertino.dart';

import '../../../core/theme/cy_tokens.dart';
import '../../../data/models/play_check.dart';
import '../advanced/fullscreen/playkit_fullscreen_parts.dart';

// R14 旅程检定三屏。字号逐值真源 tokens.wxss(rpx/2):body 14 / label 12 /
// caption 11 / section-title 18 / display 28 / data-xl 32 —— 与 playkit_scan_view
// 等已复核台面同一口径(该族大字一律 w700,不跟真源 w900,见 T3)。
const Color _jcBg = Color(0xFF0D0D10);
const Color _jcInk = Color(0xFFF6F6F8);
const Color _jcSub = Color(0xFF8A8A92);
const Color _jcSoft = Color(0xFF1B1B20);
const Color _jcAccent = Color(0xFFFF6B6B);
const Color _jcOk = Color(0xFF3ECF8E);
const Color _jcOkSoft = Color(0x2E3ECF8E); // rgba(62,207,142,.18)
const Color _jcDangerSoft = Color(
  0x24E5484D,
); // --cy-color-status-danger-soft rgba(229,72,77,.14)
// .g-btn 白胶囊在六个皮肤上都是白底深字(play-surface.wxss:63–80)。
const Color _jcCtaBg = Color(0xFFFFFFFF);
const Color _jcCtaInk = Color(0xFF111114);
// .g-btn 的 1pt 内描边(rgba(0,0,0,.10))与常投影(0 8pt 20pt rgba(0,0,0,.14)):
// 原型在六个皮肤上一直挂着,不分深浅。
const Color _jcCtaStroke = Color(0x1A000000);
const BoxShadow _jcCtaShadow = BoxShadow(
  color: Color(0x24000000),
  blurRadius: 20,
  offset: Offset(0, 8),
);

/// R14 旅程检定一屏(题面 → 掷 → 结果 → 结算),宿主挂在游玩会话页顶层。
///
/// ★ 结构 1:1 照搬小程序 `pages/play/components/playkit-journey-check/index.wxml`,
/// 皮肤 `skin-qadark`(`style/play-surface.wxss:28`)逐值道具色 ——
/// 与 `playkit_scan_view.dart` 同一口径:玩法台面的墨色不随外观翻转。
/// 这一屏只画服务端给的东西:不自己判成败、不自己编文案。
/// ★ 失败也推进:结算前后都能退出,这一屏不拦节点完成(产品口径)。
class JourneyCheckStage extends StatelessWidget {
  const JourneyCheckStage({
    super.key,
    required this.problem,
    this.receipt,
    this.acting = false,
    required this.onAction,
    required this.onClose,
  });

  final JourneyCheckProblem problem;

  /// null = 题面屏;有回执未结算 = 结果屏;settled = 结算屏。
  final JourneyCheckReceipt? receipt;

  /// 上一次动作(掷/重掷/结算)还在途:按钮点不动,不装成功。
  final bool acting;

  /// 'roll' | 'reroll' | 'settle' —— 与真源 triggerEvent('action', {action}) 同字面值。
  final ValueChanged<String> onAction;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final JourneyCheckReceipt? r = receipt;
    return ColoredBox(
      color: _jcBg,
      child: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  CyTokens.pageX,
                  60,
                  CyTokens.pageX,
                  26,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SizedBox(height: CyTokens.space3),
                    if (r == null)
                      _ProblemFace(problem: problem)
                    else if (!r.settled)
                      _ResultFace(receipt: r)
                    else
                      _SettledFace(receipt: r),
                    // 底部动作条在 Stack 里贴底,内容列给按钮留位。
                    const SizedBox(height: 120),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(CyTokens.space2),
              child: Align(
                alignment: Alignment.topLeft,
                child: Semantics(
                  button: true,
                  label: '退出',
                  child: CupertinoButton(
                    minimumSize: const Size.square(44),
                    padding: EdgeInsets.zero,
                    onPressed: onClose,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        color: CyTokens.overlay,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        CupertinoIcons.xmark,
                        size: 16,
                        color: CupertinoColors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: CyTokens.pageX,
              right: CyTokens.pageX,
              bottom: 30, // .g-btn/.jc__act 都是 safe-area 起 60rpx
              child: _actions(context, r),
            ),
          ],
        ),
      ),
    );
  }

  /// 底部动作:题面一颗「掷骰」;结果屏「重掷 + 结算」;结算屏「继续」。
  /// 守卫与真源逐条对齐(onRoll: loading||receipt;onSettle: loading||!receipt||settled)。
  Widget _actions(BuildContext context, JourneyCheckReceipt? r) {
    final bool rerollVisible = journeyCheckCanReroll(r);
    if (r == null) {
      return _Cta(
        label: '掷骰',
        semanticLabel: '掷骰',
        onPressed: acting
            ? null
            : () {
                playKitHaptic(context, PlayKitHaptic.medium);
                onAction('roll');
              },
      );
    }
    if (!r.settled) {
      return Row(
        children: <Widget>[
          if (rerollVisible) ...<Widget>[
            Expanded(
              child: _GhostButton(
                label: '重掷',
                semanticLabel: '花一点幸运重掷',
                onPressed: acting
                    ? null
                    : () {
                        playKitHaptic(context, PlayKitHaptic.medium);
                        onAction('reroll');
                      },
              ),
            ),
            const SizedBox(width: CyTokens.space3),
          ],
          Expanded(
            flex: rerollVisible ? 2 : 1,
            child: _Cta(
              label: '结算',
              semanticLabel: '结算这次检定',
              dimmed: acting,
              onPressed: acting
                  ? null
                  : () {
                      playKitHaptic(context, PlayKitHaptic.medium);
                      onAction('settle');
                    },
            ),
          ),
        ],
      );
    }
    return _Cta(label: '继续', semanticLabel: '收起检定', onPressed: onClose);
  }
}

/// 题面屏:技能 + 难度档 + 优劣势 + 条件修正逐条给玩家看见。
class _ProblemFace extends StatelessWidget {
  const _ProblemFace({required this.problem});

  final JourneyCheckProblem problem;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        PlayKitKicker(
          problem.skill.isEmpty ? '检定' : problem.skill,
          color: _jcInk,
        ),
        const SizedBox(height: CyTokens.space2),
        Text(
          '难度 · ${journeyCheckTierLabel(problem.tier)}',
          style: const TextStyle(fontSize: CyTokens.typeBody, color: _jcSub),
        ),
        if (problem.advantage || problem.disadvantage) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (problem.advantage) const _Tag(label: '优势', good: true),
              if (problem.advantage && problem.disadvantage)
                const SizedBox(width: CyTokens.space2),
              if (problem.disadvantage) const _Tag(label: '劣势', good: false),
            ],
          ),
        ],
        if (problem.mods.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space5),
            child: _ModList(
              mods: problem.mods,
              keyword: '条件修正',
              showKeyword: true,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space6),
            child: Text(
              '没有附加条件 —— 掷一颗骰子，看过不过得去。',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: CyTokens.typeBody,
                height: 1.7,
                color: _jcSub,
              ),
            ),
          ),
      ],
    );
  }
}

/// 结果屏:骰子 / 达成值 / DC / 成败。文案还没给,这里只报事实。
class _ResultFace extends StatelessWidget {
  const _ResultFace({required this.receipt});

  final JourneyCheckReceipt receipt;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const SizedBox(height: CyTokens.space6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (final int die in receipt.dice) ...<Widget>[
              SizedBox(
                width: 60,
                height: 60,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _jcInk,
                    borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                  ),
                  child: Center(
                    child: Text(
                      '$die',
                      style: const TextStyle(
                        fontSize: 32, // --cy-type-data-xl 64rpx
                        fontWeight: FontWeight.w700,
                        color: _jcBg,
                        fontFeatures: <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: CyTokens.space3),
            ],
          ],
        ),
        const SizedBox(height: CyTokens.space3),
        Text(
          '${receipt.kept ?? ''}',
          style: const TextStyle(
            fontSize: CyTokens.typeDisplay,
            fontWeight: FontWeight.w700,
            color: _jcInk,
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: CyTokens.space1),
        Text(
          '达成值 ${receipt.total} · 难度 ${receipt.dc}',
          style: const TextStyle(fontSize: CyTokens.typeLabel, color: _jcSub),
        ),
        const SizedBox(height: CyTokens.space4),
        Text(
          receipt.success ? '过线了' : '没过线',
          style: TextStyle(
            fontSize: CyTokens.typeSectionTitle,
            fontWeight: FontWeight.w700,
            color: receipt.success ? _jcOk : _jcAccent,
          ),
        ),
        if (receipt.mods.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space4),
            child: _ModList(
              mods: receipt.mods,
              keyword: '',
              showKeyword: false,
            ),
          ),
        if (journeyCheckCanReroll(receipt))
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space3),
            child: Text(
              '还剩幸运，可以重掷一次',
              style: const TextStyle(
                fontSize: CyTokens.typeCaption,
                color: _jcSub,
              ),
            ),
          ),
      ],
    );
  }
}

/// 结算屏:这才是服务端给的文案 + 失败代价 + 生命/幸运读数。
class _SettledFace extends StatelessWidget {
  const _SettledFace({required this.receipt});

  final JourneyCheckReceipt receipt;

  @override
  Widget build(BuildContext context) {
    final int? hp = receipt.hp;
    final int? luck = receipt.luck;
    return Column(
      children: <Widget>[
        Text(
          receipt.success ? '过线了' : '没过线',
          style: TextStyle(
            fontSize: CyTokens.typeSectionTitle,
            fontWeight: FontWeight.w700,
            color: receipt.success ? _jcOk : _jcAccent,
          ),
        ),
        if (receipt.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space4),
            child: Text(
              receipt.text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: CyTokens.typeBody,
                height: 1.8,
                color: _jcInk,
              ),
            ),
          ),
        if (receipt.failCostLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space2),
            child: Text(
              '代价 · ${receipt.failCostLabel}',
              style: const TextStyle(
                fontSize: CyTokens.typeLabel,
                color: _jcAccent,
              ),
            ),
          ),
        if (hp != null || luck != null)
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (hp != null) Text('生命 $hp', style: _vitalStyle),
                if (hp != null && luck != null)
                  const SizedBox(width: CyTokens.space4),
                if (luck != null) Text('幸运 $luck', style: _vitalStyle),
              ],
            ),
          ),
        if (receipt.exhausted)
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space2),
            child: Text(
              '力竭了，先找地方休整',
              style: const TextStyle(
                fontSize: CyTokens.typeCaption,
                color: _jcAccent,
              ),
            ),
          ),
      ],
    );
  }

  static const TextStyle _vitalStyle = TextStyle(
    fontSize: CyTokens.typeLabel,
    color: _jcSub,
  );
}

/// 条件修正列表:label 左、`生效/未生效 ±value` 右;生效行点亮。
class _ModList extends StatelessWidget {
  const _ModList({
    required this.mods,
    required this.keyword,
    required this.showKeyword,
  });

  final List<JourneyCheckMod> mods;
  final String keyword;
  final bool showKeyword;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showKeyword)
          Padding(
            padding: const EdgeInsets.only(bottom: CyTokens.space1),
            child: Text(
              keyword,
              style: const TextStyle(
                fontSize: CyTokens.typeCaption,
                color: _jcSub,
              ),
            ),
          ),
        for (final JourneyCheckMod mod in mods)
          Container(
            padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _jcSoft, width: 1)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Expanded(
                  child: Text(
                    mod.label.isEmpty ? '条件' : mod.label,
                    style: TextStyle(
                      fontSize: CyTokens.typeBody,
                      color: mod.active ? _jcInk : _jcSub,
                    ),
                  ),
                ),
                const SizedBox(width: CyTokens.space2),
                Text(
                  '${mod.active ? '生效 ' : '未生效 '}'
                  '${mod.value > 0 ? '+' : ''}${mod.value}',
                  style: TextStyle(
                    fontSize: CyTokens.typeLabel,
                    fontWeight: mod.active ? FontWeight.w700 : FontWeight.w400,
                    color: mod.active ? _jcOk : _jcSub,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.good});

  final String label;
  final bool good;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: CyTokens.space3,
      vertical: CyTokens.space1,
    ),
    decoration: BoxDecoration(
      color: good ? _jcOkSoft : _jcDangerSoft,
      borderRadius: BorderRadius.circular(CyTokens.radiusPill),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: CyTokens.typeLabel,
        fontWeight: FontWeight.w700,
        color: good ? _jcOk : _jcAccent,
      ),
    ),
  );
}

/// .g-btn 白胶囊:56pt 高、胶囊、白底深字;禁用 .45 透明度(真源 .g-btn--disabled)。
class _Cta extends StatelessWidget {
  const _Cta({
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
    this.dimmed = false,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final bool dimmed;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: dimmed ? 0.45 : 1,
    child: Semantics(
      button: true,
      label: semanticLabel,
      child: DecoratedBox(
        // .g-btn 常态就有 1pt 内描边 + 0 8pt 20pt 投影;禁用态只剩内描边
        // (g-btn--disabled),Opacity .45 由外层 dimmed 承担。
        decoration: BoxDecoration(
          color: _jcCtaBg,
          borderRadius: BorderRadius.circular(28),
          border: const Border.fromBorderSide(BorderSide(color: _jcCtaStroke)),
          boxShadow: dimmed ? null : const <BoxShadow>[_jcCtaShadow],
        ),
        child: CupertinoButton(
          minimumSize: const Size.fromHeight(56),
          padding: EdgeInsets.zero,
          pressedOpacity: 0.88,
          onPressed: onPressed,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 17, // .g-btn 35rpx
                fontWeight: FontWeight.w600, // 真源 800,T3 收敛为 semibold
                color: _jcCtaInk,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// .jc__act--ghost:次级胶囊(soft 底墨字)。
class _GhostButton extends StatelessWidget {
  const _GhostButton({
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    child: CupertinoButton(
      minimumSize: const Size.fromHeight(56),
      padding: EdgeInsets.zero,
      pressedOpacity: 0.88,
      onPressed: onPressed,
      color: _jcSoft,
      borderRadius: BorderRadius.circular(28),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            fontSize: CyTokens.typeButton, // .jc__act 32rpx=16(这颗没有 .g-btn)
            fontWeight: FontWeight.w600, // 真源 800,T3 收敛为 semibold
            color: _jcInk,
          ),
        ),
      ),
    ),
  );
}
