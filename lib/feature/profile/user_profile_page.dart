import '../../l10n/im_api_display.dart';
import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/feature_flags.dart';
import '../../core/providers.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/category.dart';
import '../../data/models/profile_detail.dart';
import '../../data/models/square_post.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';
import '../merchant/merchant_public_home_page.dart';
import '../square/square_post_reactions.dart';
import '../../core/role_provider.dart';
import '../../core/widgets/cy_native_notice.dart';

/// 他人主页的资料。
///
/// ★ 走 **`/api/user/public-info`(匿名可访问)** 而不是 `/api/user/info` ——
///   后者要求先登录,**游客点别人主页会撞「请先登录」**,
///   而他人主页本来就该是能逛的(小程序侧同样用公开接口做匿名冷启动)。
final otherProfileProvider = FutureProvider.autoDispose
    .family<ProfileDetail, int>((ref, int memberId) {
      return ref.watch(registrationApiProvider).publicUserInfo(memberId);
    });

/// TA 的推文。**游客态不发请求**。
///
/// ★ `/api/v1/community/feeds/latest` 要登录态(生产实测:游客 401
///   「登录状态已失效」)。头部资料走的 `/api/user/public-info` 匿名可读,
///   所以这页对游客是开放的 —— 但这条流不是。硬发一次 401 的代价不只是白跑一趟,
///   还会踩 dio_client 的 401 全局路径(清 token + 通知上层登出)。
final otherPostsProvider = FutureProvider.autoDispose
    .family<List<SquarePost>, int>((ref, int memberId) {
      if (!ref.watch(authControllerProvider).isLoggedIn) {
        return Future<List<SquarePost>>.value(const <SquarePost>[]);
      }
      return ref.watch(squareApiProvider).list(isMy: 0, userId: memberId);
    });

enum _PublicProfileTab { posts, achievements, about }

/// 他人主页。对齐小程序 `pages/userinfo`(cy-profile viewer=other)。
///
/// ★ App 此前完全没有 —— 广场帖子、俱乐部成员都点不进作者主页。
class UserProfilePage extends ConsumerStatefulWidget {
  const UserProfilePage({super.key, required this.memberId});

  final int memberId;

  @override
  ConsumerState<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends ConsumerState<UserProfilePage> {
  bool _busy = false;
  bool _following = false;
  _PublicProfileTab _tab = _PublicProfileTab.posts;

  /// 推文点赞的本地预期(即时反馈 + 失败回滚)与串行队列 ——
  /// 与广场列表/详情同一套,不另造一份。
  final SquarePostReactions _reactions = SquarePostReactions();
  final SquareLikeQueue _likeQueue = SquareLikeQueue();

  /// 关注 / 取关。
  ///
  /// ★★ 后端只有一个**切换**接口,而且结果只能从 msg 文案区分
  ///   (见 registrationApi.toggleFollow 的注释:文案两种都不匹配时它会抛,
  ///    而不是猜一个)。所以这里**不做本地乐观翻转** ——
  ///   翻错了按钮会显示成反的,用户再点一次就真的反了。
  ///   调完直接 invalidate,让服务端说了算。
  Future<void> _toggleFollow(ProfileDetail p) async {
    // 关系未知 = 没登录。先登录,再让 provider 重新拉一次带关系的资料。
    if (p.isFollow == null) {
      if (!await requireLogin(context, ref)) return;
      ref.invalidate(otherProfileProvider(widget.memberId));
      return;
    }
    setState(() => _following = true);
    try {
      await ref.read(registrationApiProvider).toggleFollow(widget.memberId);
      ref.invalidate(otherProfileProvider(widget.memberId));
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _following = false);
    }
  }

  /// 三态文案。null ≠ 未关注 —— 见 ProfileDetail.isFollow 的注释。
  String _followLabel(ProfileDetail p) => switch (p.isFollow) {
    true => stringsOf(context).profileDetailsFollowing,
    false => stringsOf(context).profileDetailsFollow,
    null => stringsOf(context).profileDetailsLoginFollow,
  };

