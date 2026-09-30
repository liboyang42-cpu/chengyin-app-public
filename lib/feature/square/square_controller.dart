import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/api/square_api.dart';
import '../../data/models/square_post.dart';
import '../../data/models/community_report_reason.dart';
import '../auth/auth_controller.dart';
import 'square_local_draft_store.dart';

/// 评论 owner_type:3 = 创意广场。
const int kCommentOwnerSquare = 3;

/// 评论一页多少条。列表是 pageNum/pageSize 分页,「不满一页 = 到底了」
/// 这条判据两端(首屏与加载更多)必须用同一个数。
///
/// 为什么敢一次发 50:这条线是 RuoYi `startPage()` 口径,pageSize 原样透给
/// PageHelper、不封顶 —— 小程序自己就发过 `pageSize: 200 / 1000`。所以
/// 「服务端只返了这么多」是可信的判据;哪天被截断,这里会立刻退化成「每页都到底」。
const int kSquareCommentsPageSize = 50;

/// 广场动态流(全部)。
final squareListProvider = FutureProvider.autoDispose<List<SquarePost>>((ref) {
  return ref.watch(squareFeedProvider(SquareFeedMode.latest).future);
});

/// 广场按真实后端数据源读取；页面 tab 只切换这个 seam，不在本地伪过滤。
final squareFeedProvider = FutureProvider.autoDispose
    .family<List<SquarePost>, SquareFeedMode>((ref, mode) {
      return ref.watch(squareApiProvider).list(feedMode: mode);
    });

final squareFeedPageProvider = FutureProvider.autoDispose
    .family<SquareFeedPage, SquareFeedMode>((ref, mode) {
      return ref.watch(squareApiProvider).listPage(feedMode: mode);
    });

final squareNearbyPageProvider = FutureProvider.autoDispose
    .family<SquareFeedPage, String>((ref, cityCode) {
      return ref
          .watch(squareApiProvider)
          .listPage(feedMode: SquareFeedMode.nearby, cityCode: cityCode);
    });

final squareTopicPageProvider = FutureProvider.autoDispose
    .family<SquareFeedPage, String>((ref, topicCode) {
      return ref
          .watch(squareApiProvider)
          .listPage(feedMode: SquareFeedMode.topic, topicCode: topicCode);
    });

final squareCommunityPageProvider = FutureProvider.autoDispose
    .family<SquareFeedPage, int>((ref, communityId) {
      return ref
          .watch(squareApiProvider)
          .listPage(
            feedMode: SquareFeedMode.community,
            communityId: communityId,
          );
    });

/// 兼容既有测试和调用方的关注流命名。
final squareFollowingListProvider =
    FutureProvider.autoDispose<List<SquarePost>>(
      (ref) => ref.watch(squareFeedProvider(SquareFeedMode.following).future),
    );

/// “附近”必须带真实反查城市，禁止用 CURRENT 一类占位值污染分发。
final squareNearbyListProvider = FutureProvider.autoDispose
    .family<List<SquarePost>, String>((ref, cityCode) {
      return ref
          .watch(squareApiProvider)
          .list(feedMode: SquareFeedMode.nearby, cityCode: cityCode);
    });

/// 广场详情(按 id)。点赞后 invalidate 本 provider 刷新点赞态/数。
final squareDetailProvider = FutureProvider.autoDispose.family<SquarePost, int>(
  (ref, id) {
    return ref.watch(squareApiProvider).info(id);
  },
);

/// 某帖评论列表(按 postId)。发评论成功后 invalidate 刷新。
final squareCommentsProvider = FutureProvider.autoDispose
    .family<List<Comment>, int>((ref, postId) {
      return ref
          .watch(squareApiProvider)
          .comments(postId, limit: kSquareCommentsPageSize);
    });

final squareEnforcementsProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(squareApiProvider).myEnforcements(),
);

final squareNotificationsProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(squareApiProvider).notifications(),
);

final squareReportPolicyProvider =
    FutureProvider.autoDispose<CommunityReportPolicySnapshot>(
      (ref) => ref.watch(squareApiProvider).reportPolicy(),
    );

final squareNotificationPreferencesProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(squareApiProvider).notificationPreferences(),
);

final squareDraftsProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(squareApiProvider).drafts(),
);

/// 本机草稿清单（安全存储，随当前登录账号隔离；游客为空）。
final squareLocalDraftsProvider =
    FutureProvider.autoDispose<List<SquareLocalDraftEntry>>((ref) async {
      final memberId = ref.watch(authControllerProvider).user?.id;
      if (memberId == null || memberId <= 0) {
        return const <SquareLocalDraftEntry>[];
      }
      return ref.watch(squareLocalDraftStoreProvider).listFor(memberId);
    });
