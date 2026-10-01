import '../../core/util/json_parse.dart' show asInt, asDouble, asStr;

/// 俱乐部管理相关模型。对齐后端 `/api/club/*`、`/api/club-compensation/*`、
/// `/api/verify/groupcode/*` 等管理接口的返回体。

/// 经典定向团(俱乐部办的团)。对齐 `/api/club/topics` 列表项。
class ClubTopic {
  ClubTopic({
    required this.id,
    required this.name,
    this.imgUrl,
    this.signupCount = 0,
    this.startDate,
  });

  final int id;
  final String name;
  final String? imgUrl;
  final int signupCount;
  final String? startDate;

  /// 取日期部分 YYYY-MM-DD;空串或非日期返回空。
  String get dateText {
    final s = startDate;
    if (s == null || s.length < 10) return '';
    return s.substring(0, 10);
  }

  factory ClubTopic.fromJson(Map<String, dynamic> json) => ClubTopic(
    id: asInt(json['id']),
    name: asStr(json['name']),
    imgUrl: json['imgUrl'] as String?,
    signupCount: asInt(json['signupCount']),
    startDate: json['startDate'] as String?,
  );
}

/// 入会申请。对齐 `/api/club/join-requests` 列表项。
class JoinRequest {
  JoinRequest({
    required this.memberId,
    this.nickname,
    this.avatar,
    this.joinTime,
  });

  final int memberId;
  final String? nickname;
  final String? avatar;
  final String? joinTime;

  /// 展示用时间:`2026-08-01T10:20:00` → `2026-08-01 10:20`。
  String get requestTimeText {
    final t = joinTime;
    if (t == null || t.isEmpty) return '时间未知';
    final norm = t.replaceFirst('T', ' ');
    return norm.length >= 16 ? norm.substring(0, 16) : norm;
  }

  factory JoinRequest.fromJson(Map<String, dynamic> json) => JoinRequest(
    memberId: asInt(json['memberId']),
    nickname: json['nickname'] as String?,
    avatar: json['avatar'] as String?,
    joinTime: json['joinTime'] as String?,
  );
}

/// 合作保证金。对齐 `/api/club/dissolution-blockers` 的 deposits 项。
class ClubDeposit {
  ClubDeposit({
    required this.id,
    this.depositStatus = 0,
    this.amount,
    this.topicId,
    this.retryable = false,
  });

  final int id;
  final int depositStatus;
  final double? amount;
  final int? topicId;

  /// 可重试原路退款(否则只能联系平台逐笔处理)。
  final bool retryable;

  static const Map<int, String> _statusTexts = <int, String>{
    1: '支付中',
    2: '已缴冻结，待退或待扣',
    5: '应缴未缴',
  };

  String get statusText => _statusTexts[depositStatus] ?? '状态待确认';

  String get amountText {
    final a = amount;
    if (a == null) return '金额待确认';
    return '¥${a.toStringAsFixed(2)}';
  }

  String get topicText => topicId != null ? ' · 主题 #$topicId' : '';

  factory ClubDeposit.fromJson(Map<String, dynamic> json) => ClubDeposit(
    id: asInt(json['id']),
    depositStatus: asInt(json['depositStatus']),
    amount: asDouble(json['amount']),
    topicId: (json['topicId'] as num?)?.toInt(),
    retryable: (json['retryable'] as bool?) ?? false,
  );
}

/// 未打款结算。对齐 `/api/club/dissolution-blockers` 的 settlements 项。
class ClubSettlement {
  ClubSettlement({
    required this.id,
    this.direction = '',
    this.amount,
    this.topicId,
  });

  final int id;
  final String direction;
  final double? amount;
  final int? topicId;

  String get directionText => switch (direction) {
    'incoming' => '待收进来',
    'outgoing' => '待付出去',
    _ => '归属待确认',
  };

  String get amountText {
    final a = amount;
    if (a == null) return '金额待确认';
    return '¥${a.toStringAsFixed(2)}';
  }

