/// 我完成过的一局。对齐后端 `ApiPlayProgressController.myCompleted`
/// (/api/play/my-completed)。
class CompletedPlay {
  const CompletedPlay({
    required this.name,
    this.activityId,
    this.topicId,
    this.cover,
    this.dataType = 1,
    this.total = 0,
    this.doneCount = 0,
    this.completed = false,
  });

  final String name;

  /// 活动 id 与主题 id。★ **两者都可能为空** —— 自由探索没有 activityId,
  ///   跳转前必须判,不然会跳到 /activity/0。
  final int? activityId;
  final int? topicId;

  final String? cover;

  /// 1 活动 / 2 主题(自由探索)。
  final int dataType;

  final int total;
  final int doneCount;
  final bool completed;

  /// 进度文案。把「状态」和「界面说了什么」列成表之后才发现原来三档同一句话:
  ///
  ///   | doneCount | completed | 原文案    | 现在说            |
  ///   |-----------|-----------|-----------|-------------------|
  ///   | 6 / 6     | true      | 6 / 6 个点 | 已走完 · 6 个点    |
  ///   | 3 / 8     | false     | 3 / 8 个点 | 还差 5 个点        |
  ///   | 0 / 5     | false     | 0 / 5 个点 | 还没开始 · 共 5 个点 |
  ///
  /// ★ 原来三档渲出来一模一样,状态全靠用户自己心算;而这页叫「我走过的」,
  ///   里面却混着一条**一个点都没走**的 —— 「0 / 5 个点」读起来像已经在走了。
  /// ★ `completed` 字段一直解析着,但**没有任何人消费** —— 后端明明说了这局完没完,
  ///   界面上却看不出来。
  ///
  /// total 为 0 时仍然不显示:「0/0」既没信息,又让人以为这局是空的。
  String? get progressText {
    if (total <= 0) return null;
    if (completed || doneCount >= total) return '已走完 · $total 个点';
    if (doneCount <= 0) return '还没开始 · 共 $total 个点';
    // 说「还差几个」比说「已走几个」更接近用户下一步要做的事
    return '还差 ${total - doneCount} 个点 · 已走 $doneCount';
  }

  /// 详情落点。★ 拿不到可用 id 时返回 null,调用方据此**不给跳转** ——
  ///   跳到 /activity/0 会进一个永远加载失败的页面。
  String? get route {
    if (activityId != null && activityId! > 0) return '/activity/$activityId';
    if (topicId != null && topicId! > 0) return '/topic/$topicId';
    return null;
  }

  factory CompletedPlay.fromJson(Map<String, dynamic> json) {
    return CompletedPlay(
      name: ((json['name'] as String?) ?? '').trim().isEmpty
          ? '未命名'
          : (json['name'] as String).trim(),
      activityId: (json['activityId'] as num?)?.toInt(),
      topicId: (json['topicId'] as num?)?.toInt(),
      cover: json['cover'] as String?,
      dataType: (json['dataType'] as num?)?.toInt() ?? 1,
      total: (json['total'] as num?)?.toInt() ?? 0,
      doneCount: (json['doneCount'] as num?)?.toInt() ?? 0,
      completed: json['completed'] == true,
    );
  }
}
