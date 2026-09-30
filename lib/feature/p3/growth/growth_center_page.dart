import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/cy_palette.dart';
import '../../../core/theme/cy_tokens.dart';
import '../../../core/widgets/cy_net_image.dart';
import '../../../core/widgets/status_view.dart';
import '../../auth/auth_controller.dart';
import '../../auth/login_gate.dart';
import 'growth_board_logic.dart';
import 'growth_center_controller.dart';
import 'growth_overview.dart';

/// 成长中心。对齐小程序 `subpackageP3/pages/growthcenter/index`:
/// 当前积分 + 我的排名摘要(点开去完整排行榜)+ 足迹概览 + 徽章墙。
class GrowthCenterPage extends ConsumerWidget {
  const GrowthCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ★ 游客深链落地给登录门而不是被静默弹回首页(B1 模拟器报告 P1,
    //   口径同集邮册 #208)。/api/growth/center 等对游客一律 401,
    //   刻意不自动弹登录 sheet —— 冷启动直接盖 sheet 同样像"链接坏了"。
    final bool loggedIn = ref.watch(authControllerProvider).isLoggedIn;
    final async = loggedIn ? ref.watch(growthCenterPageProvider) : null;
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(middle: Text('成长中心')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: !loggedIn
              ? StatusView(
                  key: const Key('growth-login-gate'),
                  message: '登录后查看成长中心',
                  sub: '等级、积分与徽章存在账号里，登录完就能看到。',
                  icon: CupertinoIcons.lock,
                  large: true,
                  retryLabel: '去登录',
                  onRetry: () => requireLogin(context, ref),
                )
              : async!.when(
                  loading: () => const CySkeleton(),
                  error: (Object e, _) => StatusView(
                    message: '成长中心加载失败',
                    sub: classifyBoardFailure(e).message,
                    large: true,
                    onRetry: () => ref.invalidate(growthCenterPageProvider),
                  ),
                  data: (GrowthCenterPageData data) =>
                      RefreshIndicator.adaptive(
                        onRefresh: () async {
                          ref.invalidate(growthCenterPageProvider);
                          ref.invalidate(growthMyRankProvider);
                        },
                        child: ListView(
                          padding: const EdgeInsets.all(CyTokens.pageX),
                          children: <Widget>[
                            _ScoreCard(),
                            const SizedBox(height: CyTokens.space4),
                            _FootprintSection(overview: data.overview),
                            const SizedBox(height: CyTokens.space4),
                            _BadgeSection(data: data),
                          ],
                        ),
                      ),
                ),
        ),
      ),
    );
  }
}

/// 区块卡壳(真源 B68 黑白灰成长信息层:bg-surface + border-subtle +
/// radius-lg 的实色内容卡;Material Card 的投影与主题底不在 iOS 语言里)。
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// 区块标题行(真源 .gc-section-head:标题 type-section-title 700,
/// 右侧 meta type-label 三级色)。
class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.title, required this.meta});

  final String title;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          title,
          style: CyType.callout.copyWith(
            fontWeight: FontWeight.w700,
            color: p.textPrimary,
          ),
        ),
        Text(meta, style: CyType.caption1.copyWith(color: p.textTertiary)),
      ],
    );
  }
}

