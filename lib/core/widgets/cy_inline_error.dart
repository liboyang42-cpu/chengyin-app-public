import 'package:flutter/cupertino.dart';

import '../theme/cy_palette.dart';
import '../theme/cy_tokens.dart';

/// 提交失败的页内错误条(真源 `cy-inline-error`):主标固定语义,副标是失败
/// 原因(网络/后端原话),动作可选 —— 弹窗会把表单上下文整个丢掉,所以不弹窗。
class CyInlineError extends StatelessWidget {
  const CyInlineError({
    super.key,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space3,
        vertical: CyTokens.space2,
      ),
      decoration: BoxDecoration(
        color: palette.statusDanger.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // 状态不只靠颜色(V5):警示形状 + 文字两路一起说。
          Icon(
            CupertinoIcons.exclamationmark_triangle_fill,
            size: 20,
            color: palette.statusDanger,
          ),
          const SizedBox(width: CyTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: CyType.headline.copyWith(color: palette.textPrimary),
                ),
                const SizedBox(height: CyTokens.space1),
                Text(
                  detail,
                  style: CyType.footnote.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null) ...<Widget>[
            const SizedBox(width: CyTokens.space3),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(
                horizontal: CyTokens.space3,
                vertical: CyTokens.space2,
              ),
              minimumSize: const Size(72, CyTokens.btnH),
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: CyType.caption1.copyWith(
                  fontWeight: FontWeight.w600,
                  color: palette.brand,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
