import 'package:dio/dio.dart';

import '../../data/models/city_node_detail.dart';

/// 据点核销码页(玩家出码)的纯逻辑。对齐小程序
/// `subpackageRoam/citynode-code`:missing 与 error 必须分家 ——
/// 缺参不可能靠重试变出参数,给它重试就是假按钮。

enum CityNodeVoucherPhase {
  /// 链接缺 poiId:唯一走得通的出口是返回,零重试。
  missing,

  /// 出码中。
  loading,

  /// 码已出(有 code 就算 ready;qrcodeUrl 可能为空,出码接口的二维码
  /// 生成失败不影响 code 本身)。
  ready,

  /// 出码失败:可重试。
  error,
}

/// 进页初始态:缺参 → missing,否则 loading。
CityNodeVoucherPhase voucherInitialPhase({int? poiId}) {
  if (poiId == null || poiId <= 0) return CityNodeVoucherPhase.missing;
  return CityNodeVoucherPhase.loading;
}

/// 出码结果 → 态。★ 判据是 code 在不在,不是 qrcodeUrl:
/// 后端二维码生成失败时仍会带着 code 返回,二维码区降级占位、码文本照常可用。
CityNodeVoucherPhase voucherPhaseFromIssue(CityNodeVoucher voucher) =>
    voucher.hasCode ? CityNodeVoucherPhase.ready : CityNodeVoucherPhase.error;

/// 出码失败的稳定文案(不对用户展示后端原文/异常类型)。
/// 网络异常与业务失败分开说 —— 两者用户要做的事不一样。
String voucherErrorMessage(Object error) {
  if (error is DioException) return '网络异常，请检查网络后重试';
  return '暂时无法生成核销码，请稍后重试';
}

/// 倒计时下一步:到 0 返回 null(调用方触发自动重新出码)。
int? nextVoucherCountdown(int current) {
  final int next = current - 1;
  return next <= 0 ? null : next;
}
