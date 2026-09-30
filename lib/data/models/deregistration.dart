/// 账号注销状态,对齐后端 `DeregistrationStatusVO`。
///
/// status 取值:
///  · NORMAL    从未申请过(status 接口无记录时)
///  · ELIGIBLE  预检通过,可以申请
///  · BLOCKED   有阻断项,blockers 里是原因
///  · 其余      已提交申请后的流水状态(冷静期中),配合 executeAfter 展示
///
/// ⚠️ blockers 是后端按「钱在动的账号不许注销」算出来的(余额/在途提现/
/// 进行中订单/有效报名/商家俱乐部身份),文案由服务端下发,客户端**原样展示**,
/// 不在前端复刻判据 —— 复刻两份必然漂移,而这条链路错了会造成资损。
class DeregistrationStatus {
  const DeregistrationStatus({
    required this.status,
    required this.blockers,
    this.executeAfter,
  });

  final String status;
  final List<String> blockers;

  /// 冷静期到期执行时间;为 null 表示当前没有在途申请。
  final String? executeAfter;

  bool get isNormal => status == 'NORMAL';
  bool get isEligible => status == 'ELIGIBLE';
  bool get isBlocked => status == 'BLOCKED';

  /// 有在途申请(冷静期中)= 拿得到执行时间,且不是前两种预检态。
  bool get isPending =>
      executeAfter != null && !isNormal && !isEligible && !isBlocked;

  factory DeregistrationStatus.fromJson(Map<String, dynamic> json) {
    final raw = (json['blockers'] as List<dynamic>?) ?? <dynamic>[];
    return DeregistrationStatus(
      status: (json['status'] as String?) ?? 'NORMAL',
      blockers: raw.map((dynamic e) => e.toString()).toList(),
      executeAfter: json['executeAfter']?.toString(),
    );
  }
}
