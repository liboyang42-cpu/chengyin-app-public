enum ParticipationState {
  notStarted,
  inProgress,
  completed,
  pendingPayment,
  cancelled,
  expired,
  refunded,
  refunding,
  manualRefund,
  nonRefundable,
  unknown,
}

extension ParticipationStateLabel on ParticipationState {
  /// 兜底标签。真源 `utils/order-status.js` 里退款在途的文案是分档的
  /// (「退款审核中」/「退款处理中」),那种动态文案走
  /// [ParticipationOrderSummary.text],别从枚举猜。
  String get label => switch (this) {
    ParticipationState.notStarted => '未开始',
    ParticipationState.inProgress => '进行中',
    ParticipationState.completed => '已完成',
    ParticipationState.pendingPayment => '待支付',
    ParticipationState.cancelled => '已取消',
    ParticipationState.expired => '已过期',
    ParticipationState.refunded => '已退款',
    ParticipationState.refunding => '退款处理中',
    ParticipationState.manualRefund => '人工售后',
    ParticipationState.nonRefundable => '不可退款',
    ParticipationState.unknown => '订单状态更新中',
  };
}

enum ParticipationFilter { all, notStarted, inProgress, completed }

extension ParticipationFilterLabel on ParticipationFilter {
  String get label => switch (this) {
    ParticipationFilter.all => '全部',
    ParticipationFilter.notStarted => '未开始',
    ParticipationFilter.inProgress => '进行中',
    ParticipationFilter.completed => '已完成',
  };

  ParticipationState? get state => switch (this) {
    ParticipationFilter.all => null,
    ParticipationFilter.notStarted => ParticipationState.notStarted,
    ParticipationFilter.inProgress => ParticipationState.inProgress,
    ParticipationFilter.completed => ParticipationState.completed,
  };
}

List<ParticipationRecord> filterParticipations(
  List<ParticipationRecord> rows,
  ParticipationFilter filter,
) {
  final ParticipationState? state = filter.state;
  if (state == null) return rows;
  return rows
      .where((ParticipationRecord record) => record.state == state)
      .toList(growable: false);
}

/// 订单状态读模型的产物 —— 逐条对齐小程序 `utils/order-status.js` 的
/// summarizeOrderState:key 用于筛选/配色,text 是给用户看的那句原话。
class ParticipationOrderSummary {
  const ParticipationOrderSummary({
    required this.state,
    required this.text,
    this.refundText = '',
  });

  final ParticipationState state;
  final String text;
  final String refundText;
}

