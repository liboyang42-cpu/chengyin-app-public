/// 探店日完局面(图鉴 / 通关奖励到账明细 / 回访入口)。
///
/// 来源 `POST /api/registration/explore-completion`。**纯读**:
/// 不发奖、不补发、不写表 —— 奖励发放的唯一入口在核销侧。
///
/// ★★ 后端对非探索票的订单是 **fail-closed**:返「该订单没有探店日完局面」
///   而不是空壳,理由是「空壳会让 ①② 的订单详情也渲染出一块『图鉴 0/0』的假读面」。
///   ⇒ 调用方**不许把这个错误吞成空态渲染出来**,吞了就等于把 fail-closed 又打开。
///   正确做法:整块收起,页面回到原来的订单详情(小程序 emptyCompletion 同解)。
class ExploreCompletion {
  const ExploreCompletion({
    required this.completed,
    required this.requiredChapterCount,
    required this.redeemedChapterCount,
    required this.stamps,
    required this.awardsCredited,
    required this.awards,
    this.revisit,
  });

  final bool completed;
  final int requiredChapterCount;
  final int redeemedChapterCount;
  final List<ExploreStamp> stamps;

  /// 奖励**已到账**。★ 判据是 credited 且真有条目 —— credited=true 但
  /// items 为空,屏幕上就没东西可显示,那时仍该走"未到账"的文案。
  final bool awardsCredited;
  final List<ExploreAward> awards;
  final ExploreRevisit? revisit;

  /// 图鉴进度。requiredChapterCount 为 0 时**不显示** ——
  /// 「已集齐 0/0」不是事实,是个没有意义的分数。
  String? get stampProgressText => requiredChapterCount > 0
      ? '已集齐 $redeemedChapterCount/$requiredChapterCount'
      : null;

  /// 奖励还没到账时说什么。★ 分两种:
  ///   · 还没走完 → 说清还差什么(「走完全部 N 家店后发放」)
  ///   · 走完了但没到账 → 「发放中」,并指路去哪查
  /// 合并成一句笼统的"暂无奖励"会让已完成的用户以为白跑了。
  String? get awardsEmptyText {
    if (awardsCredited) return null;
    return completed
        ? '奖励发放中,可稍后在勋章与积分明细里查看'
        : '走完全部 $requiredChapterCount 家店后发放';
  }

