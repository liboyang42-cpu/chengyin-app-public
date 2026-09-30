import 'dart:math' as math;

/// 主题终价确认。对齐后端 `PricingResult`(/api/topic/pricing/preview)。
///
/// ★ 这是资金路径:终价一旦确认就开售,定错了要退票。所以这里的每一段算法
///   都做成纯函数并被测试锁死,而不是散在页面的 setState 里。
class PricingPreview {
  const PricingPreview({
    required this.priceMin,
    this.cityReferencePrice,
    this.cityReferenceSampleSize = 0,
    this.cityReferenceLabel,
    this.lineup = const <PricingLineupRow>[],
  });

  /// 乙-2 成本地板。终价**不可低于**它。
  final double priceMin;
  final double? cityReferencePrice;
  final int cityReferenceSampleSize;
  final String? cityReferenceLabel;

  /// 已锁定阵容(后端 `PricingResult.Lineup`)。真源 `pages/topic/pricing/index.js`
  /// 只保留带 toType/toId 的行,名称另走公开档案接口补齐。
  final List<PricingLineupRow> lineup;

  factory PricingPreview.fromJson(Map<String, dynamic> json) {
    final min = (json['priceMin'] as num?)?.toDouble();
    if (min == null || !min.isFinite) {
      // 地板算不出来就没法定价 —— 这不是「显示成 0」的场合,必须挡住。
      throw const PricingIncompleteException();
    }
    final rows =
        (json['lineup'] as List<dynamic>?)?.whereType<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    return PricingPreview(
      priceMin: min,
      cityReferencePrice: (json['cityReferencePrice'] as num?)?.toDouble(),
      cityReferenceSampleSize:
          (json['cityReferenceSampleSize'] as num?)?.toInt() ?? 0,
      cityReferenceLabel: json['cityReferenceLabel'] as String?,
      lineup: <PricingLineupRow>[
        for (final row in rows)
          if (PricingLineupRow.tryParse(row)
              case final PricingLineupRow lineupRow)
            lineupRow,
      ],
    );
  }

  /// 滑杆下界 = 地板向上取整。**不能向下取整** —— 那会让终价低于地板。
  int get sliderMin => priceMin.ceil();

  /// 滑杆上界。三者取大:下界+100 / 地板×2 / 参考价×1.5。
  int get sliderMax {
    final ref = cityReferencePrice;
    return math.max(
      math.max(sliderMin + 100, (priceMin * 2).ceil()),
      ref == null ? 0 : (ref * 1.5).ceil(),
    );
  }

  /// 参考价文案。样本不足时**明说样本不足**,而不是显示一个没有依据的数。
  String get referenceText {
    final ref = cityReferencePrice;
    if (ref == null || cityReferenceSampleSize <= 0) return '样本不足,暂不展示参考价';
    final city = cityReferenceLabel ?? '同城';
    return '$city同类已开售均价 ¥${_money(ref)}($cityReferenceSampleSize 个样本)';
  }

  /// 相对同城参考价的偏离文案。没有参考价时为空串(不显示这一行)。
  String deltaText(num finalPrice) {
    final ref = cityReferencePrice;
    if (ref == null || ref == 0) return '';
    final pct = ((finalPrice - ref) / ref * 100).round();
    return pct > 0 ? '高于同城参考 $pct%' : '未高于同城参考价';
  }

  /// 能不能确认。★ 唯一判据是**不低于地板**,不是「用户拖过滑杆了」。
  bool canConfirm(num finalPrice) => finalPrice >= priceMin;
}

/// 后端回了但地板缺失/非数。这不是网络错误,文案要区分开。
class PricingIncompleteException implements Exception {
  const PricingIncompleteException();
  @override
  String toString() => '定价信息不完整,请稍后重试';
}

