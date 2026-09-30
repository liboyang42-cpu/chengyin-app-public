/// 赚分任务(后台 `cms_points_setting` 的一行 + 我完成过几次)。
///
/// 来源 `POST /api/points/result_list`(ApiPointsController.resultList):
/// 后端取 type=1 的规则表,再逐条查该用户的完成次数填进 pointsNum。
///
/// ★★ 这是**积分规则的真源**。App 此前这块压根没有 —— 想赚分的用户
///   在 App 里看不到任何规则说明,而小程序早就把静态文案换成了这份动态列表。
class PointsTask {
  const PointsTask({
    required this.id,
    required this.eventType,
    required this.title,
    required this.description,
    required this.points,
    required this.doneCount,
    required this.status,
  });

  final int id;
  final int eventType;
  final String title;
  final String description;

  /// 每次给多少分。
  final int points;

  /// 我已经完成过几次。
  final int doneCount;

  /// 1 = 启用中。
  final int status;

  /// ★★ 能不能列进「怎么赚分」。两条都不能省:
  ///   · status != 1 → 规则没启用,列出来等于承诺一件做不到的事
  ///   · eventType == 14 → **解锁提示是花分规则,不是赚分任务**。
  ///     把它列进赚分列表,等于告诉用户"花分能赚分"。
  ///     (判据抄小程序 components/cy/profile 的同一处过滤,
  ///      那边注释原话:「event_type=14(解锁提示)是花分规则,不属于任务」。)
  bool get isEarnTask => status == 1 && eventType != kSpendHintUnlock;

  /// 解锁提示 —— 花分,不是赚分。
  static const int kSpendHintUnlock = 14;

  factory PointsTask.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v) => v is num ? v.toInt() : 0;
    return PointsTask(
      id: asInt(json['id']),
      eventType: asInt(json['eventType']),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      // value 后端是 BigDecimal,JSON 里可能是 12 也可能是 12.00。
      points: asInt(json['value']),
      doneCount: asInt(json['pointsNum']),
      status: asInt(json['status']),
    );
  }
}
