import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/tracker.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_action_sheet.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_tabs.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/square_post.dart';
import '../../data/models/club.dart';
import '../../data/api/square_api.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';
import '../map/map_controller.dart';
import '../search/city_node_search_page.dart';
import 'square_controller.dart';
import 'community_post_analytics.dart';
import 'square_image_viewer.dart';
import 'square_post_content.dart';
import 'square_post_reactions.dart';
import 'square_share_sheet.dart';
import 'square_topic_template_remix.dart';
import 'square_author_identity.dart';
import 'square_upcoming_events.dart';

/// 广场时间线。Threads 只作为单列信息密度和交互层级参考，
/// 路线进度、地点和活动附件仍是城瘾自己的内容语法。
class SquareListPage extends ConsumerStatefulWidget {
  const SquareListPage({super.key});

  @override
  ConsumerState<SquareListPage> createState() => _SquareListPageState();
}

class _SquareListPageState extends ConsumerState<SquareListPage> {
  static const List<SquareFeedMode> _visibleModes = <SquareFeedMode>[
    SquareFeedMode.latest,
    SquareFeedMode.following,
    SquareFeedMode.nearby,
    SquareFeedMode.topic,
    SquareFeedMode.community,
    SquareFeedMode.featured,
  ];
  SquareFeedMode _mode = SquareFeedMode.latest;
  String? _nearbyCityCode;
  String? _topicCode;
  int? _communityId;
  bool _nearbyPurposeAccepted = false;
  final Set<int> _busyPosts = <int>{};
  final Set<String> _impressedPostScopes = <String>{};
  final List<SquarePost> _extraPosts = <SquarePost>[];

  /// 点赞/收藏的本地预期(即时反馈 + 失败回滚),见 [SquarePostReactions]。
  final SquarePostReactions _reactions = SquarePostReactions();
  final SquareLikeQueue _likeQueue = SquareLikeQueue();
  int? _nextCursor;
  int? _nextCursorScore;
  bool _hasMore = true;
  bool _loadingMore = false;
  int _feedGeneration = 0;
  int _modeSelectionGeneration = 0;

