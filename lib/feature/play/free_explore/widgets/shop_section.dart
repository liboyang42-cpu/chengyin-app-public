import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/cy_tokens.dart';
import '../../../../core/widgets/cy_net_image.dart';
import '../../../../data/models/checkin_models.dart';

/// 卡片详情段②:店铺卡(整卡可点进分身对话)+ 独立地址/导航行。
///
/// 照样机 `index.wxml:394-424`:两块在同一张玻璃底上，各自一个手势 ——
/// 嵌进店铺卡的可点区域会跟「进分身对话」的手势打架。
///
/// ★ 没有 npc 不渲染分身行(没有分身就没有可点的东西)；
/// ★ 地址行的判据是**有没有地址**(样机 `wx:if="{{hero.node.address}}"`)，
///   不是有没有坐标 —— 商家录了地址却缺坐标时，把地址一起吞掉是内容回归。
///   [onTapNav] 为 null 只是**不挂导航手势、不显示「导航」二字**(不做点了没反应的
///   假入口)，地址照样看得见。
class ShopSection extends StatelessWidget {
  const ShopSection({
    super.key,
    required this.node,
    required this.onTapShop,
    required this.onTapNav,
  });

  final PlayNode node;

  /// 进分身对话(批 4 才有目的地；本批传 null = 整卡不可点)。
  final VoidCallback? onTapShop;

  /// 导航。★ 无坐标时**也照挂** —— 样机 `.fx-shop__nav` 的判据只有
  /// `wx:if="{{address}}"`(index.wxml:420),点了由 `openHeroNav` 回一句
  /// 「这家还没标坐标」(index.js:1516)。整行不渲染的话用户根本不知道
  /// 这里本该能导航,也拿不到那句解释。
  final VoidCallback onTapNav;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '店铺',
          style: TextStyle(
            color: CyTokens.textTertiary,
            fontSize: CyTokens.typeCaption,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: CyTokens.space3),
        ClipRRect(
          borderRadius: BorderRadius.circular(CyTokens.radiusLg),
          child: ColoredBox(
            color: CyTokens.actionSecondaryBg,
            child: Column(
              children: [
                _ShopTop(node: node, onTap: onTapShop),
                if (node.address.isNotEmpty)
                  _AddressRow(address: node.address, onTap: onTapNav),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ShopTop extends StatelessWidget {
  const _ShopTop({required this.node, required this.onTap});

  final PlayNode node;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // ★ 一次 build 里算一次就够 —— 原来 if 判一次、渲染再算一次。
    final String? status = _statusText(node);
    final Color? dot = _statusDot(node);
    final Widget content = Padding(
      padding: const EdgeInsets.all(CyTokens.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (node.imgUrl != null && node.imgUrl!.isNotEmpty) ...[
            CyNetImage(
              node.imgUrl!.split(',').first,
              width: 48,
              height: 48,
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            ),
            const SizedBox(width: CyTokens.space3),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: CyTokens.typeBody,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (dot != null) ...[
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: dot,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: CyTokens.space1),
                      ],
                      Flexible(
                        child: Text(
                          status,
                          style: const TextStyle(
                            color: CyTokens.textTertiary,
                            fontSize: CyTokens.typeCaption,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (node.npc != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${node.npc!.name} · 店铺替身 在店里',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: CyTokens.typeCaption,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 20, color: CyTokens.textTertiary),
        ],
      ),
    );
    if (onTap == null) return content;
    // 读屏拿到的不能是「店名 + 营业中 + 阿旧 · 店铺替身 在店里」那一大串粘连文本,
    // 也不能只有 tap 没有 button —— 样机两处都写了 aria-role="button" + 专门的 label。
    return Semantics(
      container: true,
      button: true,
      // ⚠️ 没有分身时不能回落成「和 {店名} 对话」:那家点了也不进页,
      //    入口(card_detail_page.dart:131)只弹一句「这家还没有店铺分身」。
      //    读屏念出「和 长乐路旧物店 对话」= 承诺了一个点不开的东西。
      label: node.npc != null
          ? '和 ${node.npc!.name} 对话'
          : '${node.name}，这家还没有店铺分身',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      ),
    );
  }

  /// `node.done ? '已核销' : openStatus(后端三态,直接用,不在端上从 businessTime 反推)`,
  /// 后面接 `· 今日 {businessTime}`(businessTime 为空则整个后缀不接)。
  ///
  /// ★ 「今日 …」在样机里排在 `wx:else` **之外**(index.wxml:408-413)——
  ///   已核销照渲营业时间,别一进 done 就直接 return。
  static String? _statusText(PlayNode node) {
    final String? head = node.done
        ? '已核销'
        : (node.openStatus != null && node.openStatus!.isNotEmpty)
        ? node.openStatus
        : null;
    final String? tail = (node.businessTime != null && node.businessTime!.isNotEmpty)
        ? '今日 ${node.businessTime}'
        : null;
    final List<String> parts = [?head, ?tail];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// 营业态圆点(样机 `.fx-tile__dot` + `resolveOpenState` 的 openDot)。
  /// ⚠️ 小程序那边 OPEN_OK 与 OPEN_SOON 是**同一个常量** `--cy-color-play-accent`
  /// (= #FFFFFF),只有已打烊落到 text-tertiary —— 玩家端是单色契约,不是三色。
  /// 已核销和读不出营业态时不挂点(一个没有文字的灰点读不出任何意思)。
  static Color? _statusDot(PlayNode node) {
    if (node.done) return null;
    switch (node.openStatus) {
      case '营业中':
      case '即将打烊':
        return AppColors.textPrimary;
      case null:
        return null;
      case final String s when s.isEmpty:
        return null;
      default:
        return CyTokens.textTertiary;
    }
  }
}

/// 地址行。有地址就渲染,「导航」始终在(样机 index.wxml:420-425)。
class _AddressRow extends StatelessWidget {
  const _AddressRow({required this.address, required this.onTap});

  final String address;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Widget row = Container(
      margin: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
      // ★ 44pt 是 iOS HIG / Material 的最小触达尺寸;原来实测 41.0pt。
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: CyTokens.borderSubtle)),
      ),
      child: Row(
        children: [
          const Icon(Icons.place_outlined, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: CyTokens.space2),
          Expanded(
            child: Text(
              address,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: CyTokens.typeCaption,
              ),
            ),
          ),
          const Text(
            '导航',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: CyTokens.typeCaption,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Icon(Icons.chevron_right, size: 16, color: AppColors.textPrimary),
        ],
      ),
    );
    return Semantics(
      container: true,
      button: true,
      label: '导航到 $address',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: row,
      ),
    );
  }
}