/// 玩家订单状态的唯一读模型(小程序 utils/order-status.js 的 1:1 移植)。
/// 退款终态只能取 refundApplication.payoutStatus,不能由报名取消态猜测。
ParticipationOrderSummary summarizeParticipationOrderState(
  Map<String, dynamic> json, {
  required DateTime now,
}) {
  if (_truthy(json['manualRefundCaseStatus'])) {
    final Object? rawRefundInfo = json['refundInfo'];
    final String reason = rawRefundInfo is Map
        ? trimmed(rawRefundInfo['reason'])
        : '';
    return ParticipationOrderSummary(
      state: ParticipationState.manualRefund,
      text: '人工售后',
      refundText: reason.isEmpty ? '请查看订单的人工处理进度' : reason,
    );
  }

  final ParticipationOrderSummary? refund = _payoutSummary(
    json['refundApplication'],
  );
  if (refund != null) return refund;

  final int registrationStatus = _asInt(json['registrationStatus']);
  if (registrationStatus == 1) {
    return const ParticipationOrderSummary(
      state: ParticipationState.pendingPayment,
      text: '待支付',
      refundText: '完成支付后可使用',
    );
  }
  if (registrationStatus == 3) {
    return const ParticipationOrderSummary(
      state: ParticipationState.cancelled,
      text: '已取消',
      refundText: '订单已关闭',
    );
  }
  // 后端 CmsRegistration:4=已过期(closeExpired 关单)。
  if (registrationStatus == 4) {
    return const ParticipationOrderSummary(
      state: ParticipationState.expired,
      text: '已过期',
      refundText: '超时未支付，订单已关闭',
    );
  }
  if (registrationStatus != 2) {
    return const ParticipationOrderSummary(
      state: ParticipationState.unknown,
      text: '订单状态更新中',
    );
  }

  if (_asInt(json['verificationStatus']) == 1) {
    return const ParticipationOrderSummary(
      state: ParticipationState.completed,
      text: '已完成',
      refundText: '已核销订单不可退款',
    );
  }

  final Object? rawRefundInfo = json['refundInfo'];
  final Map<dynamic, dynamic> refundInfo = rawRefundInfo is Map
      ? rawRefundInfo
      : const <dynamic, dynamic>{};
  if (refundInfo['refundable'] == false) {
    final String reason = trimmed(refundInfo['reason']);
    return ParticipationOrderSummary(
      state: ParticipationState.nonRefundable,
      text: '不可退款',
      refundText: reason.isEmpty ? '当前订单不可自助退款' : reason,
    );
  }

  final Map<String, dynamic> source = _sourceOf(json);
  final DateTime? start = _parseChinaDate(
    source['startDate'] ?? source['startTime'],
  );
  final DateTime? end = _parseChinaDate(
    source['endDate'] ??
        source['endTime'] ??
        source['startDate'] ??
        source['startTime'],
  );
  final String reason = trimmed(refundInfo['reason']);
  if (end != null && now.isAfter(end)) {
    return const ParticipationOrderSummary(
      state: ParticipationState.completed,
      text: '已完成',
      refundText: '活动已结束',
    );
  }
  if (start != null && now.isBefore(start)) {
    return ParticipationOrderSummary(
      state: ParticipationState.notStarted,
      text: '未开始',
      refundText: reason.isEmpty ? '可在退款截止前申请原路退款' : reason,
    );
  }
  return ParticipationOrderSummary(
    state: ParticipationState.inProgress,
    text: '进行中',
    refundText: reason.isEmpty ? '可在退款截止前申请原路退款' : reason,
  );
}

/// payoutSummary:refund_application.status 0 待审核 / 1 批准 / 2 驳回;
/// payout_status 建单即 5,批准后 6 派发中 → 0 微信已受理 → 1 到账 /
/// 2 待人工 / 3 人工已退 / 4 复核完成。不在 1–4 时只说真实走到的那一步,
/// 不给「预计 N 个工作日」这种没人兑现的承诺。
ParticipationOrderSummary? _payoutSummary(Object? raw) {
  if (raw is! Map) return null;
  final int? payout = _asNullableInt(raw['payoutStatus']);
  final int? status = _asNullableInt(raw['status']);
  if (payout == 1 || payout == 4) {
    return const ParticipationOrderSummary(
      state: ParticipationState.refunded,
      text: '已退款',
      refundText: '退款已原路退回',
    );
  }
  if (payout == 2) {
    return const ParticipationOrderSummary(
      state: ParticipationState.refunding,
      text: '退款处理中',
      refundText: '原路退款异常，平台正在人工处理',
    );
  }
  if (payout == 3) {
    return const ParticipationOrderSummary(
      state: ParticipationState.refunding,
      text: '退款处理中',
      refundText: '人工退款已处理，等待复核确认',
    );
  }
  // 零元单没有钱可退,不给在途承诺。
  if (raw.containsKey('refundAmount') && raw['refundAmount'] != null) {
    final num? amount = _asNumber(raw['refundAmount']);
    if (amount == null || amount <= 0) return null;
  }
  // 驳回:不是退款中,回落到订单真实状态。
  if (status == 2) return null;
  if (status == 0) {
    return const ParticipationOrderSummary(
      state: ParticipationState.refunding,
      text: '退款审核中',
      refundText: '退款申请已提交，等待平台审核',
    );
  }
  if (payout == 0) {
    return const ParticipationOrderSummary(
      state: ParticipationState.refunding,
      text: '退款处理中',
      refundText: '微信已受理原路退款，到账以微信退款通知为准',
    );
  }
  if (status == 1) {
    return const ParticipationOrderSummary(
      state: ParticipationState.refunding,
      text: '退款处理中',
      refundText: '退款已批准，正在提交原路退款',
    );
  }
  return const ParticipationOrderSummary(
    state: ParticipationState.refunding,
    text: '退款处理中',
    refundText: '退款进度更新中，请以微信退款通知为准',
  );
}

