import 'package:flutter/material.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import 'finance_state_text.dart';

/// 资金域的一条竖向进度节点。批次明细和核销详情**共用同一条时间线**。
///
/// ★ 抽出来是因为两页各画一遍必然画歪一处:真源也是同一套 `.fin-tl` 样式类。
class FinanceTimelineRow extends StatelessWidget {
  const FinanceTimelineRow({super.key, required this.node});

  final BatchTimelineNode node;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final CyPalette p = CyPalette.of(context);
    final bool done = node.state == 'done';
    final bool now = node.state == 'now';
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            done
                ? Icons.check_circle
                : (now ? Icons.radio_button_checked : Icons.circle_outlined),
            size: 16,
            color: done
                ? p.statusSuccess
                : (now ? p.statusWarning : p.textTertiary),
          ),
          const SizedBox(width: CyTokens.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  node.label,
                  style: textTheme.bodyMedium?.copyWith(
                    color: done || now ? p.textPrimary : p.textTertiary,
                  ),
                ),
                // ★ 只有服务端真给了时间的节点才有小字 —— 未来节点不写「预计」。
                if (node.at != null)
                  Text(
                    node.at!,
                    style: textTheme.labelSmall?.copyWith(
                      color: p.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
