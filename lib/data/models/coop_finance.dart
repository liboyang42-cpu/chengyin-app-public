import '../../feature/merchant/merchant_money.dart';

/// 合作结算一行(发起人视角看自己发布的主题)。
/// 对齐后端 `CoopInviteServiceImpl.clubFinance`(/api/coop/finance → data.topics)。
///
/// ★★ 这一页的钱有两个方向,别混:
///   - myIncome     = **我(发起人)**的分润
///   - merchantTotal / merchantPaid = **承接方/商家**应收与已付
///   平台佣金(payeeType=platform)后端已剔除,不进任何一方视图。
class CoopFinanceRow {
  const CoopFinanceRow({
    required this.topicId,
    required this.topicName,
    this.hasCustomTopicName = true,
    this.lifecycle,
    this.settled = false,
    this.settledKnown = true,
    this.totalSales,
    this.verifiedSales,
    this.platformAmount,
    this.merchantTotal,
    this.merchantPaid,
    this.myIncome,
    this.myIncomeArrived = false,
    this.myIncomeArrivedKnown = true,
    this.merchantPayableTime,
    this.merchantPayoutTime,
  });

  final int topicId;
  final String topicName;
  /// False only for an absent server name; identical supplied text stays raw.
  final bool hasCustomTopicName;
  final String? lifecycle;
  final bool settled;

  /// 服务端**有没有就 settled 给出布尔判据**。缺判据时真源不猜
  /// (`scene-merchant-profit/index.js:83` `typeof t.settled === 'boolean'`),
  /// 提现口径据此走「待确认」。[settled] 本身仍按 [flag] 的宽松判真。
  final bool settledKnown;

  final String? totalSales;
  final String? verifiedSales;
  final String? platformAmount;
  final String? merchantTotal;
  final String? merchantPaid;

  /// 我的分润。★ **结算前后端下发 null**(待结算),不是 0 ——
  ///   用 `?? 0` 会把「还没结算」显示成「你这单赚了 0 元」。
  final String? myIncome;

  /// 我的分润是否已到账。
  final bool myIncomeArrived;

  /// 同上,针对 myIncomeArrived 的布尔判据
  /// (`scene-merchant-profit/index.js:85`)。
  final bool myIncomeArrivedKnown;

  /// 承接方 T+7 预告到账日 / 实际到账日。
  final String? merchantPayableTime;
  final String? merchantPayoutTime;

  /// 我的分润展示。三态,不能合并:
  /// 未结算(null)→「待结算」;已结算已到账 → 金额;已结算未到账 → 金额 + 在途。
  String get myIncomeDisplay {
    final v = cny(myIncome);
    if (v == null) return '待结算';
    return '¥$v';
  }

  /// 到账提示。★ 只有在**有金额**时才谈到账;没金额时说到账与否毫无意义。
  String? get myIncomeHint {
    if (cny(myIncome) == null) return null;
    return myIncomeArrived ? '已到账' : '结算完成,等待打款';
  }

  /// 承接方到账信息。实际到账日优先于预告日;都没有则不显示这一行。
  String? get merchantPayoutHint {
    if ((merchantPayoutTime ?? '').isNotEmpty) {
      return '承接方已于 $merchantPayoutTime 到账';
    }
    if ((merchantPayableTime ?? '').isNotEmpty) {
      return '承接方预计 $merchantPayableTime 到账';
    }
    return null;
  }

  factory CoopFinanceRow.fromJson(Map<String, dynamic> json) {
    String? str(String k) => json[k]?.toString();
    bool flag(String k) {
      final value = json[k];
      return value == true || value == 1 || value == '1';
    }

    return CoopFinanceRow(
      topicId: (json['topicId'] as num?)?.toInt() ?? 0,
      topicName: (json['topicName'] as String?) ?? '未命名主题',
      hasCustomTopicName: json['topicName'] != null,
      lifecycle: str('lifecycle'),
      settled: flag('settled'),
      settledKnown: json['settled'] is bool,
      totalSales: str('totalSales'),
      verifiedSales: str('verifiedSales'),
      platformAmount: str('platformAmount'),
      merchantTotal: str('merchantTotal'),
      merchantPaid: str('merchantPaid'),
      // ⚠️ 不能用 `?? '0'` —— null 表示待结算,与 "0.00" 含义不同。
      myIncome: json['myIncome']?.toString(),
      myIncomeArrived: flag('myIncomeArrived'),
      myIncomeArrivedKnown: json['myIncomeArrived'] is bool,
      merchantPayableTime: json['merchantPayableTime'] as String?,
      merchantPayoutTime: json['merchantPayoutTime'] as String?,
    );
  }
}