/// 金额显示:去掉无意义的小数尾巴(100.00 → 100,99.50 → 99.5)。
String _money(double v) {
  final s = v.toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// 定价子类型。guided=带队(要填带队成本与成团人数),self=自玩。
enum PricingSubType { guided, self }

extension PricingSubTypeX on PricingSubType {
  String get wire => this == PricingSubType.guided ? 'guided' : 'self';
  String get label => this == PricingSubType.guided ? '带队' : '自玩';
}

/// 阵容一行:后端只给 toType/toId + 条款,名称由公开档案接口异步补齐。
class PricingLineupRow {
  const PricingLineupRow({
    required this.toType,
    required this.toId,
    required this.shareMode,
    this.shareRate,
    this.fixedFee,
  });

  final String toType;
  final int toId;

  /// 0 引流 / 1 分成 / 2 固定。
  final int shareMode;

  /// 后端原样值(可能是数字或字符串);空串/null = 未填。
  final String? shareRate;
  final String? fixedFee;

  /// 真源 `pricing/index.js`:只保留 `row.toType && row.toId` 齐全的行。
  static PricingLineupRow? tryParse(Map<String, dynamic> json) {
    final toType = '${json['toType'] ?? ''}'.trim();
    final toId = _positiveInt(json['toId']);
    if (toType.isEmpty || toId == null) return null;
    // 后端可能回数字也可能回字符串数字(小程序 `Number(item.shareMode)` 同样两种都吃)。
    final rawMode = json['shareMode'];
    final shareMode = rawMode is num
        ? rawMode.toInt()
        : int.tryParse('${rawMode ?? ''}'.trim()) ?? -1;
    return PricingLineupRow(
      toType: toType,
      toId: toId,
      shareMode: shareMode,
      shareRate: _raw(json['shareRate']),
      fixedFee: _raw(json['fixedFee']),
    );
  }

  /// 定价页阵容行的条款摘要。真源 `termsText(row)` 逐字。
  String get termsText => switch (shareMode) {
    1 =>
      '分成型 · ${shareRate == null || shareRate!.isEmpty ? '—' : '${shareRate!}%'}',
    2 => '固定 · ¥${fixedFee == null || fixedFee!.isEmpty ? '—' : fixedFee!}/人',
    _ => '引流型',
  };

  String get fallbackName => toType == 'club' ? '合作俱乐部' : '承接商家';

  /// 合作方详情页的条款校验。真源 `normalizedTerms`:认不出的条款**不是**
  /// 「按 0 处理」,而是整块报错 —— 条款缺失时宁可不出,不猜。
  PricingLineupTerms? get terms {
    if (![0, 1, 2].contains(shareMode)) return null;
    if (shareMode == 1) {
      final rate = shareRate;
      final value = rate == null || rate.trim().isEmpty
          ? null
          : num.tryParse(rate.trim());
      if (value == null || !value.isFinite || value < 0 || value > 100) {
        return null;
      }
      return PricingLineupTerms(
        shareMode: 1,
        shareRateText: rate!,
        fixedFeeText: '',
      );
    }
    if (shareMode == 2) {
      final fee = fixedFee;
      final value = fee == null || fee.trim().isEmpty
          ? null
          : num.tryParse(fee.trim());
      if (value == null || !value.isFinite || value < 0) return null;
      return PricingLineupTerms(
        shareMode: 2,
        shareRateText: '',
        fixedFeeText: fee!,
      );
    }
    return const PricingLineupTerms(
      shareMode: 0,
      shareRateText: '',
      fixedFeeText: '',
    );
  }
}

/// 校验通过的条款(值保留后端原样,展示各自加单位)。
class PricingLineupTerms {
  const PricingLineupTerms({
    required this.shareMode,
    required this.shareRateText,
    required this.fixedFeeText,
  });

  final int shareMode;
  final String shareRateText;
  final String fixedFeeText;

  String get settlementName => switch (shareMode) {
    1 => '分成型',
    2 => '固定型',
    _ => '引流型',
  };

  /// 空值口径走 `money.wxs`:空 → 「—」,0 是合法金额照常出 ¥0。
  String get shareRateDisplay =>
      shareMode == 1 && shareRateText.trim().isNotEmpty
      ? '$shareRateText%'
      : '—';
  String get fixedFeeDisplay => shareMode == 2 && fixedFeeText.trim().isNotEmpty
      ? '¥$fixedFeeText/人'
      : '—';

  /// 真源 partner `termsFootnote(shareMode)` 逐字。
  String get footnote => switch (shareMode) {
    1 => '开售后条款冻结，按实际票款参与分成结算。',
    2 => '开售后条款冻结，按实际核销人头结算。',
    _ => '开售后阵容冻结；引流型合作不产生现金分成。',
  };
}

int? _positiveInt(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  if (text.isEmpty) return null;
  final number = num.tryParse(text);
  if (number == null || !number.isFinite) return null;
  final intResult = number.toInt();
  return intResult == number && intResult > 0 ? intResult : null;
}

String? _raw(Object? value) {
  if (value == null) return null;
  final text = '$value';
  return text;
}