class ParticipationRecord {
  ParticipationRecord({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.sourceName,
    required this.coverUrl,
    required this.address,
    required this.dateText,
    required this.typeLabel,
    required this.state,
    String? stateText,
  }) : stateText = stateText ?? state.label;

  final int id;
  final int ownerType;
  final int ownerId;
  final String sourceName;
  final String coverUrl;
  final String address;
  final String dateText;
  final String typeLabel;
  final ParticipationState state;

  /// 状态原话(退款在途时与 [ParticipationState.label] 不同档)。
  final String stateText;

  factory ParticipationRecord.fromJson(
    Map<String, dynamic> json, {
    DateTime? now,
  }) {
    final int ownerType = _asInt(json['ownerType']);
    final Map<String, dynamic> source = _sourceOfByOwnerType(json);
    final DateTime current = now ?? DateTime.now();
    final ParticipationOrderSummary orderState =
        summarizeParticipationOrderState(json, now: current);
    final DateTime? start = _parseChinaDate(
      source['startDate'] ?? source['startTime'],
    );
    final DateTime? end = _parseChinaDate(
      source['endDate'] ??
          source['endTime'] ??
          source['startDate'] ??
          source['startTime'],
    );
    final bool freeExplore =
        _asInt(json['purchaseKind']) == 3 || _asInt(source['productType']) == 2;
    return ParticipationRecord(
      id: _asInt(json['id']),
      ownerType: ownerType,
      ownerId: _asInt(json['ownerId']),
      sourceName: _nonEmpty(source['name'], '活动信息待补充'),
      coverUrl: _firstImage(source['imgUrl'] ?? source['imgArr']),
      address: _nonEmpty(source['address'] ?? source['addressName'], '地点待定'),
      dateText: _formatListDateRange(start, end),
      typeLabel: switch (ownerType) {
        1 => freeExplore ? '自由探索' : '城市定向',
        2 => '线下活动',
        _ => '类型待确认',
      },
      state: orderState.state,
      stateText: orderState.text,
    );
  }
}

/// 参与详情动作 —— 真源底部栏:开始玩/取消参与/去修改/联系客服/核验扫码,
/// 以及模板行跳转。半屏只负责收集意图,执行(确认弹窗、路由跳转)在宿主列表页,
/// 对齐真源「先 close 再 navigateTo」。
enum ParticipationDetailActionKind {
  startPlay,
  cancel,
  modify,
  contact,
  scan,
  openTemplate,
}

class ParticipationDetailResult {
  const ParticipationDetailResult({required this.kind, required this.detail});

  final ParticipationDetailActionKind kind;
  final ParticipationDetail detail;
}

class ParticipationDetail {
  const ParticipationDetail({
    required this.id,
    required this.topicName,
    required this.dateText,
    required this.statusText,
    required this.modeText,
    required this.ownerType,
    required this.ownerId,
    required this.isTopic,
    required this.paymentStatus,
    required this.showOrderStats,
    required this.showRemainingBadge,
    required this.remainingDaysText,
    required this.canCancel,
    required this.showContactService,
    required this.needModify,
    required this.hasRuleInstructions,
    this.refundDeadlineDisplay = '',
    this.activityDescription,
    this.nodeName,
    this.cooperateDate,
    this.coverUrl = '',
    this.templateId,
    this.templateName = '',
    this.templateBannerUrl = '',
    this.pendingVerification,
    this.verifiedCount,
    this.totalOrderCount,
  });

