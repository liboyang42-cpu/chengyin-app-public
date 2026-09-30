import '../../feature/merchant/merchant_money.dart';

/// 商家工作台数据。对齐后端 `ApiMerchantController.getDashboard`(/api/merchant/dashboard)。
///
/// ★ 资金域:金额一律保留后端下发的**字符串原样**,不转 double 再格式化 ——
///   后端已经 setScale(2).toPlainString(),前端再转一手只会引入精度问题。
class MerchantDashboard {
  const MerchantDashboard({
    this.revenue,
    this.pendingOrders = 0,
    this.revenue7d = const <RevenuePoint>[],
  });

  /// 品牌累计收入(后端字符串,可能缺席)。
  final String? revenue;

  /// 待处理订单数(作为卖家、待发货)。
  final int pendingOrders;

  /// 近 7 日收入。
  final List<RevenuePoint> revenue7d;

  /// 展示用金额。缺席显破折号,不冒充 0。
  String get revenueDisplay => summaryMoney(revenue);

  factory MerchantDashboard.fromJson(Map<String, dynamic> json) {
    return MerchantDashboard(
      revenue: json['revenue'] as String?,
      pendingOrders: (json['pendingOrders'] as num?)?.toInt() ?? 0,
      revenue7d: ((json['revenue7d'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(RevenuePoint.fromJson)
          .toList(),
    );
  }
}

class RevenuePoint {
  const RevenuePoint({required this.date, this.amount});

  final String date;
  final String? amount;

  /// 画图用的数值。解析不出来当 0 处理 —— **仅限画图**,
  /// 展示金额一律走 summaryMoney,不能用这个。
  double get value => double.tryParse(amount ?? '') ?? 0;

  factory RevenuePoint.fromJson(Map<String, dynamic> json) {
    return RevenuePoint(
      date: (json['date'] as String?) ?? '',
      amount: json['amount'] as String?,
    );
  }
}

/// 商家待办概要。对齐 `/api/merchant/todo-summary`。
///
/// ★ 每一项都是一个**需要商家去做的动作**,不是统计数字。
///   所以为 0 的项不该显示 —— 显示「待核销 0」只是噪音。
class MerchantTodo {
  const MerchantTodo({
    this.biddingTopics = 0,
    this.pendingVerify = 0,
    this.verifiedCount = 0,
    this.pendingScanConfirm = 0,
    this.pendingOrders = 0,
    this.refundCount = 0,
    this.byProject = const <MerchantProjectTodo>[],
    this.projectBreakdownAvailable = false,
  });

  /// 已中标主题数。
  final int biddingTopics;

  /// 待核销。
  final int pendingVerify;

  /// 已核销(这一项是**结果**不是待办,单独展示)。
  final int verifiedCount;

  /// 待确认的扫码。
  final int pendingScanConfirm;

  /// 待处理订单。
  final int pendingOrders;

  /// 退款单数。
  final int refundCount;

  final List<MerchantProjectTodo> byProject;
  final bool projectBreakdownAvailable;

  bool get hasProjectBreakdown =>
      projectBreakdownAvailable || byProject.isNotEmpty;

  MerchantProjectTodo? project(int ownerType, int ownerId) {
    for (final row in byProject) {
      if (row.ownerType == ownerType && row.ownerId == ownerId) return row;
    }
    return null;
  }

  /// 需要商家动手的总数。★ 不含 verifiedCount —— 那是已完成的,不是待办。
  int get actionableTotal =>
      pendingVerify + pendingScanConfirm + pendingOrders + refundCount;

  bool get hasAnything => actionableTotal > 0;

  factory MerchantTodo.fromJson(Map<String, dynamic> json) {
    int n(String k) => (json[k] as num?)?.toInt() ?? 0;
    return MerchantTodo(
      biddingTopics: n('biddingTopics'),
      pendingVerify: n('pendingVerify'),
      verifiedCount: n('verifiedCount'),
      pendingScanConfirm: n('pendingScanConfirm'),
      pendingOrders: n('pendingOrders'),
      refundCount: n('refundCount'),
      byProject: ((json['byProject'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(MerchantProjectTodo.tryParse)
          .whereType<MerchantProjectTodo>()
          .toList(growable: false),
      projectBreakdownAvailable: json['byProject'] is List<dynamic>,
    );
  }
}

class MerchantProjectTodo {
  const MerchantProjectTodo({
    required this.ownerType,
    required this.ownerId,
    this.pendingVerify = 0,
    this.pendingScanConfirm = 0,
  });

  final int ownerType;
  final int ownerId;
  final int pendingVerify;
  final int pendingScanConfirm;

  int get actionableTotal => pendingVerify + pendingScanConfirm;

  static MerchantProjectTodo? tryParse(Map<String, dynamic> json) {
    final ownerType = (json['ownerType'] as num?)?.toInt();
    final ownerId = (json['ownerId'] as num?)?.toInt();
    if (ownerType == null ||
        (ownerType != 1 && ownerType != 2) ||
        ownerId == null ||
        ownerId <= 0) {
      return null;
    }
    int count(String key) {
      final value = (json[key] as num?)?.toInt() ?? 0;
      return value < 0 ? 0 : value;
    }

    return MerchantProjectTodo(
      ownerType: ownerType,
      ownerId: ownerId,
      pendingVerify: count('pendingVerify'),
      pendingScanConfirm: count('pendingScanConfirm'),
    );
  }
}
