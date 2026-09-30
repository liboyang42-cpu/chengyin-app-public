import '../../data/models/square_post.dart';

/// 点赞 / 收藏的**乐观更新**层。
///
/// ★ 为什么要它:后端 `setAction` 是**切换式**的(已赞再调一次就是取消),
///   调完只能靠 invalidate 重拉 —— 一次点赞要等一个来回才变色,
///   失败则连个影子都留不下。App 侧把它改成:本地先落预期(即时反馈),
///   请求失败**原样回滚**(不留下假的已赞态)。
///
/// ★ 回滚凭什么可信:覆盖层只在请求在途/刚失败时存在。
///   成功路径由 [reconcile] 在服务端数据追上来之后撤掉覆盖 ——
///   撤掉那一刻渲染值与覆盖值相同(所以才撤),不会闪回旧态。
class SquarePostReactions {
  final Map<int, SquarePost> _overrides = <int, SquarePost>{};

  bool get hasPending => _overrides.isNotEmpty;

  /// 渲染用:有本地预期就用本地预期。
  SquarePost display(SquarePost post) => _overrides[post.id] ?? post;

  /// 记一次点赞态变化,返回叠加后的帖子(已处理重复点击的加减)。
  SquarePost applyLike(SquarePost post, {required bool liked}) {
    final SquarePost base = display(post);
    final int delta = liked == base.liked ? 0 : (liked ? 1 : -1);
    final SquarePost next = base.copyWith(
      isLiked: liked ? 1 : 0,
      likeNum: base.likeNum + delta < 0 ? 0 : base.likeNum + delta,
    );
    _overrides[post.id] = next;
    return next;
  }

  /// 记一次收藏态变化,返回叠加后的帖子。
  SquarePost applyBookmark(SquarePost post, {required bool bookmarked}) {
    final SquarePost next = display(post).copyWith(bookmarked: bookmarked);
    _overrides[post.id] = next;
    return next;
  }

  /// 请求失败/被拒 → 回滚到服务端态。
  void rollback(int postId) => _overrides.remove(postId);

  /// 服务端数据已经等于本地预期 → 撤掉覆盖,交还给服务端。
  bool reconcile(Iterable<SquarePost> serverPosts) {
    bool changed = false;
    for (final SquarePost server in serverPosts) {
      final SquarePost? local = _overrides[server.id];
      if (local == null) continue;
      if (server.isLiked == local.isLiked &&
          server.likeNum == local.likeNum &&
          server.bookmarked == local.bookmarked) {
        _overrides.remove(server.id);
        changed = true;
      }
    }
    return changed;
  }
}

/// 评论点赞的乐观更新层(同一套约定,见 [SquarePostReactions])。
class SquareCommentReactions {
  final Map<int, Comment> _overrides = <int, Comment>{};

  bool get hasPending => _overrides.isNotEmpty;

  Comment display(Comment comment) => _overrides[comment.id] ?? comment;

  Comment applyLike(Comment comment, {required bool liked}) {
    final Comment base = display(comment);
    final int delta = liked == base.liked ? 0 : (liked ? 1 : -1);
    final Comment next = base.copyWith(
      isLiked: liked ? 1 : 0,
      likeCount: base.likeCount + delta < 0 ? 0 : base.likeCount + delta,
    );
    _overrides[comment.id] = next;
    return next;
  }

  void rollback(int commentId) => _overrides.remove(commentId);

  bool reconcile(Iterable<Comment> serverComments) {
    bool changed = false;
    for (final Comment server in serverComments) {
      final Comment? local = _overrides[server.id];
      if (local == null) continue;
      if (server.isLiked == local.isLiked &&
          server.likeCount == local.likeCount) {
        _overrides.remove(server.id);
        changed = true;
      }
    }
    return changed;
  }
}

/// 帖子点赞的**串行队列**。
///
/// ★ 为什么不能只靠「请求在途就禁用按钮」:禁用等于把第二次点击吞掉 ——
///   用户点快了(赞→取消赞)会看到「点了没反应」。允许点,但同一目标
///   只让一个请求在跑;跑的过程中点出来的新期望登记下来,
///   由在跑的那一轮收尾时补发。响应乱序也就不会把状态停在错误的一边。
class SquareLikeQueue {
  final Map<int, bool> _desired = <int, bool>{};
  final Set<int> _running = <int>{};

  bool isRunning(int postId) => _running.contains(postId);

  /// 返回**最终落定**的期望态;若已有请求在跑,返回 null(它收尾时会补发)。
  /// 发送失败会把登记清掉并原样抛出,由调用方负责回滚本地预期。
  Future<bool?> submit(
    int postId, {
    required bool want,
    required Future<void> Function(bool want) send,
  }) async {
    _desired[postId] = want;
    if (_running.contains(postId)) return null;
    _running.add(postId);
    try {
      bool applied = want;
      while (true) {
        final bool target = _desired[postId] ?? applied;
        await send(target);
        applied = target;
        if (_desired[postId] == target) break;
      }
      _desired.remove(postId);
      return applied;
    } catch (_) {
      _desired.remove(postId);
      rethrow;
    } finally {
      _running.remove(postId);
    }
  }
}
