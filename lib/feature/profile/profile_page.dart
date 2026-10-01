import '../../l10n/strings.dart';
import '../../l10n/profile_error_display.dart';
import '../../core/widgets/localized_error_status.dart';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/feature_flags.dart';
import '../../core/merchant_access_provider.dart';
import '../../core/role_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/merchant_api.dart';
import '../../data/models/activity.dart';
import '../../data/models/club.dart';
import '../../data/models/growth.dart';
import '../../data/models/my_project.dart';
import '../../data/models/profile_detail.dart';
import '../../data/models/role_info.dart';
import '../../data/models/square_post.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';
import '../club/club_controller.dart';
import '../merchant/merchant_edit_page.dart';
import '../orders/orders_page.dart';
import '../publish/my_projects_page.dart';
import 'profile_controller.dart';

enum ProfileRootTab { mine, posts, achievements, about }

enum ProfileDestination {
  settings,
  editProfile,
  explore,
  verify,
  orders,
  projects,
  assets,
  merchantTeam,
  club,
  becomeLeader,
  creator,
  coupons,
  invites,
  complaints,
  tickets,
  points,
  mall,
  growth,
  badges,
  stamps,
  participations,
  objectCards,
}

void openProfileDestination(
  BuildContext context,
  ProfileDestination destination, {
  required bool isMerchantView,
  required AsyncValue<bool> activeRegistration,
  required VoidCallback retryActiveRegistration,
  required AsyncValue<List<Club>> ownedClubs,
  required VoidCallback retryOwnedClubs,
}) {
  if (destination == ProfileDestination.explore) {
    if (activeRegistration.isLoading) return;
    if (activeRegistration.hasError) {
      retryActiveRegistration();
      return;
    }
    context.go('/roam');
    return;
  }
  if (destination == ProfileDestination.club) {
    if (ownedClubs.isLoading) return;
    if (ownedClubs.hasError) {
      retryOwnedClubs();
      return;
    }
    final List<Club> owned = ownedClubs.value ?? const <Club>[];
    context.push(owned.isEmpty ? '/club/create' : '/club/${owned.first.id}');
    return;
  }
  final String route = switch (destination) {
    ProfileDestination.settings => '/settings',
    ProfileDestination.editProfile =>
      isMerchantView ? '/merchant/decor' : '/profile/edit',
    ProfileDestination.explore => throw StateError('探索入口已在上方处理'),
    ProfileDestination.verify => '/merchant/scan',
    ProfileDestination.orders => '/orders',
    ProfileDestination.projects => '/my-projects',
    ProfileDestination.assets => '/assets',
    ProfileDestination.merchantTeam => '/merchant/team',
    ProfileDestination.club => throw StateError('俱乐部入口已在上方处理'),
    ProfileDestination.becomeLeader => '/club/apply',
    ProfileDestination.creator => '/creator',
    ProfileDestination.coupons => '/coupons',
    ProfileDestination.invites => '/invites',
    ProfileDestination.complaints => '/complaint',
    ProfileDestination.tickets => '/tickets',
    ProfileDestination.points => '/points',
    ProfileDestination.mall => '/mall',
    ProfileDestination.objectCards => '/object-cards',
    ProfileDestination.growth => '/growth',
    ProfileDestination.badges => '/badges',
    ProfileDestination.stamps => '/roam/stamp-album',
    ProfileDestination.participations => '/participations',
  };
  context.push(route);
}

/// 我的根页公开 widget seam。只接收已解析业务数据与语义目的地，测试不需要探实现细节。
class ProfileRootView extends StatefulWidget {
  const ProfileRootView({
    super.key,
    required this.user,
    required this.effectiveRole,
    required this.orders,
    required this.projects,
    required this.posts,
    required this.growth,
    required this.playGrowth,
    this.merchantInfo,
    required this.onPost,
    required this.onDestination,
    required this.onOrder,
    required this.onProject,
    required this.onRetryOrders,
    required this.onRetryProjects,
    required this.onRetryPosts,
    required this.onRetryGrowth,
    this.clubOwnedCount = 0,
    this.exploreEnabled = true,
    this.onRetryMerchant,
    this.merchantTeam,
    this.roleInfo,
    this.onRetryRoleInfo,
  });

  final ProfileDetail user;
  final String effectiveRole;
  final AsyncValue<List<MyRegistration>> orders;
  final AsyncValue<List<MyProject>> projects;
  final AsyncValue<List<SquarePost>> posts;
  final AsyncValue<GrowthCenter> growth;
  final AsyncValue<PlayGrowth> playGrowth;
  final AsyncValue<Map<String, dynamic>>? merchantInfo;
  final ValueChanged<int> onPost;
  final ValueChanged<ProfileDestination> onDestination;
  final ValueChanged<MyRegistration> onOrder;
  final ValueChanged<MyProject> onProject;
  final VoidCallback onRetryOrders;
  final VoidCallback onRetryProjects;
  final VoidCallback onRetryPosts;
  final VoidCallback onRetryGrowth;
  final int clubOwnedCount;
  final bool exploreEnabled;
  final VoidCallback? onRetryMerchant;

  /// 「经营团队」一行右侧的说明(真源 `merchantTeamEntryValue`)。
  /// null = 当前不是激活经营身份,整行不显示。
  final String? merchantTeam;

  /// 当前权益九项数据源(`/api/role/info`)。缺席则整块不显示。
  final AsyncValue<RoleInfo>? roleInfo;
  final VoidCallback? onRetryRoleInfo;

  @override
  State<ProfileRootView> createState() => _ProfileRootViewState();
}

class _ProfileRootViewState extends State<ProfileRootView> {
  ProfileRootTab _tab = ProfileRootTab.mine;

  bool get _merchant => widget.effectiveRole == 'merchant';