  final int id;
  final String topicName;

  /// 'YYYY.MM.DD - YYYY.MM.DD';缺任一端为 ''(真源:整块徽标不渲染)。
  final String dateText;
  final String statusText;
  final String modeText;
  final int ownerType;
  final int ownerId;

  /// 真源 goPlay 判据:`ownerType == 1 || cmsTopic 存在`(路线 vs 场次)。
  final bool isTopic;

  /// CmsRegistration.paymentStatus,2=已支付 —— 取消走哪个接口的判据。
  final int paymentStatus;
  final String refundDeadlineDisplay;

  /// 真源「没有真值整行不渲染」的字段一律可空:
  final String? activityDescription;
  final String? nodeName;
  final String? cooperateDate;

  final String coverUrl;

  /// info.status == 1:核销进度块与「核验扫码」入口共用这一开关。
  final bool showOrderStats;
  final int? pendingVerification;
  final int? verifiedCount;
  final int? totalOrderCount;

  /// 开始前 3 天内的「距离路线开始还剩N天」warning 徽标。
  final bool showRemainingBadge;
  final String remainingDaysText;

  final int? templateId;
  final String templateName;
  final String templateBannerUrl;

  /// 有 ruleInstructions 时渲染真源那段固定规则文案(wxml 是硬字段的)。
  final bool hasRuleInstructions;

  final bool canCancel;
  final bool showContactService;
  final bool needModify;

  factory ParticipationDetail.fromJson(
    int id,
    Map<String, dynamic> json, {
    DateTime? now,
  }) {
    final Map<String, dynamic> source = _sourceOf(json);
    final bool isTopic =
        _asInt(json['ownerType']) == 1 || json['cmsTopic'] is Map;
    final DateTime current = now ?? DateTime.now();

    final String name = trimmed(
      trimmed(source['name']).isNotEmpty ? source['name'] : source['title'],
    );
    final String topicName = trimmed(json['activityTitle']).isNotEmpty
        ? trimmed(json['activityTitle'])
        : name.isNotEmpty
        ? name
        : '未知主题';

    final DateTime? start = _parseChinaDate(source['startDate']);
    final DateTime? end = _parseChinaDate(source['endDate']);
    final String dateText = _formatDetailDateRange(start, end);

    final _TimeStatus timeStatus = _calculateTimeStatus(
      start: start,
      end: end,
      now: current,
    );

    final ParticipationOrderSummary summary = summarizeParticipationOrderState(
      json,
      now: current,
    );

    final String modeText = !isTopic
        ? '线下活动'
        : (_asInt(json['purchaseKind']) == 3 ||
              _asInt(source['productType']) == 2)
        ? '自由探索'
        : '城市定向';

    final String activityDesc = trimmed(json['activityDesc']).isNotEmpty
        ? trimmed(json['activityDesc'])
        : trimmed(source['description']);
    final String cooperateDate = trimmed(json['cooperateDate']);
    final String nodeName = trimmed(json['nodeName']);

    final int? total = _asNonNegativeInt(json['totalOrderNum']);
    final int? verified = _asNonNegativeInt(json['verifiedNum']);
    final bool statsKnown =
        total != null && verified != null && verified <= total;

    final bool needModify = trimmed(json['displayStatus']) == '需修改';
    // 取消参与:开始前3天以上;联系客服:开始前3天内/已开始/已结束。
    final bool canCancel =
        timeStatus.isBeforeThreeDays &&
        !timeStatus.isInThreeDaysRange &&
        !timeStatus.isStarted &&
        !timeStatus.isEnded &&
        !needModify;
    final bool showContactService =
        (timeStatus.isInThreeDaysRange ||
            timeStatus.isStarted ||
            timeStatus.isEnded) &&
        !needModify;

    return ParticipationDetail(
      id: _asInt(json['id']) != 0 ? _asInt(json['id']) : id,
      topicName: topicName,
      dateText: dateText,
      statusText: summary.text,
      modeText: modeText,
      ownerType: _asInt(json['ownerType']),
      isTopic: isTopic,
      ownerId: _asInt(json['ownerId']) != 0
          ? _asInt(json['ownerId'])
          : _asInt(source['id']),
      paymentStatus: _asInt(json['paymentStatus']),
      refundDeadlineDisplay: trimmed(json['refundDeadlineDisplay']),
      activityDescription: activityDesc.isEmpty ? null : activityDesc,
      nodeName: nodeName.isEmpty ? null : nodeName,
      cooperateDate: cooperateDate.isEmpty ? null : cooperateDate,
      coverUrl: _firstImage(source['imgUrl'] ?? source['imgArr']),
      templateId: _asNullableInt(json['templateId']),
      templateName: trimmed(json['templateName']),
      templateBannerUrl: _firstImage(json['topicImgArr']),
      hasRuleInstructions: trimmed(json['ruleInstructions']).isNotEmpty,
      pendingVerification: statsKnown ? total - verified : null,
      verifiedCount: statsKnown ? verified : null,
      totalOrderCount: statsKnown ? total : null,
      showOrderStats: _asInt(json['status']) == 1,
      showRemainingBadge:
          timeStatus.isInThreeDaysRange &&
          timeStatus.remainingDaysText.isNotEmpty,
      remainingDaysText: timeStatus.remainingDaysText,
      canCancel: canCancel,
      showContactService: showContactService,
      needModify: needModify,
    );
  }
}

