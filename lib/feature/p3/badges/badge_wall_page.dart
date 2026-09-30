import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/cy_palette.dart';
import '../../../core/theme/cy_tokens.dart';
import '../../../core/widgets/cy_native_button.dart';
import '../../../core/widgets/cy_tabs.dart';
import '../../../core/widgets/status_view.dart';
import '../../auth/auth_controller.dart';
import '../../auth/login_gate.dart';
import 'badge_detail_logic.dart';
import 'badge_wall_controller.dart';
import 'badge_wall_logic.dart';

/// 勋章墙。对齐小程序 subpackageP3/pages/badge-wall:
/// 小程序是 WebGL 数字装置(墙模式) + 静态网格/列表降级;
/// App 侧用卡片网格(墙)与列表两种视图,数据与锁定语义一致。
class BadgeWallPage extends ConsumerStatefulWidget {
  const BadgeWallPage({super.key});

  @override
  ConsumerState<BadgeWallPage> createState() => _BadgeWallPageState();
}

class _BadgeWallPageState extends ConsumerState<BadgeWallPage> {
  // 真源默认列表视图(badge-wall/index.js:178 viewMode:'list'):
  // WebGL 墙是数字装置降级链的顶端,App 不移植引擎,默认视图按真源取列表。
  bool _wallMode = false;