  factory ExploreCompletion.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v) => v is num ? v.toInt() : 0;
    final Map<String, dynamic> awards =
        (json['awards'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final List<ExploreAward> items =
        ((awards['items'] as List<dynamic>?) ?? <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(ExploreAward.fromJson)
            .toList();
    final Map<String, dynamic>? revisit =
        json['revisit'] as Map<String, dynamic>?;
    return ExploreCompletion(
      completed: json['completed'] == true,
      requiredChapterCount: asInt(json['requiredChapterCount']),
      redeemedChapterCount: asInt(json['redeemedChapterCount']),
      stamps: ((json['stamps'] as List<dynamic>?) ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(ExploreStamp.fromJson)
          .toList(),
      awardsCredited: awards['credited'] == true && items.isNotEmpty,
      awards: items,
      // clubId 是回访块存在与否的开关(小程序同判据):没有主办俱乐部就没这块。
      revisit: (revisit != null && revisit['clubId'] != null)
          ? ExploreRevisit.fromJson(revisit)
          : null,
    );
  }
}

class ExploreStamp {
  const ExploreStamp({
    this.hasServerTitle = true,
    required this.chapterId,
    required this.title,
    required this.collected,
  });

  final bool hasServerTitle;
  final int chapterId;
  final String title;
  final bool collected;

  factory ExploreStamp.fromJson(Map<String, dynamic> json) {
    final int id = (json['chapterId'] as num?)?.toInt() ?? 0;
    final String t = (json['title'] ?? '').toString();
    return ExploreStamp(
      hasServerTitle: (json['title'] ?? '').toString().isNotEmpty,
      chapterId: id,
      // 后端没给标题时用章节号兜底,不留空行。
      title: t.isEmpty ? '章节 $id' : t,
      collected: json['collected'] == true,
    );
  }
}

class ExploreAward {
  const ExploreAward({
    required this.kind,
    required this.title,
    required this.iconUrl,
    this.amount,
  });

  final String kind;
  final String title;
  final String iconUrl;

  /// ★★ 可空。**null ≠ 0**:后端无流水时根本不下发这一项,
  ///   兜成 0 会在屏幕上造出「+0 积分」这个不存在的事实。
  final int? amount;

  /// 数量文本。没有数量的奖励(比如一枚勋章)就不显示数字。
  String? get amountText => amount == null ? null : '+$amount';

  factory ExploreAward.fromJson(Map<String, dynamic> json) => ExploreAward(
    kind: (json['kind'] ?? '').toString(),
    title: (json['title'] ?? '').toString(),
    iconUrl: (json['iconUrl'] ?? '').toString(),
    amount: (json['amount'] as num?)?.toInt(),
  );
}

class ExploreRevisit {
  const ExploreRevisit({
    this.hasServerClubName = true,
    required this.clubId,
    required this.clubName,
    this.clubLeaderMemberId,
    this.followed = false,
    this.joined = false,
    this.nextEdition,
  });

  final bool hasServerClubName;
  final int clubId;
  final String clubName;
  final int? clubLeaderMemberId;
  final bool followed;
  final bool joined;
  final ExploreNextEdition? nextEdition;

  /// 能不能关注。★ 没有 leaderMemberId 就**不给按钮** ——
  /// 关注接口要的是 member id,没有它点下去必然失败。
  bool get canFollow => !followed && clubLeaderMemberId != null;

  /// 真源 `canJoin = !joined`:没入过团就给加入钮(公开团直进、私密团进待审)。
  bool get canJoin => !joined;

  /// 真源 `hasNextEdition = !!(next && next.topicId)`:topicId 是跳转落点,
  /// 没有它这行就是纯文案,不许装成可点。
  ExploreNextEdition? get nextEditionTarget =>
      nextEdition != null && nextEdition!.topicId != 0 ? nextEdition : null;

  bool get hasNextEdition => nextEditionTarget != null;

  /// 下期回访行文案(真源 `nextEditionText`):没有下期也占行,
  /// 钮上写的就是「下一期开售后会在这里出现」。日期取 MM-DD(slice 5..10)。
  String get nextEditionText {
    final ExploreNextEdition? next = nextEditionTarget;
    if (next == null) return '下一期开售后会在这里出现';
    final String raw = next.startDate ?? '';
    final String mmdd = raw.length <= 5
        ? ''
        : raw.substring(5, raw.length < 10 ? raw.length : 10);
    return '${next.name} · $mmdd 开场';
  }

  factory ExploreRevisit.fromJson(Map<String, dynamic> json) => ExploreRevisit(
    hasServerClubName: (json['clubName'] ?? '').toString().isNotEmpty,
    clubId: (json['clubId'] as num?)?.toInt() ?? 0,
    clubName: (json['clubName'] ?? '').toString().isEmpty
        ? '主办俱乐部'
        : (json['clubName']).toString(),
    clubLeaderMemberId: (json['clubLeaderMemberId'] as num?)?.toInt(),
    followed: json['followed'] == true,
    joined: json['joined'] == true,
    nextEdition: json['nextEdition'] is Map<String, dynamic>
        ? ExploreNextEdition.fromJson(
            json['nextEdition'] as Map<String, dynamic>,
          )
        : null,
  );
}

class ExploreNextEdition {
  const ExploreNextEdition({
    this.hasServerName = true,
    required this.topicId,
    required this.name,
    this.startDate,
    this.imgUrl,
  });

  final bool hasServerName;
  final int topicId;
  final String name;
  final String? startDate;
  final String? imgUrl;

  factory ExploreNextEdition.fromJson(Map<String, dynamic> json) {
    return ExploreNextEdition(
      hasServerName: (json['name'] ?? '').toString().isNotEmpty,
      topicId: (json['topicId'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? '').toString().isEmpty
          ? '下一期'
          : json['name'].toString(),
      startDate: json['startDate']?.toString(),
      imgUrl: json['imgUrl'] as String?,
    );
  }
}