  @override
  Widget build(BuildContext context) {
    if (_merchant) {
      final ThemeData light = AppTheme.merchantLight();
      return Theme(
        data: light,
        // ★ 只包 Material `Theme` 不够:`ThemeData.cupertinoOverrideTheme` 在
        //   `CupertinoApp` 下不生效(根已有 CupertinoTheme 时,`Theme.build`
        //   把**祖先那份**转发布),Cupertino 侧会留在根暗色。
        //   路由层同机制收口见 `app_router.dart` 的商家浅色包装(`_merchantLight`,
        //   PR #198 补齐 Cupertino 那一半)。
        child: CupertinoTheme(
          data: CupertinoThemeData(
            brightness: light.brightness,
            primaryColor: light.colorScheme.primary,
            scaffoldBackgroundColor: light.scaffoldBackgroundColor,
            barBackgroundColor: light.scaffoldBackgroundColor,
          ),
          child: Builder(builder: _buildContent),
        ),
      );
    }
    return _buildContent(context);
  }

  Widget _buildContent(BuildContext context) {
    final palette = CyPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bgPage,
      body: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: _ProfileHero(
              user: widget.user,
              merchant: _merchant,
              streakDays: widget.playGrowth.value?.streakDays,
              merchantInfo: widget.merchantInfo?.value,
              exploreEnabled: widget.exploreEnabled,
              onDestination: widget.onDestination,
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabsHeader(
              tab: _tab,
              merchant: _merchant,
              background: palette.bgPage,
              textScale: MediaQuery.textScalerOf(context).scale(17) / 17,
              onChanged: (ProfileRootTab value) => setState(() => _tab = value),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              CyTokens.pageX,
              CyTokens.space4,
              CyTokens.pageX,
              CyTokens.space8 + MediaQuery.paddingOf(context).bottom,
            ),
            sliver: SliverList.list(
              children: switch (_tab) {
                ProfileRootTab.mine => _mineChildren(),
                ProfileRootTab.posts => <Widget>[
                  _PostsTab(
                    posts: widget.posts,
                    onRetry: widget.onRetryPosts,
                    onPost: widget.onPost,
                  ),
                ],
                ProfileRootTab.achievements => <Widget>[
                  _AchievementsTab(
                    growth: widget.growth,
                    onRetry: widget.onRetryGrowth,
                    onDestination: widget.onDestination,
                  ),
                ],
                ProfileRootTab.about => <Widget>[
                  _AboutTab(
                    user: widget.user,
                    role: widget.effectiveRole,
                    clubOwnedCount: widget.clubOwnedCount,
                    merchantInfo: widget.merchantInfo,
                    roleInfo: widget.roleInfo,
                    onRetryRoleInfo: widget.onRetryRoleInfo,
                    onDestination: widget.onDestination,
                    onRetryMerchant: widget.onRetryMerchant,
                  ),
                ],
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _mineChildren() {
    final String? team = widget.merchantTeam;
    return <Widget>[
      _SectionHeader(
        title: stringsOf(context).profileOrders,
        action: stringsOf(context).profileDetails,
        actionKey: const ValueKey<String>('profile-orders'),
        onAction: () => widget.onDestination(ProfileDestination.orders),
      ),
      _OrdersPreview(
        orders: widget.orders,
        onRetry: widget.onRetryOrders,
        onOpen: widget.onOrder,
      ),
      const SizedBox(height: CyTokens.space5),
      _SectionHeader(
        title: stringsOf(context).profileProjects,
        action: stringsOf(context).profileManageAll,
        actionKey: const ValueKey<String>('profile-projects'),
        onAction: () => widget.onDestination(ProfileDestination.projects),
      ),
      _ProjectsPreview(
        projects: widget.projects,
        onRetry: widget.onRetryProjects,
        onOpen: widget.onProject,
      ),
      const SizedBox(height: CyTokens.space5),
      _SectionHeader(
        title: stringsOf(context).profileAssets,
        action: stringsOf(context).profileDetails,
        actionKey: const ValueKey<String>('profile-assets'),
        onAction: () => widget.onDestination(ProfileDestination.assets),
      ),
      _AssetCard(
        balance: widget.user.balance,
        onTap: () => widget.onDestination(ProfileDestination.assets),
      ),
      // 真源把这行放在资产**之后**:资产回答「钱在哪里」,团队回答「谁能经营」。
      if (team != null)
        _MerchantTeamEntry(
          value: team,
          onTap: () => widget.onDestination(ProfileDestination.merchantTeam),
        ),
    ];
  }
}

/// 单条权益(解锁/锁定)。仅「我的收益」带跳转。
class _Benefit {
  const _Benefit({required this.text, required this.unlocked, this.onTap});
  final String text;
  final bool unlocked;
  final VoidCallback? onTap;
}

/// 「当前权益」九项(对齐小程序 cy-profile buildBenefits,数据源 /api/role/info)。
/// 未解锁项显示锁图标、不可点;解锁项显示勾。
class _BenefitsSection extends StatelessWidget {
  const _BenefitsSection({required this.role, required this.onOpenEarnings});

  final RoleInfo role;
  final VoidCallback onOpenEarnings;

  List<_Benefit> _benefits(BuildContext context) {
    final int? maxThemes = role.quota('maxThemes');
    return <_Benefit>[
      _Benefit(
        text: stringsOf(context).profileThemeLimit(maxThemes == null ? stringsOf(context).profileUnlimited : '$maxThemes'),
        unlocked: maxThemes == null || maxThemes > 0,
      ),
      _Benefit(text: stringsOf(context).profileBenefitCoupons, unlocked: role.can('canPublishCoupon')),
      _Benefit(text: stringsOf(context).profileBenefitRedeem, unlocked: role.can('canRedeemCoupon')),
      _Benefit(text: stringsOf(context).profileBenefitBranch, unlocked: role.can('canBranch')),
      _Benefit(text: stringsOf(context).profileBenefitGame, unlocked: role.can('canGameMechanic')),
      _Benefit(text: stringsOf(context).profileBenefitNode, unlocked: role.can('canOpenAsNode')),
      _Benefit(text: stringsOf(context).profileBenefitMedal, unlocked: role.can('canDesignMedal')),
      _Benefit(text: stringsOf(context).profileBenefitGroup, unlocked: role.can('canCreateGroup')),
      _Benefit(
        text: stringsOf(context).profileEarnings,
        unlocked: role.can('withdrawable'),
        onTap: onOpenEarnings,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    final benefits = _benefits(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          stringsOf(context).profileBenefits,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: palette.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: CyTokens.space3),
        Container(
          decoration: BoxDecoration(
            color: palette.bgSurfaceSubtle,
            borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            border: Border.all(color: palette.borderSubtle),
          ),
          child: Column(
            children: <Widget>[
              for (int i = 0; i < benefits.length; i++) ...<Widget>[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    indent: CyTokens.space4,
                    color: palette.borderSubtle,
                  ),
                _benefitRow(context, palette, benefits[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _benefitRow(
    BuildContext context,
    CyPalette palette,
    _Benefit benefit,
  ) {
    final IconData icon = benefit.unlocked
        ? CupertinoIcons.checkmark_alt_circle_fill
        : CupertinoIcons.lock_circle_fill;
    final Color iconColor = benefit.unlocked
        ? palette.textPrimary
        : palette.textTertiary;
    final bool tappable = benefit.unlocked && benefit.onTap != null;
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space4,
        vertical: CyTokens.space3,
      ),
      minSize: 0,
      onPressed: tappable ? benefit.onTap : null,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: CyTokens.space3),
          Expanded(
            child: Text(
              benefit.text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: benefit.unlocked
                    ? palette.textPrimary
                    : palette.textTertiary,
              ),
            ),
          ),
          if (tappable)
            Icon(
              CupertinoIcons.chevron_forward,
              size: 14,
              color: palette.textTertiary,
            ),
        ],
      ),
    );
  }
}

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    if (!auth.isLoggedIn) return const _GuestPrompt();

    final bool communityOpen = ref.watch(
      featureFlagProvider('communityPostRead'),
    );
    final detail = ref.watch(profileDetailProvider);
    final AsyncValue<bool> activeRegistration = ref.watch(
      hasActiveRegistrationProvider,
    );
    final AsyncValue<List<Club>> ownedClubs = auth.user?.effectiveRole == 'club'
        ? ref.watch(clubMyProvider)
        : const AsyncData<List<Club>>(<Club>[]);
    final MerchantAccess? access = auth.user?.isMerchantView == true
        ? ref.watch(merchantAccessProvider).asData?.value
        : null;
    final String? merchantTeam = access == null || !access.active
        ? null
        : '${access.roleName} · ${access.canManageOperators ? stringsOf(context).profileManage : stringsOf(context).profileView}';
    return detail.when(
      skipLoadingOnReload: false,
      skipLoadingOnRefresh: false,
      loading: () => const Scaffold(body: CySkeleton()),
      error: (Object error, StackTrace stack) => Scaffold(
        body: StatusView(
          message: stringsOf(context).profileLoadError,
          sub: stringsOf(context).profileRetryNetwork,
          icon: CupertinoIcons.cloud,
          onRetry: () => ref.invalidate(profileDetailProvider),
        ),
      ),
      data: (ProfileDetail user) => ProfileRootView(
        user: user,
        effectiveRole: auth.user?.effectiveRole ?? 'player',
        orders: ref.watch(myOrdersProvider),
        projects: ref.watch(myProjectsProvider),
        posts: ref.watch(myCreativesProvider),
        growth: ref.watch(growthCenterProvider),
        playGrowth: ref.watch(playGrowthProvider),
        clubOwnedCount: ownedClubs.value?.length ?? 0,
        roleInfo: ref.watch(roleInfoProvider),
        merchantInfo: auth.user?.isMerchantView == true
            ? ref.watch(merchantInfoProvider)
            : null,
        merchantTeam: merchantTeam,
        onRetryOrders: () => ref.invalidate(myOrdersProvider),
        onRetryProjects: () => ref.invalidate(myProjectsProvider),
        onRetryPosts: () => ref.invalidate(myCreativesProvider),
        onRetryGrowth: () => ref.invalidate(growthCenterProvider),
        onRetryRoleInfo: () => ref.invalidate(roleInfoProvider),
        exploreEnabled: !activeRegistration.isLoading,
        onRetryMerchant: () => ref.invalidate(merchantInfoProvider),
        onPost: (int id) {
          if (!communityOpen) {
            CyNativeNotice.show(context, stringsOf(context).profileCommunityClosed);
            return;
          }
          context.push('/square/$id');
        },
        onOrder: (MyRegistration order) =>
            context.push('/orders?detailId=${order.id}'),
        onProject: (MyProject project) {
          if (project.detailRoute == null) {
            // 纯告知不弹 alert(手册 S7)。
            CyNativeNotice.show(context, stringsOf(context).profileProjectUnavailable);
            return;
          }
          context.push(project.detailRoute!);
        },
        onDestination: (ProfileDestination destination) {
          openProfileDestination(
            context,
            destination,
            isMerchantView: auth.user?.isMerchantView == true,
            activeRegistration: activeRegistration,
            retryActiveRegistration: () =>
                ref.invalidate(hasActiveRegistrationProvider),
            ownedClubs: ownedClubs,
            retryOwnedClubs: () => ref.invalidate(clubMyProvider),
          );
        },
      ),
    );
  }
}

class _GuestPrompt extends ConsumerWidget {
  const _GuestPrompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 未登录空态走共用层 StatusView(对照表 #29):文案逐字不变,
    // 排版 / 触达区 / CTA 交给共用层 —— 手搓的这一份字号与间距和别处空态对不上。
    return Scaffold(
      backgroundColor: CyPalette.of(context).bgPage,
      body: StatusView(
        message: stringsOf(context).profileLoginTitle,
        sub: stringsOf(context).profileLoginDetail,
        icon: CupertinoIcons.person_crop_circle,
        large: true,
        onRetry: () => showLoginSheet(context),
        retryLabel: stringsOf(context).profileSignIn,
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.user,
    required this.merchant,
    required this.streakDays,
    required this.merchantInfo,
    required this.exploreEnabled,
    required this.onDestination,
  });

  final ProfileDetail user;
  final bool merchant;

  /// `play.streakDays`。★ null = **没拿到**,不是 0 —— 小程序 cy-profile 写的是
  /// `streakDays === 0 ? 0 : (streakDays || '—')`,缺值显示「—」。
  final int? streakDays;
  final Map<String, dynamic>? merchantInfo;
  final bool exploreEnabled;
  final ValueChanged<ProfileDestination> onDestination;

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    final TextScaler textScaler = MediaQuery.textScalerOf(context);
    final double bodyTextScale = textScaler.scale(CyTokens.space4);
    final double baseHeight = CyTokens.space8 * 7 + CyTokens.space5;
    final double heroHeight =
        baseHeight +
        (bodyTextScale > CyTokens.space4
            ? (bodyTextScale - CyTokens.space4) * CyTokens.space3
            : 0);
    final bool usesAccessibilityTextSize = bodyTextScale > CyTokens.space4;
    final merchantAvatar = (merchantInfo?['logo'] ?? '').toString();
    final merchantCoverImage = (merchantInfo?['coverImage'] ?? '').toString();
    final merchantLegacyCover = (merchantInfo?['cover'] ?? '').toString();
    final merchantCover = merchantCoverImage.isNotEmpty
        ? merchantCoverImage
        : merchantLegacyCover;
    final avatar = merchant ? merchantAvatar : user.avatar;
    final cover = merchant
        ? (merchantCover.isNotEmpty ? merchantCover : merchantAvatar)
        : user.avatar;
    final merchantName = (merchantInfo?['name'] ?? '').toString();
    final merchantRole = (merchantInfo?['cityRole'] ?? '').toString();
    final merchantSlogan = (merchantInfo?['slogan'] ?? '').toString();
    return SizedBox(
      key: const ValueKey<String>('profile-hero'),
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (cover.isNotEmpty)
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: CyTokens.space4 + CyTokens.space1 / 2,
                sigmaY: CyTokens.space4 + CyTokens.space1 / 2,
              ),
              child: CyNetImage(cover, fit: BoxFit.cover),
            )
          else
            ColoredBox(color: palette.bgElevated),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  palette.bgPage.withValues(alpha: 0.12),
                  palette.bgPage.withValues(alpha: 0.52),
                  palette.bgPage,
                ],
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                CyTokens.pageX,
                CyTokens.space1,
                CyTokens.pageX,
                CyTokens.space4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Semantics(
                        label: stringsOf(context).profileSettings,
                        button: true,
                        excludeSemantics: true,
                        onTap: () => onDestination(ProfileDestination.settings),
                        child: CupertinoButton(
                          padding: const EdgeInsets.all(CyTokens.space2),
                          minimumSize: const Size.square(CyTokens.btnH),
                          onPressed: () =>
                              onDestination(ProfileDestination.settings),
                          child: Icon(
                            CupertinoIcons.settings,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          stringsOf(context).profileHome,
                          textAlign: TextAlign.center,
                          // T3:强调上限 bold(700),w800 属堆重。
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      const SizedBox(width: CyTokens.btnH),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: <Widget>[
                      Stack(
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          Semantics(
                            label: stringsOf(context).profileEdit,
                            button: true,
                            excludeSemantics: true,
                            onTap: () =>
                                onDestination(ProfileDestination.editProfile),
                            child: CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size.square(CyTokens.btnH),
                              onPressed: () =>
                                  onDestination(ProfileDestination.editProfile),
                              child: CyAvatar(
                                url: avatar.isEmpty ? null : avatar,
                                // 尺寸 = 原 CircleAvatar 直径 2×(space7 − space1/2);
                                // 无图时共用件自带兜底(V4),不再裸 NetworkImage。
                                size: CyTokens.space7 * 2 - CyTokens.space1,
                                bordered: false,
                              ),
                            ),
                          ),
                          Positioned(
                            top: -CyTokens.space1 / 2,
                            right: -CyTokens.space1 / 2,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: palette.actionPrimaryBg,
                                shape: BoxShape.circle,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(CyTokens.space1),
                                child: Icon(
                                  CupertinoIcons.pencil,
                                  size: CyTokens.space3,
                                  color: palette.actionPrimaryFg,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: CyTokens.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              merchant
                                  ? (merchantName.isEmpty ? stringsOf(context).profileMerchant : merchantName)
                                  : (user.nickname.isEmpty
                                        ? stringsOf(context).profileExplorer
                                        : user.nickname),
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    color: palette.textPrimary,
                                    // T3:强调上限 bold(700),w800 属堆重。
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: CyTokens.space1),
                            Text(
                              merchant
                                  ? (merchantRole.isEmpty
                                        ? stringsOf(context).profileCityMerchant
                                        : merchantRole)
                                  : stringsOf(context).profileExplorerLevel(user.levelId),
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: palette.textSecondary),
                            ),
                            // 连续探索:小程序 cy-profile index.wxml:70,本人专属,
                            // 值取 `/api/play/growth` 的 streakDays。没拿到写「—」,
                            // **不是 0** —— 那是在替用户陈述他的打卡记录。
                            if (!merchant) ...<Widget>[
                              const SizedBox(height: CyTokens.space1),
                              Text(
                                stringsOf(context).profileStreak(streakDays?.toString() ?? '—'),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: palette.textSecondary),
                              ),
                            ],
                            const SizedBox(height: CyTokens.space1),
                            Text(
                              merchant
                                  ? (merchantSlogan.isEmpty
                                        ? stringsOf(context).profileMerchantSlogan
                                        : merchantSlogan)
                                  : (user.introduction.isEmpty
                                        ? stringsOf(context).profileIntroductionFallback
                                        : user.introduction),
                              maxLines: usesAccessibilityTextSize ? 3 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: palette.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: CyTokens.space3),
                  Row(
                    children: <Widget>[
                      // ★ 三格 = 好友 / 关注 / 粉丝(小程序 cy-profile
                      //   index.wxml:76-82)。「获赞」不在这三格里 —— 它归
                      //   「发布内容 / 获赞 / 粉丝」那组公开统计。
                      _Stat(value: user.friendNum, label: stringsOf(context).profileFriends),
                      _Stat(value: user.followNum, label: stringsOf(context).profileFollowing),
                      _Stat(value: user.fansNum, label: stringsOf(context).profileFollowers),
                    ],
                  ),
                  const SizedBox(height: CyTokens.space3),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: CupertinoButton(
                          color: palette.actionPrimaryBg,
                          borderRadius: BorderRadius.circular(
                            CyTokens.radiusLg,
                          ),
                          onPressed: !merchant && !exploreEnabled
                              ? null
                              : () => onDestination(
                                  merchant
                                      ? ProfileDestination.verify
                                      : ProfileDestination.explore,
                                ),
                          child: Text(
                            merchant ? stringsOf(context).profileRedeem : stringsOf(context).profileExplore,
                            style: TextStyle(
                              color: !merchant && !exploreEnabled
                                  ? palette.textPlaceholder
                                  : palette.actionPrimaryFg,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      if (!merchant) ...<Widget>[
                        const SizedBox(width: CyTokens.space2),
                        Expanded(
                          child: CupertinoButton(
                            color: palette.actionPrimaryBg,
                            borderRadius: BorderRadius.circular(
                              CyTokens.radiusLg,
                            ),
                            onPressed: () =>
                                onDestination(ProfileDestination.tickets),
                            child: Text(
                              stringsOf(context).profileTickets,
                              style: TextStyle(
                                color: palette.actionPrimaryFg,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  /// null = 没拿到(如 `/api/user/info` 目前没有 friendNum),显示「—」。
  /// ★ 写 0 是在陈述「他是 0 个好友」,我们并不知道。
  final int? value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    return Expanded(
      child: Text(
        '${value ?? '—'} $label',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  _TabsHeader({
    required this.tab,
    required this.merchant,
    required this.background,
    required this.textScale,
    required this.onChanged,
  });

  final ProfileRootTab tab;
  final bool merchant;
  final Color background;
  final double textScale;
  final ValueChanged<ProfileRootTab> onChanged;

  @override
  double get minExtent => (CyTokens.btnH + CyTokens.space2 + CyTokens.space1 / 2) * textScale.clamp(1, 3);

  @override
  double get maxExtent => minExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final palette = CyPalette.of(context);
    Widget item(ProfileRootTab value, String label) {
      final selected = tab == value;
      return SizedBox(
        width: MediaQuery.sizeOf(context).width / (merchant ? 3 : 4) * textScale.clamp(1, 3),
        child: CupertinoButton(
          key: ValueKey('profile-tab-${value.name}'),
          padding: EdgeInsets.zero,
          onPressed: () => onChanged(value),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: selected
                          ? palette.textPrimary
                          : palette.textDisabled,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Container(
                width: CyTokens.btnHSm + CyTokens.space1,
                height: CyTokens.space1 / 2,
                color: selected
                    ? palette.textPrimary
                    : palette.bgPage.withValues(alpha: 0),
              ),
            ],
          ),
        ),
      );
    }

    return ColoredBox(
      color: background,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
        children: <Widget>[
          item(ProfileRootTab.mine, stringsOf(context).profileTabMine),
          item(ProfileRootTab.posts, stringsOf(context).profileTabPosts),
          if (!merchant) item(ProfileRootTab.achievements, stringsOf(context).profileTabAchievements),
          item(ProfileRootTab.about, stringsOf(context).profileTabAbout),
        ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabsHeader oldDelegate) =>
      oldDelegate.tab != tab ||
      oldDelegate.merchant != merchant ||
      oldDelegate.background != background ||
      oldDelegate.textScale != textScale;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.action,
    required this.actionKey,
    required this.onAction,
  });

  final String title;
  final String action;
  final Key actionKey;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    // 区块标题走共用层 CySectionTitle(L2/T3:Title3 Semibold + Semantics header),
    // 不再页内手搓 titleLarge w800。
    if (MediaQuery.textScalerOf(context).scale(17) > 22) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CySectionTitle(title),
          CupertinoButton(
            key: actionKey,
            padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
            onPressed: onAction,
            child: Text(action, style: TextStyle(color: palette.textSecondary)),
          ),
        ],
      );
    }
    return CySectionTitle(
      title,
      trailing: CupertinoButton(
        key: actionKey,
        padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
        minimumSize: const Size.square(CyTokens.btnH),
        onPressed: onAction,
        child: Text(action, style: TextStyle(color: palette.textSecondary)),
      ),
    );
  }
}

class _OrdersPreview extends StatelessWidget {
  const _OrdersPreview({
    required this.orders,
    required this.onRetry,
    required this.onOpen,
  });
  final AsyncValue<List<MyRegistration>> orders;
  final VoidCallback onRetry;
  final ValueChanged<MyRegistration> onOpen;

  @override
  Widget build(BuildContext context) => orders.when(
    loading: () => const CySkeleton(type: CySkeletonType.card, count: 1),
    error: (Object error, StackTrace stack) => StatusView(
      message: stringsOf(context).profileOrdersError,
      sub: stringsOf(context).profileOrdersErrorDetail,
      onRetry: onRetry,
    ),
    data: (List<MyRegistration> rows) => rows.isEmpty
        ? _CompactEmpty(title: stringsOf(context).profileOrdersEmpty, subtitle: stringsOf(context).profileOrdersEmptyDetail)
        : Column(
            children: rows
                .take(2)
                .map(
                  (MyRegistration order) => _PreviewRow(
                    title: (order.title ?? '').isEmpty ? stringsOf(context).profileUnnamedOrder : order.title!,
                    subtitle: order.participateDate ?? stringsOf(context).profileOrderDetails,
                    onTap: () => onOpen(order),
                  ),
                )
                .toList(),
          ),
  );
}

class _ProjectsPreview extends StatelessWidget {
  const _ProjectsPreview({
    required this.projects,
    required this.onRetry,
    required this.onOpen,
  });
  final AsyncValue<List<MyProject>> projects;
  final VoidCallback onRetry;
  final ValueChanged<MyProject> onOpen;

  @override
  Widget build(BuildContext context) => projects.when(
    loading: () => const CySkeleton(type: CySkeletonType.card, count: 1),
    error: (Object error, StackTrace stack) => StatusView(
      message: stringsOf(context).profileProjectsError,
      sub: stringsOf(context).profileProjectsErrorDetail,
      onRetry: onRetry,
    ),
    data: (List<MyProject> rows) => rows.isEmpty
        ? _CompactEmpty(title: stringsOf(context).profileProjectsEmpty, subtitle: stringsOf(context).profileProjectsEmptyDetail)
        : Column(
            children: rows
                .take(2)
                .map(
                  (MyProject project) => _PreviewRow(
                    title: project.title,
                    subtitle: project.stateText ?? stringsOf(context).profileProjectDetails,
                    onTap: () => onOpen(project),
                  ),
                )
                .toList(),
          ),
  );
}

class _AchievementsTab extends StatelessWidget {
  const _AchievementsTab({
    required this.growth,
    required this.onRetry,
    required this.onDestination,
  });

  final AsyncValue<GrowthCenter> growth;
  final VoidCallback onRetry;
  final ValueChanged<ProfileDestination> onDestination;

  @override
  Widget build(BuildContext context) => growth.when(
    // 真源 components/cy/profile 成长记录档:`type="list" count="2"`。
    loading: () => const CySkeleton(type: CySkeletonType.list, count: 2),
    error: (Object error, StackTrace stack) => StatusView(
      message: stringsOf(context).profileGrowthError,
      sub: stringsOf(context).profileGrowthErrorDetail,
      onRetry: onRetry,
    ),
    data: (GrowthCenter value) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _AchievementLink(
          actionKey: const ValueKey<String>('profile-points'),
          title: stringsOf(context).profilePoints,
          subtitle: '${value.points}',
          onTap: () => onDestination(ProfileDestination.points),
        ),
        const SizedBox(height: CyTokens.space3),
        // ★ 积分商城是 **App 独有域**(小程序 `chengyinhub-xcx` 全仓没有商城页:
        //   app.json 无该页、全仓搜「商城/兑换/购物车」零命中;后端 /api/product/*、
        //   /api/cart/* 只有 App 在调),所以没有可 1:1 对齐的小程序位置。
        //   入口挂在**积分块**里 —— 它跟「城瘾积分」是同一件事的两面(攒/花),
        //   而小程序的城瘾积分卡也正在这里(components/cy/profile/index.wxml:257)。
        //   没有它时全仓只有购物车空态一处跳 /mall,商城是个够不着的孤岛。
        _AchievementLink(
          actionKey: const ValueKey<String>('profile-mall'),
          title: stringsOf(context).profileMall,
          subtitle: stringsOf(context).profileMallDetail,
          onTap: () => onDestination(ProfileDestination.mall),
        ),
        const SizedBox(height: CyTokens.space3),
        _AchievementLink(
          actionKey: const ValueKey<String>('profile-growth'),
          title: stringsOf(context).profileGrowth,
          subtitle: 'Lv.${value.levelNo} · ${value.expValue} EXP',
          onTap: () => onDestination(ProfileDestination.growth),
        ),
        const SizedBox(height: CyTokens.space3),
        _AchievementLink(
          actionKey: const ValueKey<String>('profile-badges'),
          title: stringsOf(context).profileBadges,
          subtitle: stringsOf(context).profileBadgesDetail,
          onTap: () => onDestination(ProfileDestination.badges),
        ),
        const SizedBox(height: CyTokens.space3),
        _AchievementLink(
          actionKey: const ValueKey<String>('profile-stamps'),
          title: stringsOf(context).profileStamps,
          subtitle: stringsOf(context).profileStampsDetail,
          onTap: () => onDestination(ProfileDestination.stamps),
        ),
        const SizedBox(height: CyTokens.space3),
        _AchievementLink(
          actionKey: const ValueKey<String>('profile-object-cards'),
          title: stringsOf(context).objectCardsTitle,
          subtitle: stringsOf(context).objectCardsProfileHint,
          onTap: () => onDestination(ProfileDestination.objectCards),
        ),
        const SizedBox(height: CyTokens.space5),
        Text(
          stringsOf(context).profileMedalCount(value.badges.length),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: CyTokens.space3),
        if (value.badges.isEmpty)
          _CompactEmpty(title: stringsOf(context).profileBadgesEmpty, subtitle: stringsOf(context).profileBadgesEmptyDetail)
        else
          for (final MedalBadge badge in value.badges)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: badge.iconUrl.isEmpty
                  ? const Icon(CupertinoIcons.star_fill)
                  : ClipOval(
                      child: CyNetImage(
                        badge.iconUrl,
                        width: CyTokens.btnH,
                        height: CyTokens.btnH,
                        fit: BoxFit.cover,
                      ),
                    ),
              title: Text(badge.badgeName),
              trailing: const Icon(CupertinoIcons.check_mark),
            ),
      ],
    ),
  );
}

class _AchievementLink extends StatelessWidget {
  const _AchievementLink({
    required this.actionKey,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Key actionKey;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    return CupertinoButton(
      key: actionKey,
      padding: const EdgeInsets.all(CyTokens.space4),
      color: palette.bgSurface,
      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      onPressed: onTap,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: TextStyle(color: palette.textPrimary)),
                const SizedBox(height: CyTokens.space1),
                Text(subtitle, style: TextStyle(color: palette.textSecondary)),
              ],
            ),
          ),
          Icon(CupertinoIcons.chevron_forward, color: palette.textSecondary),
        ],
      ),
    );
  }
}

class _CompactEmpty extends StatelessWidget {
  const _CompactEmpty({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space5),
      child: Column(
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CyTokens.space2),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.bgSurface,
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          border: Border.all(color: palette.cardBorder),
        ),
        child: CupertinoButton(
          padding: const EdgeInsets.all(CyTokens.space3),
          onPressed: onTap,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: CyTokens.space1),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: CyTokens.space4,
                color: palette.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssetCard extends StatelessWidget {
  const _AssetCard({required this.balance, required this.onTap});
  final double? balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.bgSurfaceSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: CupertinoButton(
        padding: const EdgeInsets.all(CyTokens.space4),
        onPressed: onTap,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    stringsOf(context).profileBalance,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: CyTokens.space2),
                  Text(
                    balance == null ? '—' : '¥${balance!.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: palette.textPrimary,
                      // T3:强调上限 bold(700)。
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              color: palette.textTertiary,
              size: CyTokens.space4 + CyTokens.space1 / 2,
            ),
          ],
        ),
      ),
    );
  }
}

