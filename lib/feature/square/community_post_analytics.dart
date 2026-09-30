import '../../core/analytics/tracker.dart';
import 'package:share_plus/share_plus.dart';

/// 广场帖文最小可聚合事件合同。
///
/// 只记录已经发生的正向动作；取消赞/取消收藏不伪装成一次新转化。
/// 文本和位置不进入 properties；登录用户身份由后端在鉴权后关联，客户端不自行填充。
abstract final class CommunityPostAnalytics {
  static const String _bizType = 'community_post';

  static void impression(
    Tracker tracker,
    int postId, {
    required String feedMode,
    String pagePath = '/square',
  }) {
    tracker.track(
      'community_post_impression',
      bizType: _bizType,
      bizId: postId,
      pagePath: pagePath,
      properties: <String, dynamic>{
        'stage': 'impression',
        'feed_mode': feedMode,
      },
    );
  }

  static void opened(
    Tracker tracker,
    int postId, {
    String pagePath = '/square/:id',
  }) {
    tracker.track(
      'community_post_open',
      bizType: _bizType,
      bizId: postId,
      pagePath: pagePath,
      properties: const <String, dynamic>{'stage': 'open'},
    );
  }

  static void qualified(
    Tracker tracker,
    int postId, {
    required String qualification,
    String pagePath = '/square/:id',
  }) {
    tracker.track(
      'community_post_qualified_view',
      bizType: _bizType,
      bizId: postId,
      pagePath: pagePath,
      // actor_scope 由服务端认证态兜底区分用户；post 维度保持稳定，
      // 保证同次投递稳定；服务端会按事件日期规范化为 user-post-day，
      // 试点窗口分母再从原始日志按 user-post 去重。
      idempotencyKey: 'community-post-qualified-$postId',
      properties: <String, dynamic>{
        'stage': 'qualified',
        'qualification': qualification,
      },
    );
  }

  static bool shouldCountShare(ShareResultStatus status) =>
      status == ShareResultStatus.success;

  static bool consumedAtLeast70Percent({
    required double pixels,
    required double viewportDimension,
    required double contentExtent,
  }) {
    if (contentExtent <= 0) return false;
    return (pixels + viewportDimension) / contentExtent >= 0.7;
  }

  static void liked(
    Tracker tracker,
    int postId, {
    required bool enabled,
    String pagePath = '/square/:id',
  }) {
    if (!enabled) return;
    tracker.track(
      'content_like',
      bizType: _bizType,
      bizId: postId,
      pagePath: pagePath,
    );
  }

  static void favorited(
    Tracker tracker,
    int postId, {
    required bool enabled,
    String pagePath = '/square/:id',
  }) {
    if (!enabled) return;
    tracker.track(
      'content_favorite',
      bizType: _bizType,
      bizId: postId,
      pagePath: pagePath,
    );
  }

  static void shared(
    Tracker tracker,
    int postId, {
    String pagePath = '/square/:id',
  }) {
    tracker.track(
      'content_share',
      bizType: _bizType,
      bizId: postId,
      pagePath: pagePath,
    );
  }
}

/// 只累计同一位已登录、非作者用户的前台停留时间。
///
/// 登录态变化会清零，避免 A 用户的停留时长被 B 用户或匿名态继承。
class CommunityPostQualifiedDwell {
  int? _viewerId;
  int _seconds = 0;

  bool tick({required int? viewerId, required int? authorId}) {
    if (viewerId == null || viewerId == authorId) {
      _viewerId = null;
      _seconds = 0;
      return false;
    }
    if (_viewerId != viewerId) {
      _viewerId = viewerId;
      _seconds = 0;
    }
    _seconds++;
    return _seconds >= 10;
  }
}

/// 把“消费 70%”绑定到同一位已登录、非作者用户。
///
/// 新账号不能继承页面已有的滚动位置；它必须先自行回到正文顶部，再达到 70%。
class CommunityPostQualifiedScroll {
  int? _viewerId;
  bool _hasSeenTop = false;

  void begin({
    required int? viewerId,
    required int? authorId,
    required double pixels,
  }) {
    _syncViewer(viewerId: viewerId, authorId: authorId);
    if (_viewerId != null && pixels <= 1) _hasSeenTop = true;
  }

  bool consumed({
    required int? viewerId,
    required int? authorId,
    required double pixels,
    required double viewportDimension,
    required double contentExtent,
  }) {
    _syncViewer(viewerId: viewerId, authorId: authorId);
    if (_viewerId == null) return false;
    if (pixels <= 1) _hasSeenTop = true;
    return _hasSeenTop &&
        CommunityPostAnalytics.consumedAtLeast70Percent(
          pixels: pixels,
          viewportDimension: viewportDimension,
          contentExtent: contentExtent,
        );
  }

  void _syncViewer({required int? viewerId, required int? authorId}) {
    final int? eligibleViewer =
        viewerId == null || authorId == null || viewerId == authorId
        ? null
        : viewerId;
    if (_viewerId == eligibleViewer) return;
    _viewerId = eligibleViewer;
    _hasSeenTop = false;
  }
}

/// 页面内按账号分别记录是否已经上报过合格阅读。
class CommunityPostQualifiedMembers {
  final Set<int> _qualified = <int>{};

  bool mark({required int? viewerId, required int? authorId}) {
    if (viewerId == null || authorId == null || viewerId == authorId) {
      return false;
    }
    return _qualified.add(viewerId);
  }
}

/// 页面内每个已登录账号各记录一次打开，匿名态不产生必然被鉴权拒绝的请求。
class CommunityPostOpenedMembers {
  final Set<int> _opened = <int>{};

  bool mark(int? viewerId) => viewerId != null && _opened.add(viewerId);
}
