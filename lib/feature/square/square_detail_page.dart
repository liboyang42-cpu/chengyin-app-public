import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/status_view.dart';
import '../auth/auth_controller.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../data/models/square_post.dart';
import '../auth/login_gate.dart';
import 'square_controller.dart';
import 'community_post_analytics.dart';
import 'square_author_identity.dart';
import 'square_comment_thread.dart';
import 'square_image_viewer.dart';
import 'square_post_content.dart';
import 'square_post_reactions.dart';
import 'square_share_sheet.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/analytics/tracker.dart';
import '../../core/widgets/cy_native_notice.dart';
import 'square_topic_template_remix.dart';

/// 创意广场详情:正文 + 图 + 点赞按钮 + 评论区 + 发评论输入框。
class SquareDetailPage extends ConsumerStatefulWidget {
  const SquareDetailPage({super.key, required this.postId});
  final int postId;

  @override
  ConsumerState<SquareDetailPage> createState() => _SquareDetailPageState();
}

class _SquareDetailPageState extends ConsumerState<SquareDetailPage> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  bool _sending = false;
  bool _loadingMoreComments = false;
  bool _withdrawingLocation = false;
  bool _commentsExhausted = false;

  /// 已加载到第几页评论。评论列表是 pageNum/pageSize 分页,不是游标。
  int _commentPage = 1;
  final List<Comment> _extraComments = <Comment>[];

  /// 关注按钮的进行中态。★ 不做乐观翻转:后端只有一个切换接口,
  /// 结果只能从返回文案区分,翻了再翻回去就是真的翻错了。
  bool _followBusy = false;

  /// 点赞/收藏的本地预期(即时反馈 + 失败回滚)。
  final SquarePostReactions _reactions = SquarePostReactions();
  final SquareCommentReactions _commentReactions = SquareCommentReactions();

  /// 帖子点赞的串行队列:连点时在跑的那一轮收尾会补发最后一次期望。
  final SquareLikeQueue _likeQueue = SquareLikeQueue();
  final GlobalKey _contentEndKey = GlobalKey();
  Timer? _qualifiedTimer;
  final CommunityPostQualifiedDwell _qualifiedDwell =
      CommunityPostQualifiedDwell();
  final CommunityPostQualifiedScroll _qualifiedScroll =
      CommunityPostQualifiedScroll();
  final CommunityPostOpenedMembers _openedMembers =
      CommunityPostOpenedMembers();
  bool _contentTrackingScheduled = false;
  bool _contentTrackingStarted = false;
  final CommunityPostQualifiedMembers _qualifiedMembers =
      CommunityPostQualifiedMembers();
  bool _userScrollActive = false;

  /// 关注作者(真源 `pages/square/detail/index.wxml:37` 的表头「关注」)。
  ///
  /// ★ 关注关系一变,**关注流**的分页内容也变了 —— 和点赞不一样,
  ///   不能只改这一页的按钮;两个 feed provider 一起作废。
  Future<void> _followAuthor(SquarePost post) async {
    if (_followBusy) return;
    setState(() => _followBusy = true);
    try {
      final bool following = await ref
          .read(registrationApiProvider)
          .toggleFollow(post.memberId);
      if (!mounted) return;
      ref.invalidate(squareDetailProvider(widget.postId));
      ref.invalidate(squareFeedPageProvider);
      CyNativeNotice.show(context, following ? '已关注' : '已取消关注');
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  void _scheduleContentTracking() {
    if (_contentTrackingStarted || _contentTrackingScheduled) return;
    _contentTrackingScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _contentTrackingScheduled = false;
      if (!mounted || _contentTrackingStarted) return;
      if (ref.read(squareDetailProvider(widget.postId)).asData == null) return;
      _contentTrackingStarted = true;
      _trackOpenedForCurrentViewer();
      _qualifiedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted ||
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed ||
            ModalRoute.of(context)?.isCurrent != true ||
            ref.read(squareDetailProvider(widget.postId)).asData == null) {
          return;
        }
        _trackOpenedForCurrentViewer();
        final SquarePost post = ref
            .read(squareDetailProvider(widget.postId))
            .asData!
            .value;
        final int? viewerId = ref.read(authControllerProvider).user?.id;
        if (_qualifiedDwell.tick(viewerId: viewerId, authorId: post.memberId)) {
          _trackQualified('dwell_10s');
        }
      });
    });
  }

  void _trackOpenedForCurrentViewer() {
    final int? viewerId = ref.read(authControllerProvider).user?.id;
    if (!_openedMembers.mark(viewerId)) return;
    CommunityPostAnalytics.opened(ref.read(trackerProvider), widget.postId);
  }

  void _trackQualified(String qualification) {
    final SquarePost? post = ref
        .read(squareDetailProvider(widget.postId))
        .asData
        ?.value;
    final int? viewerId = ref.read(authControllerProvider).user?.id;
    if (post == null ||
        !_qualifiedMembers.mark(viewerId: viewerId, authorId: post.memberId)) {
      return;
    }
    CommunityPostAnalytics.qualified(
      ref.read(trackerProvider),
      widget.postId,
      qualification: qualification,
    );
  }

  bool _handleDetailScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _userScrollActive = notification.dragDetails != null;
      if (_userScrollActive) {
        final SquarePost? post = ref
            .read(squareDetailProvider(widget.postId))
            .asData
            ?.value;
        _qualifiedScroll.begin(
          viewerId: ref.read(authControllerProvider).user?.id,
          authorId: post?.memberId,
          pixels: notification.metrics.pixels,
        );
      }
      return false;
    }
    final bool shouldEvaluate =
        _userScrollActive &&
        (notification is ScrollUpdateNotification ||
            notification is ScrollEndNotification);
    if (!shouldEvaluate) return false;
    _evaluateContentConsumption(notification.metrics);
    if (notification is ScrollEndNotification) _userScrollActive = false;
    return false;
  }

  void _evaluateContentConsumption(ScrollMetrics metrics) {
    final BuildContext? markerContext = _contentEndKey.currentContext;
    final RenderObject? markerObject = markerContext?.findRenderObject();
    final ScrollableState? scrollable = markerContext == null
        ? null
        : Scrollable.maybeOf(markerContext);
    final RenderObject? viewportObject = scrollable?.context.findRenderObject();
    if (markerObject is! RenderBox || viewportObject is! RenderBox) {
      return;
    }
    final double contentExtent =
        metrics.pixels +
        markerObject.localToGlobal(Offset.zero).dy -
        viewportObject.localToGlobal(Offset.zero).dy;
    final SquarePost? post = ref
        .read(squareDetailProvider(widget.postId))
        .asData
        ?.value;
    if (_qualifiedScroll.consumed(
      viewerId: ref.read(authControllerProvider).user?.id,
      authorId: post?.memberId,
      pixels: metrics.pixels,
      viewportDimension: metrics.viewportDimension,
      contentExtent: contentExtent,
    )) {
      _trackQualified('consumed_70pct');
    }
  }

  @override
  void dispose() {
    _qualifiedTimer?.cancel();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _toggleLike(SquarePost post) async {
    if (!await requireLogin(context, ref)) return;
    if (!mounted) return;
    final bool enabled = !_reactions.display(post).liked;
    // ★ 即时反馈:本地先落预期,失败再回滚(不是等接口回来才变色)。
    setState(() => _reactions.applyLike(post, liked: enabled));
    try {
      final bool? settled = await _likeQueue.submit(
        post.id,
        want: enabled,
        send: (_) => ref.read(squareApiProvider).like(post.id),
      );
      if (settled == null) return;
      // 埋点在**成功之后**发 —— 失败也发的话,漏斗里的「点赞数」
      // 会比库里的多,而那正是拿它做决策的人最容易信错的数字。
      CommunityPostAnalytics.liked(
        ref.read(trackerProvider),
        post.id,
        enabled: settled,
      );
      ref.invalidate(squareDetailProvider(widget.postId));
    } catch (e) {
      if (!mounted) return;
      setState(() => _reactions.rollback(post.id));
      ref.invalidate(squareDetailProvider(widget.postId));
      _toast(
        '操作失败:${e.toString().replaceFirst('Exception: ', '')}',
        isError: true,
      );
    }
  }

  /// 分享这条动态:复制链接 / 系统分享。
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
      pagePath: '/square/:id',
    );
  }

  /// 正在回复的那条评论。null = 发顶层评论。
  ///
  /// ★ 回复态必须**看得见**:输入框上方横一条「回复 @某某 ×」。
  ///   不显示的话,用户不知道这条会挂到谁下面 —— 而发出去就改不了了。
  Comment? _replyTo;

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    if (!await requireLogin(context, ref)) return;
    if (!mounted) return;
    final bool wasReply = _replyTo != null;
    setState(() => _sending = true);
    try {
      await ref
          .read(squareApiProvider)
          .addComment(widget.postId, text, replyToId: _replyTo?.id);
      _input.clear();
      // 发完就退出回复态 —— 留着会让下一条也悄悄挂到同一个人下面。
      if (mounted) setState(() => _replyTo = null);
      if (mounted) FocusScope.of(context).unfocus();
      _refreshComments();
      ref.invalidate(squareDetailProvider(widget.postId));
      // 小程序 `addComment` / `addReplyComment` 的回执,文案照搬。
      _toast(wasReply ? '回复成功' : '评论成功');
    } catch (e) {
      // 异常原文只进日志 —— 上屏的永远是人话(后端原话优先)。
      debugPrint('[square-detail] 评论发送失败: $e');
      _toast(
        friendlyOrBackendMessage(e, fallback: '评论没能发送，请稍后重试'),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    CyNativeNotice.show(context, msg, isError: isError);
  }

  /// 举报这条动态。UGC 举报入口(Apple 审核指南 1.2)。
  ///
  /// 与小程序 `reportSquare` 同一口径:确认一次 → 提交统一审核队列。
  /// ⚠️ 后端 `/api/creativesquare/report` **不收理由** —— 所以这里不再让用户
  /// 选一个会被丢掉的理由,那只是骗他点一下。
  Future<void> _report() async {
    final bool ok = await cyConfirm(
      context,
      title: '举报内容',
      content: '确认举报这条内容？举报后将提交平台审核。',
      confirmText: '举报',
    );
    if (!ok || !mounted) return;
    try {
      final String msg = await ref
          .read(squareApiProvider)
          .report(widget.postId);
      // 后端只入审核队列、不立即下架 —— 原样转述它的话,别自己编「已处理」。
      _toast(msg);
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  /// 删除自己发的动态。
  ///
  /// ★ 删自己的东西也要确认 —— 软删在后端,前端拿不回来。
  Future<void> _delete() async {
    final bool ok = await cyConfirm(
      context,
      title: '删除这条动态?',
      content: '删除后别人就看不到了,评论也会一起消失。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      final String msg = await ref
          .read(squareApiProvider)
          .delete(widget.postId);
      if (!mounted) return;
      CyNativeNotice.show(context, msg);
      // 删完这一页就没有内容了,退回列表并让列表重取
      ref.invalidate(squareListProvider);
      ref.invalidate(squareFollowingListProvider);
      ref.invalidate(squareFeedProvider);
      if (context.mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  /// 给评论点赞 / 取消赞。
  ///
  /// 接口是显式态的(传 enabled),所以本地可以安全地先落预期:
  /// 失败就把这一格回滚,并重拉评论列表以服务端为准。
  Future<void> _likeComment(Comment comment) async {
    final bool enabled = !_commentReactions.display(comment).liked;
    setState(() => _commentReactions.applyLike(comment, liked: enabled));
    try {
      await ref
          .read(squareApiProvider)
          .setCommentLike(comment.id, enabled: enabled);
      _refreshComments();
    } catch (e) {
      if (!mounted) return;
      setState(() => _commentReactions.rollback(comment.id));
      _refreshComments();
      _toast(e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  /// 举报一条评论。与小程序 `reportComment` 同一口径:确认一次 → 进审核队列。
  Future<void> _reportComment(int commentId) async {
    final bool ok = await cyConfirm(
      context,
      title: '举报评论',
      content: '确认举报这条评论？举报后将提交平台审核。',
      confirmText: '举报',
    );
    if (!ok || !mounted) return;
    try {
      final String msg = await ref
          .read(squareApiProvider)
          .reportComment(commentId);
      _toast(msg);
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  Future<void> _approveComment(Comment comment) async {
    try {
      await ref
          .read(squareApiProvider)
          .approveComment(widget.postId, comment.id, comment.version);
      _refreshComments();
      ref.invalidate(squareDetailProvider(widget.postId));
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  Future<void> _deleteComment(Comment comment) async {
    final ok = await cyConfirm(
      context,
      title: '删除评论？',
      content: '删除后不会再出现在讨论中。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    try {
      await ref.read(squareApiProvider).deleteComment(comment.id);
      _refreshComments();
      ref.invalidate(squareDetailProvider(widget.postId));
      _toast('评论已删除');
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  void _refreshComments() {
    if (mounted) {
      setState(() {
        _extraComments.clear();
        _commentsExhausted = false;
        _commentPage = 1;
      });
    }
    ref.invalidate(squareCommentsProvider(widget.postId));
  }

  Future<void> _loadMoreComments(List<Comment> loaded) async {
    if (_loadingMoreComments || _commentsExhausted || loaded.isEmpty) return;
    setState(() => _loadingMoreComments = true);
    try {
      final List<Comment> next = await ref
          .read(squareApiProvider)
          .comments(
            widget.postId,
            page: _commentPage + 1,
            limit: kSquareCommentsPageSize,
          );
      if (!mounted) return;
      final Set<int> known = loaded.map((Comment c) => c.id).toSet();
      setState(() {
        _commentPage += 1;
        _extraComments.addAll(next.where((Comment c) => known.add(c.id)));
        // 后端返的是一整页,不满一页就是到底了。
        // (小程序用 `total` 反算 `getTotalPage(total, pageSize) > pageNum`,
        //  判据等价:都取决于「服务端这一页实际给了几条」。)
        _commentsExhausted = next.length < kSquareCommentsPageSize;
      });
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _loadingMoreComments = false);
    }
  }

  Future<void> _edit(SquarePost post) async {
    await context.push('/square/compose', extra: post);
    if (!mounted) return;
    ref.invalidate(squareDetailProvider(widget.postId));
    ref.invalidate(squareListProvider);
    ref.invalidate(squareFollowingListProvider);
    ref.invalidate(squareFeedProvider);
  }

  Future<void> _showRevisions(SquarePost post) async {
    try {
      final revisions = await ref.read(squareApiProvider).revisions(post.id);
      if (!mounted) return;
      // 纯告知不弹 alert(S7):页内轻提示,文案不变。
      _toast(
        revisions.isEmpty
            ? '这条帖文还没有历史修订。'
            : '已保留 ${revisions.length} 个不可变修订版本，便于争议复核。',
      );
    } catch (error) {
      _toast(error.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  Future<void> _withdrawLocation(SquarePost post) async {
    if (_withdrawingLocation) return;
    if (!await requireLogin(context, ref) || !mounted) return;
    final confirmed = await cyConfirm(
      context,
      title: '撤回地点？',
      content: '撤回后，这条帖文不再展示地点；正文和图片保持不变。',
      confirmText: '撤回地点',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _withdrawingLocation = true);
    try {
      await ref
          .read(squareApiProvider)
          .withdrawLocation(post.id, version: post.version);
      ref.invalidate(squareDetailProvider(widget.postId));
      ref.invalidate(squareListProvider);
      ref.invalidate(squareFollowingListProvider);
      ref.invalidate(squareFeedProvider);
      _toast('地点已撤回');
    } catch (error) {
      _toast(error.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _withdrawingLocation = false);
    }
  }

  List<Comment> _threaded(List<Comment> comments) {
    final roots = comments.where((Comment c) => c.parentId == null).toList()
      ..sort((Comment a, Comment b) => b.id.compareTo(a.id));
    final byRoot = <int, List<Comment>>{};
    final orphans = <Comment>[];
    final rootIds = roots.map((Comment c) => c.id).toSet();
    for (final comment in comments.where((Comment c) => c.parentId != null)) {
      final rootId = comment.rootId ?? comment.parentId;
      if (rootId != null && rootIds.contains(rootId)) {
        byRoot.putIfAbsent(rootId, () => <Comment>[]).add(comment);
      } else {
        orphans.add(comment);
      }
    }
    final ordered = <Comment>[];
    for (final root in roots) {
      ordered.add(root);
      final replies = byRoot[root.id] ?? <Comment>[];
      replies.sort((Comment a, Comment b) => a.id.compareTo(b.id));
      ordered.addAll(replies);
    }
    orphans.sort((Comment a, Comment b) => b.id.compareTo(a.id));
    ordered.addAll(orphans);
    return ordered;
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(squareDetailProvider(widget.postId));
    final currentUser = ref.watch(authControllerProvider).user;
    final bool isOwner =
        detail.asData?.value.memberId ==
        ref.watch(authControllerProvider).user?.id;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('动态详情'),
        // 自己的动态显示删除，别人的显示举报；真正的权限仍由后端判定。
        trailing: isOwner
            ? Semantics(
                button: true,
                label: '删除',
                child: CupertinoButton(
                  onPressed: _delete,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  child: const Icon(CupertinoIcons.delete),
                ),
              )
            : Semantics(
                button: true,
                label: '举报',
                child: CupertinoButton(
                  onPressed: _report,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  child: const Icon(CupertinoIcons.flag),
                ),
              ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: detail.when(
                  loading: () => const CySkeleton(type: CySkeletonType.detail),
                  error: (Object err, StackTrace st) => StatusView(
                    message: '详情拉取失败',
                    icon: CupertinoIcons.exclamationmark_triangle,
                    onRetry: () =>
                        ref.invalidate(squareDetailProvider(widget.postId)),
                  ),
                  data: (SquarePost post) {
                    _scheduleContentTracking();
                    return Column(
                      children: <Widget>[
                        Expanded(
                          child: NotificationListener<ScrollNotification>(
                            onNotification: _handleDetailScroll,
                            child: _body(post),
                          ),
                        ),
                        // ★ 回复态横一条在输入框上方 —— 不显示的话用户不知道
                        //   这条会挂到谁下面,而发出去就改不了了。
                        if (post.viewerCanComment && _replyTo != null)
                          _ReplyingBar(
                            name:
                                (_replyTo!.memberNickname ?? '').trim().isEmpty
                                ? '城瘾用户'
                                : _replyTo!.memberNickname!.trim(),
                            onCancel: () => setState(() => _replyTo = null),
                          ),
                        if (post.viewerCanComment)
                          _InputBar(
                            controller: _input,
                            focusNode: _inputFocus,
                            sending: _sending,
                            onSend: _send,
                            hint: _replyTo == null ? null : '回复评论',
                            avatar: currentUser?.avatar,
                            nickname: currentUser?.nickname,
                          )
                        else
                          const SafeArea(
                            top: false,
                            child: Padding(
                              padding: EdgeInsets.all(CyTokens.space3),
                              child: Text(
                                '作者限制了谁可以回复',
                                key: Key('square-comment-disabled'),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
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

  Widget _body(SquarePost post) {
    final comments = ref.watch(squareCommentsProvider(widget.postId));
    final currentUser = ref.watch(authControllerProvider).user;
    final isOwner = post.memberId == currentUser?.id;
    final textTheme = Theme.of(context).textTheme;
    return RefreshIndicator.adaptive(
      onRefresh: () async {
        ref.invalidate(squareDetailProvider(widget.postId));
        _refreshComments();
      },
      child: ListView(
        padding: const EdgeInsets.all(CyTokens.space4),
        children: <Widget>[
          KeyedSubtree(
            key: const Key('square-detail-author'),
            child: _AuthorRow(
              post: post,
              nickname: post.memberNickname,
              avatar: post.memberAvatar,
              createTime: post.createTime,
              followBusy: _followBusy,
              onFollow:
                  post.memberId != currentUser?.id && post.isFollowTheUser == 0
                  ? () => _followAuthor(post)
                  : null,
            ),
          ),
          if (post.pics.isNotEmpty) const SizedBox(height: CyTokens.space2),
          if (post.pics.isNotEmpty)
            KeyedSubtree(
              key: const Key('square-detail-media'),
              child: Column(
                children: <Widget>[
                  for (int index = 0; index < post.pics.length; index++) ...[
                    if (index > 0) const SizedBox(height: CyTokens.space2_5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                      child: AspectRatio(
                        aspectRatio: 16 / 10,
                        child: _DetailPic(pics: post.pics, index: index),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (post.pics.isNotEmpty) const SizedBox(height: CyTokens.space2),
          KeyedSubtree(
            key: const Key('square-detail-actions'),
            child: _DetailActionRow(
              liked: _reactions.display(post).liked,
              likeNum: _reactions.display(post).likeNum,
              commentCount: post.commentCount,
              onLike: () => _toggleLike(post),
              onComment: () => FocusScope.of(context).requestFocus(_inputFocus),
              onShare: (BuildContext anchor) => _sharePost(post, anchor),
            ),
          ),
          const SizedBox(height: CyTokens.space2),
          if (isOwner) ...<Widget>[
            const SizedBox(height: CyTokens.space1),
            Row(
              children: <Widget>[
                CupertinoButton(
                  key: const Key('square-post-edit'),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  onPressed: () => _edit(post),
                  child: const Text('编辑'),
                ),
                const SizedBox(width: CyTokens.space3),
                CupertinoButton(
                  key: const Key('square-post-revisions'),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  onPressed: () => _showRevisions(post),
                  child: const Text('编辑记录'),
                ),
              ],
            ),
          ],
          if (post.safetyLabels.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Wrap(
              spacing: CyTokens.space2,
              runSpacing: CyTokens.space1,
              children: post.safetyLabels
                  .map(
                    (label) => Text(
                      '⚠ ${squareSafetyLabelText(label)}',
                      style: textTheme.labelMedium?.copyWith(
                        color: CyTokens.statusWarning,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          if ((post.contents?.isNotEmpty ?? false)) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            SquarePostContent(
              key: const Key('square-detail-content'),
              text: post.contents!,
              style: textTheme.bodyLarge,
              // 详情页是整页阅读:正文全部铺开,不做二次展开。
              expandable: false,
            ),
          ],
          if (post.canRemixTopicTemplate) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            SquareTopicTemplateRemix(post: post),
          ],
          if ((post.address?.isNotEmpty ?? false)) ...<Widget>[
            const SizedBox(height: CyTokens.space2_5),
            Row(
              children: <Widget>[
                const Icon(
                  Icons.place_outlined,
                  size: 15,
                  color: AppColors.textDisabled,
                ),
                const SizedBox(width: CyTokens.space1),
                Expanded(
                  child: Text(
                    post.address!,
                    style: textTheme.labelMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                if (isOwner)
                  CupertinoButton(
                    key: const Key('square-location-withdraw'),
                    padding: const EdgeInsets.only(left: CyTokens.space2),
                    onPressed: _withdrawingLocation
                        ? null
                        : () => _withdrawLocation(post),
                    child: _withdrawingLocation
                        ? const CupertinoActivityIndicator()
                        : const Text('撤回'),
                  ),
              ],
            ),
          ],
          KeyedSubtree(key: _contentEndKey, child: const SizedBox.shrink()),
          const Divider(height: 32, color: AppColors.divider),
          Text(
            '评论 ${post.commentCount}',
            key: const Key('square-detail-comments'),
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: CyTokens.space2),
          comments.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: CyTokens.space5),
              child: CySkeleton(type: CySkeletonType.list, count: 3),
            ),
            error: (Object err, StackTrace st) => StatusView(
              message: '评论拉取失败',
              icon: CupertinoIcons.exclamationmark_triangle,
              onRetry: () =>
                  ref.invalidate(squareCommentsProvider(widget.postId)),
            ),
            data: (List<Comment> list) {
              final loaded = <Comment>[...list, ..._extraComments];
              // 服务端追上本地预期后撤掉覆盖(撤掉那一刻渲染值不变)。
              _commentReactions.reconcile(loaded);
              final threaded = _threaded(loaded);
              if (loaded.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: CyTokens.space5,
                  ),
                  child: Center(
                    child: Text(
                      '还没有评论,来抢沙发',
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                );
              }
              return Column(
                children: <Widget>[
                  for (final Comment c in threaded)
                    _CommentTile(
                      comment: _commentReactions.display(c),
                      replyToName: squareReplyToName(c, loaded),
                      indented: c.parentId != null,
                      onReport: c.memberId == currentUser?.id
                          ? null
                          : () => _reportComment(c.id),
                      onLike: () => _likeComment(c),
                      onApprove: isOwner && c.approvalState == 'PENDING'
                          ? () => _approveComment(c)
                          : null,
                      // ⚠️ 只给评论作者:后端 `/api/comment/delete` 的归属校验
                      //   就是评论作者本人(`无权删除该评论`),小程序也只给
                      //   `item.memberId == userId`。给楼主动任何评论的删除入口,
                      //   点了必失败 —— 那不是权限,是一个必然报错的按钮。
                      onDelete: c.memberId == currentUser?.id
                          ? () => _deleteComment(c)
                          : null,
                      onReply: post.viewerCanComment
                          ? () {
                              setState(() => _replyTo = c);
                              FocusScope.of(context).requestFocus(_inputFocus);
                            }
                          : null,
                    ),
                  if (!_commentsExhausted &&
                      (list.length >= kSquareCommentsPageSize ||
                          _extraComments.isNotEmpty))
                    CupertinoButton(
                      key: const Key('square-comments-load-more'),
                      onPressed: _loadingMoreComments
                          ? null
                          : () => _loadMoreComments(loaded),
                      child: _loadingMoreComments
                          ? const CupertinoActivityIndicator()
                          : const Text('加载更多回复'),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DetailActionRow extends StatelessWidget {
  const _DetailActionRow({
    required this.liked,
    required this.likeNum,
    required this.commentCount,
    required this.onLike,
    required this.onComment,
    required this.onShare,
  });
  final bool liked;
  final int likeNum;
  final int commentCount;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final ValueChanged<BuildContext> onShare;

  @override
  Widget build(BuildContext context) {
    final Color secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: <Widget>[
        Semantics(
          button: true,
          label: liked ? '取消点赞，当前 $likeNum 个赞' : '点赞，当前 $likeNum 个赞',
          child: CupertinoButton(
            key: const Key('square-detail-like-action'),
            padding: const EdgeInsets.only(right: CyTokens.space4),
            minimumSize: const Size(44, 44),
            onPressed: onLike,
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    liked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                    size: 20,
                    color: liked ? CyTokens.statusDanger : secondary,
                  ),
                  if (likeNum > 0) ...<Widget>[
                    const SizedBox(width: CyTokens.space1),
                    Text('$likeNum'),
                  ],
                ],
              ),
            ),
          ),
        ),
        Semantics(
          button: true,
          label: '评论，当前 $commentCount 条',
          child: CupertinoButton(
            key: const Key('square-detail-comment-action'),
            padding: const EdgeInsets.only(right: CyTokens.space4),
            minimumSize: const Size(44, 44),
            onPressed: onComment,
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(CupertinoIcons.chat_bubble, size: 20, color: secondary),
                  if (commentCount > 0) ...<Widget>[
                    const SizedBox(width: CyTokens.space1),
                    Text('$commentCount'),
                  ],
                ],
              ),
            ),
          ),
        ),
        Semantics(
          button: true,
          label: '分享这条动态',
          child: Builder(
            builder: (BuildContext anchorContext) => CupertinoButton(
              key: const Key('square-detail-share-action'),
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: () => onShare(anchorContext),
              child: ExcludeSemantics(
                child: Icon(
                  CupertinoIcons.paperplane,
                  size: 20,
                  color: secondary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.onReport,
    required this.onLike,
    required this.onReply,
    this.indented = false,
    this.replyToName,
    this.onApprove,
    this.onDelete,
  });

  /// 回复这条评论。
  final VoidCallback? onReply;
  final Comment comment;
  final bool indented;

  /// 楼中楼:它是在回谁(解不出来时不显示,见 `squareReplyToName`)。
  final String? replyToName;

  /// 给这条评论点赞 / 取消赞。
  final VoidCallback onLike;
  final VoidCallback? onApprove;
  final VoidCallback? onDelete;

  /// 举报这条评论。★ 评论也是 UGC,Apple 1.2 同样覆盖 ——
  ///   只给动态举报、评论没有,审核照样会挑出来。
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(
        left: indented ? CyTokens.space5 : 0,
        top: CyTokens.space2,
        bottom: CyTokens.space2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Avatar(url: comment.memberAvatar, name: comment.memberNickname),
          const SizedBox(width: CyTokens.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        (comment.memberNickname?.isNotEmpty ?? false)
                            ? comment.memberNickname!
                            : '城瘾用户',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall,
                      ),
                    ),
                    if ((comment.createTime?.isNotEmpty ?? false))
                      Text(
                        comment.createTime!,
                        style: textTheme.labelSmall?.copyWith(
                          color: AppColors.textDisabled,
                        ),
                      ),
                    if (onReport != null)
                      Semantics(
                        button: true,
                        label: '举报这条评论',
                        child: CupertinoButton(
                          onPressed: onReport,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(44, 44),
                          child: const Icon(
                            CupertinoIcons.flag,
                            size: 16,
                            color: AppColors.textDisabled,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                if ((replyToName ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '回复 @$replyToName',
                      key: Key('comment-reply-quote-${comment.id}'),
                      style: textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                if ((comment.contents?.isNotEmpty ?? false))
                  Text(comment.contents!, style: textTheme.bodyMedium),
                if (comment.lifecycle == 'CHECKING' ||
                    comment.approvalState == 'PENDING')
                  Padding(
                    padding: const EdgeInsets.only(top: CyTokens.space1),
                    child: Text(
                      comment.lifecycle == 'CHECKING' ? '平台审核中' : '待作者确认后公开',
                      style: textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                Row(
                  children: <Widget>[
                    _CommentLike(comment: comment, onTap: onLike),
                    const SizedBox(width: CyTokens.space2),
                    // 44pt 热区。
                    if (onReply != null)
                      SizedBox(
                        height: 44,
                        child: CupertinoButton(
                          key: Key('comment-reply-${comment.id}'),
                          onPressed: onReply,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(44, 44),
                          child: Text(
                            '回复',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: AppColors.textDisabled),
                          ),
                        ),
                      ),
                    if (onApprove != null)
                      CupertinoButton(
                        onPressed: onApprove,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(44, 44),
                        child: const Text('通过'),
                      ),
                    if (onDelete != null)
                      CupertinoButton(
                        onPressed: onDelete,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(44, 44),
                        child: const Text('删除'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部发评论输入框。
class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
    this.focusNode,
    this.hint,
    this.avatar,
    this.nickname,
  });
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final FocusNode? focusNode;

  /// 回复态换个占位文案,和发顶层评论区分开。
  final String? hint;
  final String? avatar;
  final String? nickname;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CyTokens.space3,
          vertical: CyTokens.space2,
        ),
        decoration: const BoxDecoration(
          color: AppColors.bgSurface,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: <Widget>[
            if (hint == null) ...<Widget>[
              _Avatar(url: avatar, name: nickname, size: 40),
              const SizedBox(width: CyTokens.space2),
            ],
            Expanded(
              child: CupertinoTextField(
                key: const Key('square-comment-input'),
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                keyboardType: TextInputType.text,
                autocorrect: true,
                enableSuggestions: true,
                onSubmitted: (_) => onSend(),
                placeholder: hint ?? '留下你的评论',
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.space3,
                  vertical: CyTokens.space2,
                ),
                decoration: BoxDecoration(
                  color: CyTokens.bgPage,
                  borderRadius: BorderRadius.circular(CyTokens.radiusLg),
                ),
              ),
            ),
            const SizedBox(width: CyTokens.space2),
            if (sending)
              const SizedBox(
                width: 44,
                height: 44,
                child: CupertinoActivityIndicator(),
              )
            else
              CupertinoButton(
                key: const Key('square-comment-send'),
                onPressed: onSend,
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                child: const Icon(
                  CupertinoIcons.paperplane_fill,
                  color: AppColors.primary,
                  semanticLabel: '发送评论',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 作者头像 + 昵称 + 身份徽章 + 俱乐部 + 时间 + 关注(详情页内复用)。
///
/// ★ 真源 `pages/square/detail/index.wxml:27-46` 表头逐项对齐:
///   头像 · 昵称 · 时间(无条件出)· 未关注且不是自己时给「关注」。
///   徽章来自 `components/cy/post-card/index.wxml:22-25`(详情页复用同一组件)。
class _AuthorRow extends StatelessWidget {
  const _AuthorRow({
    required this.post,
    required this.nickname,
    required this.avatar,
    required this.createTime,
    this.followBusy = false,
    this.onFollow,
  });
  final SquarePost post;
  final String? nickname;
  final String? avatar;
  final String? createTime;
  final bool followBusy;
  final VoidCallback? onFollow;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final CyPalette palette = CyPalette.of(context);
    return Row(
      children: <Widget>[
        _Avatar(url: avatar, name: nickname),
        const SizedBox(width: CyTokens.space2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      (nickname?.isNotEmpty ?? false) ? nickname! : '城瘾用户',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall,
                    ),
                  ),
                  if (SquareAuthorBadges.anyOf(post)) ...<Widget>[
                    const SizedBox(width: CyTokens.space1),
                    Flexible(child: SquareAuthorBadges(post: post)),
                  ],
                ],
              ),
              if ((post.clubName ?? '').trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: CyTokens.space1),
                SquareClubLink(post: post),
              ],
            ],
          ),
        ),
        if ((createTime?.isNotEmpty ?? false))
          Text(
            createTime!,
            style: textTheme.labelSmall?.copyWith(
              color: AppColors.textDisabled,
            ),
          ),
        if (onFollow != null) ...<Widget>[
          const SizedBox(width: CyTokens.space2),
          CupertinoButton(
            key: const Key('square-detail-follow'),
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
            minimumSize: const Size(44, 44),
            onPressed: followBusy ? null : onFollow,
            child: Text(
              '关注',
              style: textTheme.labelLarge?.copyWith(
                color: palette.brand,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name, this.size = 32});
  final String? url;
  final String? name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.bgElevated,
        shape: BoxShape.circle,
      ),
      child: Text(
        (name?.isNotEmpty ?? false) ? name!.characters.first : '瘾',
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: AppColors.primary),
      ),
    );
    if (url == null || url!.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

/// 详情页里的单张图:点开全屏查看器(翻页看完整组图)。
class _DetailPic extends StatelessWidget {
  const _DetailPic({required this.pics, required this.index});

  final List<String> pics;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '查看第 ${index + 1} 张图片，共 ${pics.length} 张',
      child: CupertinoButton(
        key: Key('square-detail-pic-$index'),
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
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      errorBuilder: (_, _, _) => Container(
        height: 160,
        color: AppColors.bgElevated,
        alignment: Alignment.center,
        child: const Icon(
          Icons.broken_image_outlined,
          color: AppColors.textDisabled,
          size: 28,
        ),
      ),
    );
  }
}

class _CommentLike extends StatelessWidget {
  const _CommentLike({required this.comment, required this.onTap});
  final Comment comment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: CupertinoButton(
        key: Key('comment-like-${comment.id}'),
        onPressed: onTap,
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        // 44pt 最小触达:图标只有 14pt,不撑热区会点不中。
        child: Container(
          height: 44,
          padding: const EdgeInsets.only(right: CyTokens.space2),
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                comment.liked ? Icons.favorite : Icons.favorite_border,
                size: 14,
                // 已赞用主色,未赞用禁用色 —— 状态不只靠形状,
                // 但形状(实心/空心)也在,不是只靠颜色。
                color: comment.liked
                    ? AppColors.primary
                    : AppColors.textDisabled,
              ),
              const SizedBox(width: 4),
              Text(
                // ★ 0 也照常显示 —— 小程序那边是 `{{item.likeCount || 0}}`,
                //   藏起来会让「还没人赞」和「不能赞」长得一样。
                '${comment.likeCount}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: comment.liked
                      ? AppColors.primary
                      : AppColors.textDisabled,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「正在回复 @某某」那一条。
class _ReplyingBar extends StatelessWidget {
  const _ReplyingBar({required this.name, required this.onCancel});
  final String name;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('replying-bar'),
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space3,
        vertical: CyTokens.space1,
      ),
      color: AppColors.bgElevated,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '回复 @$name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          // 44pt 热区:退出回复态是个高频动作,点不中会误发成顶层评论。
          SizedBox(
            width: 44,
            height: 44,
            child: CupertinoButton(
              key: const Key('replying-cancel'),
              onPressed: onCancel,
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              child: const Icon(
                CupertinoIcons.xmark,
                size: 14,
                color: AppColors.textDisabled,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