  String get topicText => topicId != null ? ' · 主题 #$topicId' : '';

  factory ClubSettlement.fromJson(Map<String, dynamic> json) => ClubSettlement(
    id: asInt(json['id']),
    direction: asStr(json['direction']),
    amount: asDouble(json['amount']),
    topicId: (json['topicId'] as num?)?.toInt(),
  );
}

/// 解散前资金阻断总览。对齐 `/api/club/dissolution-blockers`。
class DissolutionBlockers {
  DissolutionBlockers({
    this.deposits = const <ClubDeposit>[],
    this.settlements = const <ClubSettlement>[],
  });

  final List<ClubDeposit> deposits;
  final List<ClubSettlement> settlements;

  bool get isEmpty => deposits.isEmpty && settlements.isEmpty;

  factory DissolutionBlockers.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawD =
        (json['deposits'] as List<dynamic>?) ?? const <dynamic>[];
    final List<dynamic> rawS =
        (json['settlements'] as List<dynamic>?) ?? const <dynamic>[];
    return DissolutionBlockers(
      deposits: rawD
          .whereType<Map<String, dynamic>>()
          .map(ClubDeposit.fromJson)
          .toList(),
      settlements: rawS
          .whereType<Map<String, dynamic>>()
          .map(ClubSettlement.fromJson)
          .toList(),
    );
  }
}

/// 报名者(名册)。对齐 `/api/club/topic-registrations` 的 cmsRegistrationList 项。
class TeamRegistrant {
  TeamRegistrant({
    required this.id,
    this.avatar,
    this.nickname,
    this.memberId = 0,
    this.paymentStatus = 0,
    this.verificationStatus = 0,
  });

  final int id;
  final String? avatar;
  final String? nickname;
  final int memberId;
  final int paymentStatus;
  final int verificationStatus;

  /// 可退:已支付(2)且未核销(verificationStatus != 1)。
  bool get refundable => paymentStatus == 2 && verificationStatus != 1;

  factory TeamRegistrant.fromJson(Map<String, dynamic> json) => TeamRegistrant(
    id: asInt(json['id']),
    avatar: json['avatar'] as String?,
    nickname: json['nickname'] as String?,
    memberId: asInt(json['memberId']),
    paymentStatus: asInt(json['paymentStatus']),
    verificationStatus: asInt(json['verificationStatus']),
  );
}

/// 票种 + 报名者名单。对齐 `/api/club/topic-registrations` 的 omsTicketList 项。
class TeamTicket {
  TeamTicket({
    required this.name,
    this.mode,
    this.totalInventory = 0,
    this.signupDeadline,
    this.teamStatus = 0,
    this.regs = const <TeamRegistrant>[],
  });

  final String name;
  final String? mode;
  final int totalInventory;
  final String? signupDeadline;
  final int teamStatus;
  final List<TeamRegistrant> regs;

  int get signups => regs.length;
  int get paidCount => regs.length;
  int get refundableCount =>
      regs.where((TeamRegistrant r) => r.refundable).length;

  /// `2026-08-01 10:20:00` → 截断前 16 位。
  String get signupDeadlineText {
    final d = signupDeadline;
    if (d == null || d.isEmpty) return '';
    return d.length >= 16 ? d.substring(0, 16) : d;
  }

  String get teamStatusText => switch (teamStatus) {
    1 => '已成团',
    2 => '已散团',
    _ => '募集中',
  };

  factory TeamTicket.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawRegs =
        (json['cmsRegistrationList'] as List<dynamic>?) ?? const <dynamic>[];
    return TeamTicket(
      name: asStr(json['name']),
      mode: json['mode'] as String?,
      totalInventory: asInt(json['totalInventory']),
      signupDeadline: json['signupDeadline'] as String?,
      teamStatus: asInt(json['teamStatus']),
      regs: rawRegs
          .whereType<Map<String, dynamic>>()
          .map(TeamRegistrant.fromJson)
          .toList(),
    );
  }
}

