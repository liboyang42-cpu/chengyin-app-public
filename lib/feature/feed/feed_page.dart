import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_tabs.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/activity.dart';
import '../../data/models/banner.dart';
import '../../data/models/play_run_session.dart';
import '../../data/models/topic.dart';
import '../../data/models/upcoming_activity.dart';
import '../activity/activity_controller.dart';
import '../auth/auth_controller.dart';
import '../play/advanced/fullscreen/playkit_timer_logic.dart'
    show formatPlayClock;
import 'feed_controller.dart';
import 'feed_sections_controller.dart';
import 'widgets/countdown_text.dart';
import 'widgets/home_activity_live.dart';

/// 玩家首页。区块顺序镜像小程序首页(index.wxml 的 sec-* 声明顺序):
/// Hero -> 推荐主题 -> 继续探索 -> 附近活动 -> 即将上线 -> 主题流。
class FeedPage extends ConsumerStatefulWidget {
  const FeedPage({super.key});

  @override
  ConsumerState<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends ConsumerState<FeedPage> {
  bool _showActivities = false;

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    final notifier = ref.read(feedProvider.notifier);
    return Scaffold(
      body: RefreshIndicator.adaptive(
        onRefresh: () async {
          ref.invalidate(feedBannerProvider);
          ref.invalidate(feedRecommendProvider);
          ref.invalidate(feedUpcomingProvider);
          ref.invalidate(feedNearbyProvider);
          ref.invalidate(feedActivityStreamProvider);
          ref.invalidate(myJoinedActivitiesProvider);
          ref.invalidate(feedProvider);
          await ref.read(feedProvider.future);
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification notification) {
            if (!_showActivities &&
                notification.metrics.pixels >=
                    notification.metrics.maxScrollExtent - 240 &&
                notifier.hasMore &&
                !notifier.loadMoreFailed) {
              notifier.loadMore();
            }
            return false;
          },
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: <Widget>[
              const SliverToBoxAdapter(child: _HeroSection()),
              const SliverToBoxAdapter(child: _HomeSearchEntry()),
              // 真源 index.wxml:sec-reco(69 行,注释「紧跟 Banner,作为首页首个
              // 内容区块」)→ v3-continue(120)→ sec-nearby(133)→ sec-upcoming。
              const SliverToBoxAdapter(child: _RecommendSection()),
              const SliverToBoxAdapter(child: _ContinueSection()),
              const SliverToBoxAdapter(child: _NearbySection()),
              const SliverToBoxAdapter(child: _UpcomingSection()),
              SliverToBoxAdapter(
                child: _FeedTabs(
                  activities: _showActivities,
                  onChanged: (bool value) =>
                      setState(() => _showActivities = value),
                ),
              ),
              if (_showActivities)
                ..._buildActivitySlivers(
                  context,
                  ref.watch(feedActivityStreamProvider),
                )
              else
                ..._buildFeedSlivers(context, ref, feed, notifier),
              const SliverToBoxAdapter(
                child: SafeArea(
                  top: false,
                  child: SizedBox(height: CyTokens.space5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActivitySlivers(
    BuildContext context,
    AsyncValue<List<Activity>> activities,
  ) {
    return <Widget>[
      activities.when(
        loading: () => const SliverToBoxAdapter(child: LoadingView()),
        error: (Object error, StackTrace stack) => SliverToBoxAdapter(
          child: StatusView(
            message: stringsOf(context).feedActivityError,
            sub: stringsOf(context).feedPullRetry,
            icon: Icons.cloud_off,
            onRetry: () => ref.invalidate(feedActivityStreamProvider),
          ),
        ),
        data: (List<Activity> rows) => rows.isEmpty
            ? SliverToBoxAdapter(
                child: StatusView(
                  message: stringsOf(context).feedActivitiesEmpty,
                  sub: stringsOf(context).feedComeBack,
                  icon: Icons.event_outlined,
                ),
              )
            : SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.space4,
                ),
                sliver: SliverList.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: CyTokens.space5),
                  itemBuilder: (_, int index) =>
                      _ActivityFeedCard(activity: rows[index]),
                ),
              ),
      ),
    ];
  }

  List<Widget> _buildFeedSlivers(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Topic>> feed,
    FeedNotifier notifier,
  ) {
    return <Widget>[
      feed.when(
        loading: () => const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: CyTokens.space4),
            child: LoadingView(),
          ),
        ),
        error: (Object err, StackTrace st) => SliverToBoxAdapter(
          child: StatusView(
            message: stringsOf(context).feedTopicError,
            sub: stringsOf(context).feedPullRetry,
            icon: Icons.cloud_off,
            onRetry: () => ref.invalidate(feedProvider),
          ),
        ),
        data: (List<Topic> list) {
          if (list.isEmpty) {
            return SliverToBoxAdapter(
              child: StatusView(
                message: stringsOf(context).feedTopicsEmpty,
                sub: stringsOf(context).feedComeBack,
                icon: Icons.route_outlined,
              ),
            );
          }
          return SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.space4),
            sliver: SliverList.separated(
              itemCount: list.length + 1,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: CyTokens.space5),
              itemBuilder: (BuildContext context, int index) {
                if (index == list.length) {
                  return _FeedFooter(
                    hasMore: notifier.hasMore,
                    failed: notifier.loadMoreFailed,
                    onRetry: notifier.loadMore,
                  );
                }
                return _TopicCard(topic: list[index]);
              },
            ),
          );
        },
      ),
    ];
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space6,
        CyTokens.pageX,
        CyTokens.space4,
      ),
      // 区块标题走共用件:Title3 Semibold + Semantics(header)(§6 P2 / T2 / T3)。
      child: CySectionTitle(title),
    );
  }
}

