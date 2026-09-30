import 'package:flutter/cupertino.dart';

import '../../../data/models/npc.dart';
import '../../../core/theme/cy_tokens.dart';
import '../../../core/widgets/cy_net_image.dart';

/// 单条 NPC 冒泡: 头像+名字+文字, 淡入动画。
class NpcBubble extends StatelessWidget {
  const NpcBubble({
    super.key,
    required this.line,
    this.onTap,
    this.showAvatar = true,
  });

  final NpcLine line;
  final VoidCallback? onTap;
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    final Widget bubble = Container(
      margin: const EdgeInsets.symmetric(
        horizontal: CyTokens.space4,
        vertical: CyTokens.space1,
      ),
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: CyTokens.bgElevated.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        border: Border.all(color: CyTokens.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showAvatar && line.avatar != null) ...[
            CyNetImage(
              line.avatar,
              width: 28,
              height: 28,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            ),
            const SizedBox(width: CyTokens.space2),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (line.name != null)
                  Text(
                    line.name!,
                    style: const TextStyle(
                      color: CyTokens.textSecondary,
                      fontSize: CyTokens.typeLabel,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: CyTokens.space1),
                Text(
                  line.line,
                  style: const TextStyle(
                    color: CyTokens.textPrimary,
                    fontSize: CyTokens.typeBody,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            const Padding(
              padding: EdgeInsets.only(left: CyTokens.space2),
              child: Icon(
                CupertinoIcons.text_bubble,
                color: CyTokens.textSecondary,
                size: 18,
              ),
            ),
        ],
      ),
    );
    final VoidCallback? action = onTap;
    if (action == null) return bubble;
    final String label = <String?>[line.name, line.line]
        .where((String? value) => value?.trim().isNotEmpty == true)
        .map((String? value) => value!.trim())
        .join('，');
    return Semantics(
      button: true,
      label: label,
      onTap: action,
      excludeSemantics: true,
      child: CupertinoButton(
        onPressed: action,
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: bubble,
        ),
      ),
    );
  }
}
