import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/club.dart';
import '../../data/models/club_post.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';
import '../profile/profile_controller.dart';
import 'club_controller.dart';
import 'club_login_gate.dart';
import 'club_feed_page.dart';

enum ClubRootTab { posts, clubs }

enum ClubDestination { create, merchantCoop, club, manage, join }

/// 俱乐部根页。公开 widget seam 让角色态、空态与目的地可以独立验证。
class ClubRootView extends StatefulWidget {
  const ClubRootView({
    super.key,
    required this.home,
    required this.feed,
    required this.isMerchantViewer,
    this.joiningClubId,
    this.imUnread = 0,
    required this.onDestination,
    required this.onOpenMessages,
    required this.onRetryHome,
    required this.onRetryFeed,
  });

  final AsyncValue<ClubHome> home;
  final AsyncValue<ClubFeed> feed;
  final bool isMerchantViewer;
  final int? joiningClubId;

  /// 站内消息未读数(`POST /api/im/unread-total`)。0/失败不显角标,
  /// >99 显 99+ —— 与源 pages/talent/list/index.wxml:14 同口径。
  final int imUnread;

  final void Function(ClubDestination destination, int? id) onDestination;

  /// 右上「消息」铃铛。★ 根页不许自己 push('/im'):`/im` 在整页需登录表里,
  /// 游客 push 会撞 redirect 兜底把 shell 根再压一层 —— #379 真点 P1
  /// 「tab 选中态与内容永久脱钩」就是这么来的。闸(requireLogin)接在页面侧。
  final VoidCallback onOpenMessages;
  final VoidCallback onRetryHome;
  final VoidCallback onRetryFeed;

  @override
  State<ClubRootView> createState() => _ClubRootViewState();
}

class _ClubRootViewState extends State<ClubRootView> {
  ClubRootTab _tab = ClubRootTab.clubs;