class _TimeStatus {
  const _TimeStatus({
    this.isStarted = false,
    this.isEnded = false,
    this.isInThreeDaysRange = false,
    this.isBeforeThreeDays = false,
    this.remainingDaysText = '',
  });

  final bool isStarted;
  final bool isEnded;
  final bool isInThreeDaysRange;
  final bool isBeforeThreeDays;
  final String remainingDaysText;
}

_TimeStatus _calculateTimeStatus({
  required DateTime? start,
  required DateTime? end,
  required DateTime now,
}) {
  if (start == null || end == null) return const _TimeStatus();
  final bool isEnded = now.isAfter(end);
  if (isEnded) return const _TimeStatus(isEnded: true);
  if (!now.isBefore(start)) return const _TimeStatus(isStarted: true);

  // ★「今天零点」按中国自然日取,不能用设备本地零点 —— 手机在 UTC 时区时
  //   会把中国的凌晨归到前一天,「还有几天开始」差一天,取消窗口跟着错一天。
  final int diffMs =
      _chinaDayStartMs(start.millisecondsSinceEpoch) -
      _chinaDayStartMs(now.millisecondsSinceEpoch);
  // 真源 Math.ceil(diffTime / 86400000);diffMs ≥ 0 时即向上取整。
  final int diffDays =
      (diffMs + Duration.millisecondsPerDay - 1) ~/ Duration.millisecondsPerDay;
  if (diffDays <= 0) return const _TimeStatus();
  return _TimeStatus(
    remainingDaysText: '距离路线开始还剩$diffDays天',
    isInThreeDaysRange: diffDays <= 3,
    isBeforeThreeDays: diffDays > 3,
  );
}

const int _chinaOffsetMs = 8 * 60 * 60 * 1000;

int _floorDiv(int a, int b) => (a - (a % b + b) % b) ~/ b;

/// epoch 毫秒 → 该时刻所在中国自然日的 00:00(epoch 毫秒)。
int _chinaDayStartMs(int epochMs) =>
    _floorDiv(epochMs + _chinaOffsetMs, Duration.millisecondsPerDay) *
        Duration.millisecondsPerDay -
    _chinaOffsetMs;