  @override
  Widget build(BuildContext context) {
    // ★ 游客深链落地给登录门,不被路由静默弹回首页(B1 报告 P1,口径同 #208);
    //   wall-v2/medal 对游客一律 401,游客不发注定失败的请求。
    final CyPalette palette = CyPalette.of(context);
    final bool loggedIn = ref.watch(authControllerProvider).isLoggedIn;
    final async = loggedIn ? ref.watch(badgeWallProvider) : null;
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('勋章墙')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: !loggedIn
              ? StatusView(
                  key: const Key('badge-wall-login-gate'),
                  message: '登录后查看勋章墙',
                  sub: '勋章存在账号里，登录完就能看到。',
                  icon: Icons.lock_outline,
                  large: true,
                  retryLabel: '去登录',
                  onRetry: () => requireLogin(context, ref),
                )
              : async!.when(
                  loading: () => const CySkeleton(),
                  error: (Object e, _) => StatusView(
                    message: '勋章数据没有到达',
                    sub: '网络或渲染暂时失败，重试会重新加载',
                    large: true,
                    onRetry: () => ref.invalidate(badgeWallProvider),
                  ),
                  data: (BadgeWallPageData data) {
                    if (data.failure != null) {
                      // 两态分开(真源 index.wxml:84-88):loadFail 说网络,
                      // partialFail 说结果不完整,不共用一句、不把异常原文甩给用户。
                      final bool loadFail =
                          data.failure == BadgeWallFailure.loadFail;
                      return StatusView(
                        message: loadFail ? '勋章数据没有到达' : '部分勋章数据未到达，当前结果不完整',
                        sub: loadFail
                            ? '网络或渲染暂时失败，重试会重新加载'
                            : '当前结果不完整，请重试获取全部勋章。',
                        large: true,
                        onRetry: () => ref.invalidate(badgeWallProvider),
                      );
                    }
                    if (data.badges.isEmpty) {
                      return _WallEmpty(onExplore: () => context.go('/feed'));
                    }
                    return RefreshIndicator.adaptive(
                      onRefresh: () async => ref.invalidate(badgeWallProvider),
                      child: ListView(
                        padding: const EdgeInsets.all(CyTokens.pageX),
                        children: <Widget>[
                          Text(
                            '已点亮 ${data.unlockedCount} / ${data.badges.length}'
                            ' · 还有 ${data.lockedCount} 枚等待探索',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: CyTokens.space3),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: CyTabs(
                                  tabs: const <CyTab>[
                                    CyTab(key: 'wall', label: '墙'),
                                    CyTab(key: 'list', label: '列表'),
                                  ],
                                  active: _wallMode ? 'wall' : 'list',
                                  variant: CyTabsVariant.segmented,
                                  onChanged: (String mode) => setState(
                                    () => _wallMode = mode == 'wall',
                                  ),
                                ),
                              ),
                              const SizedBox(width: CyTokens.space3),
                              if (data.legend.length > 1)
                                Expanded(
                                  flex: 2,
                                  child: _Legend(entries: data.legend),
                                ),
                            ],
                          ),
                          const SizedBox(height: CyTokens.space3),
                          if (_wallMode)
                            _WallGrid(
                              badges: data.badges,
                              onTap: (WallBadgeView b) => _openSheet(b),
                            )
                          else
                            // 真源列表视图按三族分组并有分组标题(bw-list +
                            // badgeGroups,index.wxml:30-43);平铺少一层结构。
                            for (final group in buildFamilyGroups(
                              data.badges,
                            )) ...[
                              Padding(
                                key: Key('badge-family-${group.key}'),
                                padding: const EdgeInsets.only(
                                  top: CyTokens.space3,
                                  bottom: CyTokens.space1,
                                ),
                                child: Text(
                                  group.title,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                              for (final badge in group.items) ...[
                                _WallRow(
                                  badge: badge,
                                  onTap: () => _openSheet(badge),
                                ),
                                // 真源 .bw-list-row { border-bottom: border-subtle }。
                                Container(
                                  height: 1,
                                  color: palette.borderSubtle,
                                ),
                              ],
                            ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  void _openSheet(WallBadgeView badge) {
    showCupertinoSheet<void>(
      context: context,
      showDragHandle: true,
      topGap: 0.28,
      scrollableBuilder:
          (BuildContext context, ScrollController scrollController) =>
              _BadgeSheet(
                badge: badge,
                scrollController: scrollController,
                onOpen3d: badge.style == 'enamel'
                    ? () {
                        Navigator.of(context).pop();
                        context.push(
                          '/badge',
                          extra: badgeDetailParams(<String, String>{
                            'name': badge.name,
                            'style': badge.style,
                            'rarity': '${badge.track}',
                            if (badge.iconUrl.isNotEmpty) 'img': badge.iconUrl,
                          }),
                        );
                      }
                    : null,
              ),
    );
  }
}

/// 空态:唯一有意义的动作是去探索。
class _WallEmpty extends StatelessWidget {
  const _WallEmpty({required this.onExplore});

  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(CupertinoIcons.rosette, size: 64, color: AppColors.textDisabled),
          const SizedBox(height: CyTokens.space3),
          const Text('还没有点亮勋章'),
          const SizedBox(height: CyTokens.space1_5),
          Text(
            '完成一次城市探索或成长里程，第一枚勋章会在这里出现',
            // 逐字对齐真源 cy-empty sub(badge-wall/index.wxml:51,全角逗号)。
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: CyTokens.space4),
          CyNativeButton(
            label: '去探索',
            borderRadius: CyTokens.radiusLg,
            onPressed: onExplore,
          ),
        ],
      ),
    );
  }
}

/// 类别图例(点色 + 类别 + 数量)。
class _Legend extends StatelessWidget {
  const _Legend({required this.entries});

  final List<WallLegendEntry> entries;

  static const List<Color> _trackColors = <Color>[
    AppColors.success,
    AppColors.textSecondary,
    AppColors.warning,
    AppColors.textDisabled,
    AppColors.danger,
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: CyTokens.space2_5,
      runSpacing: CyTokens.space1_5,
      children: <Widget>[
        for (final entry in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _trackColors[entry.track],
                ),
              ),
              const SizedBox(width: CyTokens.space1),
              Text(
                '${entry.zh}×${entry.count}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// 墙视图:2 列卡片网格。
class _WallGrid extends StatelessWidget {
  const _WallGrid({required this.badges, required this.onTap});

  final List<WallBadgeView> badges;
  final ValueChanged<WallBadgeView> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: CyTokens.space3,
      crossAxisSpacing: CyTokens.space3,
      childAspectRatio: 0.92,
      children: <Widget>[
        for (final badge in badges)
          _BadgeCard(badge: badge, onTap: () => onTap(badge)),
      ],
    );
  }
}

class _BadgeCard extends StatelessWidget {
  const _BadgeCard({required this.badge, required this.onTap});

  final WallBadgeView badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final String state = badge.locked ? '尚未点亮，查看条件' : '已点亮，查看详情';
    return Semantics(
      button: true,
      label: '${badge.name}，$state',
      onTap: onTap,
      excludeSemantics: true,
      child: CupertinoButton(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.all(CyTokens.space3),
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        pressedOpacity: reduceMotion ? 1 : 0.4,
        onPressed: onTap,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Center(
                child: badge.iconUrl.isNotEmpty
                    ? Image.network(
                        badge.iconUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => _disc(),
                      )
                    : _disc(),
              ),
            ),
            const SizedBox(height: CyTokens.space2),
            Text(
              badge.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: CyTokens.space1),
            Text(
              badge.locked ? '尚未点亮' : badge.timeText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // 「尚未点亮」原先用 statusWarning —— 警告语义被挪用作锁定态(C3),
              // 真源里锁定只是压暗 48%,没有警示色;状态行统一 text-secondary。
              style: CyType.caption2.copyWith(color: palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _disc() {
    return Opacity(
      opacity: badge.locked ? 0.45 : 1,
      child: Icon(
        CupertinoIcons.star_fill,
        size: 44,
        color: badge.locked ? AppColors.textDisabled : AppColors.textSecondary,
      ),
    );
  }
}

/// 列表视图行。
class _WallRow extends StatelessWidget {
  const _WallRow({required this.badge, required this.onTap});

  final WallBadgeView badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final String state = badge.locked ? '尚未点亮，查看条件' : '已点亮，查看详情';
    return Semantics(
      button: true,
      label: '${badge.name}，$state',
      onTap: onTap,
      excludeSemantics: true,
      child: CupertinoButton(
        minimumSize: const Size(44, 44),
        padding: EdgeInsets.zero,
        pressedOpacity: MediaQuery.disableAnimationsOf(context) ? 1 : 0.4,
        onPressed: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CyTokens.space2_5),
          child: Row(
            children: <Widget>[
              // 真源 .bw-list-mark:80rpx(40pt) radius-md 方盘,bg-surface-subtle
              // + border-strong,锁定时整盘 opacity .48;图标 aspectFit,
              // 无图标才落星形占位(原先行里只有裸星,徽章图字段没上屏)。
              Opacity(
                opacity: badge.locked ? 0.48 : 1,
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                    color: palette.bgSurfaceSubtle,
                    border: Border.all(color: palette.borderStrong),
                  ),
                  child: badge.iconUrl.isNotEmpty
                      ? ClipOval(
                          child: Image.network(
                            badge.iconUrl,
                            width: 38,
                            height: 38,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => _rowMarkIcon(palette),
                          ),
                        )
                      : _rowMarkIcon(palette),
                ),
              ),
              const SizedBox(width: CyTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      badge.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${badge.locked ? '尚未点亮' : badge.timeText} · ${badge.tierZh}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                badge.locked ? '查看条件' : '查看',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rowMarkIcon(CyPalette palette) {
    // 真源占位星随方盘一起被 .is-locked 的 48% 压暗,盘底已中性化,字色不再分态。
    return Icon(CupertinoIcons.star_fill, size: 24, color: palette.textPrimary);
  }
}

/// 详情底部弹层。
class _BadgeSheet extends StatelessWidget {
  const _BadgeSheet({
    required this.badge,
    required this.scrollController,
    required this.onOpen3d,
  });

  final WallBadgeView badge;
  final ScrollController scrollController;
  final VoidCallback? onOpen3d;

  static const List<Color> _trackColors = <Color>[
    AppColors.success,
    AppColors.textSecondary,
    AppColors.warning,
    AppColors.textDisabled,
    AppColors.danger,
  ];

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AppColors.bgElevated,
      child: SafeArea(
        top: false,
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(CyTokens.space5),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    badge.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: CyTokens.space2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space1_5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: _trackColors[badge.track]),
                    borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                  ),
                  child: Text(
                    badge.tierZh,
                    // 真源 .bw-sh-rar:轨道色 1rpx 描边药丸,18rpx 字低于 T1
                    // 最小档 → caption2。
                    style: CyType.caption2.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _trackColors[badge.track],
                    ),
                  ),
                ),
                CyNativeIconButton(
                  label: '关闭勋章详情',
                  icon: const CyNativeButtonIcon(
                    sfSymbol: 'xmark',
                    fallback: CupertinoIcons.xmark,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            if (badge.desc.isNotEmpty) ...<Widget>[
              const SizedBox(height: CyTokens.space2),
              Text(
                badge.desc,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: CyTokens.space3),
            _kv(context, '获得时间', badge.timeText),
            _kv(context, '来源', badge.source),
            if (badge.cond.isNotEmpty)
              _kv(context, badge.locked ? '如何点亮' : '获得条件', badge.cond),
            if (onOpen3d != null) ...<Widget>[
              const SizedBox(height: CyTokens.space3),
              CupertinoButton(
                minimumSize: const Size.fromHeight(44),
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                foregroundColor: AppColors.primary,
                onPressed: onOpen3d,
                child: const Text('查看 3D 徽章 →'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space1_5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(
              k,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textDisabled),
            ),
          ),
          Expanded(
            child: Text(v, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
