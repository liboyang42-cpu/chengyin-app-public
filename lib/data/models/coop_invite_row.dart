/// 我的协作邀请一行(发出的 / 收到的)。对齐后端 `CoopInvite` + `CoopPartnerVO`
/// (`/api/coop/list`)。逐条对齐小程序 `utils/coop-invite-view.js` 的 `decorate()`
/// —— 列表 `pages/coop/list` 与详情 `pages/coop/invite-detail` 共用同一份整形,
/// 同一条邀约的条款/联系方式两页念法必须一致。
class CoopInviteRow {
  const CoopInviteRow({
    required this.id,
    required this.inviteType,
    required this.fromId,
    required this.toType,
    required this.toId,
    this.topicId,
    this.gameId,
    this.status,
    this.message,
    this.handleReason,
    this.shareMode,
    this.shareRate,
    this.fixedFee,
    this.depositOwed = false,
    this.depositAmount,
    this.depositRefundPending = false,
    this.termsFrozen = false,
    this.expireTime,
    this.partnerName,
    this.partnerLeaderName,
    this.partnerPhone,
    this.coverUrl,
    this.createTime,
  });

  final int id;

  /// 0主题发布者→商家 1商家→俱乐部;2历史商家节点邀约(只读)。
  final int inviteType;
  final int fromId;

  /// 受邀方类型 merchant/club。
  final String toType;
  final int toId;
  final int? topicId;

  /// 主题里的玩法 id(游戏级邀约才有)。席位占用按它算。
  final int? gameId;

  /// 0待确认 1已接受 2已拒绝 3已取消 4已顶替 5已过期。
  final int? status;
  final String? message;

  /// 对方处理这条邀约时给的理由(已拒绝 / 已撤销 / 已取消时最该被看见的一句)。
  /// ★ 列表只放得下一行状态字,这句只有详情页装得下。
  final String? handleReason;

  /// 0引流 1分成 2固定。
  final int? shareMode;
  final double? shareRate;
  final double? fixedFee;

  /// 当前登录人是否为锁价后应缴保证金方。
  /// 为 true 时 App 走 `/api/coop/deposit/create/app`建单，并以
  /// `/api/coop/deposit/status` 的回读作为入账真源。
  final bool depositOwed;

  /// 待缴保证金金额。★ 拿不到就是 null —— **不兜 0、也不编一个默认值**。
  final double? depositAmount;
  final bool depositRefundPending;

  /// 条款是否已锁价冻结。冻结后后端拒单方取消合作(转客服协商)。
  final bool termsFrozen;

  /// 招募截止时间。后端可能给毫秒时间戳,也可能给 "YYYY-MM-DD HH:MM:SS"。
  final DateTime? expireTime;

  final String? partnerName;

  /// 负责人 + 电话,受闸(仅 status=1 已接受时后端才下发)。
  final String? partnerLeaderName;
  final String? partnerPhone;

  /// 主题封面。★ 小程序详情页读的是 `invite.cover`,而这一行的**真源字段**是
  /// `topicImgUrl || topicCover`(见 `pages/coop/list/index.wxml:43`)——
  /// 指的是同一张图,这里按真源取;取不到就留兜底底色,不画一个假封面。
  final String? coverUrl;

  final String? createTime;

  static const List<String> _typeLabels = <String>[
    '主题发布者 → 商家',
    '商家 → 俱乐部',
    '商家 → 商家承接节点',
  ];
  static const List<String> _statusLabels = <String>[
    '待确认',
    '已接受',
    '已拒绝',
    '已取消',
    '已顶替',
    '已过期',
  ];

  String get typeText =>
      (inviteType >= 0 && inviteType < _typeLabels.length) ? _typeLabels[inviteType] : '合作';

  String get statusText =>
      (status != null && status! >= 0 && status! < _statusLabels.length)
          ? _statusLabels[status!]
          : '';

  /// 历史商家节点邀约仅供查看,不能再处理(后端多处显式拒绝)。
  bool get legacyReadonly => inviteType == 2;

  String get topicText => topicId != null ? '主题 #$topicId' : '';

  /// ★ 联系方式只拼后端**实际下发**到的字段,不自己判条件——
  ///   闸在后端(status=1 才给 leaderName/phone),前端再判一次只会两边不一致。
  String get partnerContact {
    final parts = <String>[
      if ((partnerLeaderName ?? '').isNotEmpty) partnerLeaderName!,
      if ((partnerPhone ?? '').isNotEmpty) partnerPhone!,
    ];
    return parts.join(' · ');
  }

  String? get termsText {
    switch (shareMode) {
      case 1:
        return '分成型 · 票款 ${shareRate ?? '?'}%';
      case 2:
        return '固定型 · ¥${fixedFee ?? '?'} / 核销人头';
      case 0:
        return '引流型 · 无分成';
      default:
        return null;
    }
  }

  /// 待确认态需要三样都齐全才可处理:发起方/受邀方名称、主题、条款。
  bool get decisionReady =>
      (partnerName ?? '').isNotEmpty && topicText.isNotEmpty && (termsText ?? '').isNotEmpty;

  String get timeText =>
      (createTime != null && createTime!.length >= 16) ? createTime!.substring(5, 16) : (createTime ?? '');

