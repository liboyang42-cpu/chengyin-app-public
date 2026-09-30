import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/cy_tokens.dart';
import '../../../../data/models/checkin_models.dart';

/// 卡片详情段③:本站游戏 —— **叙事优先的到店态**。
///
/// 版面次序:一条角色/故事钩子([storyOf])→ 一条行动指令
/// ([actionInstructionOf])→ 次级规格行(时长/人数/权益/材料);
/// 其余玩法规则折叠进「怎么玩」帮助入口,要看再展开。规格不抢主视觉,
/// 玩家这一屏的主要动作仍是详情页底部的主 CTA,本段不与它争。
///
/// ★ 判据是 **gameTitle 非空(含 [gameTitleOf] 那条回落)或有 storyText**,
///   不是 [PlayNode.hasGame] —— 与小程序 `wx:if="{{hero.node.gameTitle}}"`
///   (index.wxml:431)同一条。
///   后端 `!arrived` 那条 removeAll 摘 gameTitle/ruleInstructions 却**不摘**
///   hasGame 和 duration/players/difficulty/requiredMaterials
///   (ApiPlayProgressController:681-705),所以按 hasGame 判,「有玩法 + 还没扫码」
///   会渲出一个没标题、没「怎么玩」的孤儿段。整块到店后才长出来才是对的。
///
/// ⚠️ 答案类字段(question/options/answerReveal/feedbackText)对探店日是
///   fail-closed 一律剥,不接、不渲染。
class GameSection extends StatelessWidget {
  const GameSection({super.key, required this.node});

  final PlayNode node;

  /// 段③出不出现的**唯一判据**,调用方(段间距)与本组件共用一份,免得两处漂。
  ///
  /// ★ **硬闸 `node.arrived` 排在最前**:未到店时整段绝不渲染,哪怕后端投影
  ///   异常误发了 gameTitle / storyText。叙事是到店态,未到店没有这一屏。
  ///   到店后才是叙事优先(有 `storyText` 也成段)。
  static bool visibleFor(PlayNode node) =>
      node.arrived && (gameTitleOf(node) != null || storyOf(node) != null);

  /// 叙事钩子:`storyText` 非空才算。
  ///
  /// ⚠️ **缺失不回落 [PlayNode.hookText]** —— hookText 是「小瘾说」,由详情页
  ///   单独渲染(index.wxml:573 的 place-hook),这里再念一遍就是同一句出现两次。
  static String? storyOf(PlayNode node) {
    final String? story = node.storyText;
    return (story != null && story.isNotEmpty) ? story : null;
  }

  /// 行动指令:拍照任务优先用拍摄要求,否则取规则首行。没有就不占位。
  static String? actionInstructionOf(PlayNode node) {
    final String? photo = node.photoRequireDesc;
    if (photo != null && photo.isNotEmpty) return photo;
    final List<String> rules = rulesOf(node);
    return rules.isEmpty ? null : rules.first;
  }

  /// 规则按换行分条(原样机 index.js:2718 口径)。
  static List<String> rulesOf(PlayNode node) => (node.ruleInstructions ?? '')
      .split('\n')
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList();

  /// 折叠进帮助入口的规则。
  /// 行动指令若已占用规则首行,就跳过它 —— 展开后不重复同一条。
  static List<String> foldedRulesOf(PlayNode node) {
    final List<String> rules = rulesOf(node);
    final String? photo = node.photoRequireDesc;
    if (photo != null && photo.isNotEmpty) return rules;
    return rules.length <= 1 ? const <String>[] : rules.sublist(1);
  }

  /// 模板没配 gameTitle 时,按 validationMethod 回落一个通用名 ——
  /// 小程序 normNode 就这么写(index.js:2717):
  /// `n.gameTitle || (vm===6 ? '生活偏好校准' : vm===4 ? '现场打卡'
  ///                : vm===2 ? '拍照任务' : (vm ? '点位任务' : ''))`。
  ///
  /// ⚠️ **vm 拿不到就返回 null,整段不渲染**。未到店时后端把 gameTitle 和
  ///   validationMethod 一起摘掉(ApiPlayProgressController:703-705 的清单里
  ///   两个都在),这时若也回落成「点位任务」,未到店会凭空长出一个段 ——
  ///   正是段③判据当初改掉 hasGame 要躲的那个孤儿段。
  ///   vm=0(到达即完成)在小程序里也是 falsy,同样不回落。
  static String? gameTitleOf(PlayNode node) {
    final String? title = node.gameTitle;
    if (title != null && title.isNotEmpty) return title;
    return switch (node.validationMethod) {
      6 => '生活偏好校准',
      4 => '现场打卡',
      2 => '拍照任务',
      null || 0 => null,
      _ => '点位任务',
    };
  }

