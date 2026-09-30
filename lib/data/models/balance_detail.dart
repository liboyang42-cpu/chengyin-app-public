/// 余额流水一条:`POST /api/user/balance/list`。
///
/// ★★ **两个 type 并存,管的不是一件事**:
///   · `changeType` —— 方向:1 收入 / 2 支出
///   · `eventType`  —— 事由:1 主题分润 / 2 活动分润 / 3 提现申请 /
///                          4 提现驳回 / 5 商家邀请分润
///
///   ⚠️ 用 eventType 猜方向会错:**提现申请(3)是支出、提现驳回(4)是收入**
///     —— 同一件事的两半,方向相反。只有 changeType 说得准。
///
/// ★ 金额是 BigDecimal,可能以字符串下发。这里保持字符串原样显示,
///   不 parse 成 double 再格式化(见 merchant_finance.dart 里同一条理由)。
library;

class BalanceDetail {
  const BalanceDetail({
    required this.id,
    this.changeBalance,
    this.afterBalance,
    this.changeReason,
    this.changeType,
    this.eventType,
    this.eventId,
    this.createTime,
  });

  final int id;

  /// 变化金额(原样字符串)。null = 后端没给,**不是 0**。
  final String? changeBalance;

  /// 变化后余额(原样字符串)。
  final String? afterBalance;

  final String? changeReason;

  /// 方向:1 收入 / 2 支出。**判进出只看它**。
  final int? changeType;

  /// 事由:1 主题分润 / 2 活动分润 / 3 提现申请 / 4 提现驳回 / 5 商家邀请分润。
  final int? eventType;

  final int? eventId;
  final String? createTime;

  bool get isIncome => changeType == 1;
  bool get isExpense => changeType == 2;

  /// 事由文案。未知值说「其他」而不是编一个 —— 后端加了新类型时,
  /// 编出来的名字会一直错下去而没人发现。
  String get eventLabel {
    switch (eventType) {
      case 1:
        return '主题分润';
      case 2:
        return '活动分润';
      case 3:
        return '提现申请';
      case 4:
        return '提现驳回';
      case 5:
        return '商家邀请分润';
      default:
        return '其他';
    }
  }

  /// 带符号的展示金额。
  ///
  /// ★ 符号由 **changeType** 决定,不是看金额本身有没有负号 ——
  ///   后端存的是绝对值,自己判负号会让所有支出都显示成收入。
  String? get signedAmount {
    final String? a = changeBalance;
    if (a == null || a.isEmpty) return null;
    if (isExpense) return a.startsWith('-') ? a : '-$a';
    return a;
  }

  static int _int(Object? v) => v is num ? v.toInt() : 0;
  static int? _intOrNull(Object? v) => v is num ? v.toInt() : null;

  factory BalanceDetail.fromJson(Map<String, dynamic> json) => BalanceDetail(
        id: _int(json['id']),
        changeBalance: json['changeBalance']?.toString(),
        afterBalance: json['afterBalance']?.toString(),
        changeReason: json['changeReason']?.toString(),
        changeType: _intOrNull(json['changeType']),
        eventType: _intOrNull(json['eventType']),
        eventId: _intOrNull(json['eventId']),
        createTime: json['createTime']?.toString(),
      );
}

/// 余额流水的方向筛选。
enum BalanceFilter {
  all('', '全部'),
  income('1', '收入'),
  expense('2', '支出');

  const BalanceFilter(this.wire, this.label);
  final String wire;
  final String label;
}

/// 收益明细的**事由**筛选(对应小程序 scene-asset-income-detail 的四个 chip)。
///
/// ⚠️ 和 [BalanceFilter] 不是一个轴:那个筛收支方向(change_type),
///   这个筛事由(eventType)。后端 `/api/user/balance/list` 只认后者。
enum IncomeEventFilter {
  all('', '全部'),
  create('1', '创作收益'),
  brand('2', '品牌收益'),
  /// 俱乐部分润走的是另一条链路(`/api/coop/finance`),不在本接口里 ——
  /// 选中它要跳到合作财务页,不是换个参数重查。
  club('', '俱乐部');

  const IncomeEventFilter(this.wire, this.label);
  final String wire;
  final String label;
}
