/// 支付后终态轮询 —— 与小程序 `utils/checkout/payment-verifier.js` +
/// `registration-payment-verifier.js` 同参同判据的 Dart 端口。
///
/// 节奏:每 [interval] 打一次 `POST /api/registration/info`,单请求最多
/// [perRequestTimeout],总墙钟 [totalDeadline] 到点仍无终态 → `unknown`
/// (不是失败 —— 钱可能已经扣了,催用户去订单看,别重复支付)。
library;

import 'dart:async';

enum RegistrationVerifyStatus { success, failed, pending }

/// 判据逐字对齐 `classifyRegistrationStatus`:
/// paymentStatus==2 或 registrationStatus==2 → success;
/// paymentStatus∈{3,4} 或 registrationStatus==3 → failed;
/// 其余(包括查不到)→ 继续等。
RegistrationVerifyStatus classifyRegistrationStatus(Map<String, dynamic>? res) {
  if (res == null) return RegistrationVerifyStatus.pending;
  int? n(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
  final int? payment = n(res['paymentStatus']);
  final int? registration = n(res['registrationStatus']);
  if (payment == 2 || registration == 2) {
    return RegistrationVerifyStatus.success;
  }
  if (payment == 3 || payment == 4 || registration == 3) {
    return RegistrationVerifyStatus.failed;
  }
  return RegistrationVerifyStatus.pending;
}

class PaymentVerifyOutcome {
  const PaymentVerifyOutcome({
    required this.status,
    this.data,
    this.errMsg = '',
  });

  /// 'success' | 'failed' | 'unknown'。
  final String status;
  final Map<String, dynamic>? data;
  final String errMsg;
}

/// 与真源逐字同源(payment-verifier.js finish('unknown'))。
const String paymentUnknownErrMessage = '支付结果未知，请到订单查看，暂不要重复支付';

class RegistrationPaymentVerifier {
  RegistrationPaymentVerifier({
    required this.requestStatus,
    this.interval = const Duration(milliseconds: 1500),
    this.perRequestTimeout = const Duration(milliseconds: 5000),
    Duration totalDeadline = const Duration(milliseconds: 20000),
    Stopwatch Function()? stopwatchFactory,
  }) : // 真源纪律:总时限不得小于单请求时限,否则第一发就没有预算。
       totalDeadline = totalDeadline > perRequestTimeout
           ? totalDeadline
           : perRequestTimeout,
       _stopwatch = stopwatchFactory ?? Stopwatch.new;

  /// 回读一次订单状态;查不到/异常返回 null(按 pending 处理,继续等)。
  final Future<Map<String, dynamic>?> Function(int registrationId)
  requestStatus;

  final Duration interval;
  final Duration perRequestTimeout;
  final Duration totalDeadline;
  final Stopwatch Function() _stopwatch;

  bool _aborted = false;

  void abort() => _aborted = true;

  Future<PaymentVerifyOutcome> verify(int registrationId) async {
    final Stopwatch watch = _stopwatch()..start();
    Duration remaining() => totalDeadline - watch.elapsed;
    Duration minDuration(Duration a, Duration b) => a < b ? a : b;

    while (!_aborted) {
      if (remaining() <= Duration.zero) {
        return const PaymentVerifyOutcome(
          status: 'unknown',
          errMsg: paymentUnknownErrMessage,
        );
      }
      Map<String, dynamic>? res;
      try {
        res = await requestStatus(
          registrationId,
        ).timeout(minDuration(perRequestTimeout, remaining()));
      } on Object {
        res = null;
      }
      if (_aborted) {
        return const PaymentVerifyOutcome(
          status: 'unknown',
          data: null,
          errMsg: paymentUnknownErrMessage,
        );
      }
      final RegistrationVerifyStatus status = classifyRegistrationStatus(res);
      if (status == RegistrationVerifyStatus.success) {
        return PaymentVerifyOutcome(status: 'success', data: res);
      }
      if (status == RegistrationVerifyStatus.failed) {
        final String raw = res?['errMsg']?.toString().trim() ?? '';
        return PaymentVerifyOutcome(
          status: 'failed',
          data: res,
          errMsg: raw.isEmpty ? '支付未完成' : raw,
        );
      }
      if (remaining() <= Duration.zero) {
        return PaymentVerifyOutcome(
          status: 'unknown',
          data: res,
          errMsg: paymentUnknownErrMessage,
        );
      }
      await Future<void>.delayed(minDuration(interval, remaining()));
    }
    return const PaymentVerifyOutcome(
      status: 'unknown',
      data: null,
      errMsg: paymentUnknownErrMessage,
    );
  }
}
