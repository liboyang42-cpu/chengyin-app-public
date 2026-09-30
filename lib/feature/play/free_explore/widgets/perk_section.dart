import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/cy_tokens.dart';
import '../../../../data/models/checkin_models.dart';

/// 卡片详情段⑤:本店权益。缺就整段不渲染 —— 调用方按 `perk == null` 判断。
///
/// ★ 用户 09-07 当面定:到店三步是绿、本店权益是橙。橙取现有色板里语义最近的
/// `CyTokens.statusWarning`(= `AppColors.warning`,深色主题下调亮的琥珀色),
/// 不新造颜色常量。
class PerkSection extends StatelessWidget {
  const PerkSection({super.key, required this.perk});

  final PlayPerk perk;

  @override
  Widget build(BuildContext context) {
    final String? validEndText = _formatValidEnd(perk.validEnd);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '本店权益',
          style: TextStyle(
            color: CyTokens.textTertiary,
            fontSize: CyTokens.typeCaption,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: CyTokens.space3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.card_giftcard, size: 20, color: AppColors.warning),
            const SizedBox(width: CyTokens.space2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    perk.name,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: CyTokens.typeCardTitle,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: CyTokens.space1_5),
                  // 样机 index.js:1564 `perk.redeemRule || '到店出示核销'`:
                  // 整行不渲染会让权益看着没有兑换方式,而兑换方式恰恰是它的用法。
                  Text(
                    (perk.redeemRule != null && perk.redeemRule!.isNotEmpty)
                        ? perk.redeemRule!
                        : '到店出示核销',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: CyTokens.typeCaption),
                  ),
                  if (validEndText != null) ...[
                    const SizedBox(height: CyTokens.space1),
                    Text(
                      validEndText,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: CyTokens.typeCaption),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 「有效期至 M/D」的 M/D 取的是**中国日历**字段,不是设备本地的。
///
/// ★★ 与小程序 `chinaParts()`(utils/datetime.js:82)同一条算法,`perkValid`
///   (index.js:1565)就这么算:先把瞬时 +8h,再用 `getUTC*` 取字段,**刻意不依赖
///   运行环境时区**。用 `toLocal()` 的话,手机时区在美西时 12/31 到期的权益会显示
///   「有效期至 12/30」—— 而且这台开发机就是 PDT,基线 png 一度把 12/30 烤了进去。
///
/// 解析口径也照 `toTimestamp()`:
///   · 带时区标记(Z / ±HH:MM)⇒ 是绝对时刻,转 UTC 后 +8h 读字段;
///   · 不带 ⇒ 后端裸串语义就是中国时间(CoopPerk.validEnd 是
///     `@JsonFormat(pattern="yyyy-MM-dd")`),字面即日历字段,按 UTC 解析读回来即可,
///     绝不让设备时区插一脚。
String? _formatValidEnd(String? validEnd) {
  final DateTime? china = chinaCalendar(validEnd);
  return china == null ? null : '有效期至 ${china.month}/${china.day}';
}

@visibleForTesting
DateTime? chinaCalendar(String? raw) {
  String s = (raw ?? '').trim();
  if (s.isEmpty) return null;
  if (RegExp(r'([zZ]|[+-]\d{2}:?\d{2})$').hasMatch(s)) {
    return DateTime.tryParse(s)?.toUtc().add(const Duration(hours: 8));
  }
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) s = '$s 00:00:00';
  return DateTime.tryParse('${s}Z');
}
