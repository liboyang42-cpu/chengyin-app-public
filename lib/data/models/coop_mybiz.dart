/// 商家结算工作台。对齐后端 `ApiCoopController.mybiz`(/api/coop/mybiz)。
class CoopMyBiz {
  const CoopMyBiz({
    required this.fulfillmentRate,
    required this.violationCount,
    required this.avgRating,
    required this.reviewCount,
    required this.settlements,
  });

  /// 近 90 天履约率(0~100)。
  final int fulfillmentRate;
  final int violationCount;

  /// 均分,**没有评价时后端也给 0**(SQL `COALESCE(...,0)`)——
  /// 靠 [reviewCount] 而不是 avgRating 本身来判断"有没有评价"。
  final double avgRating;
  final int reviewCount;

  final List<CoopSettlementRow> settlements;

  factory CoopMyBiz.fromJson(Map<String, dynamic> json) {
    final credit =
        (json['credit'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final review =
        (json['review'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return CoopMyBiz(
      fulfillmentRate: (credit['fulfillmentRate'] as num?)?.toInt() ?? 100,
      violationCount: (credit['violationCount'] as num?)?.toInt() ?? 0,
      avgRating: (review['avgRating'] as num?)?.toDouble() ?? 0,
      reviewCount: (review['reviewCount'] as num?)?.toInt() ?? 0,
      settlements:
          ((json['settlements'] as List<dynamic>?) ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(CoopSettlementRow.fromJson)
              .toList(),
    );
  }
}

/// 一条结算记录。对齐后端 `CoopSettlement`。
class CoopSettlementRow {
  const CoopSettlementRow({
    required this.id,
    this.topicId,
    this.topicName,
    this.amount,
    this.status,
    this.payeeType,
    this.shareMode,
    this.shareRate,
    this.fixedFee,
    this.verifiedHeads,
    this.verifiedSales,
    this.payableTime,
    this.payoutTime,
    this.createTime,
    this.settleTime,
    this.updateTime,
  });

  final int id;
  final int? topicId;
  final String? topicName;
  final double? amount;

  /// 0待打款 1已打款 2作废。
  final int? status;
  final String? payeeType;
  final int? shareMode;
  final double? shareRate;
  final double? fixedFee;
  final int? verifiedHeads;
  final double? verifiedSales;
  final String? payableTime;
  final String? payoutTime;
  final String? createTime;
  final String? settleTime;
  final String? updateTime;

  /// 后端旧记录可能没有 topicName。与小程序 view-model 同步:
  /// 有名字展示名字,否则回退到 topicId,不编造假名字。
  String get topicTitle {
    final name = (topicName ?? '').trim();
    if (name.isNotEmpty) return name;
    return topicId != null ? '主题 #$topicId' : '未命名主题';
  }

  String get statusText {
    switch (status) {
      case 0:
        return '待入账';
      case 1:
        return '已入余额';
      case 2:
        return '已作废';
      default:
        return '状态待确认';
    }
  }

  String get payeeText {
    final t = (payeeType ?? '').trim().toLowerCase();
    if (t == 'club') return '俱乐部分润';
    return '商家分润';
  }

  String? get shareRuleText {
    switch (shareMode) {
      case 0:
        return '引流';
      case 1:
        return shareRate != null ? '分成 · $shareRate%' : '分成';
      case 2:
        return fixedFee != null
            ? '固定 · ¥${fixedFee!.toStringAsFixed(2)}/人'
            : '固定';
      default:
        return null;
    }
  }

  factory CoopSettlementRow.fromJson(Map<String, dynamic> json) {
    int? integer(String key) {
      final value = json[key];
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '');
    }

    int? canonicalCode(String key) {
      final value = json[key];
      if (value is num) {
        if (value == 0 || value == 1 || value == 2) return value.toInt();
        return null;
      }
      if (value is! String) return null;
      switch (value.trim()) {
        case '0':
          return 0;
        case '1':
          return 1;
        case '2':
          return 2;
        default:
          return null;
      }
    }

    double? number(String key) {
      final value = json[key];
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '');
    }

    return CoopSettlementRow(
      id: integer('id') ?? 0,
      topicId: integer('topicId'),
      topicName: json['topicName']?.toString(),
      amount: number('amount'),
      status: canonicalCode('status'),
      payeeType: json['payeeType'] as String?,
      shareMode: canonicalCode('shareMode'),
      shareRate: number('shareRate'),
      fixedFee: number('fixedFee'),
      verifiedHeads: integer('verifiedHeads'),
      verifiedSales: number('verifiedSales'),
      payableTime: json['payableTime']?.toString(),
      payoutTime: json['payoutTime']?.toString(),
      createTime: json['createTime']?.toString(),
      settleTime: json['settleTime']?.toString(),
      updateTime: json['updateTime']?.toString(),
    );
  }
}
