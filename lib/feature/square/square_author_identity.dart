import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../data/models/square_post.dart';

/// 作者身份徽章:实名认证 / 会员等级 / 作者徽章 / 通知徽章。
///
/// ★ 真源 `components/cy/post-card/index.wxml:22-25`,四个条件一条不落:
///   · `post.rz`            → 认证标(`:22`)
///   · `memberLevelId > 0`  → `Lv.N`(`:23`)
///   · `post.authorBadge`   → 身份徽章(`:24`)
///   · `post.noticeBadge`   → 通知徽章,轻一档(`:25`)
///
/// App 此前一个都没接 —— 模型上有没有字段都无所谓,列表和详情都不渲染,
/// 于是「小程序能看到认证和等级、App 看不到」这件事用户一眼就能发现。
///
/// 视觉按 §3.5 T3:徽章是次级信息,用 labelSmall + 胶囊底,
/// **不堆字重**(w500 封顶),不抢标题。
class SquareAuthorBadges extends StatelessWidget {
  const SquareAuthorBadges({super.key, required this.post});

  final SquarePost post;

  /// 四个徽章里有没有一个要出。调用方用它决定要不要留间距。
  static bool anyOf(SquarePost post) =>
      post.rz ||
      post.memberLevelId > 0 ||
      (post.authorBadge ?? '').isNotEmpty ||
      (post.noticeBadge ?? '').isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Wrap(
      spacing: CyTokens.space1,
      runSpacing: CyTokens.space1,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        if (post.rz)
          // 形状 + 语义,不靠颜色单独承载状态(V5)。
          Semantics(
            label: '已实名认证',
            child: const ExcludeSemantics(
              child: Icon(
                CupertinoIcons.checkmark_seal_fill,
                size: 14,
                color: CyTokens.brand,
              ),
            ),
          ),
        if (post.memberLevelId > 0)
          _Chip(
            key: const Key('square-author-level'),
            text: 'Lv.${post.memberLevelId}',
            semanticLabel: '等级 ${post.memberLevelId}',
            background: palette.bgSubtle,
            foreground: palette.textSecondary,
          ),
        if ((post.authorBadge ?? '').isNotEmpty)
          _Chip(
            key: const Key('square-author-badge'),
            text: post.authorBadge!,
            semanticLabel: '身份 ${post.authorBadge!}',
            background: palette.brandSoft,
            foreground: palette.brand,
          ),
        if ((post.noticeBadge ?? '').isNotEmpty)
          _Chip(
            key: const Key('square-author-notice-badge'),
            text: post.noticeBadge!,
            semanticLabel: post.noticeBadge!,
            background: palette.bgSubtle,
            foreground: palette.textTertiary,
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.text,
    required this.semanticLabel,
    required this.background,
    required this.foreground,
  });

  final String text;
  final String semanticLabel;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CyTokens.space1_5,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(CyTokens.radiusPill),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w500,
            height: 1.2,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

/// 俱乐部归属(真源 `components/cy/post-card/index.wxml:29`)。
///
/// 有 `clubId` 才可点(真源里 `interactiveClub` 决定的也是这一条);
/// 点了进 `/club/:id`,与广场其它入口同一条路由,不另造。
class SquareClubLink extends StatelessWidget {
  const SquareClubLink({super.key, required this.post});

  final SquarePost post;

  @override
  Widget build(BuildContext context) {
    final String name = (post.clubName ?? '').trim();
    if (name.isEmpty) return const SizedBox.shrink();
    final CyPalette palette = CyPalette.of(context);
    final TextStyle style = Theme.of(
      context,
    ).textTheme.labelSmall!.copyWith(color: palette.textTertiary);
    final int? clubId = post.clubId;
    if (clubId == null || clubId <= 0) {
      return Text(
        name,
        key: const Key('square-author-club'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
        semanticsLabel: '来自俱乐部 $name',
      );
    }
    return CupertinoButton(
      key: const Key('square-author-club-link'),
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      alignment: Alignment.centerLeft,
      onPressed: () => context.push('/club/$clubId'),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style.copyWith(color: palette.textSecondary),
      ),
    );
  }
}
