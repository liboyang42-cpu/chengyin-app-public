/// 俱乐部分润页(G2)模型。
///
/// 契约真源:小程序 `pages/club/settlement/index.js#normalizeSummary`。
/// **fail-closed**:所有**已知金额**字段必须是服务端已格式化好的字符串,
/// 前端只做透传展示 —— 缺字段 / 类型不对整块拒收,不补 0、不二次拼装。
/// 钱的显示口径(几位小数、符号、千分位)只有后端一处真源。
///
/// 但「拒收」只针对**真正的坏回执**;`void`(作废)与「金额待核验」
/// (`amountStatus='unverified'` / `settledAmountStatus='unverified'`)是后端**合法的**
/// 业务态,金额字段本就是 null,必须解析出来交给页面渲染成「待核验」,
/// 绝不能再抛 FormatException 把整页拖进 error 态(2026-09 缺口:void / 待核验回执直接崩)。
class ClubSettlementSummary {
  const ClubSettlementSummary({
    this.settledAmountText,
    this.settledAmountStatus = 'verified',
    this.unverifiedSettledCount = 0,
    this.isOwner = false,
    this.pendingAdjustment,
    required this.topics,
  });

  /// 已入账合计;「金额待核验」(`settledAmountStatus='unverified'`)时为 null。
  final String? settledAmountText;

  /// verified / unverified。unverified 时顶部金额显示「金额待核验」。
  final String settledAmountStatus;

  /// 有多少笔已结算记录缺入账证据、金额待核验(合计卡片下方副文案)。
  final int unverifiedSettledCount;

  /// 余额三段(/api/wallet/stages)只对主理人本人显示;缺省 / 非 true 一律不显示。
  final bool isOwner;

  final ClubSettlementAdjustment? pendingAdjustment;
  final List<ClubSettlementTopic> topics;

  bool get amountUnverified => settledAmountStatus == 'unverified';

  /// 逐字移植 normalizeSummary 的校验:合法回执(含 void / 待核验)返回实例,
  /// 真坏回执抛 FormatException → provider 落 error 态(等价小程序 `!summary → error`)。
  factory ClubSettlementSummary.fromJson(Map<String, dynamic> json) {
    final String settledAmountText = _nonEmpty(json['settledAmountText']);
    final String settledAmountStatus = '${json['settledAmountStatus'] ?? ''}';
    final Object? rawUnverified = json['unverifiedSettledCount'];
    final int unverifiedSettledCount = rawUnverified is num
        ? rawUnverified.toInt()
        : -1;
    if (unverifiedSettledCount < 0) {
      throw const FormatException('结算回执不完整');
    }
    if (settledAmountStatus == 'verified') {
      if (settledAmountText.isEmpty || unverifiedSettledCount != 0) {
        throw const FormatException('结算回执不完整');
      }
    } else if (settledAmountStatus == 'unverified') {
      // 未核验时后端**必须**不下发合计金额,且至少有一笔待核验。
      if (json['settledAmountText'] != null || unverifiedSettledCount == 0) {
        throw const FormatException('结算回执不完整');
      }
    } else {
      throw const FormatException('结算回执不完整');
    }

    final Object? rawTopics = json['topics'];
    if (rawTopics is! List) {
      throw const FormatException('结算回执不完整');
    }
    final List<ClubSettlementTopic> topics = <ClubSettlementTopic>[];
    final Set<int> seen = <int>{};
    int missing = 0;
    for (final Object? row in rawTopics) {
      if (row is! Map) throw const FormatException('结算回执不完整');
      final ClubSettlementTopic topic = ClubSettlementTopic.fromJson(
        Map<String, dynamic>.from(row),
      );
      if (!seen.add(topic.id)) {
        throw const FormatException('结算回执有重复记录');
      }
      if (topic.amountUnverified) missing += 1;
      topics.add(topic);
    }
    if (missing != unverifiedSettledCount) {
      throw const FormatException('待核验笔数与明细对不上');
    }

    ClubSettlementAdjustment? pendingAdjustment;
    final Object? rawAdjustment = json['pendingAdjustment'];
    if (rawAdjustment is Map) {
      // 调整卡是低频补充信息,坏值不牵连整页拒收(真源 normalizeSummary 也不校验它)。
      final ClubSettlementAdjustment? parsed =
          ClubSettlementAdjustment.tryParse(
            Map<String, dynamic>.from(rawAdjustment),
          );
      pendingAdjustment = parsed;
    }

    return ClubSettlementSummary(
      settledAmountText: settledAmountStatus == 'unverified'
          ? null
          : settledAmountText,
      settledAmountStatus: settledAmountStatus,
      unverifiedSettledCount: unverifiedSettledCount,
      isOwner: json['isOwner'] == true,
      pendingAdjustment: pendingAdjustment,
      topics: topics,
    );
  }
}

