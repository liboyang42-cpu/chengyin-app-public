import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// 附近可参加的自由探索活动(探店日)。
///
/// ★★ 后端**没有合适的时返回 `success(null)`** —— 那是**正常态**(附近没活动),
///   不是错误。所以整条链路一律「没有就没有」,不弹错误、不占位。
///
/// ⚠️ `activityId` 必须是**正整数**才算数(小程序同判据:
///   `!Number.isInteger(activityId) || activityId <= 0` 直接丢)。
///   拿一个 0 或者 null 去跳转,用户会落到一个不存在的活动页。
class NearbyExploreDay {
  const NearbyExploreDay({
    required this.activityId,
    required this.title,
    this.subtitle = '',
    this.coverImg = '',
    this.meetingPoint = '',
    this.distanceM,
  });

  final int activityId;
  final String title;
  final String subtitle;
  final String coverImg;
  final String meetingPoint;

  /// 距离(米)。★ **可空**:后端没给就是不知道,
  ///   兜 0 会显示成「距离 0 米」——那是"就在脚下",不是"不知道"。
  final int? distanceM;

  /// 距离怎么说。拿不到就不说这一行。
  String? get distanceText {
    final int? d = distanceM;
    if (d == null || d < 0) return null;
    return d < 1000 ? '$d 米' : '${(d / 1000).toStringAsFixed(1)} 公里';
  }

  /// ★ 解析失败返回 null —— 由调用方"整块不显示",不做半张卡。
  static NearbyExploreDay? tryParse(Map<String, dynamic>? json) {
    if (json == null) return null;
    final Object? raw = json['activityId'];
    final int id = raw is num ? raw.toInt() : (int.tryParse('$raw') ?? 0);
    if (id <= 0) return null;
    final String title = (json['title'] ?? '').toString().trim();
    if (title.isEmpty) return null; // 没名字的卡片点进去也不知道是什么
    final Object? d = json['distanceM'];
    return NearbyExploreDay(
      activityId: id,
      title: title,
      subtitle: (json['subtitle'] ?? '').toString().trim(),
      coverImg: (json['coverImg'] ?? '').toString().trim(),
      meetingPoint: (json['meetingPoint'] ?? '').toString().trim(),
      distanceM: d is num ? d.toInt() : null,
    );
  }
}

/// 按当前坐标找附近的探店日。★ 找不到 / 拉不到都返回 null,不抛 ——
/// 它是"顺带推荐",失败不该打断玩家正在做的事。
final nearbyExploreDayProvider = FutureProvider.autoDispose
    .family<NearbyExploreDay?, (double, double)>((Ref ref, (double, double) at) async {
  try {
    final Map<String, dynamic>? data = await ref
        .watch(roamApiProvider)
        .nearbyExploreDay(lat: at.$1, lng: at.$2);
    return NearbyExploreDay.tryParse(data);
  } catch (_) {
    return null;
  }
});