/// 「经营团队」入口(真源 `components/cy/profile/index.wxml:207-216`)。
///
/// ★ 店主与**员工**共用这一行,判据只有 `access/me` 的 `active` ——
///   右侧那句「你是谁 · 能做什么」也由 access/me 现算,不拿全局 role 猜。
class _MerchantTeamEntry extends StatelessWidget {
  const _MerchantTeamEntry({required this.value, required this.onTap});

  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: CyTokens.space3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.bgSurface,
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          border: Border.all(color: palette.borderSubtle),
        ),
        child: CyCell(
          key: const ValueKey<String>('profile-merchant-team'),
          title: stringsOf(context).profileMerchantTeam,
          subtitle: stringsOf(context).profileMerchantTeamDetail,
          trailing: Text(
            value,
            style: CyType.caption1.copyWith(color: palette.textSecondary),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _PostsTab extends StatelessWidget {
  const _PostsTab({
    required this.posts,
    required this.onRetry,
    required this.onPost,
  });
  final AsyncValue<List<SquarePost>> posts;
  final VoidCallback onRetry;
  final ValueChanged<int> onPost;

  @override
  Widget build(BuildContext context) => posts.when(
    skipLoadingOnReload: false,
    skipLoadingOnRefresh: false,
    loading: () => const CySkeleton(type: CySkeletonType.card, count: 2),
    error: (Object error, StackTrace stack) => LocalizedErrorStatus(
      error: error,
      fallback: profileFailureSummary(error, stringsOf(context)) ?? stringsOf(context).profilePostsError,
      originalApiMessage: profileOriginalMessage(error),
      hint: stringsOf(context).profilePostsErrorDetail,
      onRetry: onRetry,
    ),
    data: (List<SquarePost> rows) => rows.isEmpty
        // 副标逐字对齐真源 `cy-profile`(index.wxml:223,isSelf 分支)。
        ? _CompactEmpty(title: stringsOf(context).profilePostsEmpty, subtitle: stringsOf(context).profilePostsEmptyDetail)
        : Column(
            children: rows
                .map(
                  (SquarePost post) =>
                      _PostCard(post: post, onTap: () => onPost(post.id)),
                )
                .toList(),
          ),
  );
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.onTap});
  final SquarePost post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: CyTokens.space3),
        padding: const EdgeInsets.all(CyTokens.space3),
        decoration: BoxDecoration(
          color: palette.bgSurface,
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          border: Border.all(color: palette.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if ((post.contents ?? '').isNotEmpty)
              Text(
                post.contents!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            if (post.pics.isNotEmpty) ...<Widget>[
              const SizedBox(height: CyTokens.space2),
              ClipRRect(
                borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                child: CyNetImage(
                  post.pics.first,
                  width: double.infinity,
                  height: CyTokens.space8 * 3 + CyTokens.space4,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            const SizedBox(height: CyTokens.space2),
            Text(
              stringsOf(context).profilePostCounts(post.likeNum, post.commentCount),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutTab extends StatelessWidget {
  const _AboutTab({
    required this.user,
    required this.role,
    required this.clubOwnedCount,
    required this.merchantInfo,
    required this.onDestination,
    required this.onRetryMerchant,
    this.roleInfo,
    this.onRetryRoleInfo,
  });

  final ProfileDetail user;
  final String role;
  final int clubOwnedCount;
  final AsyncValue<Map<String, dynamic>>? merchantInfo;
  final ValueChanged<ProfileDestination> onDestination;
  final VoidCallback? onRetryMerchant;
  final AsyncValue<RoleInfo>? roleInfo;
  final VoidCallback? onRetryRoleInfo;

  @override
  Widget build(BuildContext context) {
    final merchant = role == 'merchant';
    if (merchant) {
      return _MerchantAbout(info: merchantInfo, onRetry: onRetryMerchant);
    }
    final palette = CyPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CySectionTitle(stringsOf(context).profileIntroduction),
        const SizedBox(height: CyTokens.space3),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(CyTokens.space4),
          decoration: BoxDecoration(
            color: palette.bgSurfaceSubtle,
            borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            border: Border.all(color: palette.borderSubtle),
          ),
          child: Text(
            user.introduction.isEmpty ? stringsOf(context).profileIntroductionEmpty : user.introduction,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        // 当前权益(玩家/主理人 persona,本人页):数据源 /api/role/info。
        ..._benefitsChildren(context),
        ...<Widget>[
          const SizedBox(height: CyTokens.space5),
          CySectionTitle(stringsOf(context).profileMore),
          const SizedBox(height: CyTokens.space3),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisExtent: CyTokens.space8 * 3 * (MediaQuery.textScalerOf(context).scale(17) / 17).clamp(1, 3),
            children: <Widget>[
              _AboutEntry(
                icon: CupertinoIcons.group,
                label: role == 'club'
                    ? (clubOwnedCount > 0 ? stringsOf(context).profileClub : stringsOf(context).profileCreateClub)
                    : stringsOf(context).profileBecomeLeader,
                onTap: () => onDestination(
                  role == 'club'
                      ? ProfileDestination.club
                      : ProfileDestination.becomeLeader,
                ),
              ),
              _AboutEntry(
                icon: CupertinoIcons.money_yen_circle,
                label: stringsOf(context).profileEarnings,
                onTap: () => onDestination(ProfileDestination.assets),
              ),
              // 真源「我的」根场景挂有「我的参与」(utils/scene-registry.js
              // member-participation-history → subpackageMember/mycanyu)。
              _AboutEntry(
                icon: CupertinoIcons.square_list,
                label: stringsOf(context).profileParticipations,
                onTap: () => onDestination(ProfileDestination.participations),
              ),
              _AboutEntry(
                icon: CupertinoIcons.pencil,
                label: stringsOf(context).profileCreator,
                onTap: () => onDestination(ProfileDestination.creator),
              ),
              _AboutEntry(
                icon: CupertinoIcons.ticket,
                label: stringsOf(context).profileCoupons,
                onTap: () => onDestination(ProfileDestination.coupons),
              ),
              _AboutEntry(
                icon: CupertinoIcons.gift,
                label: stringsOf(context).profileInvites,
                onTap: () => onDestination(ProfileDestination.invites),
              ),
              _AboutEntry(
                icon: CupertinoIcons.exclamationmark_bubble,
                label: stringsOf(context).profileComplaints,
                onTap: () => onDestination(ProfileDestination.complaints),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// 「当前权益」三态:加载骨架 / 失败可重试 / 成功九项。缺席则整块不显示。
  List<Widget> _benefitsChildren(BuildContext context) {
    final AsyncValue<RoleInfo>? info = roleInfo;
    if (info == null) return const <Widget>[];
    final palette = CyPalette.of(context);
    return <Widget>[
      const SizedBox(height: CyTokens.space5),
      ...info.when(
        loading: () => <Widget>[
          const CySkeleton(type: CySkeletonType.card, count: 3),
        ],
        error: (Object error, StackTrace stack) => <Widget>[
          CupertinoButton(
            key: const Key('profile-benefits-retry'),
            padding: const EdgeInsets.symmetric(vertical: CyTokens.space3),
            onPressed: onRetryRoleInfo,
            child: Text(
              stringsOf(context).profileBenefitsError,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
          ),
        ],
        data: (RoleInfo role) => <Widget>[
          _BenefitsSection(
            role: role,
            onOpenEarnings: () => onDestination(ProfileDestination.assets),
          ),
        ],
      ),
    ];
  }
}

class _MerchantAbout extends StatelessWidget {
  const _MerchantAbout({required this.info, required this.onRetry});
  final AsyncValue<Map<String, dynamic>>? info;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final value = info;
    // 真源 components/cy/profile 商家 About 探测档:`type="list" count="2"`。
    if (value == null) {
      return const CySkeleton(type: CySkeletonType.list, count: 2);
    }
    return value.when(
      loading: () => const CySkeleton(type: CySkeletonType.list, count: 2),
      error: (Object error, StackTrace stack) =>
          StatusView(message: stringsOf(context).profileMerchantError, sub: stringsOf(context).profileMerchantErrorDetail, onRetry: onRetry),
      data: (Map<String, dynamic> merchant) {
        final description = (merchant['description'] ?? '').toString().trim();
        final businessStatus = (merchant['businessStatusText'] ?? '')
            .toString()
            .trim();
        final businessTime = (merchant['businessTime'] ?? '').toString().trim();
        final address = (merchant['address'] ?? '').toString().trim();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _AboutHeading(stringsOf(context).profileBrandStory),
            const SizedBox(height: CyTokens.space3),
            description.isEmpty
                ? _CompactEmpty(
                    title: stringsOf(context).profileBrandStoryEmpty,
                    subtitle: stringsOf(context).profileBrandStoryEmptyDetail,
                  )
                : _AboutSurface(text: description),
            if (businessStatus.isNotEmpty ||
                businessTime.isNotEmpty ||
                address.isNotEmpty) ...<Widget>[
              const SizedBox(height: CyTokens.space5),
              _AboutHeading(stringsOf(context).profileBusinessInformation),
              const SizedBox(height: CyTokens.space3),
              _MerchantInfoRows(
                businessStatus: businessStatus,
                businessTime: businessTime,
                address: address,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _AboutHeading extends StatelessWidget {
  const _AboutHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => CySectionTitle(text);
}

class _AboutSurface extends StatelessWidget {
  const _AboutSurface({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: palette.bgSurfaceSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _MerchantInfoRows extends StatelessWidget {
  const _MerchantInfoRows({
    required this.businessStatus,
    required this.businessTime,
    required this.address,
  });
  final String businessStatus;
  final String businessTime;
  final String address;

  @override
  Widget build(BuildContext context) {
    return _AboutSurface(
      text: <String>[
        if (businessStatus.isNotEmpty) stringsOf(context).profileBusinessStatus(businessStatus),
        if (businessTime.isNotEmpty) stringsOf(context).profileBusinessTime(businessTime),
        if (address.isNotEmpty) stringsOf(context).profileBusinessAddress(address),
      ].join('\n'),
    );
  }
}

class _AboutEntry extends StatelessWidget {
  const _AboutEntry({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    return CupertinoButton(
      padding: const EdgeInsets.all(CyTokens.space2),
      onPressed: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, color: palette.textPrimary, size: CyTokens.space5),
          const SizedBox(height: CyTokens.space1),
          Text(
            label,
            maxLines: 3,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}
