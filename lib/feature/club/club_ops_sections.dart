import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';

/// 运营四页共用的区块骨架 —— 逐字对齐小程序 `.section / .section-title /
/// .section-note / .card / .row / .divider`(event-ops/index.wxss 顶部注释那批值):
/// 区块左对齐 page-x,卡片 bg-elevated + radius-md,行与行之间发丝分隔,
/// 卡片不再画外描边(2026-09-02 对齐 Figma 的结论)。
///
/// ⚠️ 只服务 club 运营四页,不进 core/widgets —— 共用层组件归 `feat/shared-widgets-p2`
///   那条线统一收口,这里不抢跑。
class ClubOpsSection extends StatelessWidget {
  const ClubOpsSection({
    super.key,
    required this.title,
    this.note,
    this.caption,
    this.trailing,
    required this.children,
  });

  final String title;
  final String? note;
  final String? caption;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space4,
        CyTokens.pageX,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: CyTokens.typeSectionTitle,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          if (note != null) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            Text(
              note!,
              style: TextStyle(
                fontSize: CyTokens.typeCaption,
                height: 1.45,
                color: palette.textTertiary,
              ),
            ),
          ],
          if (caption != null) ...<Widget>[
            const SizedBox(height: CyTokens.space1),
            Text(
              caption!,
              style: TextStyle(
                fontSize: CyTokens.typeCaption,
                color: palette.textTertiary,
              ),
            ),
          ],
          ...children,
        ],
      ),
    );
  }
}

/// `.card` + `.divider`:页面上的卡容器,行之间自动插发丝线。
class ClubOpsCard extends StatelessWidget {
  const ClubOpsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < children.length; i += 1) {
      if (i > 0) rows.add(const ClubOpsDivider());
      rows.add(children[i]);
    }
    return Container(
      margin: const EdgeInsets.only(top: CyTokens.space3),
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgElevated,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

class ClubOpsDivider extends StatelessWidget {
  const ClubOpsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.space4),
      child: Container(height: 1, color: CyPalette.of(context).borderSubtle),
    );
  }
}

/// `.row`:标题/描述在左,值或动作在右;min-height 60pt,横向 padding 16。
class ClubOpsRow extends StatelessWidget {
  const ClubOpsRow({
    super.key,
    required this.title,
    this.meta,
    this.metaLines = 1,
    this.leading,
    this.value,
    this.valueColor,
    this.titleColor,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.minHeight = 60,
  });

  final String title;
  final String? meta;
  final int metaLines;
  final Widget? leading;
  final String? value;
  final Color? valueColor;

  /// 标题色覆盖(危险动作行,如「结束主题」)。不传走 [CyPalette.textPrimary]。
  final Color? titleColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// 禁用态:压暗且不响应点按(小程序 `.row--disabled`)。
  final bool enabled;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final Color resolvedTitleColor = enabled
        ? (titleColor ?? palette.textPrimary)
        : palette.textDisabled;
    final Color metaColor = enabled ? palette.textTertiary : palette.textDisabled;
    final Widget content = Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space4,
        vertical: CyTokens.space2,
      ),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading!,
            const SizedBox(width: CyTokens.space3),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: CyTokens.typeBody,
                    color: resolvedTitleColor,
                  ),
                ),
                if (meta != null && meta!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 1.5),
                  Text(
                    meta!,
                    maxLines: metaLines,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: CyTokens.typeCaption,
                      height: 1.35,
                      color: metaColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (value != null) ...<Widget>[
            const SizedBox(width: CyTokens.space2),
            Text(
              value!,
              style: TextStyle(
                fontSize: CyTokens.typeLabel,
                color: enabled
                    ? (valueColor ?? palette.textTertiary)
                    : palette.textDisabled,
              ),
            ),
          ],
          if (trailing != null) ...<Widget>[
            const SizedBox(width: CyTokens.space2),
            trailing!,
          ],
        ],
      ),
    );
    if (onTap == null || !enabled) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: content,
    );
  }
}

/// 行内文字动作(小程序 `.row-link`),如「解封」「撤销」。
class ClubOpsRowLink extends StatelessWidget {
  const ClubOpsRowLink({
    super.key,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onTap;
  final bool danger;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        alignment: Alignment.centerRight,
        child: Text(
          label,
          style: TextStyle(
            fontSize: CyTokens.typeLabel,
            fontWeight: FontWeight.w600,
            color: !enabled
                ? palette.textDisabled
                : (danger ? palette.statusDanger : palette.textPrimary),
          ),
        ),
      ),
    );
  }
}
