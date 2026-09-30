/// 商家资金域金额处理(只读展示)。对齐小程序 `utils/merchant-finance.js`。
///
/// ★ 资金域纪律:
///   1. 金额一律用后端下发的值,前端不自己算、不做加减。
///   2. 解析必须处理 null:区分「没有这个字段」(→ null)和「金额是 0」(→ "0.00")。
///      一律不用 `?? 0` 糊掉 —— 那会把「未结算」渲染成「收入 0 元」。
///   3. 后端 finance 域金额是「CNY 两位字符串」(BigDecimal setScale(2).toPlainString()),
///      这里只做规范化为两位小数展示,不做精度运算。
library;

/// 规范化 CNY 金额为两位小数字符串。
///
/// null / 空串 / 非数字 → **null**(字段缺席,不是 0)。
/// 数字形态(int/double/String)都能收。
String? cny(Object? value) {
  if (value == null) return null;
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  final n = double.tryParse(s);
  if (n == null || !n.isFinite) return null;
  return n.toStringAsFixed(2);
}

/// 金额是否**明确**是零。null(字段缺席)不算零 —— 这是与 `?? 0` 的关键区别。
bool isZeroCny(Object? value) {
  final normalized = cny(value);
  if (normalized == null) return false;
  return normalized == '0.00' || normalized == '-0.00';
}

/// 核销行金额展示(镜像小程序 redemptionRow):
/// - 金额缺席(null)或明确为 0 → 不显示金额,按 displayState 落「—」(不结现金)
///   或「待定」(尚未结算)。
/// - 否则 `+¥xx.xx` / `¥-xx.xx`(正数加号,负数符号跟在 ¥ 后,与小程序一致)。
String redemptionAmountDisplay(Object? settlementAmount, String displayState) {
  final absent = cny(settlementAmount) == null || isZeroCny(settlementAmount);
  if (absent) {
    return displayState == 'NO_CASH_SETTLEMENT' ? '—' : '待定';
  }
  final normalized = cny(settlementAmount)!;
  final negative = normalized.startsWith('-');
  final prefix = negative ? '' : '+';
  return '$prefix¥$normalized';
}

/// 收入明细行金额展示(镜像小程序 entryRow):
/// signedAmount 带符号,正数加 + 号、负数 ¥-xx.xx。
String signedAmountDisplay(Object? signedAmount) {
  final normalized = cny(signedAmount);
  if (normalized == null) return '—';
  final negative = normalized.startsWith('-');
  return negative ? '¥$normalized' : '+¥$normalized';
}

/// 对公批次金额展示(镜像小程序 batchRow):固定 `¥xx.xx`,不带符号。
String batchAmountDisplay(Object? amountTotal) {
  final normalized = cny(amountTotal);
  if (normalized == null) return '—';
  return '¥$normalized';
}

/// 概要数字展示(镜像小程序 summaryView):
/// `¥xx.xx`。null(字段缺席) → '—',不冒充 0。
String summaryMoney(Object? value) {
  final normalized = cny(value);
  if (normalized == null) return '—';
  return '¥$normalized';
}

/// 金额色调。镜像小程序 `fin-row__v--{pos,neg,mute}`
/// (style/merchant-finance.wxss:40-42)。
///
/// ★ 为什么单独一个函数而不是在页面里 `startsWith('-') ? red : green`:
///   「—」和「待定」既不是正也不是负 —— 它们是**金额还不成立**,必须落 mute。
///   按字符串符号判会把这两个判成「正数」渲成绿色,读起来像「已入账 0 元」。
AmountTone amountToneOf(String display) {
  if (display == '—' || display == '待定') return AmountTone.mute;
  return display.contains('-') ? AmountTone.negative : AmountTone.positive;
}

enum AmountTone { positive, negative, mute }