  /// 招募倒计时。口径同小程序 `coop-invite-view.js:countdownOf`:
  /// 只有**待确认**且有截止时间才算;已过截止是个事实,不显示负数。
  ///
  /// ★ 传 [now] 而不是内部取 —— 否则测不了(本项目栽过「当前时间不可控」的坑,
  ///   同 `officialEventCountdown`)。
  String countdownText(DateTime now) {
    final DateTime? end = expireTime;
    if (status != 0 || end == null) return '';
    final Duration left = end.difference(now);
    if (left.isNegative) return '已过招募截止';
    final int days = left.inDays;
    return '招募剩 ${days > 0 ? '$days 天' : '${left.inHours} 小时'}';
  }

  /// 保证金一句话(列表与详情共用)。
  ///
  /// ⚠️ **有意偏离**小程序 `depositDueText` 的 `depositAmount || 50`:那句会把
  /// 「后端没下发金额」显示成「¥50」—— 把不知道说成了 50 元。这里照说
  /// 「有保证金要交」这个事实,金额没拿到就不说金额。
  String get depositDueText {
    if (legacyReadonly || !depositOwed) return '';
    final double? amount = depositAmount;
    if (amount == null) return '锁价后需缴保证金';
    final String text = amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
    return '锁价后待缴 ¥$text 保证金';
  }

  /// 席位占用:游戏级看挂起(pending/cap),主题级看已接受(accepted/cap)。
  ///
  /// slots 由 `/api/coop/list` 的**响应顶层**下发,不在行里 —— 所以它是参数不是字段。
  /// 判据与小程序 `coop-invite-view.js:slotOf` 一致:拿不到就是空串,那一行不显示,
  /// 不编一个 0/0 出来。
  String slotText(Map<String, dynamic>? slots) {
    if (slots == null) return '';
    final int? game = gameId;
    if (game != null) {
      final Map<String, dynamic>? slot =
          (slots['byGame'] as Map<String, dynamic>?)?['$game'] as Map<String, dynamic>?;
      if (slot != null) return '本游戏挂起 ${slot['pending']}/${slot['cap']}';
    }
    final int? topic = topicId;
    if (topic != null) {
      final Map<String, dynamic>? slot =
          (slots['byTopic'] as Map<String, dynamic>?)?['$topic'] as Map<String, dynamic>?;
      if (slot != null) return '本主题已接受 ${slot['accepted']}/${slot['cap']}';
    }
    return '';
  }

  factory CoopInviteRow.fromJson(Map<String, dynamic> json) {
    final partner = json['partner'] as Map<String, dynamic>?;
    return CoopInviteRow(
      id: (json['id'] as num?)?.toInt() ?? 0,
      inviteType: (json['inviteType'] as num?)?.toInt() ?? 0,
      fromId: (json['fromId'] as num?)?.toInt() ?? 0,
      toType: (json['toType'] as String?) ?? '',
      toId: (json['toId'] as num?)?.toInt() ?? 0,
      topicId: (json['topicId'] as num?)?.toInt(),
      gameId: (json['gameId'] as num?)?.toInt(),
      status: (json['status'] as num?)?.toInt(),
      message: json['message'] as String?,
      handleReason: json['handleReason'] as String?,
      shareMode: (json['shareMode'] as num?)?.toInt(),
      shareRate: (json['shareRate'] as num?)?.toDouble(),
      fixedFee: (json['fixedFee'] as num?)?.toDouble(),
      depositOwed: json['depositOwed'] == true,
      depositAmount: (json['depositAmount'] as num?)?.toDouble(),
      depositRefundPending: json['depositRefundPending'] == true,
      termsFrozen: json['termsFrozen'] == true,
      expireTime: _parseTime(json['expireTime']),
      partnerName: partner?['name'] as String?,
      partnerLeaderName: partner?['leaderName'] as String?,
      partnerPhone: partner?['phone'] as String?,
      coverUrl: _text(json['cover']) ?? _text(json['topicCover']) ?? _text(json['topicImgUrl']),
      createTime: json['createTime']?.toString(),
    );
  }
}

/// 后端时间可能是毫秒时间戳,也可能是 "YYYY-MM-DD HH:MM:SS"(同 official_event.dart)。
DateTime? _parseTime(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
  if (raw is String && raw.isNotEmpty) {
    return DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  }
  return null;
}

/// 空串与缺席一样处理 —— 后端两种都发过。
String? _text(Object? raw) {
  final String text = raw?.toString() ?? '';
  return text.trim().isEmpty ? null : text;
}

/// `/api/coop/list` 整体响应:发出的 + 收到的两个方向,外加席位占用表。
///
/// ★ 三半从**同一个响应**里取 —— 为了 slots 再打一次同样的请求是白打。
///   (后端 `ApiCoopController.list` 返的是裸 Map `{sent, received, slots}`)
class CoopInviteList {
  const CoopInviteList({
    this.sent = const <CoopInviteRow>[],
    this.received = const <CoopInviteRow>[],
    this.slots,
  });

  final List<CoopInviteRow> sent;
  final List<CoopInviteRow> received;

  /// 席位占用表,按游戏 / 主题索引(`byGame` / `byTopic`)。后端可能不发,所以可空。
  final Map<String, dynamic>? slots;

  factory CoopInviteList.fromJson(Map<String, dynamic> json) {
    List<CoopInviteRow> parse(Object? raw) => ((raw as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(CoopInviteRow.fromJson)
        .toList();
    return CoopInviteList(
      sent: parse(json['sent']),
      received: parse(json['received']),
      slots: json['slots'] as Map<String, dynamic>?,
    );
  }
}