/// 第一层:当前积分 + 本人名次(对齐 gc-score-card)。
class _ScoreCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CyPalette p = CyPalette.of(context);
    final async = ref.watch(growthMyRankProvider);
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        border: Border.all(color: p.borderSubtle),
      ),
      child: async.when(
        loading: () => _stateLine(context, '加载中…'),
        error: (Object e, _) {
          // 英文异常原文不进 UI:与数据失败同一分类口径。
          final f = classifyBoardFailure(e);
          return _stateLine(context, f.message, title: _stateTitle(f));
        },
        data: (MyRankBoard board) {
          if (board.failure != null) {
            return _stateLine(
              context,
              board.failure!.message,
              title: _stateTitle(board.failure!),
              notice: board.failure!.kind == BoardFailureKind.notice,
            );
          }
          final me = board.view;
          if (me == null) {
            // 真源两态分开:无排名时积分照常显示「—」(gc-score-line),
            // 「暂无排名」是中性空态(cy-empty title)。原先一把塞进
            // _stateLine 会渲染成**红字 + 重试**,把空态冒充成失败态。
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '当前积分',
                  style: CyType.caption1.copyWith(color: p.textTertiary),
                ),
                const SizedBox(height: CyTokens.space2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      '—',
                      style: CyType.largeTitle.copyWith(color: p.textPrimary),
                    ),
                    const SizedBox(width: CyTokens.space1_5),
                    // 本页恒为积分榜(boardUnitText('point'))。
                    Text(
                      boardUnitText('point'),
                      style: CyType.caption1.copyWith(color: p.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: CyTokens.space2),
                Text(
                  '暂无排名',
                  style: CyType.footnote.copyWith(color: p.textSecondary),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 真源 .gc-score-kicker: type-label(12) text-tertiary
              Text(
                '当前积分',
                style: CyType.caption1.copyWith(color: p.textTertiary),
              ),
              const SizedBox(height: CyTokens.space2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  // 真源 .gc-score-value: --cy-type-data-xl 64rpx=32pt,
                  // 750 → T3 上限 w700,tabular-nums。
                  Text(
                    me.scoreText,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: p.textPrimary,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  const SizedBox(width: CyTokens.space2),
                  Text(
                    me.unit,
                    style: CyType.caption1.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
              // 真源 .gc-score-rank 与分数之间有一条 border-subtle 分隔线。
              Container(
                margin: const EdgeInsets.only(
                  top: CyTokens.space4,
                  bottom: CyTokens.space1,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: p.borderSubtle)),
                ),
              ),
              Semantics(
                button: true,
                // 小程序 gc-score-rank 的 aria-label 就是「查看完整排行榜」
                // (可见文字是「查看榜单」,屏幕阅读器读的是这一句)。
                label: '查看完整排行榜',
                child: CupertinoButton(
                  minimumSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    context.push('/growth/leaderboard');
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: CyTokens.space1_5,
                    ),
                    child: Row(
                      children: <Widget>[
                        _Avatar(avatarUrl: me.avatarUrl, initial: me.initial),
                        const SizedBox(width: CyTokens.space2_5),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                me.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: CyType.caption1.copyWith(
                                  color: p.textPrimary,
                                ),
                              ),
                              const SizedBox(height: CyTokens.space1),
                              Text(
                                '总榜第 ${me.rank ?? '--'} 名',
                                // 真源 .gc-score-rank-copy 只有两行:昵称 +
                                // 总榜名次。TOP 百分位是 profile 组件的字段,
                                // 成长中心不展示(原先多显示了一截)。
                                style: CyType.caption1.copyWith(
                                  color: p.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 真源 .gc-score-link 是 text-secondary + arrow-right
                        // 图标,不上品牌强调色(C1);「›」字符换原生 chevron。
                        Text(
                          '查看榜单',
                          style: CyType.caption1.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                        const SizedBox(width: CyTokens.space1),
                        Icon(
                          CupertinoIcons.chevron_forward,
                          size: 12,
                          color: p.textTertiary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 真源 gc-inline-error 固定标题:permission/HTTP 态「当前无法查看排行榜」,
  /// 其余「排行榜没有加载出来」(growthcenter/index.wxml)。
  static String _stateTitle(BoardFailure f) =>
      f.kind == BoardFailureKind.notice ? '当前无法查看排行榜' : '排行榜没有加载出来';

  Widget _stateLine(
    BuildContext context,
    String text, {
    String? title,
    bool notice = false,
  }) {
    final CyPalette p = CyPalette.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 真源错误态是固定标题 + 原因 sub,不是一行裸文案。
              if (title != null) ...<Widget>[
                Text(
                  title,
                  style: CyType.subhead.copyWith(color: p.textPrimary),
                ),
                const SizedBox(height: CyTokens.space1),
              ],
              Text(
                text,
                style: CyType.caption1.copyWith(
                  color: notice ? p.textSecondary : p.statusDanger,
                ),
              ),
            ],
          ),
        ),
        if (!notice)
          Consumer(
            builder: (context, ref, _) => CupertinoButton(
              onPressed: () => ref.invalidate(growthMyRankProvider),
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
              child: Text(
                '重试',
                style: CyType.caption1.copyWith(color: p.textPrimary),
              ),
            ),
          ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.avatarUrl, required this.initial});

  final String avatarUrl;
  final String initial;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    const size = 32.0;
    if (avatarUrl.isNotEmpty) {
      return CyNetImage(
        avatarUrl,
        width: size,
        height: size,
        borderRadius: BorderRadius.circular(size / 2),
        fallback: _textAvatar(p, size),
      );
    }
    return _textAvatar(p, size);
  }

  // 真源 .gc-score-avatar--text:surface-subtle 底 + 主色字,
  // 不是品牌色圆 + 白字(强调色克制 C1)。
  Widget _textAvatar(CyPalette p, double size) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p.bgSurfaceSubtle,
      ),
      child: Text(
        initial,
        style: CyType.caption1.copyWith(
          fontWeight: FontWeight.w700,
          color: p.textPrimary,
        ),
      ),
    );
  }
}

/// 第二层:四项足迹指标(对齐 gc-metric-list:行分隔的列表容器)。
class _FootprintSection extends StatelessWidget {
  const _FootprintSection({required this.overview});

  final GrowthOverview overview;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return _SectionCard(
      children: <Widget>[
        _SectionHead(title: '我的足迹', meta: overview.levelText),
        const SizedBox(height: CyTokens.space3),
        for (var i = 0; i < overview.stats.length; i++) ...<Widget>[
          if (i > 0)
            SizedBox(height: 0.5, child: ColoredBox(color: p.borderSubtle)),
          _MetricRow(stat: overview.stats[i]),
        ],
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.stat});

  final OverviewStat stat;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space2_5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          // 真源 .gc-metric-label: type-label(12) secondary
          Text(
            stat.label,
            style: CyType.caption1.copyWith(color: p.textSecondary),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              // 真源 .gc-metric-value: type-card-title 700 primary tabular
              Text(
                stat.value ?? '—',
                style: CyType.callout.copyWith(
                  fontWeight: FontWeight.w700,
                  color: stat.value == null ? p.textDisabled : p.textPrimary,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              if (stat.value != null) ...<Widget>[
                const SizedBox(width: CyTokens.space1),
                // 真源 unit: type-caption w500 tertiary
                Text(
                  stat.unit,
                  style: CyType.caption2.copyWith(
                    fontWeight: FontWeight.w500,
                    color: p.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 第三层:徽章列表,点按展开获得时刻(对齐 gc-badge-sec)。
class _BadgeSection extends ConsumerStatefulWidget {
  const _BadgeSection({required this.data});

  final GrowthCenterPageData data;

  @override
  ConsumerState<_BadgeSection> createState() => _BadgeSectionState();
}

class _BadgeSectionState extends ConsumerState<_BadgeSection> {
  final Set<String> _expanded = <String>{};

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final data = widget.data;
    return _SectionCard(
      children: <Widget>[
        _SectionHead(
          title: '我的徽章',
          meta: data.badgeLoadError ? '—' : '${data.badges.length}',
        ),
        const SizedBox(height: CyTokens.space3),
        if (data.badgeLoadError)
          _BadgeUnavailable(
            onRetry: () => ref.invalidate(growthCenterPageProvider),
          )
        else if (data.badges.isEmpty)
          // 真源 cy-empty 带 cta="去探索"(growthcenter/index.wxml:96-97),
          // 空态不能只说"没有什么",要给下一步。
          // 真源图标是 no_data 插画(素材缺口已登记),字形兜底走系统线性图标。
          Padding(
            padding: const EdgeInsets.symmetric(vertical: CyTokens.space4),
            child: StatusView(
              icon: CupertinoIcons.star,
              message: '还没有点亮任何徽章',
              sub: '继续探索城市，第一枚徽章会在这里出现',
              retryLabel: '去探索',
              onRetry: () => context.go('/feed'),
            ),
          )
        else
          for (var i = 0; i < data.badges.length; i++) ...<Widget>[
            if (i > 0)
              SizedBox(height: 0.5, child: ColoredBox(color: p.borderSubtle)),
            _BadgeRow(
              badge: data.badges[i],
              expanded: _expanded.contains(data.badges[i].code),
              onTap: () {
                setState(() {
                  if (!_expanded.remove(data.badges[i].code)) {
                    _expanded.add(data.badges[i].code);
                  }
                });
              },
            ),
          ],
      ],
    );
  }
}

class _BadgeUnavailable extends StatelessWidget {
  const _BadgeUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    // 真源 .gc-badge-state:border-card 描边小容器 + 描边胶囊重试
    // (.gc-badge-state-retry min-height 88rpx,靠 minimumSize 兜到 44pt)。
    return Container(
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: p.bgSurfaceSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '徽章数据暂时不可用',
              style: CyType.caption1.copyWith(color: p.textSecondary),
            ),
          ),
          const SizedBox(width: CyTokens.space3),
          CupertinoButton(
            onPressed: onRetry,
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
            child: Semantics(
              button: true,
              // 一屏上有两处「重试」(排名 / 徽章),屏幕阅读器要能分清点的是哪一个。
              label: '重试徽章数据',
              excludeSemantics: true,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.space3,
                  vertical: CyTokens.space1,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                  border: Border.all(color: p.borderStrong),
                ),
                child: Text(
                  '重试',
                  style: CyType.caption1.copyWith(color: p.textPrimary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeRow extends StatelessWidget {
  const _BadgeRow({
    required this.badge,
    required this.expanded,
    required this.onTap,
  });

  final CenterBadgeView badge;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return CupertinoButton(
      minimumSize: const Size(44, 44),
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CyTokens.space2_5),
        child: Row(
          children: <Widget>[
            _BadgeDisc(badge: badge),
            const SizedBox(width: CyTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // 真源 .gc-badge-name: type-card-title(15) 600 primary,
                  // 单行截断。
                  Text(
                    badge.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CyType.subhead.copyWith(
                      fontWeight: FontWeight.w600,
                      color: p.textPrimary,
                    ),
                  ),
                  const SizedBox(height: CyTokens.space1),
                  // 真源 .gc-badge-hint / .gc-badge-moment:caption(11) tertiary
                  Text(
                    expanded
                        ? (badge.unlockText != null
                              ? '获得于 ${badge.unlockText}'
                              : '获得时间未记录')
                        : '查看获得时刻',
                    style: CyType.caption2.copyWith(color: p.textTertiary),
                  ),
                ],
              ),
            ),
            // 真源 .gc-badge-arrow: type-label secondary,不用品牌色。
            Text(
              expanded ? '收起' : '查看',
              style: CyType.caption1.copyWith(color: p.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeDisc extends StatelessWidget {
  const _BadgeDisc({required this.badge});

  final CenterBadgeView badge;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    // 真源 .gc-badge-disc:space-7(40pt) radius-md 方圆牌,surface-subtle 底
    // + border-strong 描边 + 主色字 —— 不是品牌紫圆面(那是自造视觉语言);
    // 图标是 76rpx=38pt 圆图 aspectFit 嵌在方牌里。
    const size = 40.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        color: p.bgSurfaceSubtle,
        border: Border.all(color: p.borderStrong),
      ),
      child: badge.iconUrl.isNotEmpty
          ? CyNetImage(
              badge.iconUrl,
              width: 38,
              height: 38,
              fit: BoxFit.contain,
              borderRadius: BorderRadius.circular(19),
              fallback: _initialFace(p),
            )
          : _initialFace(p),
    );
  }

  Widget _initialFace(CyPalette p) {
    return Text(
      badge.initial,
      style: CyType.body.copyWith(
        fontWeight: FontWeight.w700,
        color: p.textPrimary,
      ),
    );
  }
}