/// 一个团的报名明细(票种 + 汇总)。
class TeamDetail {
  TeamDetail({this.tickets = const <TeamTicket>[]});

  final List<TeamTicket> tickets;

  int get paidCount =>
      tickets.fold<int>(0, (int acc, TeamTicket t) => acc + t.paidCount);
  int get refundableCount =>
      tickets.fold<int>(0, (int acc, TeamTicket t) => acc + t.refundableCount);

  String get signupDeadlineText {
    for (final TeamTicket t in tickets) {
      if (t.signupDeadlineText.isNotEmpty) return t.signupDeadlineText;
    }
    return '';
  }

  /// 汇总团状态:任一成团则成团,否则任一散团则散团,默认募集中。
  String get teamStatusText {
    bool disbanded = false;
    for (final TeamTicket t in tickets) {
      if (t.teamStatus == 1) return '已成团';
      if (t.teamStatus == 2) disbanded = true;
    }
    return disbanded ? '已散团' : '募集中';
  }

  factory TeamDetail.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawTickets =
        (json['omsTicketList'] as List<dynamic>?) ?? const <dynamic>[];
    return TeamDetail(
      tickets: rawTickets
          .whereType<Map<String, dynamic>>()
          .map(TeamTicket.fromJson)
          .toList(),
    );
  }
}

/// 探店日期次候选。对齐 `/api/club-compensation/editions` 列表项。
class EditionOption {
  EditionOption({
    required this.id,
    required this.label,
    this.hasGeneratedLabel = false,
    this.topicName = '',
    this.startDate,
    this.executingClubId,
  });

  final int id;

  /// `主题名(YYYY-MM-DD)`。
  final String label;
  final bool hasGeneratedLabel;

  final String topicName;
  final String? startDate;

  /// 开售冻结条款里的执行俱乐部 —— 「带票分享」只认真源这一列
  /// (`pages/club/detail/index.js:974-1006` 的 filter)。
  final int? executingClubId;

  /// 取日期部分 YYYY-MM-DD;空返回空串(真源 dateOf)。
  String get dateText {
    final s = startDate;
    if (s == null || s.length < 10) return '';
    return s.substring(0, 10);
  }

  factory EditionOption.fromJson(Map<String, dynamic> json) {
    final id = asInt(json['topicId']);
    final name = asStr(json['topicName']);
    final start = json['startDate'] as String?;
    final date = (start != null && start.length >= 10)
        ? start.substring(0, 10)
        : '';
    final topicLabel = name.isNotEmpty ? name : '期次 #$id';
    return EditionOption(
      hasGeneratedLabel: true,
      id: id,
      label: date.isNotEmpty ? '$topicLabel（$date）' : topicLabel,
      topicName: name,
      startDate: start,
      executingClubId:
          json['executingClubId'] == null ? null : asInt(json['executingClubId']),
    );
  }
}

/// 团码可用场次。对齐 `/api/topic/info-to-user` 的 activityList 项(经 group-code-session 过滤)。
class GroupCodeActivity {
  GroupCodeActivity({required this.id, required this.name});

  final int id;
  final String name;

  factory GroupCodeActivity.fromJson(Map<String, dynamic> json) {
    final raw = json['id'];
    final id = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
    return GroupCodeActivity(
      id: id,
      name: asStr(json['name']).isNotEmpty ? asStr(json['name']) : '场次 $id',
    );
  }
}

/// 团码出码结果。对齐 `/api/verify/groupcode/issue` 的 data。
class GroupCodeIssue {
  GroupCodeIssue({this.qrcodeUrl = '', this.code = '', this.ttlMs = 0});

  final String qrcodeUrl;
  final String code;
  final int ttlMs;

  factory GroupCodeIssue.fromJson(Map<String, dynamic> json) => GroupCodeIssue(
    qrcodeUrl: asStr(json['qrcodeUrl']),
    code: asStr(json['code']),
    ttlMs: asInt(json['ttlMs']),
  );
}
