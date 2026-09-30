import 'package:dio/dio.dart';

/// 资金域(提现记录等)读失败副文案:后端给了中文原话就用原话;
/// dio 英文栈(`DioException [bad response] … developer.mozilla.org`)
/// 换成人话兜底。资金页上尤其不能把英文堆栈甩给用户
/// (见 b1-sim-r10-withdrawal P1-1,兜底文案逐字对齐真源 cy-error,
/// 由 main 的 withdrawal_funds_entry 测试锁死)。
String withdrawalFailureSub(Object error) {
  if (error is! DioException) return '$error';
  final Object? data = error.response?.data;
  final String msg = data is Map ? (data['msg']?.toString().trim() ?? '') : '';
  return msg.isEmpty ? '网络可能不稳定，你的提现记录还在' : msg;
}