  /// 眉标后缀「· 拍照任务 / 答题 / 现场打卡」,由 validationMethod 推
  /// (小程序 index.js:1557 同表)。推不出就不接后缀。
  static String? gameKind(PlayNode node) {
    switch (node.validationMethod) {
      case 2:
        return '拍照任务';
      case 1:
      case 3:
        return '答题';
      case 4:
        return '现场打卡';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!visibleFor(node)) return const SizedBox.shrink();
    final String? gameTitle = gameTitleOf(node);
    final String? story = storyOf(node);

    final String? kind = gameKind(node);
    // ★ vm=2/4 缺 gameTitle 时 [gameTitleOf] 会合成一个与 [gameKind] 同名的标题
    //   (拍照任务 / 现场打卡),眉标再缀一遍类型名就是同一句出现两次 ——
    //   同名时眉标退回裸「本站游戏」,标题位保留那个名字。
    final bool titleDuplicatesKind = gameTitle != null && gameTitle == kind;
    final String? instruction = actionInstructionOf(node);
    final List<String> foldedRules = foldedRulesOf(node);

    // 规格信息(时长 / 人数 / 权益名),退到卡片底部的小字行 ——
    // 不抢叙事与行动指令的主视觉。(difficulty 样机不进这一行,故此处不取。)
    final List<(IconData, String)> metaParts = <(IconData, String)>[
      // ★ 判据是 falsy 不是 non-null:样机两处都写 `n.duration ? … : ''`
      //   (index.js:2718 / 1532),0 不出现。后端 duration 是 Long,后台表单
      //   默认值就可能是 0 —— 「🕐 0 分钟」是编出来的信息,比不显示更糟。
      //   本仓同口径:template_list_page.dart:111 的 `duration <= 0 ? null`。
      if (node.duration != null && node.duration! > 0)
        (Icons.schedule, '${node.duration} 分钟'),
      if (node.players != null && node.players!.isNotEmpty)
        (Icons.people_outline, node.players!),
      if (node.perk != null) (Icons.card_giftcard, node.perk!.name),
    ];

    final String? materials =
        (node.requiredMaterials != null && node.requiredMaterials!.isNotEmpty)
        ? node.requiredMaterials
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          (kind == null || titleDuplicatesKind) ? '本站游戏' : '本站游戏 · $kind',
          style: const TextStyle(
            color: CyTokens.textTertiary,
            fontSize: CyTokens.typeCaption,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: CyTokens.space3),
        // 叙事卡:故事钩子 → 一条行动指令 → 次级规格行。
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(CyTokens.space4),
          decoration: BoxDecoration(
            color: CyTokens.bgSurface,
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
            border: Border.all(color: CyTokens.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (gameTitle != null)
                Text(
                  gameTitle,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: CyTokens.typeCardTitle,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (story != null) ...[
                if (gameTitle != null) const SizedBox(height: CyTokens.space2),
                Text(
                  story,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: CyTokens.typeBody,
                    height: CyTokens.leadingLoose,
                  ),
                ),
              ],
              if (instruction != null) ...[
                const SizedBox(height: CyTokens.space3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.play_arrow_rounded,
                      size: 18,
                      color: AppColors.textPrimary,
                    ),
                    const SizedBox(width: CyTokens.space1_5),
                    Expanded(
                      child: Text(
                        instruction,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: CyTokens.typeLabel,
                          fontWeight: FontWeight.w600,
                          height: CyTokens.leadingNormal,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (metaParts.isNotEmpty || materials != null) ...[
                const SizedBox(height: CyTokens.space3),
                Wrap(
                  spacing: CyTokens.space4,
                  runSpacing: CyTokens.space1_5,
                  children: <Widget>[
                    for (final (IconData icon, String text) in metaParts)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(icon, size: 13, color: CyTokens.textTertiary),
                          const SizedBox(width: CyTokens.space1),
                          Text(
                            text,
                            style: const TextStyle(
                              color: CyTokens.textTertiary,
                              fontSize: CyTokens.typeCaption,
                            ),
                          ),
                        ],
                      ),
                    if (materials != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.inventory_2_outlined,
                            size: 13,
                            color: CyTokens.textTertiary,
                          ),
                          const SizedBox(width: CyTokens.space1),
                          Text(
                            '所需材料 · $materials',
                            style: const TextStyle(
                              color: CyTokens.textTertiary,
                              fontSize: CyTokens.typeCaption,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        // 玩法规则折叠到帮助入口:叙事与行动指令在前,规则要看再展开。
        if (foldedRules.isNotEmpty) ...[
          const SizedBox(height: CyTokens.space2),
          _RulesHelp(rules: foldedRules),
        ],
      ],
    );
  }
}

/// 玩法规则折叠入口。默认收起 —— 只有 [rules] 非空时才会被挂上。
class _RulesHelp extends StatefulWidget {
  const _RulesHelp({required this.rules});

  final List<String> rules;

  @override
  State<_RulesHelp> createState() => _RulesHelpState();
}

class _RulesHelpState extends State<_RulesHelp> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 仓库风格的可访问按钮:CupertinoButton(44pt 最小热区)+ Semantics 承载
        // label / button / expanded,ExcludeSemantics 避免「怎么玩」子文案再成节点。
        // 不用裸 GestureDetector —— 那样只有 tap 没有 button、也不暴露展开态。
        Semantics(
          container: true,
          button: true,
          expanded: _open,
          label: _open ? '收起玩法规则' : '展开玩法规则',
          onTap: () => setState(() => _open = !_open),
          child: ExcludeSemantics(
            child: CupertinoButton(
              onPressed: () => setState(() => _open = !_open),
              minimumSize: const Size(CyTokens.btnH, CyTokens.btnH),
              padding: EdgeInsets.zero,
              pressedOpacity: MediaQuery.disableAnimationsOf(context) ? 1 : 0.4,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: CyTokens.btnH),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '怎么玩',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: CyTokens.typeLabel,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: CyTokens.space1),
                    Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < widget.rules.length; i++) ...[
                  if (i > 0) const SizedBox(height: CyTokens.space1_5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${i + 1}.',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: CyTokens.typeCaption,
                          height: CyTokens.leadingLoose,
                        ),
                      ),
                      const SizedBox(width: CyTokens.space1_5),
                      Expanded(
                        child: Text(
                          widget.rules[i],
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: CyTokens.typeCaption,
                            height: CyTokens.leadingLoose,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
