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
import 'growth_board_logic.dart';
import 'leaderboard_controller.dart';

/// 完整排行榜。对齐小程序 `subpackageP3/pages/growthcenter/leaderboard`:
/// 周/总榜 × 积分/成长榜 切换 + 前三领奖台 + 全量名次 + 我的名次。
class LeaderboardPage extends ConsumerStatefulWidget {
  const LeaderboardPage({super.key});

  @override
  ConsumerState<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends ConsumerState<LeaderboardPage> {
  LeaderboardQuery _query = const LeaderboardQuery(
    metric: 'point',
    period: 'total',
  );

  @override
  Widget build(BuildContext context) {
    // ★ 游客深链落地给登录门,不被路由静默弹回首页(B1 报告 P1,口径同 #208);
    //   游客不发注定 401 的 /api/growth/leaderboard 请求。
    final bool loggedIn = ref.watch(authControllerProvider).isLoggedIn;
    final async = loggedIn ? ref.watch(leaderboardProvider(_query)) : null;
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('完整排行榜')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CyTokens.pageX,
                  CyTokens.space3,
                  CyTokens.pageX,
                  CyTokens.space2,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: CyTabs(
                        variant: CyTabsVariant.segmented,
                        active: _query.metric,
                        tabs: const <CyTab>[
                          CyTab(key: 'point', label: '积分榜'),
                          CyTab(key: 'exp', label: '成长榜'),
                        ],
                        onChanged: (String v) {
                          setState(() {
                            _query = _query.copyWith(metric: v);
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: CyTokens.space3),
                    Expanded(
                      child: CyTabs(
                        variant: CyTabsVariant.segmented,
                        active: _query.period,
                        // 真源 tab 顺序是 周榜→总榜(leaderboard/index.wxml:15)。
                        tabs: const <CyTab>[
                          CyTab(key: 'week', label: '周榜'),
                          CyTab(key: 'total', label: '总榜'),
                        ],
                        onChanged: (String v) {
                          setState(() {
                            _query = _query.copyWith(period: v);
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: !loggedIn
                    ? StatusView(
                        key: const Key('leaderboard-login-gate'),
                        message: '登录后查看排行榜',
                        sub: '名次存在账号里，登录完就能看到。',
                        icon: Icons.lock_outline,
                        large: true,
                        retryLabel: '去登录',
                        onRetry: () => requireLogin(context, ref),
                      )
                    : async!.when(
                        loading: () => const CySkeleton(),
                        // 真源 cy-error 固定标题「排行榜没能加载出来」+ 恒有
                        // 「重新加载」(leaderboard/index.wxml:24-33);
                        // 失败原因走 sub(后端中文 msg 优先,见 classifyBoardFailure),
                        // 英文异常原文不进 UI。
                        error: (Object e, _) => StatusView(
                          message: '排行榜没能加载出来',
                          sub: classifyBoardFailure(e).message,
                          large: true,
                          retryLabel: '重新加载',
                          onRetry: () =>
                              ref.invalidate(leaderboardProvider(_query)),
                        ),
                        data: (LeaderboardResult result) {
                          if (result.failure != null) {
                            final f = result.failure!;
                            final notice = f.kind == BoardFailureKind.notice;
                            return StatusView(
                              message: '排行榜没能加载出来',
                              sub: f.message,
                              large: true,
                              icon: notice ? null : Icons.error_outline,
                              retryLabel: '重新加载',
                              onRetry: () =>
                                  ref.invalidate(leaderboardProvider(_query)),
                            );
                          }
                          final data = result.data!;
                          if (data.top3.every((r) => r == null) &&
                              data.rest.isEmpty) {
                            return _EmptyBoard(
                              unit: data.unit,
                              onExplore: () => context.go('/feed'),
                            );
                          }
                          return RefreshIndicator.adaptive(
                            onRefresh: () async =>
                                ref.invalidate(leaderboardProvider(_query)),
                            child: ListView(
                              padding: const EdgeInsets.all(CyTokens.pageX),
                              children: <Widget>[
                                _Podium(top3: data.top3, unit: data.unit),
                                if (data.me != null) ...<Widget>[
                                  const SizedBox(height: CyTokens.space3),
                                  _MeRow(me: data.me!),
                                ],
                                const SizedBox(height: CyTokens.space4),
                                for (final row in data.rest)
                                  _RankRow(row: row, unit: data.unit),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 前三领奖台(对齐 leaderboard 页 podium)。
class _Podium extends StatelessWidget {
  const _Podium({required this.top3, required this.unit});

  final List<LeaderboardRowView?> top3;
  final String unit;

  static const List<Color> _rings = <Color>[
    Color(0xFFF5C542),
    Color(0xFFE6C46A),
    Color(0xFFD8964B),
  ];

  @override
  Widget build(BuildContext context) {
    // 真源站位是 2-1-3(亚军在左、冠军居中且更大),不是名次从左到右。
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(child: _slot(2)),
        Expanded(child: _slot(1)),
        Expanded(child: _slot(3)),
      ],
    );
  }

  Widget _slot(int rank) {
    final LeaderboardRowView? row = top3[rank - 1];
    if (row == null) {
      // 空位不塌高度:冠军缺席时两侧仍按底对齐站住。
      return const SizedBox(height: 40);
    }
    return _PodiumSlot(
      rank: rank,
      row: row,
      unit: unit,
      ringColor: _rings[rank - 1],
    );
  }
}

class _PodiumSlot extends StatelessWidget {
  const _PodiumSlot({
    required this.rank,
    required this.row,
    required this.unit,
    required this.ringColor,
  });

  final int rank;
  final LeaderboardRowView row;
  final String unit;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    // 真源 .gc-ring-1 172rpx(86pt) / .gc-ring-2 144rpx(72pt):
    // 层级由环的大小表达,不是自造的领奖台立柱。
    final double ring = rank == 1 ? 86 : 72;
    final double pav = rank == 1 ? 76 : 62;
    final bool gold = rank == 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // 真源是「星冠 + 奖牌数字」;App 把名次直说成文字,三档统一,
        // 装饰星冠不移植(删减优先)。
        Text(
          '第$rank名',
          style: CyType.caption1.copyWith(color: palette.textSecondary),
        ),
        Container(
          width: ring,
          height: ring,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ringColor, width: 2),
          ),
          child: _AvatarCircle(
            url: row.avatarUrl,
            initial: row.initial,
            size: pav,
            medalColor: ringColor,
          ),
        ),
        const SizedBox(height: CyTokens.space2),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 124),
          child: Text(
            row.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            // 真源 .gc-pod-name:label(12) w600;冠军 body(15) w700。
            style: (gold ? CyType.subhead : CyType.caption1).copyWith(
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: CyTokens.space1),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(
              row.scoreText,
              // 真源 .gc-num / .gc-num-g:冠军分数走金色体系,其余中性。
              style: CyType.caption1.copyWith(
                fontWeight: FontWeight.w600,
                color: gold ? _Podium._rings[0] : palette.textSecondary,
                // critic 二轮:数值等宽,列不跳位。
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: CyTokens.space1),
            Text(
              unit,
              style: CyType.caption2.copyWith(
                color: gold ? _Podium._rings[0] : palette.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 榜单头像:真头像 → 缩写盘兜底(真源三处头像同一结构:
/// avatarUrl 图 → memoji → initial,App 无 memoji 通道)。
class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({
    required this.url,
    required this.initial,
    required this.size,
    this.medalColor,
  });

  final String url;
  final String initial;
  final double size;

  /// 非空时(领奖台)盘底淡铺奖牌渐变的终点色,与真源 `.gc-pav` 彩底一致。
  final Color? medalColor;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        color: medalColor?.withValues(alpha: 0.18) ?? palette.bgSurfaceSubtle,
        child: url.isNotEmpty
            ? Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Text(
                  initial,
                  style: CyType.headline.copyWith(color: palette.textPrimary),
                ),
              )
            : Text(
                initial,
                style: CyType.headline.copyWith(color: palette.textPrimary),
              ),
      ),
    );
  }
}

/// 我的名次条。
class _MeRow extends StatelessWidget {
  const _MeRow({required this.me});

  final MyRankView me;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: const Color(0x33F5C542),
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      ),
      child: Row(
        children: <Widget>[
          Text(
            '第 ${me.rank} 名',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(width: CyTokens.space3),
          // 真源 .gc-row-me:名次后紧跟 40pt 头像盘。
          _AvatarCircle(url: me.avatarUrl, initial: me.initial, size: 40),
          const SizedBox(width: CyTokens.space3),
          Expanded(
            child: Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    me.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CyType.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                // 真源 .gc-me-tag:金色「我」字药丸,只标身份,不染整行。
                const SizedBox(width: CyTokens.space1_5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space1_5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _Podium._rings[0],
                    borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                  ),
                  child: Text(
                    '我',
                    style: CyType.caption2.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0A0A0B),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Text(
            me.scoreText,
            // 真源 .gc-num-g:我的分数走金色体系(label→caption1 不越 T1)。
            style: CyType.caption1.copyWith(
              fontWeight: FontWeight.w600,
              color: _Podium._rings[0],
              // critic 二轮:数值等宽,列不跳位。
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: CyTokens.space1),
          Text(
            me.unit,
            style: CyType.caption2.copyWith(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 空榜:唯一有意义的动作是去探索(去挣积分),不是重试。
/// 文案逐字对齐真源 leaderboard/index.wxml:46-48 的 cy-empty。
class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard({required this.unit, required this.onExplore});

  final String unit;
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.emoji_events_outlined,
            size: 64,
            color: AppColors.textDisabled,
          ),
          const SizedBox(height: CyTokens.space3),
          const Text('这张榜还没有人上榜'),
          const SizedBox(height: CyTokens.space1_5),
          Text(
            '完成一次城市探索就会累计$unit，第一个上榜的可能就是你',
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

/// 4 名之后的名次行。
class _RankRow extends StatelessWidget {
  const _RankRow({required this.row, required this.unit});

  final LeaderboardRowView row;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Padding(
      // 真源 .gc-row:min-height 80+24rpx、padding 22rpx、gap 26rpx。
      padding: const EdgeInsets.symmetric(
        vertical: CyTokens.space2_5,
        horizontal: CyTokens.space1,
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 28,
            child: Text(
              '${row.rank}',
              textAlign: TextAlign.center,
              // 真源 .gc-row-rank:subtitle(16) w600 + text-secondary。
              style: CyType.callout.copyWith(
                fontWeight: FontWeight.w600,
                color: palette.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: CyTokens.space3),
          // 真源 .gc-row 名次后是 40pt 头像盘(原先整行没有头像,字段缺失)。
          _AvatarCircle(url: row.avatarUrl, initial: row.initial, size: 40),
          const SizedBox(width: CyTokens.space3),
          Expanded(
            child: Text(
              row.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // 真源 .gc-row-name:body(15) w600 → Headline 档。
              style: CyType.headline.copyWith(color: palette.textPrimary),
            ),
          ),
          Text(
            row.scoreText,
            // 真源 .gc-num:label(12) w600 + text-secondary。
            style: CyType.caption1.copyWith(
              fontWeight: FontWeight.w600,
              color: palette.textSecondary,
              // critic 二轮:数值等宽,列不跳位。
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: CyTokens.space1),
          Text(
            unit,
            // 真源 .gc-unit:caption(11) + text-secondary(原先漏了单位)。
            style: CyType.caption2.copyWith(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}