  /// 给 TA 的推文点赞。
  ///
  /// ★ 小程序这一格打的是旧路由 `/api/creativesquare/like`(userinfo 页在
  ///   接口对账里唯一的一条缺口)。App 侧同一个动作走
  ///   `/api/v1/community/posts/{id}/actions/LIKE` —— 与广场列表/详情同一套,
  ///   旧路由是路由换代不是漏接(交接文档 §5.4)。
  Future<void> _toggleLike(SquarePost post) async {
    if (!await requireLogin(context, ref)) return;
    if (!mounted) return;
    final bool enabled = !_reactions.display(post).liked;
    setState(() => _reactions.applyLike(post, liked: enabled));
    try {
      await _likeQueue.submit(
        post.id,
        want: enabled,
        send: (bool want) => ref
            .read(squareApiProvider)
            .setAction(post.id, 'LIKE', enabled: want),
      );
    } catch (error) {
      if (!mounted) return;
      // 失败 → 回滚到服务端态,不留一个下次刷新才被打回原形的假已赞。
      setState(() => _reactions.rollback(post.id));
      CyNativeNotice.show(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<void> _startChat() async {
    // 游客点「发消息」先弹登录引导 —— 直打 IM 接口只会拿到一句 401 原文
    // (b1 报告 P1-1:这几处 IM 入口都没接登录门)。
    if (!await requireLogin(context, ref) || !mounted) return;
    setState(() => _busy = true);
    try {
      final cid = await ref.read(imApiProvider).startChat(widget.memberId);
      if (!mounted) return;
      final me = ref.read(otherProfileProvider(widget.memberId)).asData?.value;
      context.push(
        '/im/chat/$cid',
        extra: <String, String>{
          'name': me?.nickname ?? '',
          'avatar': me?.avatar ?? '',
          // 拉黑要 memberId —— 从这里进聊天也要带上,否则聊天页拿不到。
          'memberId': widget.memberId.toString(),
        },
      );
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        imErrorText(e, stringsOf(context)),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 访客向商家主页发起合作。对齐小程序 cy-profile `onCoopInvite`
  /// (coop/invite type=0,达人→商家,与 club/detail 同链路)。
  /// toId 用的是** memberId** —— 商家主页语境下 userId 就是被看者 memberId。
  Future<void> _openCoopInvite(Map<String, dynamic> merchant) async {
    if (!await requireLogin(context, ref)) return;
    if (!mounted) return;
    final q = <String>['type=0', 'toId=${widget.memberId}'];
    final name = (merchant['name'] as String?)?.trim() ?? '';
    if (name.isNotEmpty) q.add('toName=${Uri.encodeComponent(name)}');
    final logo = (merchant['logo'] as String?)?.trim() ?? '';
    if (logo.isNotEmpty) q.add('toLogo=${Uri.encodeComponent(logo)}');
    // 真源 toMeta 取值优先级:suitActivityTypes > address > cityRole。
    final meta =
        <String?>[
              merchant['suitActivityTypes'] as String?,
              merchant['address'] as String?,
              merchant['cityRole'] as String?,
            ]
            .map((String? s) => s?.trim())
            .firstWhere(
              (String? s) => s != null && s.isNotEmpty,
              orElse: () => null,
            ) ??
        '';
    if (meta.isNotEmpty) q.add('toMeta=${Uri.encodeComponent(meta)}');
    context.push('/coop/invite?${q.join('&')}');
  }

  @override
  Widget build(BuildContext context) {
    // 小程序 pages/userinfo/userinfo.wxml:链接里没有 userId 时整页换成
    // cy-empty(kind=missing-param)+「回到我的主页」,**不打任何接口**。
    // App 这边路由参数解析失败会落成 0 —— 之前拿 0 去问后端,只能拿到一个
    // 看不懂的错误态;而这本来就不是"查不到",是"链接不完整"。
    if (widget.memberId <= 0) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).profileDetailsPublicTitle)),
        child: Material(
          color: Colors.transparent,
          child: StatusView(
            message: stringsOf(context).profileDetailsIncompleteLink,
            sub: stringsOf(context).profileDetailsIncompleteLinkHint,
            large: true,
            onRetry: () => context.go(kProfileRoute),
            retryLabel: stringsOf(context).profileDetailsMyProfile,
          ),
        ),
      );
    }

    final async = ref.watch(otherProfileProvider(widget.memberId));
    final posts = ref.watch(otherPostsProvider(widget.memberId));
    final textTheme = Theme.of(context).textTheme;
    // 被看者是不是商家 —— 唯一真源:public-home 按 memberId 查得到一条可公开记录。
    // 查不到(未开放/网络)不当成"是商家",按钮不出现 —— 与真源 probeSubjectMerchant
    // 的三态分开一致:没查到 ≠ 他不是商家,但也不能拿没查到冒充他能对接。
    final subjectMerchant = ref
        .watch(merchantPublicHomeProvider(widget.memberId))
        .asData
        ?.value;
    // 真源底栏条件:isMerchantView && !isSelf && (!viewerIsMerchant || topicId)。
    // 这页恒 !isSelf 且无 topicId ⇒ 仅当"被看者是商家 且 观看者不是商家"才给入口
    // (达人→商家)。观看者角色没取到(未登录)按"不是商家"处理,游客也能发起(点了走登录)。
    final viewerIsMerchant =
        ref.watch(roleInfoProvider).asData?.value.hasMerchantFace ?? false;
    final Map<String, dynamic>? coopMerchant =
        subjectMerchant != null && !viewerIsMerchant ? subjectMerchant : null;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).profileDetailsPageTitle)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: async.when(
            loading: () => const Center(child: CupertinoActivityIndicator()),
            error: (Object e, _) => StatusView(
              message: stringsOf(context).profileDetailsPublicUnavailable,
              sub: e.toString().replaceFirst('Exception: ', ''),
              large: true,
              onRetry: () =>
                  ref.invalidate(otherProfileProvider(widget.memberId)),
            ),
            data: (ProfileDetail p) => ListView(
              padding: const EdgeInsets.all(CyTokens.pageX),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    CyAvatar(
                      url: p.avatar.isEmpty ? null : p.avatar,
                      fallback: p.nickname.isEmpty
                          ? null
                          : p.nickname.characters.first,
                      size: 64,
                    ),
                    const SizedBox(width: CyTokens.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            p.nickname.trim().isEmpty ? stringsOf(context).profileDetailsDefaultName : p.nickname,
                            style: textTheme.titleLarge,
                          ),
                          // 简介为空时整行不渲染,不留一段空白。
                          if (p.introduction.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: CyTokens.space1,
                              ),
                              child: Text(
                                p.introduction.trim(),
                                style: textTheme.bodySmall?.copyWith(
                                  color: CyTokens.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CyTokens.space4),
                Row(
                  children: <Widget>[
                    // 三格 = 好友 / 关注 / 粉丝(小程序 cy-profile index.wxml:76-82);
                    // 获赞/发布内容归下面那组公开统计,不在这里出现第二次。
                    _stat(context, stringsOf(context).profileDetailsFriends, p.friendNum),
                    _stat(context, stringsOf(context).profileDetailsFollow, p.followNum),
                    _stat(context, stringsOf(context).profileDetailsFollowers, p.fansNum),
                  ],
                ),
                const SizedBox(height: CyTokens.space4),
                CyNativeButton(
                  width: double.infinity,
                  role: CyNativeButtonRole.secondary,
                  label: _followLabel(p),
                  key: const Key('profile-follow-btn'),
                  onPressed: _following ? null : () => _toggleFollow(p),
                ),
                const SizedBox(height: CyTokens.space2),
                CyNativeButton(
                  width: double.infinity,
                  // 真源 components/cy/profile/index.wxml:119 写的就是「发消息」。
                  label: _busy ? stringsOf(context).profileDetailsOpening : stringsOf(context).profileDetailsMessage,
                  onPressed: _busy ? null : _startChat,
                  loading: _busy,
                  icon: const CyNativeButtonIcon(
                    sfSymbol: 'message',
                    fallback: CupertinoIcons.chat_bubble,
                  ),
                ),
                // 访客看商家主页的「发起合作」(真源 pc-coop-bar)。iOS 原生化:
                // 收进操作按钮组而非固定底栏 —— 结构/参数 1:1,观感走系统按钮。
                if (coopMerchant != null) ...<Widget>[
                  const SizedBox(height: CyTokens.space2),
                  CyNativeButton(
                    width: double.infinity,
                    role: CyNativeButtonRole.primary,
                    label: stringsOf(context).profileDetailsCooperate,
                    key: const Key('profile-coop-btn'),
                    onPressed: () => _openCoopInvite(coopMerchant),
                  ),
                ],
                const SizedBox(height: CyTokens.space4),
                _tabs(),
                const SizedBox(height: CyTokens.space4),
                switch (_tab) {
                  _PublicProfileTab.posts => _posts(posts),
                  _PublicProfileTab.achievements => _achievements(p),
                  _PublicProfileTab.about => _about(p),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabs() {
    Widget item(_PublicProfileTab value, String label) {
      final bool selected = _tab == value;
      return Expanded(
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
          onPressed: () => setState(() => _tab = value),
          child: Column(
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? CyTokens.textPrimary
                      : CyTokens.textTertiary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: CyTokens.space1),
              Container(
                height: 2,
                color: selected ? CyTokens.textPrimary : Colors.transparent,
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: <Widget>[
        item(_PublicProfileTab.posts, stringsOf(context).profileDetailsPosts),
        item(_PublicProfileTab.achievements, stringsOf(context).profileDetailsAchievements),
        item(_PublicProfileTab.about, stringsOf(context).profileDetailsAbout),
      ],
    );
  }

  Widget _posts(AsyncValue<List<SquarePost>> posts) {
    // 游客:这条流要登录态。通用错误态(「已发布的动态都还在,只是这次没取到」
    // +「重试」)在这里是**误导** —— 重试按多少次都还是 401,是条死路;
    // 而且该页不在登录守卫前缀里,是**有意**让游客进来的,得给个出口。
    // 口径与活动详情页的 401 处理一致(activity_detail_page 同款)。
    if (!ref.watch(authControllerProvider).isLoggedIn) {
      return StatusView(
        key: const Key('profile-posts-login-gate'),
        message: stringsOf(context).profileDetailsLoginPosts,
        sub: stringsOf(context).profileDetailsLoginPostsHint,
        icon: CupertinoIcons.lock,
        retryLabel: stringsOf(context).profileDetailsSignIn,
        onRetry: () async {
          if (!await requireLogin(context, ref)) return;
          if (!mounted) return;
          ref.invalidate(otherPostsProvider(widget.memberId));
        },
      );
    }
    return posts.when(
      // 动态流与广场同源,真源是 post-card 鱼骨(头像+长短三线+媒体),不是 card 封面。
      loading: () => const CySkeleton(type: CySkeletonType.postCard, count: 2),
      error: (Object error, StackTrace stack) => StatusView(
        message: stringsOf(context).profileDetailsPostsFailed,
        sub: stringsOf(context).profileDetailsPostsFailedHint,
        onRetry: () => ref.invalidate(otherPostsProvider(widget.memberId)),
      ),
      data: (List<SquarePost> rows) {
        if (rows.isEmpty) {
          // 小程序 cy-empty:主标「还没有推文」,副标「TA 还没有发布推文」。
          return StatusView(message: stringsOf(context).profileDetailsPostsEmpty, sub: stringsOf(context).profileDetailsPostsEmptyHint);
        }
        return Column(
          children: <Widget>[for (final SquarePost row in rows) _postRow(row)],
        );
      },
    );
  }

  /// 单条推文:点正文进详情,右侧点赞 —— 对应小程序 `pc-post-tools` 的点赞位。
  ///
  /// 那一排还有「踩」与「分享」:分享 App 侧无解(appid 与落地页都缺,见
  /// `tool/copy_parity.py` 的系统性差异);「踩」在社区 v1 的动作类型里没有
  /// 可核证据 —— 不猜一个动作名(交接文档 §5.4 只核到 LIKE)。
  Widget _postRow(SquarePost raw) {
    final SquarePost post = _reactions.display(raw);
    final bool communityOpen = ref.watch(
      featureFlagProvider('communityPostRead'),
    );
    // 行用 CupertinoListTile —— 推文行是内容层列表,iOS 27 原生化不留 Material ListTile。
    return CupertinoListTile(
      padding: EdgeInsets.zero,
      title: Text(
        (post.contents ?? '').isEmpty ? stringsOf(context).profileDetailsPhotoPost : post.contents!,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _LikeAction(
        key: Key('profile-post-like-${post.id}'),
        liked: post.liked,
        count: post.likeNum,
        onPressed: () => _toggleLike(post),
      ),
      onTap: () {
        if (!communityOpen) {
          CyNativeNotice.show(context, stringsOf(context).profileDetailsRollout);
          return;
        }
        context.push('/square/${post.id}');
      },
    );
  }

  Widget _achievements(ProfileDetail profile) => Row(
    children: <Widget>[
      _publicStat(stringsOf(context).profileDetailsPublished, profile.topicNum + profile.activityNum),
      _publicStat(stringsOf(context).profileDetailsLikes, profile.likeNum),
      _publicStat(stringsOf(context).profileDetailsFollowers, profile.fansNum),
    ],
  );

  Widget _publicStat(String label, int value) => Expanded(
    child: Column(
      children: <Widget>[
        Text('$value', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: CyTokens.space1),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );

  Widget _about(ProfileDetail profile) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      // 区块标题走共用层(L2/T2):同域「我的」页同一块标题用的也是它,
      // 自带 Semantics header,字号字重跟 iOS 阶梯。
      CySectionTitle(stringsOf(context).profileDetailsIntroduction),
      const SizedBox(height: CyTokens.space2),
      Text(
        profile.introduction.trim().isEmpty
            ? stringsOf(context).profileDetailsIntroductionEmpty
            : profile.introduction.trim(),
      ),
      // 小程序关于页(= 他人视角全部内容):个人介绍 → 兴趣标签 → 探索作品。
      // 两个列表的字段后端一直在下发(`sysCategoryList` / `casePics`),
      // 模型也一直在解析 —— 只是没人渲染。
      const SizedBox(height: CyTokens.space5),
      // 同「个人介绍」:区块标题统一走共用层(Title3 Semibold + Semantics header),
      // 不再 titleLarge 手搓。
      CySectionTitle(stringsOf(context).profileDetailsInterests),
      const SizedBox(height: CyTokens.space2),
      if (profile.routePreferences.isEmpty)
        Text(
          stringsOf(context).profileDetailsInterestsEmpty,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: CyTokens.textTertiary),
        )
      else
        Wrap(
          spacing: CyTokens.space1_5,
          runSpacing: CyTokens.space1_5,
          children: <Widget>[
            for (final Category category in profile.routePreferences)
              CyTag(label: category.name),
          ],
        ),
      if (profile.casePics.isNotEmpty) ...<Widget>[
        const SizedBox(height: CyTokens.space5),
        CySectionTitle(stringsOf(context).profileDetailsWork),
        const SizedBox(height: CyTokens.space2),
        Wrap(
          spacing: CyTokens.space2,
          runSpacing: CyTokens.space2,
          children: <Widget>[
            // 150rpx = 75pt、radius-sm:照 `{}.pc-work-pic` 取。
            for (final String pic in profile.casePics)
              CyNetImage(
                pic,
                width: 75,
                height: 75,
                borderRadius: BorderRadius.circular(CyTokens.radiusSm),
              ),
          ],
        ),
      ],
    ],
  );

  /// value = null 时写「—」:后端没有 friendNum 契约时**不能造 0**。
  Widget _stat(BuildContext context, String label, int? value) {
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: <Widget>[
          Text('${value ?? '—'}', style: textTheme.titleMedium),
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(color: CyTokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 推文行右侧的点赞键。
///
/// ★ 数字**恒显**(小程序 `{{item.likeCount || 0}}`,0 也照渲)——
///   和广场那边的评论数同一口径,不要改成"有赞才显示"。
class _LikeAction extends StatelessWidget {
  const _LikeAction({
    super.key,
    required this.liked,
    required this.count,
    required this.onPressed,
  });

  final bool liked;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final Color foreground = liked
        ? CyTokens.statusDanger
        : CyTokens.textSecondary;
    return Semantics(
      button: true,
      label: liked ? stringsOf(context).profileDetailsUnlikeCount(count) : stringsOf(context).profileDetailsLikeCount(count),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              liked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
              size: 20,
              color: foreground,
            ),
            const SizedBox(width: CyTokens.space1),
            Text(
              '$count',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
