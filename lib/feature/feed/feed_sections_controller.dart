import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/models/banner.dart';
import '../../data/models/activity.dart';
import '../../data/models/topic.dart';
import '../../data/models/upcoming_activity.dart';

/// 首页各分区独立加载、各自三态。均为只读拉取(无分页),用 FutureProvider。

/// 1. Banner 轮播:/api/common/banner showType=1 linkType=0(玩家)。
final feedBannerProvider = FutureProvider.autoDispose<List<HomeBanner>>((
  ref,
) async {
  return ref.watch(bannerApiProvider).list(showType: 1, linkType: 0);
});

/// 2. 推荐主题:topic/list recommend:true(横向卡片)。
final feedRecommendProvider = FutureProvider.autoDispose<List<Topic>>((
  ref,
) async {
  return ref
      .watch(topicApiProvider)
      .list(recommend: true, pageNum: 1, pageSize: 10);
});

/// 3. 即将上线 + 倒计时:activity/list is_my=2,解析 startDate。
final feedUpcomingProvider = FutureProvider.autoDispose<List<UpcomingActivity>>(
  (ref) async {
    return ref.watch(feedSectionApiProvider).upcoming(pageNum: 1, pageSize: 6);
  },
);

/// 4. 附近活动:activity/list sort_type:2(时间排序兜底,无 GPS 不传经纬度)。
final feedNearbyProvider = FutureProvider.autoDispose<List<Activity>>((
  ref,
) async {
  return ref
      .watch(activityApiProvider)
      .list(sortType: '2', pageNum: 1, pageSize: 6);
});

/// 首页底部“活动”流，与主题流并列；不复用附近 6 条切片冒充完整列表。
final feedActivityStreamProvider = FutureProvider.autoDispose<List<Activity>>((
  ref,
) async {
  return ref.watch(activityApiProvider).list(pageNum: 1, pageSize: 10);
});
