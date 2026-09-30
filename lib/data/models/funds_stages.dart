/// 余额三段(2026-09-16 晚拍板第 5 条):待结算(活动未结束)→ 客诉期中
/// (X月X日可提现)→ 可提现;涉诉金额单列「客诉处理中」。数据源
/// `POST /api/wallet/stages`(字段与口径全部在后端 `MemberFundsStageService`)。
///
/// ★「如实」是这块的全部逻辑:字段缺失 / 不是数 / 日期坏 ⇒ **整块判「取不到」**,
///   绝不把缺失渲染成 ¥0 —— 0 是合法金额,缺席不是。口径逐条对齐小程序
///   `components/cy/funds-stages/view-model.js` 的 `buildFundsStages`
///   (那条 view-model 有自己的 node:test 用例,本文件是它的 Dart 移植)。
class FundsStageComplaint {
  const FundsStageComplaint({
    required this.key,
    required this.label,
    required this.amountText,
  });

  /// 可提现日(`yyyy-MM-dd`),同一日期后端已合并成一行,页面只按它排序。
  final String key;

  /// 「客诉期中 · 9月24日可提现」。
  final String label;

  /// 两位小数金额文本(后端说的是多少就显示多少)。
  final String amountText;
}

class FundsStages {
  const FundsStages({
    required this.pending,
    required this.complaintPeriod,
    required this.disputed,
    required this.withdrawable,
    required this.amountsKnown,
  });

  /// 待结算金额(两位小数);空串 = 这一段不画(金额 ≤ 0)。
  final String pending;

  /// 客诉期中逐行;空 = 这一段不画。
  final List<FundsStageComplaint> complaintPeriod;

  /// 客诉处理中金额;空串 = 不画。
  final String disputed;

  /// 可提现金额(两位小数)。0 是合法金额,照常显示。
  final String withdrawable;

  /// 后端明说「部分未到账金额暂时算不出」(费率配置异常)时为 false,
  /// 页面照实提示「以结算到账为准」,不拿 0 冒充。
  final bool amountsKnown;
}

/// 把 `/api/wallet/stages` 的 `data` 读成三段;读不懂一律 null(「取不到」)。
FundsStages? buildFundsStages(Object? data) {
  if (data is! Map) return null;
  final Object? rawPeriod = data['complaintPeriod'];
  if (rawPeriod is! List) return null;
  final double? pending = _amount(data['pendingSettlement']);
  final double? disputed = _amount(data['disputed']);
  final double? withdrawable = _amount(data['withdrawable']);
  if (pending == null || disputed == null || withdrawable == null) {
    return null;
  }
  final List<FundsStageComplaint> period = <FundsStageComplaint>[];
  for (final Object? item in rawPeriod) {
    if (item is! Map) return null;
    final double? amount = _amount(item['amount']);
    final String dateKey = item['availableDate']?.toString() ?? '';
    final String? dateText = _complainPeriodDate(dateKey);
    if (amount == null || dateText == null) return null;
    if (amount > 0) {
      period.add(
        FundsStageComplaint(
          key: dateKey,
          label: '客诉期中 · $dateText可提现',
          amountText: amount.toStringAsFixed(2),
        ),
      );
    }
  }
  return FundsStages(
    pending: pending > 0 ? pending.toStringAsFixed(2) : '',
    complaintPeriod: period,
    disputed: disputed > 0 ? disputed.toStringAsFixed(2) : '',
    withdrawable: withdrawable.toStringAsFixed(2),
    amountsKnown: data['amountsKnown'] != false,
  );
}

/// 非负有限数;字符串先 trim(空串不算 0)。其余一律 null。
double? _amount(Object? value) {
  Object? raw = value;
  if (raw is String) {
    final String text = raw.trim();
    if (text.isEmpty) return null;
    raw = num.tryParse(text);
  }
  if (raw is! num) return null;
  final double number = raw.toDouble();
  if (!number.isFinite || number < 0) return null;
  return number;
}

/// `yyyy-MM-dd` → 「9月24日」;别的形状一律 null(不猜日期)。
String? _complainPeriodDate(String value) {
  final RegExpMatch? match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})$',
  ).firstMatch(value);
  if (match == null) return null;
  final int month = int.parse(match.group(2)!);
  final int day = int.parse(match.group(3)!);
  return '$month月$day日';
}
