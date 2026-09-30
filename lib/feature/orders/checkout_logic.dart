/// 结算支付状态机的纯判据 —— 与小程序 `utils/checkout/checkout-workflow.js`
/// (2026-09-17 拍板 #21 + fix-be-0917 B-R2)同源逐条移植。
///
/// 两条「旧幂等键不可用」的来源,前端都识别,识别面只用于**自动换幂等键重建一次**:
///  · ① `/pay`·`/pay/app` 对过期待支付单的拒绝 —— 后端映射成业务 code 410
///    (HTTP 仍是 200);文案兜底兼容尚未升级的 jar。
///  · ② `/create` 对终态单(已取消3/已过期4)的拒绝 —— 不再当重放返回,
///    改抛 409「该幂等键对应的报名已取消/已过期，请重新发起报名」。
/// 同码 409 的「价格已更新，请重新确认」是另一回事:那是重报价,不是重建。
library;

const int orderExpiredCode = 410;
const String orderExpiredText = '订单已过期';
const int terminalOrderConflictCode = 409;
const String terminalOrderConflictText = '该幂等键对应的报名已';

/// 与后端拒绝原文逐字同源(`CmsRegistrationServiceImpl.preparePaymentRetry`),
/// 重建仍失败时给用户看这句。
const String orderExpiredUserMessage = '订单已过期,请重新报名';

/// 来源①:code 410,或(未升级 jar 的)文案兜底。
bool isOrderExpiredFailure({required int? code, String message = ''}) {
  if (code == orderExpiredCode) return true;
  return message.contains(orderExpiredText);
}

/// 来源②:409 且文案点名旧幂等键对应的单已进终态。
bool isTerminalOrderConflict({required int? code, String message = ''}) {
  if (code != terminalOrderConflictCode) return false;
  return message.contains(terminalOrderConflictText);
}

/// 价格变更(409 的另一半):走重报价,不走重建。
bool isPriceChangedFailure({required int? code}) =>
    code == terminalOrderConflictCode;

/// 重报价分支给用户的固定提示(真源 tips 逐字)。
const String priceChangedUserMessage = '价格已更新，请重新确认';

/// `baoming.js` handlePayment catch 的分流结论。
enum CheckoutFailureRoute {
  /// 旧幂等键对应的单已终态/已过期 → **换键重建一次**。
  rebuild,

  /// 409 但不是终态冲突 → 价格变了:重报价 + [priceChangedUserMessage]。
  priceChanged,
}

/// null = 不特判,原样把后端 msg 报给用户。
/// ⚠️ 终态冲突必须先于「409 即价格变更」判 —— 同码两条语义,文案定身份。
CheckoutFailureRoute? routeCheckoutFailure({
  required int? code,
  String message = '',
}) {
  if (isTerminalOrderConflict(code: code, message: message)) {
    return CheckoutFailureRoute.rebuild;
  }
  if (isOrderExpiredFailure(code: code, message: message)) {
    return CheckoutFailureRoute.rebuild;
  }
  if (isPriceChangedFailure(code: code)) {
    return CheckoutFailureRoute.priceChanged;
  }
  return null;
}