  @override
  Widget build(BuildContext context) {
    if (widget.isMerchantViewer) {
      final ThemeData light = AppTheme.merchantLight();
      return Theme(
        data: light,
        // ★ 只包 Material `Theme` 不够:`ThemeData.cupertinoOverrideTheme` 在
        //   `CupertinoApp` 下不生效(根已有 CupertinoTheme 时,`Theme.build`
        //   把**祖先那份**转发布),Cupertino 侧会留在根暗色 —— 本页
        //   `CupertinoButton` 前景取的正是 `CupertinoTheme.primaryColor`。
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
    void openMessages() => widget.onOpenMessages();
    return Scaffold(
      backgroundColor: palette.bgPage,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CyTokens.pageX,
                CyTokens.space2,
                CyTokens.pageX,
                0,
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: Semantics(
                  container: true,
                  excludeSemantics: true,
                  label: widget.imUnread > 0
                      ? '站内消息,${widget.imUnread > 99 ? '99+' : widget.imUnread} 条未读'
                      : '站内消息',
                  button: true,
                  onTap: openMessages,
                  child: CupertinoButton(
                    padding: const EdgeInsets.all(CyTokens.space2),
                    minimumSize: const Size.square(CyTokens.btnH),
                    onPressed: openMessages,
                    child: ExcludeSemantics(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          Icon(
                            CupertinoIcons.chat_bubble,
                            color: palette.textPrimary,
                          ),
                          if (widget.imUnread > 0)
                            Positioned(
                              top: -2,
                              right: -6,
                              child: CyBadge(
                                key: const Key('club-im-unread'),
                                count: widget.imUnread,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _ClubTabs(
              value: _tab,
              onChanged: (ClubRootTab tab) => setState(() => _tab = tab),
            ),
            Expanded(
              child: _tab == ClubRootTab.posts
                  ? _PostTab(
                      feed: widget.feed,
                      onRetry: widget.onRetryFeed,
                      onOpenClub: (int id) =>
                          widget.onDestination(ClubDestination.club, id),
                    )
                  : _ClubsTab(
                      home: widget.home,
                      merchant: widget.isMerchantViewer,
                      joiningClubId: widget.joiningClubId,
                      onDestination: widget.onDestination,
                      onRetry: widget.onRetryHome,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 根路由只负责 provider 与目的地接线；视觉与状态逻辑在 [ClubRootView]。
class ClubListPage extends ConsumerStatefulWidget {
  const ClubListPage({super.key});

  @override
  ConsumerState<ClubListPage> createState() => _ClubListPageState();
}

class _ClubListPageState extends ConsumerState<ClubListPage> {
  int? _joiningClubId;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    return ClubRootView(
      home: ref.watch(clubHomeProvider),
      feed: ref.watch(clubFeedProvider),
      isMerchantViewer: user?.isMerchantView == true,
      joiningClubId: _joiningClubId,
      imUnread: ref.watch(unreadTotalProvider).value ?? 0,
      onOpenMessages: () async {
        if (!await requireLogin(context, ref) || !context.mounted) return;
        context.push('/im');
      },
      onRetryHome: () => ref.invalidate(clubHomeProvider),
      onRetryFeed: () => ref.invalidate(clubFeedProvider),
      onDestination: (ClubDestination destination, int? id) async {
        switch (destination) {
          case ClubDestination.create:
            if (!await requireLogin(context, ref) || !context.mounted) return;
            final currentUser = ref.read(authControllerProvider).user;
            final route = currentUser?.effectiveRole == 'club'
                ? '/club/create'
                : '/club/apply';
            context.push(route);
          case ClubDestination.merchantCoop:
            if (!await requireLogin(context, ref) || !context.mounted) return;
            context.push('/merchant/coop');
          case ClubDestination.club:
            if (id != null) context.push('/club/$id');
          case ClubDestination.manage:
            if (id != null) context.push('/club/workbench?id=$id');
          case ClubDestination.join:
            if (id == null || _joiningClubId == id) return;
            if (!await requireLogin(context, ref) || !context.mounted) return;
            setState(() => _joiningClubId = id);
            try {
              await ref.read(clubApiProvider).join(id);
              ref.invalidate(clubHomeProvider);
            } catch (error) {
              if (!context.mounted) return;
              CyNativeNotice.show(
                context,
                error.toString().replaceFirst('Exception: ', ''),
                isError: true,
              );
            } finally {
              if (mounted) setState(() => _joiningClubId = null);
            }
        }
      },
    );
  }
}

class _ClubTabs extends StatelessWidget {
  const _ClubTabs({required this.value, required this.onChanged});
  final ClubRootTab value;
  final ValueChanged<ClubRootTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    Widget item(ClubRootTab tab, String label) {
      final selected = value == tab;
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
              minimumSize: const Size.square(CyTokens.btnH),
              onPressed: () => onChanged(tab),
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: selected ? palette.textPrimary : palette.textDisabled,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
            Container(
              height: CyTokens.space1 / 2,
              color: selected ? palette.textPrimary : palette.borderSubtle,
            ),
          ],
        ),
      );
    }

    return Row(
      children: <Widget>[
        item(ClubRootTab.posts, '帖文'),
        item(ClubRootTab.clubs, '俱乐部'),
      ],
    );
  }
}

class _PostTab extends StatelessWidget {
  const _PostTab({
    required this.feed,
    required this.onRetry,
    required this.onOpenClub,
  });
  final AsyncValue<ClubFeed> feed;
  final VoidCallback onRetry;
  final ValueChanged<int> onOpenClub;

  @override
  Widget build(BuildContext context) {
    return feed.when(
      loading: () => const CySkeleton(),
      // 游客态整页 401(实测生产):说成「检查网络后重试」是误导 —— 重试按
      // 多少次都还是 401。走登录门,登录完就地把 feed 重取一次。
      error: (Object error, StackTrace stack) => clubLoginRequired(error)
          ? ClubLoginGate(message: '登录后查看帖文', onSignedIn: onRetry)
          : StatusView(
              message: '动态加载失败',
              sub: '检查网络后重试',
              icon: CupertinoIcons.cloud,
              onRetry: onRetry,
            ),
      data: (ClubFeed value) {
        if (value.rows.isEmpty) {
          return StatusView(
            message: value.hasNoClub ? '这里还没有帖文' : '还没有帖文',
            sub: value.hasNoClub
                ? '帖文来自你加入的俱乐部，加入或创建一个俱乐部后即可看到'
                : '你加入的俱乐部还没有人发布帖文，去俱乐部主页发第一条',
            icon: CupertinoIcons.news,
            large: true,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(CyTokens.pageX),
          itemCount: value.rows.length,
          itemBuilder: (_, int index) {
            final ClubPost post = value.rows[index];
            return ClubPostTile(
              post: post,
              viewerIsClubAdmin: post.viewerCanManage,
              onOpenClub: post.clubId == null || post.clubId! <= 0
                  ? null
                  : () => onOpenClub(post.clubId!),
            );
          },
        );
      },
    );
  }
}

class _ClubsTab extends StatelessWidget {
  const _ClubsTab({
    required this.home,
    required this.merchant,
    required this.joiningClubId,
    required this.onDestination,
    required this.onRetry,
  });

  final AsyncValue<ClubHome> home;
  final bool merchant;
  final int? joiningClubId;
  final void Function(ClubDestination destination, int? id) onDestination;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return home.when(
      loading: () => const CySkeleton(),
      error: (Object error, StackTrace stack) => clubLoginRequired(error)
          ? ClubLoginGate(message: '登录后查看俱乐部', onSignedIn: onRetry)
          : StatusView(
              message: '没能加载俱乐部',
              sub: '检查网络后重试',
              icon: CupertinoIcons.cloud,
              onRetry: onRetry,
            ),
      data: (ClubHome value) => ListView(
        padding: EdgeInsets.fromLTRB(
          CyTokens.pageX,
          CyTokens.space4,
          CyTokens.pageX,
          CyTokens.space8 + MediaQuery.paddingOf(context).bottom,
        ),
        children: <Widget>[
          _CreateEntry(
            merchant: merchant,
            onTap: () => onDestination(
              merchant ? ClubDestination.merchantCoop : ClubDestination.create,
              null,
            ),
          ),
          if (!merchant) ...<Widget>[
            const SizedBox(height: CyTokens.space5),
            const _SectionHeading(title: '我的', subtitle: '我创建或加入的俱乐部'),
            if (value.owned.isEmpty && value.joined.isEmpty)
              const _EmptyState(
                title: '还没有加入俱乐部',
                subtitle: '创建自己的俱乐部，或从附近找到同好',
              )
            else
              ...<Club>[...value.owned, ...value.joined].map(
                (Club club) => _ClubCard(
                  club: club,
                  busy: joiningClubId == club.id,
                  onTap: () => onDestination(ClubDestination.club, club.id),
                  onAction: () => onDestination(
                    club.isOwner
                        ? ClubDestination.manage
                        : ClubDestination.club,
                    club.id,
                  ),
                ),
              ),
          ],
          const SizedBox(height: CyTokens.space6),
          const _SectionHeading(title: '附近', subtitle: '发现本城正在组织探索的同好'),
          if (value.nearby.isEmpty)
            _EmptyState(
              title: '附近还没有其他俱乐部',
              subtitle: merchant
                  ? '本城暂无正在组织探索的同好'
                  : '本城暂无正在组织探索的同好，创建你自己的俱乐部，成为第一个',
              actionLabel: merchant ? null : '创建俱乐部',
              onAction: merchant
                  ? null
                  : () => onDestination(ClubDestination.create, null),
            )
          else
            ...value.nearby.map(
              (Club club) => _ClubCard(
                club: club,
                busy: joiningClubId == club.id,
                onTap: () => onDestination(ClubDestination.club, club.id),
                onAction: () => onDestination(
                  club.isJoined ? ClubDestination.club : ClubDestination.join,
                  club.id,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CreateEntry extends StatelessWidget {
  const _CreateEntry({required this.merchant, required this.onTap});
  final bool merchant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            merchant ? '俱乐部邀约情况 · 接受 / 拒绝合作' : '创建你自己的俱乐部',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: CyTokens.space2),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(
            horizontal: CyTokens.space3,
            vertical: CyTokens.space2,
          ),
          minimumSize: const Size(CyTokens.btnH, CyTokens.btnH),
          borderRadius: BorderRadius.circular(CyTokens.radiusLg),
          color: palette.actionSecondaryBg,
          onPressed: onTap,
          child: Text(
            merchant ? '查看' : '创建俱乐部',
            style: TextStyle(color: palette.textPrimary),
          ),
        ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space5),
      child: Column(
        children: <Widget>[
          Text(
            title,
            textAlign: TextAlign.center,
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
          if (actionLabel != null && onAction != null) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            CupertinoButton(
              color: palette.actionPrimaryBg,
              borderRadius: BorderRadius.circular(CyTokens.radiusPill),
              // 外层 if 已经断言过非空，和下面的 actionLabel! 一个口径。
              onPressed: onAction!,
              child: Text(
                actionLabel!,
                style: TextStyle(color: palette.actionPrimaryFg),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ClubCard extends StatelessWidget {
  const _ClubCard({
    required this.club,
    required this.onTap,
    required this.onAction,
    this.busy = false,
  });
  final Club club;
  final VoidCallback onTap;
  final VoidCallback onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    final subtitle = <String>[
      if ((club.clubType ?? '').isNotEmpty) club.clubType!,
      if ((club.city ?? club.address ?? '').isNotEmpty)
        (club.city ?? club.address)!,
    ].join(' · ');
    final button = club.isOwner
        ? '管理'
        : club.isJoined
        ? '进入'
        : club.needsApproval
        ? '申请加入'
        : '加入';
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.bgSurface,
          borderRadius: BorderRadius.circular(CyTokens.radiusLg),
          border: Border.all(color: palette.cardBorder),
          boxShadow: palette.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(CyTokens.radiusLg),
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  height: CyTokens.space8 * 2 + CyTokens.space5,
                  width: double.infinity,
                  child: (club.cover ?? '').isEmpty
                      ? ColoredBox(
                          color: palette.bgSurfaceSubtle,
                          child: Icon(
                            CupertinoIcons.group_solid,
                            color: palette.textTertiary,
                            size: CyTokens.space7,
                          ),
                        )
                      : CyNetImage(club.cover!, fit: BoxFit.cover),
                ),
                Padding(
                  padding: const EdgeInsets.all(CyTokens.space3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              club.name.isEmpty ? '未命名俱乐部' : club.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: palette.textPrimary),
                            ),
                          ),
                          if (club.level > 0)
                            Text(
                              'Lv.${club.level}',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: palette.textSecondary),
                            ),
                        ],
                      ),
                      if (subtitle.isNotEmpty) ...<Widget>[
                        const SizedBox(height: CyTokens.space1),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.textSecondary),
                        ),
                      ],
                      const SizedBox(height: CyTokens.space1),
                      Text(
                        '${club.memberCount} 位成员',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.textTertiary,
                        ),
                      ),
                      const SizedBox(height: CyTokens.space2),
                      Align(
                        alignment: Alignment.centerRight,
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: CyTokens.space3,
                            vertical: CyTokens.space2,
                          ),
                          minimumSize: const Size(CyTokens.btnH, CyTokens.btnH),
                          color: club.isOwner || club.isJoined
                              ? palette.actionSecondaryBg
                              : palette.actionPrimaryBg,
                          onPressed: busy ? null : onAction,
                          child: busy
                              ? CupertinoActivityIndicator(
                                  color: palette.textPlaceholder,
                                )
                              : Text(
                                  button,
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        color: club.isOwner || club.isJoined
                                            ? palette.textPrimary
                                            : palette.actionPrimaryFg,
                                      ),
                                ),
                        ),
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