Map<String, dynamic> _sourceOf(Map<String, dynamic> json) {
  final Object? activity = json['cmsActivity'];
  final Object? topic = json['cmsTopic'];
  if (activity is Map<String, dynamic>) return activity;
  if (topic is Map<String, dynamic>) return topic;
  return <String, dynamic>{};
}

/// mycanyu.js normalize：ownerType==1 只读 cmsTopic、==2 只读 cmsActivity，
/// 未知类型不猜读另一份业务对象（不冒充线下活动，也不串数据）。
Map<String, dynamic> _sourceOfByOwnerType(Map<String, dynamic> json) {
  final Object? source = switch (_asInt(json['ownerType'])) {
    1 => json['cmsTopic'],
    2 => json['cmsActivity'],
    _ => null,
  };
  return source is Map<String, dynamic> ? source : const <String, dynamic>{};
}

bool _truthy(Object? value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is num) return value != 0;
  return value.toString().trim().isNotEmpty && value.toString() != '0';
}

int _asInt(Object? value) => value is num
    ? value.toInt()
    : int.tryParse(value?.toString().trim() ?? '') ?? 0;

int? _asNullableInt(Object? value) {
  if (value == null || value.toString().trim().isEmpty) return null;
  return value is num
      ? value.toInt()
      : (num.tryParse(value.toString().trim())?.toInt());
}

int? _asNonNegativeInt(Object? value) {
  final int? parsed = _asNullableInt(value);
  if (parsed == null || parsed < 0) return null;
  return parsed;
}

num? _asNumber(Object? value) {
  if (value is num) return value;
  return num.tryParse(value?.toString().trim() ?? '');
}

String trimmed(Object? value) => value?.toString().trim() ?? '';

String _nonEmpty(Object? value, String fallback) {
  final String text = trimmed(value);
  return text.isEmpty ? fallback : text;
}

String _firstImage(Object? value) {
  if (value is List) {
    return value.isEmpty ? '' : trimmed(value.first);
  }
  final String text = trimmed(value);
  if (text.isEmpty) return '';
  return trimmed(text.split(',').first);
}

/// 后端时间串不带时区,口径按中国(+08:00)—— 与真源 toTimestamp 一致。
DateTime? _parseChinaDate(Object? value) {
  final String text = trimmed(value);
  if (text.isEmpty) return null;
  final String normalized = text.replaceFirst(' ', 'T');
  final bool hasZone =
      normalized.endsWith('Z') ||
      RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(normalized);
  final DateTime? parsed = DateTime.tryParse(
    hasZone ? normalized : '$normalized+08:00',
  );
  return parsed;
}

String _two(int value) => value.toString().padLeft(2, '0');

String _shortDate(DateTime? value) => value == null
    ? ''
    : '${_two(value.toUtc().add(const Duration(hours: 8)).month)}.${_two(value.toUtc().add(const Duration(hours: 8)).day)}';

String _fullDate(DateTime? value) {
  if (value == null) return '';
  final DateTime china = value.toUtc().add(const Duration(hours: 8));
  return '${china.year}.${_two(china.month)}.${_two(china.day)}';
}

String _range(String start, String end, String fallback) {
  if (start.isNotEmpty && end.isNotEmpty) return '$start - $end';
  if (start.isNotEmpty) return start;
  if (end.isNotEmpty) return end;
  return fallback;
}

String _formatListDateRange(DateTime? start, DateTime? end) =>
    _range(_shortDate(start), _shortDate(end), '时间待定');

/// 真源 formatDateRange:任一端缺失返回 ''(徽标整块不渲染)。
String _formatDetailDateRange(DateTime? start, DateTime? end) =>
    start == null || end == null
    ? ''
    : '${_fullDate(start)} - ${_fullDate(end)}';
