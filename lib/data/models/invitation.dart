/// 邀请人绑定。对齐后端 `MemberInvitationServiceImpl.bindInviter`
/// 与 `/api/user/setInviter`。
///
/// ★ 后端有三条规则,前端能挡的先挡:
///   1. inviterId 非法(空/非数字/<=0)→ 直接拒
///   2. **不能绑自己**(parsedInviterId.equals(memberId))
///   3. `bindInviterIfAbsent` —— **只在还没绑定时生效**,已绑过再绑返回 false
///
/// ⚠️ 第 3 条决定了失败文案:后端只回一句笼统的失败,
///   但用户最可能的处境是「已经绑过了」—— 说成"绑定失败,请重试"会让他反复试。
class InviterBinding {
  const InviterBinding._();

  /// 本地能判定的拒绝原因。返回 null 表示可以提交给后端。
  static String? localReject({
    required String? inviterId,
    required int? myMemberId,
  }) {
    final raw = inviterId?.trim() ?? '';
    if (raw.isEmpty) return '邀请码是空的';
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed <= 0) return '这个邀请码不对';
    if (myMemberId != null && parsed == myMemberId) {
      return '不能填自己的邀请码';
    }
    return null;
  }

  /// 后端返回失败时给的说法。
  ///
  /// ★ 后端 setInviter 失败只回一句统一文案,分不出是"已绑过"还是"码不对"。
  ///   ⚠️ 所以**不要编一个确定的原因** —— 把两种可能都说出来,
  ///   并明确「不用重试」,否则用户会反复点。
  static const String remoteFailureHint =
      '没能绑定。可能这个邀请码不存在,也可能你之前已经绑过邀请人了 —— 邀请人只能绑一次,重试不会有变化。';
}
