import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/models/activity.dart';

/// 活动列表(isMy=0 所有已通过),按 App 范围收窄到 ③ 探店日。
///
/// ★ 只在**列表页这一层**筛,不动 ActivityApi.list() —— 地图等其他调用方
///   可能需要全量数据,在 API 层一刀切会波及它们。
/// ★ 判据 shouldShowInApp 是「排除明确的 ①」而非「只留明确的 ③」:
///   生产存在 product_type 为 NULL 的存量主题(第 0 批 0-5 待回填),
///   严格筛会把本该展示的局藏掉,与票夹同一口径。
final activityListProvider = FutureProvider.autoDispose<List<Activity>>((
  ref,
) async {
  final all = await ref.watch(activityApiProvider).list();
  return all.where((Activity a) => a.shouldShowInApp).toList();
});

/// 活动详情(按 id)。报名成功后 invalidate 刷新。
final activityDetailProvider = FutureProvider.autoDispose
    .family<ActivityDetail, int>((ref, id) {
      return ref.watch(activityApiProvider).info(id);
    });

/// 我报名的活动(ownerType==2)。
final myJoinedActivitiesProvider =
    FutureProvider.autoDispose<List<MyRegistration>>((ref) {
      return ref.watch(activityApiProvider).myJoined();
    });
