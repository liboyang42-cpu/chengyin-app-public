/// 商家营销首页。对齐 `/api/merchant/marketing-home` →
/// `MerchantAggregateReadServiceImpl.marketingHome`。
class MerchantMarketing {
  const MerchantMarketing({
    this.couponCount = 0,
    this.couponReceived = 0,
    this.couponVerified = 0,
    this.topicCount = 0,
    this.freeExploreCount = 0,
    this.activityCount = 0,
    this.funnel = const <FunnelStep>[],
  });

  final int couponCount;
  final int couponReceived;
  final int couponVerified;
  final int topicCount;
  final int freeExploreCount;
  final int activityCount;
  final List<FunnelStep> funnel;

  /// 券核销率。★ 领取数为 0 时返回 null(**不是 0%**)——
  ///   没人领过券,谈不上核销率;显示「0%」会让商家以为券做得差。
  double? get verifyRate =>
      couponReceived > 0 ? couponVerified / couponReceived : null;

  factory MerchantMarketing.fromJson(Map<String, dynamic> json) {
    int n(Object? m, String k) =>
        m is Map<String, dynamic> ? ((m[k] as num?)?.toInt() ?? 0) : 0;
    final coupons = json['coupons'];
    final content = json['content'];
    final funnelRaw = json['funnel'];
    return MerchantMarketing(
      couponCount: n(coupons, 'couponCount'),
      couponReceived: n(coupons, 'received'),
      couponVerified: n(coupons, 'verified'),
      topicCount: n(content, 'topicCount'),
      freeExploreCount: n(content, 'freeExploreCount'),
      activityCount: n(content, 'activityCount'),
      funnel: (funnelRaw is List ? funnelRaw : const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(FunnelStep.fromJson)
          .toList(),
    );
  }
}

/// 漏斗一档。
class FunnelStep {
  const FunnelStep({required this.step, this.count = 0, this.rate});

  final String step;
  final int count;

  /// 后端算好的 0-1 小数**字符串**;base 为 0 时后端给 "0"。
  final String? rate;

  /// 百分比展示。★ 解析不出来时返回 null 让界面不显示这一行,
  ///   而不是显示「0%」—— 那会被当成真实的 0。
  String? get ratePercent {
    final v = double.tryParse(rate ?? '');
    if (v == null) return null;
    return '${(v * 100).toStringAsFixed(v * 100 % 1 == 0 ? 0 : 1)}%';
  }

  /// 画条形图用的比例,0-1。
  double get ratio {
    final v = double.tryParse(rate ?? '') ?? 0;
    return v.clamp(0.0, 1.0);
  }

  factory FunnelStep.fromJson(Map<String, dynamic> json) {
    return FunnelStep(
      step: (json['step'] as String?) ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
      rate: json['rate']?.toString(),
    );
  }
}