class ClubSettlementAdjustment {
  const ClubSettlementAdjustment({
    required this.amountText,
    required this.executedText,
    required this.topicName,
    required this.note,
  });

  final String amountText;
  final String executedText;
  final String topicName;
  final String note;

  /// 四字段齐才算一条有效调整待办;任一缺即视作没有(不拖垮整页)。
  static ClubSettlementAdjustment? tryParse(Map<String, dynamic> json) {
    final String amountText = _nonEmpty(json['amountText']);
    final String executedText = _nonEmpty(json['executedText']);
    final String topicName = _nonEmpty(json['topicName']);
    final String note = _nonEmpty(json['note']);
    if (amountText.isEmpty ||
        executedText.isEmpty ||
        topicName.isEmpty ||
        note.isEmpty) {
      return null;
    }
    return ClubSettlementAdjustment(
      amountText: amountText,
      executedText: executedText,
      topicName: topicName,
      note: note,
    );
  }
}

class ClubSettlementTopic {
  const ClubSettlementTopic({
    required this.id,
    required this.topicId,
    required this.name,
    this.amountText,
    this.amountStatus = 'verified',
    required this.originalAmountText,
    required this.executedAdjustmentText,
    required this.netAmountText,
    required this.arrivedText,
    required this.paidText,
    required this.status,
  });

  /// 结算行 id(≠ 主题 id)。
  final int id;

  /// 主题 id:点行进结算详情按 **topicId** 去 /api/coop/finance 找记录,
  /// 传结算行 id 会永远落「这条结算记录不存在或已不可见」(E-02)。
  final int topicId;

  final String name;

  /// 已入账金额;`amountStatus='unverified'` 时为 null(后端不下发)。
  final String? amountText;

  /// verified / unverified。
  final String amountStatus;

  /// 三列金额:原始应结 / 已执行调整 / 核算净额(全部后端算好下发)。
  final String originalAmountText;
  final String executedAdjustmentText;
  final String netAmountText;

  final String arrivedText;
  final String paidText;

  /// settled / pending / void(作废)。
  final String status;

  bool get isSettled => status == 'settled';
  bool get isVoid => status == 'void';
  bool get amountUnverified => amountStatus == 'unverified';

  factory ClubSettlementTopic.fromJson(Map<String, dynamic> json) {
    final int? id = _positiveId(json['id']);
    final int? topicId = _positiveId(json['topicId']);
    final String name = _nonEmpty(json['name']);
    final String amountText = _nonEmpty(json['amountText']);
    final String amountStatus = '${json['amountStatus'] ?? ''}';
    final String originalAmountText = _nonEmpty(json['originalAmountText']);
    final String executedAdjustmentText = _nonEmpty(
      json['executedAdjustmentText'],
    );
    final String netAmountText = _nonEmpty(json['netAmountText']);
    final String arrivedText = _nonEmpty(json['arrivedText']);
    final String paidText = _nonEmpty(json['paidText']);
    final String status = '${json['status'] ?? ''}';

    final bool valid =
        id != null &&
        topicId != null &&
        name.isNotEmpty &&
        arrivedText.isNotEmpty &&
        paidText.isNotEmpty &&
        originalAmountText.isNotEmpty &&
        executedAdjustmentText.isNotEmpty &&
        netAmountText.isNotEmpty &&
        (status == 'settled' || status == 'pending' || status == 'void');
    if (!valid) throw const FormatException('结算回执不完整');

    if (amountStatus == 'unverified') {
      // 只有已结算行会被判「金额待核验」,且此时后端不下发金额字符串。
      if (status != 'settled' || json['amountText'] != null) {
        throw const FormatException('结算回执不完整');
      }
    } else if (amountStatus != 'verified' || amountText.isEmpty) {
      throw const FormatException('结算回执不完整');
    }

    return ClubSettlementTopic(
      id: id,
      topicId: topicId,
      name: name,
      amountText: amountStatus == 'unverified' ? null : amountText,
      amountStatus: amountStatus,
      originalAmountText: originalAmountText,
      executedAdjustmentText: executedAdjustmentText,
      netAmountText: netAmountText,
      arrivedText: arrivedText,
      paidText: paidText,
      status: status,
    );
  }
}

String _nonEmpty(Object? value) => value is String ? value.trim() : '';

int? _positiveId(Object? value) {
  if (value is num) return value.toInt() > 0 ? value.toInt() : null;
  final int? parsed = int.tryParse('${value ?? ''}'.trim());
  return (parsed != null && parsed > 0) ? parsed : null;
}