  Future<void> _changeMode(String key) async {
    final selectionGeneration = ++_modeSelectionGeneration;
    final SquareFeedMode next = SquareFeedMode.values.firstWhere(
      (SquareFeedMode mode) => mode.apiValue == key,
    );
    if (next == SquareFeedMode.following ||
        next == SquareFeedMode.topic ||
        next == SquareFeedMode.community) {
      if (!await requireLogin(context, ref)) return;
    }
    if (!mounted || selectionGeneration != _modeSelectionGeneration) return;
    if (next == SquareFeedMode.nearby) {
      if (!_nearbyPurposeAccepted) {
        final bool accepted = await cyConfirm(
          context,
          title: '使用定位发现同城内容',
          content: '只用本次位置反查城市，用于加载“附近”帖文；不会把精确坐标写入帖文或公开给其他人。',
          confirmText: '继续',
        );
        if (!accepted || !mounted) return;
        _nearbyPurposeAccepted = true;
      }
      try {
        final location = await ref.read(currentMapLocationProvider.future);
        final city = await ref
            .read(mapApiProvider)
            .reverseGeocode(
              longitude: location.longitude,
              latitude: location.latitude,
            );
        if (!city.resolved) {
          if (mounted) CyNativeNotice.show(context, city.hint, isError: true);
          return;
        }
        _nearbyCityCode = city.city.trim();
      } catch (error) {
        if (mounted) {
          CyNativeNotice.show(
            context,
            error.toString().replaceFirst('Exception: ', ''),
            isError: true,
          );
        }
        return;
      }
    }
    if (next == SquareFeedMode.topic) {
      List<Map<String, dynamic>> options;
      try {
        options = await ref.read(squareApiProvider).referenceOptions('TOPIC');
      } catch (error) {
        if (mounted) {
          CyNativeNotice.show(
            context,
            error.toString().replaceFirst('Exception: ', ''),
            isError: true,
          );
        }
        return;
      }
      if (!mounted || selectionGeneration != _modeSelectionGeneration) return;
      if (options.isEmpty) {
        CyNativeNotice.show(context, '暂时没有可浏览的话题', isError: true);
        return;
      }
      final String? selected = await showCupertinoModalPopup<String>(
        context: context,
        builder: (BuildContext sheetContext) => CupertinoActionSheet(
          title: const Text('选择话题'),
          actions: options
              .map((Map<String, dynamic> option) {
                final Object? rawId = option['reference_id'] ?? option['id'];
                final String code = '$rawId';
                final String title =
                    '${option['title'] ?? option['name'] ?? '话题 $code'}';
                return CupertinoActionSheetAction(
                  onPressed: () => Navigator.of(sheetContext).pop(code),
                  child: Text(title),
                );
              })
              .toList(growable: false),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: const Text('取消'),
          ),
        ),
      );
      if (selected == null || !mounted) return;
      _topicCode = selected;
    }
    if (next == SquareFeedMode.community) {
      late final List<Club> clubs;
      try {
        clubs = await ref.read(clubApiProvider).my();
      } catch (error) {
        if (mounted) {
          CyNativeNotice.show(
            context,
            error.toString().replaceFirst('Exception: ', ''),
            isError: true,
          );
        }
        return;
      }
      if (!mounted || selectionGeneration != _modeSelectionGeneration) return;
      if (clubs.isEmpty) {
        CyNativeNotice.show(context, '加入社群后才能浏览社群动态', isError: true);
        return;
      }
      final int? selected = await showCupertinoModalPopup<int>(
        context: context,
        builder: (BuildContext sheetContext) => CupertinoActionSheet(
          title: const Text('选择社群'),
          actions: clubs
              .map(
                (club) => CupertinoActionSheetAction(
                  onPressed: () => Navigator.of(sheetContext).pop(club.id),
                  child: Text(club.name),
                ),
              )
              .toList(growable: false),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: const Text('取消'),
          ),
        ),
      );
      if (selected == null || !mounted) return;
      _communityId = selected;
    }
    if (!mounted || selectionGeneration != _modeSelectionGeneration) return;
    setState(() {
      _feedGeneration++;
      _mode = next;
      _extraPosts.clear();
      _nextCursor = null;
      _nextCursorScore = null;
      _hasMore = true;
      _loadingMore = false;
    });
  }

  void _invalidateFeeds() {
    ref.invalidate(squareListProvider);
    ref.invalidate(squareFollowingListProvider);
    ref.invalidate(squareFeedProvider);
    ref.invalidate(squareNearbyListProvider);
    ref.invalidate(squareFeedPageProvider);
    ref.invalidate(squareNearbyPageProvider);
    ref.invalidate(squareTopicPageProvider);
    ref.invalidate(squareCommunityPageProvider);
    if (mounted) {
      setState(() {
        _feedGeneration++;
        _extraPosts.clear();
        _nextCursor = null;
        _nextCursorScore = null;
        _hasMore = true;
        _loadingMore = false;
      });
    }
  }

  Future<void> _loadMore(SquareFeedPage firstPage) async {
    if (_loadingMore || !(_extraPosts.isEmpty ? firstPage.hasMore : _hasMore)) {
      return;
    }
    final cursor = _extraPosts.isEmpty ? firstPage.nextCursor : _nextCursor;
    final cursorScore = _extraPosts.isEmpty
        ? firstPage.nextCursorScore
        : _nextCursorScore;
    if (cursor == null) return;
    final requestMode = _mode;
    final requestCityCode = _nearbyCityCode;
    final requestGeneration = _feedGeneration;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(squareApiProvider)
          .listPage(
            feedMode: requestMode,
            cityCode: requestMode == SquareFeedMode.nearby
                ? requestCityCode
                : null,
            topicCode: requestMode == SquareFeedMode.topic ? _topicCode : null,
            communityId: requestMode == SquareFeedMode.community
                ? _communityId
                : null,
            cursor: cursor,
            cursorScore: cursorScore,
          );
      if (!mounted ||
          requestGeneration != _feedGeneration ||
          requestMode != _mode) {
        return;
      }
      final known = <int>{
        ...firstPage.items.map((e) => e.id),
        ..._extraPosts.map((e) => e.id),
      };
      setState(() {
        _extraPosts.addAll(page.items.where((post) => known.add(post.id)));
        _nextCursor = page.nextCursor;
        _nextCursorScore = page.nextCursorScore;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted && requestGeneration == _feedGeneration) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _runPostAction(
    int postId,
    Future<String?> Function() action,
  ) async {
    if (_busyPosts.contains(postId)) return;
    setState(() => _busyPosts.add(postId));
    try {
      final String? message = await action();
      if (!mounted) return;
      _invalidateFeeds();
      if ((message ?? '').isNotEmpty) {
        CyNativeNotice.show(context, message!);
      }
    } catch (error) {
      if (!mounted) return;
      if (error is SquareApiException && error.isStaleReportPolicy) {
        ref.invalidate(squareReportPolicyProvider);
      }
      CyNativeNotice.show(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busyPosts.remove(postId));
    }
  }

  Future<void> _toggleLike(SquarePost post) async {
    if (!await requireLogin(context, ref)) return;
    if (!mounted) return;
    final bool enabled = !_reactions.display(post).liked;
    setState(() => _reactions.applyLike(post, liked: enabled));
    try {
      final bool? settled = await _likeQueue.submit(
        post.id,
        want: enabled,
        send: (_) => ref.read(squareApiProvider).like(post.id),
      );
      if (settled == null) return;
      CommunityPostAnalytics.liked(
        ref.read(trackerProvider),
        post.id,
        enabled: settled,
        pagePath: '/square',
      );
      _invalidateFeeds();
    } catch (error) {
      if (!mounted) return;
      // 失败 → 回滚到服务端态,不留下一个假的已赞。
      setState(() => _reactions.rollback(post.id));
      _invalidateFeeds();
      CyNativeNotice.show(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<void> _sharePost(SquarePost post, BuildContext anchorContext) async {
    final RenderBox? box = anchorContext.findRenderObject() as RenderBox?;
    final Rect? origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    await showSquareShareSheet(
      context,
      ref,
      post: _reactions.display(post),
      sharePositionOrigin: origin,
    );
  }

  /// 点头像 → 关注 / 访问个人主页(真源 `pages/square/list/index.js:508-536`)。
  ///
  /// ★ 小程序贴着头像弹一个 T5 胶囊 popover;iPhone 上 popover 不成立
  ///   (设计手册 S6「iPhone 上不用 popover,改 sheet」),所以这里落成
  ///   iOS 原生 action sheet(Liquid Glass,降级 CupertinoActionSheet):
  ///   两项动作与原稿逐字一致 —— 「关注」「访问个人主页」。
  /// ★ 已关注 / 自己的帖**不给**「关注」项 —— 与真源同一条判断
  ///   (`isFollowTheUser == 0 && memberId != userId`),给了点了也没意义。
  Future<void> _showAvatarMenu(SquarePost post) async {
    final int? viewerId = ref.read(authControllerProvider).user?.id;
    final bool canFollow =
        post.isFollowTheUser == 0 && post.memberId != viewerId;
    final String? selected = await showCyNativeActionSheet<String>(
      context: context,
      title: (post.memberNickname?.isEmpty ?? true)
          ? '城瘾用户'
          : post.memberNickname!,
      actions: <CyNativeAction<String>>[
        if (canFollow)
          const CyNativeAction<String>(
            value: 'follow',
            label: '关注',
            systemImage: 'person.badge.plus',
          ),
        const CyNativeAction<String>(
          value: 'profile',
          label: '访问个人主页',
          systemImage: 'person.crop.circle',
        ),
      ],
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case 'follow':
        if (!await requireLogin(context, ref)) return;
        if (!mounted) return;
        await _followAuthor(post);
      case 'profile':
        if (!mounted) return;
        context.push('/user/${post.memberId}');
    }
  }

  /// 关注作者。★ 后端只有一个**切换**接口,文案里区分不了「本来就没关注」,
  ///   所以成功文案按返回值说 —— 不猜、也不本地乐观翻转。
  Future<void> _followAuthor(SquarePost post) async {
    try {
      final bool following = await ref
          .read(registrationApiProvider)
          .toggleFollow(post.memberId);
      if (!mounted) return;
      // 关注关系变了,关注流的分页内容也变了。
      _invalidateFeeds();
      CyNativeNotice.show(context, following ? '已关注' : '已取消关注');
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  void _trackImpression(SquarePost post) {
    if (!_impressedPostScopes.add('${_mode.apiValue}:${post.id}')) return;
    CommunityPostAnalytics.impression(
      ref.read(trackerProvider),
      post.id,
      feedMode: _mode.apiValue,
    );
  }

  Future<void> _showMore(SquarePost post) async {
    final int? viewerId = ref.read(authControllerProvider).user?.id;
    final bool isMine = viewerId != null && viewerId == post.memberId;
    final _PostMenuAction? selected =
        await showCupertinoModalPopup<_PostMenuAction>(
          context: context,
          builder: (BuildContext sheetContext) => CupertinoActionSheet(
            actions: <Widget>[
              if (isMine) ...<Widget>[
                // 真源 H050 三合一弹层(编辑/删除):components/cy/
                // post-actions/index.wxml:5-21。编辑复用发布面板的编辑态,
                // App 侧与详情页同一落点 /square/compose(extra: post)。
                CupertinoActionSheetAction(
                  onPressed: () =>
                      Navigator.of(sheetContext).pop(_PostMenuAction.edit),
                  child: const Text('编辑动态'),
                ),
                CupertinoActionSheetAction(
                  isDestructiveAction: true,
                  onPressed: () =>
                      Navigator.of(sheetContext).pop(_PostMenuAction.delete),
                  child: const Text('删除动态'),
                ),
              ] else ...<Widget>[
                CupertinoActionSheetAction(
                  onPressed: () =>
                      Navigator.of(sheetContext).pop(_PostMenuAction.bookmark),
                  child: Text(post.bookmarked ? '取消收藏' : '收藏'),
                ),
                CupertinoActionSheetAction(
                  onPressed: () => Navigator.of(
                    sheetContext,
                  ).pop(_PostMenuAction.notInterested),
                  child: const Text('不感兴趣'),
                ),
                CupertinoActionSheetAction(
                  onPressed: () =>
                      Navigator.of(sheetContext).pop(_PostMenuAction.mute),
                  child: const Text('静音该用户'),
                ),
                CupertinoActionSheetAction(
                  onPressed: () =>
                      Navigator.of(sheetContext).pop(_PostMenuAction.report),
                  child: const Text('举报这条动态'),
                ),
                CupertinoActionSheetAction(
                  isDestructiveAction: true,
                  onPressed: () =>
                      Navigator.of(sheetContext).pop(_PostMenuAction.block),
                  child: const Text('拉黑该用户'),
                ),
              ],
            ],
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text('取消'),
            ),
          ),
        );
    if (!mounted || selected == null) return;
    if (!await requireLogin(context, ref)) return;
    if (!mounted) return;

    switch (selected) {
      case _PostMenuAction.edit:
        // 与详情页同一编辑落点(发布面板的编辑态);保存返回后刷新列表。
        await context.push('/square/compose', extra: post);
        _invalidateFeeds();
      case _PostMenuAction.delete:
        final bool confirmed = await cyConfirm(
          context,
          title: '删除这条动态？',
          content: '删除后将不再出现在广场。',
          confirmText: '删除',
          danger: true,
        );
        if (!confirmed) return;
        await _runPostAction(
          post.id,
          () => ref.read(squareApiProvider).delete(post.id),
        );
      case _PostMenuAction.bookmark:
        final bool enabled = !_reactions.display(post).bookmarked;
        // 收藏也走本地先落预期:菜单一收就能在卡片上看到结果。
        setState(() => _reactions.applyBookmark(post, bookmarked: enabled));
        try {
          await ref
              .read(squareApiProvider)
              .setAction(post.id, 'BOOKMARK', enabled: enabled);
          CommunityPostAnalytics.favorited(
            ref.read(trackerProvider),
            post.id,
            enabled: enabled,
            pagePath: '/square',
          );
          if (mounted) CyNativeNotice.show(context, enabled ? '已收藏' : '已取消收藏');
          _invalidateFeeds();
        } catch (error) {
          if (!mounted) return;
          setState(() => _reactions.rollback(post.id));
          _invalidateFeeds();
          CyNativeNotice.show(
            context,
            error.toString().replaceFirst('Exception: ', ''),
            isError: true,
          );
        }
      case _PostMenuAction.notInterested:
        await _runPostAction(post.id, () async {
          await ref
              .read(squareApiProvider)
              .setAction(post.id, 'NOT_INTERESTED');
          return '已减少此类内容';
        });
      case _PostMenuAction.mute:
        await _runPostAction(post.id, () async {
          await ref.read(squareApiProvider).mute(post.memberId);
          return '已静音该用户';
        });
      case _PostMenuAction.report:
        final bool confirmed = await cyConfirm(
          context,
          title: '举报内容',
          content: '确认举报这条内容？举报后将提交平台审核。',
          confirmText: '举报',
        );
        if (!confirmed) return;
        await _runPostAction(
          post.id,
          () => ref.read(squareApiProvider).report(post.id),
        );
      case _PostMenuAction.block:
        final bool confirmed = await cyConfirm(
          context,
          title: '拉黑该用户？',
          content: '你们将互相看不到对方的广场动态。',
          confirmText: '拉黑',
          danger: true,
        );
        if (!confirmed) return;
        await _runPostAction(
          post.id,
          () => ref.read(imApiProvider).block(post.memberId),
        );
    }
  }

  Future<void> _openComposer({String? intent}) async {
    if (!await requireLogin(context, ref)) return;
    if (!mounted) return;
    final String location = intent == null
        ? '/square/compose'
        : '/square/compose?intent=$intent';
    context.push(location);
  }

  Future<void> _openGovernance() async {
    if (!await requireLogin(context, ref)) return;
    if (!mounted) return;
    context.push('/square/governance');
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final currentUser = ref.watch(authControllerProvider).user;
    final AsyncValue<SquareFeedPage> posts = switch (_mode) {
      SquareFeedMode.nearby when _nearbyCityCode != null => ref.watch(
        squareNearbyPageProvider(_nearbyCityCode!),
      ),
      SquareFeedMode.topic when _topicCode != null => ref.watch(
        squareTopicPageProvider(_topicCode!),
      ),
      SquareFeedMode.community when _communityId != null => ref.watch(
        squareCommunityPageProvider(_communityId!),
      ),
      _ => ref.watch(squareFeedPageProvider(_mode)),
    };
    // 「即将开始」只在有数据时渲染;拿不到就整块不出(真源 `silentError`)。
    final AsyncValue<List<SquareUpcomingCard>> upcomingAsync = ref.watch(
      squareUpcomingCardsProvider,
    );
    final List<SquareUpcomingCard> upcoming =
        upcomingAsync is AsyncData<List<SquareUpcomingCard>>
        ? upcomingAsync.value
        : const <SquareUpcomingCard>[];
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('动态'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Semantics(
              button: true,
              label: '社区治理与申诉',
              child: CupertinoButton(
                key: const Key('square-governance-entry'),
                padding: EdgeInsets.zero,
                minimumSize: const Size.square(CyTokens.btnH),
                onPressed: _openGovernance,
                child: const ExcludeSemantics(
                  child: Icon(CupertinoIcons.shield),
                ),
              ),
            ),
            Semantics(
              button: true,
              label: '在地图上搜索',
              child: CupertinoButton(
                key: const Key('square-search-map'),
                padding: EdgeInsets.zero,
                minimumSize: const Size.square(CyTokens.btnH),
                onPressed: () => context.push(searchMapLocation()),
                child: const ExcludeSemantics(child: Icon(CupertinoIcons.map)),
              ),
            ),
          ],
        ),
      ),
      child: Material(
        color: palette.bgPage,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
                child: CyTabs(
                  tabs: _visibleModes
                      .map(
                        (SquareFeedMode mode) =>
                            CyTab(key: mode.apiValue, label: mode.label),
                      )
                      .toList(growable: false),
                  active: _mode.apiValue,
                  onChanged: _changeMode,
                  variant: CyTabsVariant.chip,
                ),
              ),
              if (_mode == SquareFeedMode.latest)
                _SquareComposer(
                  avatar: currentUser?.avatar,
                  nickname: currentUser?.nickname,
                  onCompose: () => _openComposer(),
                  onPhoto: () => _openComposer(intent: 'photo'),
                  onLocation: () => _openComposer(intent: 'location'),
                  onRoute: () => _openComposer(intent: 'route'),
                ),
              Expanded(
                child: posts.when(
                  // 真源 pages/square/list 动态流用 post-card 鱼骨档。
                  loading: () => const CySkeleton(
                    type: CySkeletonType.postCard,
                    count: 3,
                  ),
                  error: (Object err, StackTrace st) => StatusView(
                    message: '没能加载动态',
                    sub: '检查网络后重试',
                    icon: CupertinoIcons.exclamationmark_triangle,
                    onRetry: _invalidateFeeds,
                  ),
                  data: (SquareFeedPage page) {
                    final list = <SquarePost>[...page.items, ..._extraPosts];
                    // 服务端追上本地预期后撤掉覆盖。
                    // 撤掉那一刻两边取值相同,渲染结果不变,所以不需要 setState。
                    _reactions.reconcile(list);
                    final bool hasTrack = upcoming.isNotEmpty;
                    if (list.isEmpty) {
                      final Widget empty = StatusView(
                        message: _mode == SquareFeedMode.latest
                            ? '还没有动态，来发第一条吧'
                            : '关注的人还没有发布动态',
                        icon: Icons.dynamic_feed_outlined,
                        // 有横滑卡时由外层 ListView 负责滚动,这里不能再套一层。
                        scrollable: !hasTrack,
                        onRetry: _invalidateFeeds,
                      );
                      if (!hasTrack) return empty;
                      // 一条动态都没有的广场,更该把「即将开始」给出来 ——
                      // 那是此刻唯一还能去的去处。
                      return RefreshIndicator.adaptive(
                        onRefresh: () async => _invalidateFeeds(),
                        child: ListView(
                          children: <Widget>[
                            SquareUpcomingTrack(cards: upcoming),
                            empty,
                          ],
                        ),
                      );
                    }
                    final int trackOffset = hasTrack ? 1 : 0;
                    final bool hasMoreRow = _extraPosts.isEmpty
                        ? page.hasMore
                        : _hasMore;
                    return RefreshIndicator.adaptive(
                      onRefresh: () async => _invalidateFeeds(),
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: CyTokens.space5),
                        itemCount:
                            list.length + trackOffset + (hasMoreRow ? 1 : 0),
                        separatorBuilder: (_, int index) {
                          // 横滑卡与第一条动态之间不画分隔线:那块卡自己有描边。
                          if (hasTrack && index == 0) {
                            return const SizedBox.shrink();
                          }
                          return Divider(
                            height: 1,
                            thickness: 1,
                            indent:
                                CyTokens.pageX +
                                CyTokens.space7 +
                                CyTokens.space3,
                            color: palette.borderSubtle,
                          );
                        },
                        itemBuilder: (BuildContext context, int index) {
                          if (hasTrack && index == 0) {
                            return SquareUpcomingTrack(cards: upcoming);
                          }
                          final int itemIndex = index - trackOffset;
                          if (itemIndex == list.length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: CyTokens.space3,
                              ),
                              child: Center(
                                child: CupertinoButton(
                                  onPressed: _loadingMore
                                      ? null
                                      : () => _loadMore(page),
                                  child: Text(_loadingMore ? '加载中…' : '加载更多'),
                                ),
                              ),
                            );
                          }
                          final SquarePost post = _reactions.display(
                            list[itemIndex],
                          );
                          return _PostImpressionObserver(
                            key: Key(
                              'square-impression-${_mode.apiValue}-${post.id}',
                            ),
                            onImpression: () => _trackImpression(post),
                            child: SquareThreadItem(
                              key: Key('square-thread-item-${post.id}'),
                              post: post,
                              busy: _busyPosts.contains(post.id),
                              onReply: () => context.push('/square/${post.id}'),
                              onLike: () => _toggleLike(post),
                              onShare: (BuildContext anchor) =>
                                  _sharePost(post, anchor),
                              onMore: () => _showMore(post),
                              onAvatarTap: () => _showAvatarMenu(post),
                            ),
                          );
                        },
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

class _PostImpressionObserver extends StatefulWidget {
  const _PostImpressionObserver({
    super.key,
    required this.onImpression,
    required this.child,
  });

  final VoidCallback onImpression;
  final Widget child;

  @override
  State<_PostImpressionObserver> createState() =>
      _PostImpressionObserverState();
}

class _PostImpressionObserverState extends State<_PostImpressionObserver>
    with WidgetsBindingObserver {
  ScrollPosition? _position;
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ModalRoute.isCurrentOf(context);
    final ScrollPosition? next = Scrollable.maybeOf(context)?.position;
    if (!identical(next, _position)) {
      _position?.removeListener(_checkVisibility);
      _position = next;
      _position?.addListener(_checkVisibility);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
    }
  }

  void _checkVisibility() {
    if (!mounted || _reported) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        ModalRoute.isCurrentOf(context) != true) {
      return;
    }
    final RenderObject? itemObject = context.findRenderObject();
    final ScrollableState? scrollable = Scrollable.maybeOf(context);
    final RenderObject? viewportObject = scrollable?.context.findRenderObject();
    if (itemObject is! RenderBox ||
        viewportObject is! RenderBox ||
        !itemObject.hasSize ||
        !viewportObject.hasSize ||
        itemObject.size.isEmpty) {
      return;
    }
    final Rect itemRect =
        itemObject.localToGlobal(Offset.zero) & itemObject.size;
    final Rect viewportRect =
        viewportObject.localToGlobal(Offset.zero) & viewportObject.size;
    final Rect visible = itemRect.intersect(viewportRect);
    final double visibleRatio = visible.isEmpty
        ? 0
        : (visible.width * visible.height) / (itemRect.width * itemRect.height);
    if (visibleRatio < 0.5) return;
    _reported = true;
    widget.onImpression();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _position?.removeListener(_checkVisibility);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _SquareComposer extends StatelessWidget {
  const _SquareComposer({
    required this.avatar,
    required this.nickname,
    required this.onCompose,
    required this.onPhoto,
    required this.onLocation,
    required this.onRoute,
  });

  final String? avatar;
  final String? nickname;
  final VoidCallback onCompose;
  final VoidCallback onPhoto;
  final VoidCallback onLocation;
  final VoidCallback onRoute;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space2,
        CyTokens.pageX,
        CyTokens.space2,
      ),
      decoration: BoxDecoration(
        color: palette.bgPage,
        border: Border(bottom: BorderSide(color: palette.borderSubtle)),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              _Avatar(url: avatar, name: nickname),
              const SizedBox(width: CyTokens.space3),
              Expanded(
                child: CupertinoButton(
                  key: const Key('square-compose-entry'),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  alignment: Alignment.centerLeft,
                  onPressed: onCompose,
                  child: Text(
                    '分享此刻的城市发现…',
                    style: textTheme.bodyMedium?.copyWith(
                      color: palette.textTertiary,
                    ),
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: '发布',
                child: CupertinoButton(
                  key: const Key('square-compose-submit'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space3,
                  ),
                  minimumSize: const Size(44, 44),
                  onPressed: onCompose,
                  child: const ExcludeSemantics(child: Text('发布')),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: CyTokens.space1,
              runSpacing: CyTokens.space1,
              children: <Widget>[
                _ComposerAction(
                  key: const Key('square-compose-media'),
                  label: '图片',
                  icon: CupertinoIcons.photo,
                  onPressed: onPhoto,
                ),
                _ComposerAction(
                  key: const Key('square-compose-location'),
                  label: '地点',
                  icon: CupertinoIcons.location,
                  onPressed: onLocation,
                ),
                _ComposerAction(
                  key: const Key('square-compose-route'),
                  label: '路线',
                  icon: CupertinoIcons.map_pin_ellipse,
                  onPressed: onRoute,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposerAction extends StatelessWidget {
  const _ComposerAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoButton(
      padding: const EdgeInsets.only(right: CyTokens.space3),
      minimumSize: const Size(44, 44),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: palette.textSecondary),
          const SizedBox(width: CyTokens.space1),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

enum _PostMenuAction {
  edit,
  delete,
  bookmark,
  notInterested,
  mute,
  report,
  block,
}

/// 广场的公开帖文单元，是页面测试和后续复用的稳定 seam。
class SquareThreadItem extends StatelessWidget {
  const SquareThreadItem({
    super.key,
    required this.post,
    required this.busy,
    required this.onReply,
    required this.onLike,
    required this.onShare,
    required this.onMore,
    this.onAvatarTap,
  });

  final SquarePost post;
  final bool busy;
  final VoidCallback onReply;
  final VoidCallback onLike;
  final ValueChanged<BuildContext> onShare;
  final VoidCallback onMore;

  /// 点头像 → 关注 / 访问个人主页(真源 `pages/square/list/index.js:508` 的
  /// `onAvatarTap`)。为 null 时头像退回不可点 —— 老调用方不会因此报错。
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.space4,
        CyTokens.space3,
        CyTokens.space2,
        CyTokens.space3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ★ 高度**不写死**:头像的热区从 40pt 抬到 44pt(iOS 最小触达),
          //   写死 80pt 会把它挤爆 4px。改成由内容决定 —— 卡片高度本来就由
          //   右侧正文决定,这一列只是夹在左边的视觉轨道。
          SizedBox(
            key: Key('square-thread-rail-${post.id}'),
            width: CyTokens.space7,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _AvatarTapTarget(
                  post: post,
                  onPressed: onAvatarTap,
                  child: _Avatar(
                    url: post.memberAvatar,
                    name: post.memberNickname,
                  ),
                ),
                const SizedBox(height: CyTokens.space2),
                Container(
                  width: 1,
                  height: CyTokens.space6,
                  color: palette.borderSubtle,
                ),
              ],
            ),
          ),
          const SizedBox(width: CyTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  alignment: Alignment.topLeft,
                  onPressed: onReply,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              (post.memberNickname?.isNotEmpty ?? false)
                                  ? post.memberNickname!
                                  : '城瘾用户',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleSmall?.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (SquareAuthorBadges.anyOf(post)) ...<Widget>[
                            const SizedBox(width: CyTokens.space1),
                            Flexible(child: SquareAuthorBadges(post: post)),
                          ],
                          const Spacer(),
                          if ((post.createTime?.isNotEmpty ?? false))
                            Text(
                              post.createTime!,
                              style: textTheme.labelSmall?.copyWith(
                                color: palette.textTertiary,
                              ),
                            ),
                        ],
                      ),
                      if ((post.clubName ?? '').trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: CyTokens.space1),
                        SquareClubLink(post: post),
                      ],
                      if (post.safetyLabels.isNotEmpty) ...<Widget>[
                        const SizedBox(height: CyTokens.space1),
                        Wrap(
                          spacing: CyTokens.space1,
                          runSpacing: CyTokens.space1,
                          children: post.safetyLabels
                              .map(
                                (label) => Text(
                                  '⚠ ${squareSafetyLabelText(label)}',
                                  style: textTheme.labelSmall?.copyWith(
                                    color: CyTokens.statusWarning,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ],
                      if (post.pics.isNotEmpty) ...<Widget>[
                        const SizedBox(height: CyTokens.space2),
                        KeyedSubtree(
                          key: Key('square-post-media-${post.id}'),
                          child: _PicGrid(pics: post.pics),
                        ),
                      ],
                      if ((post.contents?.isNotEmpty ?? false)) ...<Widget>[
                        const SizedBox(height: CyTokens.space2),
                        SquarePostContent(
                          key: Key('square-post-content-${post.id}'),
                          text: post.contents!,
                          maxLines: 6,
                          style: textTheme.bodyMedium?.copyWith(
                            color: palette.textPrimary,
                            height: 1.35,
                          ),
                        ),
                      ],
                      if (_hasRouteAttachment(post)) ...<Widget>[
                        const SizedBox(height: CyTokens.space2),
                        _RouteAttachment(post: post),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: CyTokens.space1),
                Row(
                  children: <Widget>[
                    _ThreadAction(
                      key: Key('square-post-reply-${post.id}'),
                      semanticLabel: '评论',
                      icon: CupertinoIcons.chat_bubble,
                      count: post.commentCount,
                      onPressed: busy ? null : onReply,
                    ),
                    _ThreadAction(
                      key: Key('square-post-like-${post.id}'),
                      semanticLabel: post.liked ? '取消点赞' : '点赞',
                      icon: post.liked
                          ? CupertinoIcons.heart_fill
                          : CupertinoIcons.heart,
                      color: post.liked ? CyTokens.statusDanger : null,
                      count: post.likeNum,
                      onPressed: busy ? null : onLike,
                    ),
                    Builder(
                      builder: (BuildContext anchorContext) => _ThreadAction(
                        key: Key('square-post-share-${post.id}'),
                        semanticLabel: '分享',
                        icon: CupertinoIcons.paperplane,
                        onPressed: busy ? null : () => onShare(anchorContext),
                      ),
                    ),
                    _ThreadAction(
                      key: Key('square-post-more-${post.id}'),
                      semanticLabel: '更多操作',
                      icon: CupertinoIcons.ellipsis,
                      onPressed: busy ? null : onMore,
                    ),
                  ],
                ),
                if (post.canRemixTopicTemplate) ...<Widget>[
                  const SizedBox(height: CyTokens.space2),
                  SquareTopicTemplateRemix(post: post),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

bool _hasRouteAttachment(SquarePost post) =>
    (post.sportName?.isNotEmpty ?? false) ||
    (post.address?.isNotEmpty ?? false) ||
    post.nodeTotal > 0;

class _RouteAttachment extends StatelessWidget {
  const _RouteAttachment({required this.post});

  final SquarePost post;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    final String image = (post.routePreviewImg?.isNotEmpty ?? false)
        ? post.routePreviewImg!
        : (post.sportCover ?? '');
    final String? path = switch (post.referenceType) {
      // 真源 pages/square/list/index.js:627-638 `goPlay`:关联的是活动就直达
      // 开局页(`/pages/play/index?activityId=`),不是活动详情 —— App 侧同名
      // 路由是 /play/:activityId。TOPIC 行走的是源里「看详情」口径(主题详情)。
      'ACTIVITY' => '/play/${post.referenceId}',
      'TOPIC' => '/topic/${post.referenceId}',
      'CLUB' => '/club/${post.referenceId}',
      'POI' => '/roam/poi/${post.referenceId}',
      'ROUTE' => '/roam/history',
      _ => null,
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: path == null ? null : () => context.push(path),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(CyTokens.space2),
        decoration: BoxDecoration(
          color: palette.bgSurfaceSubtle,
          border: Border.all(color: palette.borderSubtle),
          borderRadius: BorderRadius.circular(CyTokens.radiusSm),
        ),
        child: Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(CyTokens.radiusSm),
              child: image.isEmpty
                  ? Container(
                      width: CyTokens.space8,
                      height: CyTokens.space8,
                      color: palette.bgElevated,
                      alignment: Alignment.center,
                      child: Icon(
                        CupertinoIcons.map_pin_ellipse,
                        color: palette.textSecondary,
                      ),
                    )
                  : Image.network(
                      image,
                      width: CyTokens.space8,
                      height: CyTokens.space8,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: CyTokens.space8,
                        height: CyTokens.space8,
                        color: palette.bgElevated,
                        alignment: Alignment.center,
                        child: Icon(
                          CupertinoIcons.map_pin_ellipse,
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: CyTokens.space2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if ((post.sportName?.isNotEmpty ?? false))
                    Text(
                      post.sportName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelLarge?.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (post.nodeTotal > 0)
                    Text(
                      '${post.nodeDoneCount}/${post.nodeTotal} 个节点',
                      style: textTheme.labelSmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  if ((post.address?.isNotEmpty ?? false))
                    Text(
                      post.address!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: palette.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_forward,
              size: 14,
              color: palette.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadAction extends StatelessWidget {
  const _ThreadAction({
    super.key,
    required this.semanticLabel,
    required this.icon,
    required this.onPressed,
    this.count,
    this.color,
  });

  final String semanticLabel;
  final IconData icon;
  final VoidCallback? onPressed;
  final int? count;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final Color foreground = color ?? palette.textSecondary;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: CupertinoButton(
        padding: const EdgeInsets.only(right: CyTokens.space3),
        minimumSize: const Size(44, 44),
        alignment: Alignment.centerLeft,
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 20, color: foreground),
            if ((count ?? 0) > 0) ...<Widget>[
              const SizedBox(width: CyTokens.space1),
              Text(
                '$count',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: foreground),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name});

  final String? url;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final Widget fallback = Container(
      width: CyTokens.space7,
      height: CyTokens.space7,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.bgElevated,
        shape: BoxShape.circle,
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Text(
        (name?.isNotEmpty ?? false) ? name!.characters.first : '瘾',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: palette.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    if (url == null || url!.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        url!,
        width: CyTokens.space7,
        height: CyTokens.space7,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

/// 头像的 44pt 热区 + 语义(真源 `pages/square/list/index.wxml:4` 的
/// `aria-label="打开用户主页"`)。`onPressed` 为空时**不假装可点** ——
/// 渲染成普通头像,免得屏幕阅读器念一个点了没反应的按钮。
class _AvatarTapTarget extends StatelessWidget {
  const _AvatarTapTarget({
    required this.post,
    required this.onPressed,
    required this.child,
  });

  final SquarePost post;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? tap = onPressed;
    if (tap == null) return child;
    return Semantics(
      button: true,
      label: '打开用户主页',
      child: CupertinoButton(
        key: Key('square-avatar-${post.id}'),
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: tap,
        child: ExcludeSemantics(child: child),
      ),
    );
  }
}

/// 图片网格（最多展示 9 张，自适应单/多图）。
class _PicGrid extends StatelessWidget {
  const _PicGrid({required this.pics});

  final List<String> pics;

  @override
  Widget build(BuildContext context) {
    final List<String> shown = pics.take(9).toList();
    if (shown.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(CyTokens.radiusSm),
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: _PicTile(pics: pics, index: 0),
        ),
      );
    }
    final int cols = shown.length == 2 || shown.length == 4 ? 2 : 3;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: shown.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: CyTokens.space1,
        mainAxisSpacing: CyTokens.space1,
      ),
      itemBuilder: (BuildContext context, int index) => ClipRRect(
        borderRadius: BorderRadius.circular(CyTokens.radiusSm),
        child: _PicTile(pics: pics, index: index),
      ),
    );
  }
}

/// 可点开的图片位:点进全屏查看器,并把它标成「第 n 张 / 共 N 张」。
/// 查看器里给的是**全量** [pics] —— 网格只画前 9 张,多的在查看器里翻。
class _PicTile extends StatelessWidget {
  const _PicTile({required this.pics, required this.index});

  final List<String> pics;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '查看第 ${index + 1} 张图片，共 ${pics.length} 张',
      child: CupertinoButton(
        key: Key('square-pic-$index'),
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: () =>
            showSquareImageViewer(context, urls: pics, initialIndex: index),
        child: ExcludeSemantics(child: _Pic(url: pics[index])),
      ),
    );
  }
}

class _Pic extends StatelessWidget {
  const _Pic({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        color: palette.bgElevated,
        alignment: Alignment.center,
        child: Icon(
          Icons.broken_image_outlined,
          color: palette.textDisabled,
          size: 22,
        ),
      ),
    );
  }
}
