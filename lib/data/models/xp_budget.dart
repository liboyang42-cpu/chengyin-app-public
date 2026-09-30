/// 主题 XP 预算总览(`/api/topic/xp-budget`)。
///
/// ★ 后端契约:`Σ节点xp ≤ xp_budget`,返回
///   `{budget, totalXp, over(bool), overBy, remain, perNode:[{nodeId,name,xp}]}`
///   (IXpBudgetService.computeBudget 的 javadoc)。
///
/// ★ **App 此前完全没接这条** —— 创作者在发布页看不到自己分配了多少 XP、
///   还剩多少、有没有超。超了只能等**提交之后**被后端拒,
///   而那时他已经填完整个表单了。这是典型的「校验只在服务端、
///   前端连个进度条都没有」。
class XpBudget {
  const XpBudget({
    this.budget = 0,
    this.totalXp = 0,
    this.over = false,
    this.overBy = 0,
    this.remain = 0,
    this.perNode = const <XpNodeShare>[],
  });

  /// 本主题的 XP 预算上限。
  final int budget;

  /// 已分配到节点的 XP 总和。
  final int totalXp;

  /// 是否超预算。★ **以后端的 `over` 为准,不要前端自己比大小** ——
  /// 边界(相等算不算超)、以及将来可能出现的豁免规则都在服务端,
  /// 前端算一遍就多一个会漂移的判据。
  final bool over;

  /// 超出多少。未超时是 0。
  final int overBy;

  /// 未分配的部分 —— 按契约它会成为**通关奖励**,不是"浪费掉的额度"。
  /// 界面别写成「剩余未使用」,那会让创作者以为该把它分光。
  final int remain;

  final List<XpNodeShare> perNode;

  /// 分配比例(0~1)。budget 为 0 时返回 null ——
  /// ★ 不返回 0:「没有预算」和「预算用了 0%」是两回事,
  ///   前者根本不该画进度条。
  double? get usedRatio {
    if (budget <= 0) return null;
    return totalXp / budget;
  }

  factory XpBudget.fromJson(Map<String, dynamic> json) {
    int i(String k) => (json[k] as num?)?.toInt() ?? 0;
    return XpBudget(
      budget: i('budget'),
      totalXp: i('totalXp'),
      over: json['over'] == true,
      overBy: i('overBy'),
      remain: i('remain'),
      perNode: ((json['perNode'] as List<dynamic>?) ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(XpNodeShare.fromJson)
          .toList(),
    );
  }
}

/// 单个节点分到的 XP。
class XpNodeShare {
  const XpNodeShare({required this.nodeId, this.name, this.xp = 0});

  final int nodeId;

  /// 节点名。拿不到时界面显示 `#nodeId`,别渲一个空行让人不知道是哪个点。
  final String? name;

  final int xp;

  String get label {
    final String n = (name ?? '').trim();
    return n.isEmpty ? '#$nodeId' : n;
  }

  factory XpNodeShare.fromJson(Map<String, dynamic> json) {
    final String n = (json['name'] ?? '').toString().trim();
    return XpNodeShare(
      nodeId: (json['nodeId'] as num?)?.toInt() ?? 0,
      name: n.isEmpty ? null : n,
      xp: (json['xp'] as num?)?.toInt() ?? 0,
    );
  }
}
