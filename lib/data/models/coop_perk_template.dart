/// 商家常备权益模板。对齐后端 `CoopPerkTemplate`(/api/coop/perk-template/*)。
///
/// ★ 后端**只新增不更新**(save 时 `body.setId(null)`)—— 界面别做成"编辑"。
class CoopPerkTemplate {
  const CoopPerkTemplate({
    required this.id,
    required this.perkType,
    required this.name,
    this.unitCost,
    this.retailValue,
    this.quota,
    this.validEnd,
  });

  final int id;

  /// 0礼品 1优惠券 2折扣体验。
  final int perkType;
  final String name;

  /// 成本价,仅自己可见;可空(未填)。
  final double? unitCost;

  /// 零售价(玩家眼里这份权益值多少)。
  final double? retailValue;

  /// 可接待份数。
  final int? quota;

  /// 有效期(yyyy-MM-dd),可空=长期有效。
  final String? validEnd;

  static const List<String> typeLabels = <String>['礼品', '优惠券', '折扣'];

  String get typeText =>
      (perkType >= 0 && perkType < typeLabels.length) ? typeLabels[perkType] : '权益';

  /// 能不能被邀约方申报选用:零售价须为正数,配额须为正整数。
  /// ★ 与小程序 `isUsableTemplate` 同判据 —— 不满足的模板在「申报供给」里不给选。
  bool get usable => (retailValue ?? 0) > 0 && (quota ?? 0) > 0;

  String? get validText =>
      (validEnd != null && validEnd!.length >= 10) ? validEnd!.substring(0, 10) : validEnd;

  factory CoopPerkTemplate.fromJson(Map<String, dynamic> json) {
    return CoopPerkTemplate(
      id: (json['id'] as num?)?.toInt() ?? 0,
      perkType: (json['perkType'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      unitCost: (json['unitCost'] as num?)?.toDouble(),
      retailValue: (json['retailValue'] as num?)?.toDouble(),
      quota: (json['quota'] as num?)?.toInt(),
      validEnd: json['validEnd']?.toString(),
    );
  }
}

/// 已申报到某次合作邀约的供给。对齐后端 `CoopPerk`(/api/coop/perks/list)。
///
/// ★★ `unitCost` 只有受邀方(申报方)本人看得到 —— 后端对发起方主动清空。
///   前端**不许兜成 0** —— 拿不到就整行不显示,别让发起方以为对方成本是零。
class CoopPerk {
  const CoopPerk({
    required this.id,
    required this.perkType,
    required this.name,
    this.unitCost,
    this.retailValue,
    this.quota,
  });

  final int id;
  final int perkType;
  final String name;
  final double? unitCost;
  final double? retailValue;
  final int? quota;

  String get typeText => (perkType >= 0 && perkType < CoopPerkTemplate.typeLabels.length)
      ? CoopPerkTemplate.typeLabels[perkType]
      : '权益';

  factory CoopPerk.fromJson(Map<String, dynamic> json) {
    return CoopPerk(
      id: (json['id'] as num?)?.toInt() ?? 0,
      perkType: (json['perkType'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      unitCost: (json['unitCost'] as num?)?.toDouble(),
      retailValue: (json['retailValue'] as num?)?.toDouble(),
      quota: (json['quota'] as num?)?.toInt(),
    );
  }
}
