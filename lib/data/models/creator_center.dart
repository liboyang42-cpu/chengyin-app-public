/// 创作者中心(`/api/creator/center`)。
///
/// ★ 后端把申请状态归一成**四个字符串**(CreatorCenterServiceImpl:40-49、120-123):
///   `not_applied` 还没申请 · `pending` 审核中 · `approved` 已通过 · `rejected` 被驳回
///
/// 四态必须**各说各的**。最容易犯的错是把 `not_applied` 和 `rejected` 渲成同一屏
/// (都"不是创作者"),但对用户来说完全不同:前者该看到"去申请",
/// 后者该看到"为什么被拒 + 能不能再申请"。
library;

enum CreatorApplyStatus {
  notApplied,
  pending,
  approved,
  rejected;

  /// ★ 未知取值落到 [notApplied] 而不是抛异常 —— 后端将来加了新状态时,
  ///   页面退化成"去申请"比整页崩掉好;但**不要**落到 approved,
  ///   那会给一个没通过审核的人开放创作者能力。
  static CreatorApplyStatus parse(String? raw) {
    switch ((raw ?? '').trim()) {
      case 'approved':
        return CreatorApplyStatus.approved;
      case 'pending':
        return CreatorApplyStatus.pending;
      case 'rejected':
        return CreatorApplyStatus.rejected;
      case 'not_applied':
      default:
        return CreatorApplyStatus.notApplied;
    }
  }
}

class CreatorCenter {
  const CreatorCenter({
    required this.status,
    this.creatorName,
    this.bio,
    this.avatarUrl,
    this.rejectReason,
    this.recentIncome = const <CreatorIncomeRow>[],
    this.metric,
  });

  final CreatorApplyStatus status;
  final String? creatorName;
  final String? bio;
  final String? avatarUrl;

  /// 驳回原因。★ 被驳回却拿不到原因时是 null —— 界面要说"未说明原因",
  /// 不能空着,否则用户不知道该改什么。
  final String? rejectReason;

  final List<CreatorIncomeRow> recentIncome;

  /// 数据概览(后端 `CreatorMetricDaily`,取最近一天)。
  /// ★ 可空 —— 还没有统计过的新创作者拿不到,界面要说「—」不能兜 0:
  ///   「今天还没数据」和「一次都没被看过」不是一回事。
  final CreatorMetric? metric;

  /// 是否已经是创作者。★ 只有 approved 算 —— pending 不算。
  bool get isCreator => status == CreatorApplyStatus.approved;

  /// 能不能(重新)提交申请。审核中不能重复提交;已通过也不需要。
  bool get canApply =>
      status == CreatorApplyStatus.notApplied ||
      status == CreatorApplyStatus.rejected;

  factory CreatorCenter.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> profile =
        (json['profile'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    String? s(Object? v) {
      final String t = (v ?? '').toString().trim();
      return t.isEmpty ? null : t;
    }

    return CreatorCenter(
      status: CreatorApplyStatus.parse(json['applyStatus'] as String?),
      creatorName: s(profile['creatorName']),
      bio: s(profile['bio']),
      avatarUrl: s(profile['avatarUrl']),
      rejectReason: s(profile['rejectReason'] ?? json['rejectReason']),
      metric: json['metric'] is Map<String, dynamic>
          ? CreatorMetric.fromJson(json['metric'] as Map<String, dynamic>)
          : null,
      recentIncome: ((json['recentIncome'] as List<dynamic>?) ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(CreatorIncomeRow.fromJson)
          .toList(),
    );
  }
}

/// 创作者近期收入的一行。
class CreatorIncomeRow {
  const CreatorIncomeRow({this.date, this.amount, this.source});

  final String? date;

  /// ★ 金额保持后端字符串原样 —— 与商家结算同一条纪律:这是钱,不做二次格式化。
  final String? amount;
  final String? source;

  factory CreatorIncomeRow.fromJson(Map<String, dynamic> json) {
    String? s(String k) {
      final String t = (json[k] ?? '').toString().trim();
      return t.isEmpty ? null : t;
    }

    return CreatorIncomeRow(
      date: s('date'),
      amount: s('amount'),
      source: s('source'),
    );
  }
}

/// 创作者数据概览。★ 每格都可空 —— 缺的那格显示「—」,不兜 0。
class CreatorMetric {
  const CreatorMetric({this.contentCount, this.viewCount, this.likeCount});

  final int? contentCount;
  final int? viewCount;
  final int? likeCount;

  factory CreatorMetric.fromJson(Map<String, dynamic> json) {
    int? n(String k) => (json[k] as num?)?.toInt();
    return CreatorMetric(
      contentCount: n('contentCount'),
      viewCount: n('viewCount'),
      likeCount: n('likeCount'),
    );
  }
}