class _FeedTabs extends StatelessWidget {
  const _FeedTabs({required this.activities, required this.onChanged});

  final bool activities;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('home-topic-stream'),
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space6,
        CyTokens.pageX,
        CyTokens.space4,
      ),
      child: SizedBox(
        width: double.infinity,
        // 分段走共用件:iOS 26+ 原生玻璃分段,旧系统回退 Cupertino 分段(对照表 #24)。
        child: CyTabs(
          key: const Key('home-feed-tabs'),
          variant: CyTabsVariant.segmented,
          tabs: <CyTab>[
            CyTab(key: 'topic', label: stringsOf(context).feedTopics),
            CyTab(key: 'activity', label: stringsOf(context).feedActivities),
          ],
          active: activities ? 'activity' : 'topic',
          onChanged: (String key) {
            final bool value = key == 'activity';
            if (value != activities) onChanged(value);
          },
        ),
      ),
    );
  }
}

class _HomeSearchEntry extends StatelessWidget {
  const _HomeSearchEntry();

  @override
  Widget build(BuildContext context) {
    // 小程序 pages/index/index.wxml `.v3-search`(2026-09-17 拍板 #15):
    // 首页带一个只读搜索条,点它整行走既有搜索页;本页不另造搜索态。
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.space4,
        CyTokens.space5,
        CyTokens.space4,
        0,
      ),
      child: Semantics(
        button: true,
        label: stringsOf(context).feedSearch,
        excludeSemantics: true,
        child: CupertinoButton(
          key: const Key('home-search'),
          onPressed: () => context.push('/search'),
          minimumSize: const Size.fromHeight(CyTokens.btnH),
          padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
          color: CyTokens.inputBgEmpty,
          borderRadius: BorderRadius.circular(CyTokens.radiusPill),
          child: Row(
            children: <Widget>[
              const Icon(
                CupertinoIcons.search,
                size: 16,
                color: CyTokens.textPlaceholder,
              ),
              const SizedBox(width: CyTokens.space2),
              Expanded(
                child: Text(
                  stringsOf(context).feedSearch,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: CyTokens.typeBody,
                    color: CyTokens.textPlaceholder,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroSection extends ConsumerStatefulWidget {
  const _HeroSection();

  @override
  ConsumerState<_HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends ConsumerState<_HeroSection> {
  final PageController _controller = PageController();
  int _current = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onBannerTap(HomeBanner banner) {
    final String? dataId = banner.dataId;
    if (dataId == null || dataId.isEmpty) return;
    if (banner.linkType == 3) {
      context.push('/activity/$dataId');
    } else if (banner.linkType == 4) {
      context.push('/topic/$dataId');
    }
  }

  /// 真源 `utils/index/home-action-banner.js` 的 `home-action-activity`:
  /// 首页固定行动卡「和朋友报名活动」。它的落点 `pages/activity/list`
  /// 是官方活动列表(≠ App 的 /activities),App 路由 = /official-events。
  /// 固定卡恒在轮播尾页 —— 后台 banner 为空时首页也留着这条入口。
  Widget _homeActionBanner(BuildContext context) {
    void open() => context.push('/official-events');
    return Semantics(
      button: true,
      label: stringsOf(context).feedOpenFriends,
      onTap: open,
      excludeSemantics: true,
      child: CupertinoButton(
        key: const Key('home-action-activity'),
        onPressed: open,
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _CoverImage(
              url:
                  'https://api.example.invalid/prod-api/profile/home-banners/home-banner-friends.jpg',
              fallbackIcon: Icons.event_outlined,
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  CyTokens.pageX,
                  CyTokens.space4,
                  CyTokens.pageX,
                  CyTokens.space8 + CyTokens.space3,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      stringsOf(context).feedFriends,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: CyTokens.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: CyTokens.space1),
                    Text(
                      stringsOf(context).feedFriendsDetail,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: CyTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<HomeBanner>> async = ref.watch(feedBannerProvider);
    final List<HomeBanner> banners = async.value ?? const <HomeBanner>[];
    final user = ref.watch(authControllerProvider).user;
    final String nickname = user?.nickname.trim().isNotEmpty == true
        ? user!.nickname.trim()
        : stringsOf(context).feedTraveler;
    final double height = (MediaQuery.sizeOf(context).height * 6 / 7)
        .clamp(520.0, 760.0)
        .toDouble();
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);

    return SizedBox(
      key: const Key('home-hero'),
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          PageView.builder(
            controller: _controller,
            itemCount: banners.length + 1,
            onPageChanged: (int index) => setState(() => _current = index),
            itemBuilder: (BuildContext context, int index) {
              if (index >= banners.length) {
                return _homeActionBanner(context);
              }
              final HomeBanner banner = banners[index];
              final bool canOpen =
                  banner.dataId?.isNotEmpty == true &&
                  (banner.linkType == 3 || banner.linkType == 4);
              final Widget cover = _CoverImage(
                url: banner.picUrl,
                fallbackIcon: Icons.explore_outlined,
              );
              if (!canOpen) {
                return Semantics(
                  image: true,
                  label: stringsOf(context).feedRecommendedContent,
                  excludeSemantics: true,
                  child: cover,
                );
              }
              void open() => _onBannerTap(banner);
              return Semantics(
                button: true,
                label: stringsOf(context).feedOpenRecommendation,
                onTap: open,
                excludeSemantics: true,
                child: CupertinoButton(
                  onPressed: open,
                  minimumSize: Size.zero,
                  padding: EdgeInsets.zero,
                  child: cover,
                ),
              );
            },
          ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    CyTokens.bgPage.withValues(alpha: 0.62),
                    CyTokens.bgPage.withValues(alpha: 0.08),
                    CyTokens.bgPage.withValues(alpha: 0.88),
                  ],
                  stops: <double>[0, 0.48, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                CyTokens.pageX,
                CyTokens.space2,
                CyTokens.pageX,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(
                        Icons.explore,
                        color: CyTokens.textPrimary,
                        size: 30,
                      ),
                      const SizedBox(width: CyTokens.space2),
                      Text(
                        stringsOf(context).feedBrand,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: CyTokens.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: CyTokens.space2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              stringsOf(context).feedGreeting(nickname),
                              style: Theme.of(context).textTheme.displaySmall
                                  ?.copyWith(
                                    color: CyTokens.textPrimary,
                                    fontSize: CyTokens.typeDisplay,
                                    fontWeight: FontWeight.w700,
                                    height: 1.1,
                                  ),
                            ),
                            const SizedBox(height: CyTokens.space1_5),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const _MemberBadge(),
                                const SizedBox(width: CyTokens.space1_5),
                                Text(
                                  stringsOf(context).feedPlayer,
                                  style: const TextStyle(
                                    color: CyTokens.textSecondary,
                                    fontSize: CyTokens.typeLabel,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: CyTokens.space2),
                      _AvatarButton(
                        url: user?.avatar,
                        onTap: () => context.go('/profile'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (banners.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: CyTokens.space8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List<Widget>.generate(banners.length + 1, (
                  int index,
                ) {
                  final bool active = index == _current;
                  return AnimatedContainer(
                    duration: reduceMotion ? Duration.zero : CyMotion.fast,
                    margin: const EdgeInsets.symmetric(
                      horizontal: CyTokens.space1_5 / 2,
                    ),
                    width: active ? CyTokens.space4 : CyTokens.space1_5,
                    height: CyTokens.space1_5,
                    decoration: BoxDecoration(
                      color: active
                          ? CyTokens.textPrimary
                          : CyTokens.textDisabled,
                      borderRadius: BorderRadius.circular(
                        CyTokens.space1_5 / 2,
                      ),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

class _AvatarButton extends StatelessWidget {
  const _AvatarButton({this.url, required this.onTap});

  final String? url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: stringsOf(context).feedOpenProfile,
      onTap: onTap,
      excludeSemantics: true,
      child: CupertinoButton(
        key: const Key('home-avatar'),
        onPressed: onTap,
        minimumSize: const Size(CyTokens.btnH, CyTokens.btnH),
        padding: EdgeInsets.zero,
        child: Container(
          width: CyTokens.btnH,
          height: CyTokens.btnH,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: CyTokens.bgElevated,
            border: Border.all(color: CyTokens.borderStrong, width: 2),
          ),
          child: (url == null || url!.isEmpty)
              ? const Icon(Icons.person, size: 22, color: CyTokens.textPrimary)
              : Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.person,
                    size: 22,
                    color: CyTokens.textPrimary,
                  ),
                ),
        ),
      ),
    );
  }
}

class _MemberBadge extends StatelessWidget {
  const _MemberBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: const BoxDecoration(
        color: CyTokens.statusWarning,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check, size: 14, color: CyTokens.onCoverFg),
    );
  }
}

class _ContinueSection extends ConsumerWidget {
  const _ContinueSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(authControllerProvider).user == null) {
      return const SizedBox.shrink();
    }
    // 第二轮拍板 22:进行中的游戏会话优先占这张卡(换手机登录也能从首页继续),
    // 没有才轮到报名旅程 —— 与小程序首页 `game || journey` 同序。
    // 拉不到就静默让位给旅程卡:这是首页的一张入口卡,不是错误页。
    final List<PlayRunSession> runs =
        ref.watch(playRunSessionsProvider).value ?? const <PlayRunSession>[];
    final PlayRunSession? run = runs.isEmpty ? null : runs.first;
    if (run != null) {
      final String title = run.title.isEmpty ? stringsOf(context).feedContinueGame : run.title;
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          CyTokens.pageX,
          CyTokens.space5,
          CyTokens.pageX,
          0,
        ),
        child: _ContinueCard(
          cardKey: const Key('home-continue-game'),
          kicker: stringsOf(context).feedContinueGame,
          title: title,
          subtitle: run.elapsedSeconds == null
              ? stringsOf(context).feedPaused
              : stringsOf(context).feedPausedElapsed(formatPlayClock(run.elapsedSeconds!)),
          coverUrl: run.cover,
          fallbackIcon: Icons.sports_esports_outlined,
          onTap: () => context.push(
            run.activityId > 0
                ? '/play/${run.activityId}'
                : '/play/0?topicId=${run.topicId}',
          ),
        ),
      );
    }
    final List<MyRegistration> registrations =
        ref.watch(myJoinedActivitiesProvider).value ?? const <MyRegistration>[];
    MyRegistration? active;
    for (final MyRegistration registration in registrations) {
      if (registration.ticketState == TicketState.ready) {
        active = registration;
        break;
      }
    }
    if (active == null) return const SizedBox.shrink();

    final MyRegistration registration = active;
    final String subtitle =
        (registration.participateDate ?? '').trim().isNotEmpty
        ? registration.participateDate!.trim()
        : stringsOf(context).feedWaiting;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space5,
        CyTokens.pageX,
        0,
      ),
      child: _ContinueCard(
        cardKey: const Key('home-continue'),
        kicker: stringsOf(context).feedContinueExplore,
        title: (registration.title ?? '').trim().isEmpty
            ? stringsOf(context).feedContinueExplore
            : registration.title!.trim(),
        subtitle: subtitle,
        coverUrl: registration.imgUrl,
        fallbackIcon: Icons.near_me_outlined,
        onTap: () => context.push(
          '/tickets?focusId=${registration.id}&stype=${registration.ownerType == 1 ? 0 : 2}',
        ),
      ),
    );
  }
}

/// 首页那张「继续…」卡:游戏会话与报名旅程共用一套外观,只有文案与去处不同
/// (与小程序同用一个 `continueExplore` 渲染块)。
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.cardKey,
    required this.kicker,
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.fallbackIcon,
    required this.onTap,
  });

  final Key cardKey;
  final String kicker;
  final String title;
  final String subtitle;
  final String? coverUrl;
  final IconData fallbackIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: cardKey,
      color: CyTokens.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        side: const BorderSide(color: CyTokens.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: CupertinoButton(
        onPressed: onTap,
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 76),
          child: Padding(
            padding: const EdgeInsets.all(CyTokens.space4),
            child: Row(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                  child: SizedBox.square(
                    dimension: 56,
                    child: _CoverImage(
                      url: coverUrl,
                      fallbackIcon: fallbackIcon,
                    ),
                  ),
                ),
                const SizedBox(width: CyTokens.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        kicker,
                        style: const TextStyle(
                          color: CyTokens.textPrimary,
                          fontSize: CyTokens.typeMicro,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: CyTokens.space1),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: CyTokens.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: CyTokens.space1),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: CyTokens.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: CyTokens.space2),
                Text(
                  stringsOf(context).feedContinue,
                  style: const TextStyle(
                    color: CyTokens.textPrimary,
                    fontSize: CyTokens.typeLabel,
                  ),
                ),
                const SizedBox(width: CyTokens.space1),
                const Icon(
                  // 披露箭头用系统 chevron(L3),不用 Material 实心箭头。
                  CupertinoIcons.chevron_forward,
                  color: CyTokens.textSecondary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NearbySection extends ConsumerWidget {
  const _NearbySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Activity>> async = ref.watch(feedNearbyProvider);
    return Column(
      key: const Key('home-nearby'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SectionTitle(title: stringsOf(context).feedNearby),
        async.when(
          loading: () => const SizedBox(height: 220, child: LoadingView()),
          error: (Object err, StackTrace st) => StatusView(
            message: stringsOf(context).feedNearbyError,
            sub: stringsOf(context).feedNetworkRetry,
            icon: Icons.cloud_off,
            onRetry: () => ref.invalidate(feedNearbyProvider),
          ),
          data: (List<Activity> list) {
            if (list.isEmpty) {
              return StatusView(
                message: stringsOf(context).feedNearbyEmpty,
                sub: stringsOf(context).feedNearbyEmptyDetail,
                icon: Icons.location_off_outlined,
              );
            }
            return SizedBox(
              height: 220,
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.space4,
                ),
                itemCount: list.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: CyTokens.space3),
                itemBuilder: (BuildContext context, int index) =>
                    _NearbyCard(activity: list[index]),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _NearbyCard extends StatelessWidget {
  const _NearbyCard({required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 162.5,
      child: Material(
        color: CyTokens.bgElevated,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        clipBehavior: Clip.antiAlias,
        child: CupertinoButton(
          onPressed: () => context.push('/activity/${activity.id}'),
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(CyTokens.radiusLg),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              _CoverImage(
                url: activity.imgUrl,
                fallbackIcon: Icons.directions_walk,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      CyTokens.bgPage.withValues(alpha: 0.28),
                      CyTokens.bgPage.withValues(alpha: 0),
                      CyTokens.bgPage.withValues(alpha: 0.78),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: CyTokens.space2_5,
                right: CyTokens.space2_5,
                bottom: CyTokens.space2_5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      activity.name.isEmpty ? stringsOf(context).feedUnnamedActivity : activity.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: CyTokens.textPrimary,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    HomeActivityLive(startDate: activity.startDate),
                    if ((activity.addressName ?? '').isNotEmpty) ...<Widget>[
                      const SizedBox(height: CyTokens.space2),
                      Row(
                        children: <Widget>[
                          const Icon(
                            Icons.place_outlined,
                            size: 13,
                            color: CyTokens.textSecondary,
                          ),
                          const SizedBox(width: CyTokens.space1),
                          Expanded(
                            child: Text(
                              activity.addressName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: CyTokens.textSecondary,
                                fontSize: CyTokens.typeCaption,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecommendSection extends ConsumerWidget {
  const _RecommendSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Topic>> async = ref.watch(feedRecommendProvider);
    return Column(
      key: const Key('home-recommend'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SectionTitle(title: stringsOf(context).feedRecommendations),
        async.when(
          loading: () => const SizedBox(height: 372, child: LoadingView()),
          error: (Object err, StackTrace st) => StatusView(
            message: stringsOf(context).feedRecommendationsError,
            sub: stringsOf(context).feedNetworkRetry,
            icon: Icons.cloud_off,
            onRetry: () => ref.invalidate(feedRecommendProvider),
          ),
          data: (List<Topic> list) {
            if (list.isEmpty) {
              return StatusView(
                message: stringsOf(context).feedTopicsEmpty,
                sub: stringsOf(context).feedRecommendationsEmptyDetail,
                icon: Icons.route_outlined,
              );
            }
            return _RecommendHero(topic: list.first);
          },
        ),
      ],
    );
  }
}

class _RecommendHero extends StatelessWidget {
  const _RecommendHero({required this.topic});

  final Topic topic;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.space4),
      child: AspectRatio(
        aspectRatio: 343 / 372,
        child: Material(
          color: CyTokens.bgElevated,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: CupertinoButton(
            onPressed: () => context.push('/topic/${topic.id}'),
            minimumSize: Size.zero,
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _CoverImage(
                  url: topic.picUrl,
                  fallbackIcon: Icons.route_outlined,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        CyTokens.bgPage.withValues(alpha: 0.08),
                        CyTokens.bgPage.withValues(alpha: 0.94),
                      ],
                      stops: <double>[0.35, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: CyTokens.space4,
                  right: CyTokens.space4,
                  bottom: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (topic.isRecommend == 1) ...<Widget>[
                        const _RecommendBadge(),
                        const SizedBox(height: CyTokens.space2),
                      ],
                      if (topic.betaFlag == 1) ...<Widget>[
                        CyTag(label: stringsOf(context).feedBeta),
                        const SizedBox(height: CyTokens.space2),
                      ],
                      Text(
                        topic.name.isEmpty ? stringsOf(context).feedUnnamedRoute : topic.name,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: CyType.title1.copyWith(
                          color: CyTokens.textPrimary,
                          fontWeight: FontWeight.w700,
                          height: 1.16,
                        ),
                      ),
                      if ((topic.introduction ?? '').isNotEmpty) ...<Widget>[
                        const SizedBox(height: CyTokens.space2),
                        Text(
                          topic.introduction!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: CyTokens.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpcomingSection extends ConsumerWidget {
  const _UpcomingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<UpcomingActivity>> async = ref.watch(
      feedUpcomingProvider,
    );
    final bool hidden = async.value?.isEmpty == true;
    if (hidden) return const SizedBox.shrink();
    // 横滑轨道是固定高度 —— 大字号档三行文字会顶穿(200% 实测溢出 30px,
    // A1/§9.6:固定高小组件裁字门禁抓不到)。轨道随 text scaler 等比长高。
    final double railHeight = 100 * MediaQuery.textScalerOf(context).scale(1);
    return Column(
      key: const Key('home-upcoming'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SectionTitle(title: stringsOf(context).feedUpcoming),
        async.when(
          loading: () =>
              SizedBox(height: railHeight, child: const LoadingView()),
          error: (Object err, StackTrace st) => StatusView(
            message: stringsOf(context).feedUpcomingError,
            sub: stringsOf(context).feedNetworkRetry,
            icon: Icons.cloud_off,
            onRetry: () => ref.invalidate(feedUpcomingProvider),
          ),
          data: (List<UpcomingActivity> list) => SizedBox(
            height: railHeight,
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.space4),
              itemCount: list.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: CyTokens.space3),
              itemBuilder: (BuildContext context, int index) =>
                  _UpcomingCard(activity: list[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.activity});

  final UpcomingActivity activity;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 288,
      child: Material(
        color: CyTokens.bgSurfaceSubtle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CyTokens.radiusXl),
          side: const BorderSide(color: CyTokens.borderSubtle),
        ),
        clipBehavior: Clip.antiAlias,
        child: CupertinoButton(
          onPressed: () => context.push('/activity/${activity.id}'),
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(CyTokens.radiusXl),
          child: Padding(
            padding: const EdgeInsets.all(CyTokens.space4),
            child: Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: CyTokens.borderStrong, width: 2),
                  ),
                  child: _CoverImage(
                    url: activity.imgUrl,
                    fallbackIcon: Icons.event_outlined,
                  ),
                ),
                const SizedBox(width: CyTokens.space3),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        activity.name.isEmpty ? stringsOf(context).feedUnnamedActivity : activity.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CyType.body.copyWith(
                          color: CyTokens.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if ((activity.addressName ?? '').isNotEmpty) ...<Widget>[
                        const SizedBox(height: CyTokens.space1),
                        Text(
                          activity.addressName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: CyTokens.textTertiary),
                        ),
                      ],
                      const SizedBox(height: CyTokens.space1),
                      Row(
                        children: <Widget>[
                          const Icon(
                            Icons.star,
                            size: 12,
                            color: CyTokens.textSecondary,
                          ),
                          const SizedBox(width: CyTokens.space1),
                          CountdownText(target: activity.startDate),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityFeedCard extends StatelessWidget {
  const _ActivityFeedCard({required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 246,
      child: Material(
        color: CyTokens.bgElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CyTokens.radiusLg),
          side: const BorderSide(color: CyTokens.borderSubtle),
        ),
        clipBehavior: Clip.antiAlias,
        child: CupertinoButton(
          onPressed: () => context.push('/activity/${activity.id}'),
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(CyTokens.radiusLg),
          child: Padding(
            padding: const EdgeInsets.all(CyTokens.space4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        activity.name.isEmpty ? stringsOf(context).feedUnnamedActivity : activity.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: CyTokens.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if ((activity.description ?? '').isNotEmpty) ...<Widget>[
                        const SizedBox(height: CyTokens.space2),
                        Text(
                          activity.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: CyTokens.textTertiary),
                        ),
                      ],
                      const Spacer(),
                      _FeedStatusRows(
                        price: activity.minAmount,
                        startDate: activity.startDate,
                        addressName:
                            (activity.addressName ?? activity.address ?? '')
                                .trim(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: CyTokens.space3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                  child: SizedBox(
                    width: 120,
                    child: _CoverImage(
                      url: activity.imgUrl,
                      fallbackIcon: Icons.event_outlined,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topic});

  final Topic topic;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 266,
      child: Material(
        color: CyTokens.bgElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: CyTokens.borderSubtle),
        ),
        clipBehavior: Clip.antiAlias,
        child: CupertinoButton(
          onPressed: () => context.push('/topic/${topic.id}'),
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(CyTokens.space4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        topic.name.isEmpty ? stringsOf(context).feedUnnamedRoute : topic.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: CyTokens.textPrimary,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      if ((topic.introduction ?? '').isNotEmpty) ...<Widget>[
                        const SizedBox(height: CyTokens.space2),
                        Text(
                          topic.introduction!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: CyTokens.textTertiary),
                        ),
                      ],
                      const Spacer(),
                      // 价格/时间/地点 —— 与活动卡同一种三行(小程序 .v2-status)。
                      _FeedStatusRows(
                        price: topic.minAmount,
                        startDate: topic.startDate,
                        addressName: topic.addressName ?? '',
                      ),
                      const SizedBox(height: CyTokens.space2),
                      Row(
                        children: <Widget>[
                          if (topic.isRecommend == 1) const _RecommendBadge(),
                          const Spacer(),
                          Icon(
                            topic.isLike == 1
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 16,
                            color: topic.isLike == 1
                                ? CyPalette.of(context).statusDanger
                                : CyTokens.textTertiary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: CyTokens.space3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                  child: SizedBox(
                    width: 120,
                    child: _CoverImage(
                      url: topic.picUrl,
                      fallbackIcon: Icons.route_outlined,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部流卡片的「价格 / 时间 / 地点」三行(小程序 `.v2-status`)。
///
/// 三行**恒定在**,值缺了写「—」:真源 wxs/money.wxs 的口径是
/// 「绑定值为空时渲 '—',绝不渲出一个裸的 ¥ 或空白;0 是合法金额」。
/// 时间跟 App 活动列表同一口径取「MM-dd HH:mm」(不引第二套日期格式)。
class _FeedStatusRows extends StatelessWidget {
  const _FeedStatusRows({
    required this.price,
    required this.startDate,
    required this.addressName,
  });

  final double? price;
  final String? startDate;
  final String addressName;

  @override
  Widget build(BuildContext context) {
    final TextStyle label = TextStyle(
      fontSize: CyTokens.typeCaption,
      color: CyTokens.textTertiary,
    );
    final TextStyle value = TextStyle(
      fontSize: CyTokens.typeCaption,
      color: CyTokens.textSecondary,
    );
    final String start = startDate ?? '';
    final String when = start.length >= 16
        ? '${start.substring(5, 10)} ${start.substring(11, 16)}'
        : (start.isEmpty ? '—' : start);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _row(
          stringsOf(context).feedPrice,
          stringsOf(context).feedPriceFrom(price == null ? '—' : '¥${price!.toStringAsFixed(2)}'),
          label,
          value,
        ),
        const SizedBox(height: 2),
        _row(stringsOf(context).feedTime, when, label, value),
        const SizedBox(height: 2),
        _row(
          stringsOf(context).feedPlace,
          addressName.trim().isEmpty ? '—' : addressName,
          label,
          value,
        ),
      ],
    );
  }

  Widget _row(
    String key,
    String text,
    TextStyle labelStyle,
    TextStyle valueStyle,
  ) {
    return Row(
      children: <Widget>[
        Text(key, style: labelStyle),
        const SizedBox(width: CyTokens.space2),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: valueStyle,
          ),
        ),
      ],
    );
  }
}

class _RecommendBadge extends StatelessWidget {
  const _RecommendBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: CyTokens.brandSoft,
        borderRadius: BorderRadius.circular(CyTokens.radiusPill),
        border: Border.all(color: CyTokens.borderStrong),
      ),
      child: Text(
        stringsOf(context).feedRecommended,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: CyTokens.textPrimary),
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.url, required this.fallbackIcon});

  final String? url;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = ColoredBox(
      color: CyTokens.bgElevated,
      child: Center(
        child: Icon(fallbackIcon, size: 32, color: CyTokens.textDisabled),
      ),
    );
    if (url == null || url!.isEmpty) return fallback;
    return Image.network(
      url!,
      fit: BoxFit.cover,
      frameBuilder:
          (
            BuildContext context,
            Widget child,
            int? frame,
            bool wasSynchronouslyLoaded,
          ) => frame == null ? fallback : child,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

class _FeedFooter extends StatelessWidget {
  const _FeedFooter({required this.hasMore, this.failed = false, this.onRetry});

  final bool hasMore;
  final bool failed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (failed) {
      // 真源 cy-error 三段式(标题点名失败对象 + 安慰性副标 + 重试动作),
      // 对位 pages/index/index.wxml bottomTopicFailedPage>1 分支。
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            stringsOf(context).feedMoreError,
            style: CyType.subhead.copyWith(color: CyTokens.textPrimary),
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            stringsOf(context).feedMoreErrorDetail,
            style: CyType.caption1.copyWith(color: CyTokens.textTertiary),
          ),
          CupertinoButton(
            onPressed: onRetry,
            minimumSize: const Size(44, 44),
            child: Text(stringsOf(context).feedRetry),
          ),
        ],
      );
    } else if (hasMore) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CupertinoActivityIndicator(),
          const SizedBox(width: CyTokens.space2),
          Text(stringsOf(context).feedLoadingMore),
        ],
      );
    } else {
      child = Text(
        stringsOf(context).feedNoMore,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: CyTokens.textSecondary),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space4),
      child: Center(child: child),
    );
  }
}
