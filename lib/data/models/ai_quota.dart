/// AI 创作配额。对齐 `/api/ai/theme/draft/quota`。
///
/// ★★ `limited` 与 `remaining` 是一对,**不能只看 remaining**:
///   - `limited=false` → **不限量**,这时 remaining 无意义(可能是 0 也可能缺席)
///   - `limited=true`  → 看 remaining 决定还能不能生成
///
///   只看 `remaining <= 0` 就禁用按钮,会把**不限量**的用户也挡在门外。
class AiQuota {
  const AiQuota({this.limited = false, this.remaining = 0, this.loaded = false});

  final bool limited;
  final int remaining;

  /// 有没有真的取到配额。★ 没取到时**不该禁用** ——
  ///   拿不到配额就把功能关掉,等于用一次网络抖动废掉一个功能。
  final bool loaded;

  /// 还能不能生成。
  bool get canGenerate {
    if (!loaded) return true; // 没取到就先放行,让后端把关
    if (!limited) return true; // 不限量
    return remaining > 0;
  }

  /// 剩余提示。★ 不限量时**不显示** —— 显示「剩余 0 次」会吓到人。
  String? get remainingText {
    if (!loaded || !limited) return null;
    return '今天还能生成 $remaining 次';
  }

  /// 用完时的说明。
  ///
  /// ★★ 必须说「**可以先手动填**」。AI 起草是**附加功能**,
  ///   用完了主功能(手动写主题名和简介)一点没受影响 ——
  ///   只说「明天再来」会让人以为整个发布都得等到明天。
  ///   小程序原话:「这一轮的 AI 起草次数用完了,可以先手动填,或稍后再试。」
  String? get exhaustedHint => (loaded && limited && remaining <= 0)
      ? '这一轮的 AI 起草次数用完了,可以先手动填,或稍后再试。'
      : null;

  factory AiQuota.fromJson(Map<String, dynamic> json) {
    return AiQuota(
      limited: json['limited'] == true,
      remaining: (json['remaining'] as num?)?.toInt() ?? 0,
      loaded: true,
    );
  }
}

/// AI 创作被拒的原因。
///
/// ★ 后端两条常量文案性质完全不同(ApiAiController:38/41):
///   - `当前身份暂不支持AI创作,请切换到俱乐部或商家身份` → **身份问题,重试无用**
///   - `AI 服务暂时不可用,请稍后重试`                    → **故障,重试有用**
class AiGateResult {
  const AiGateResult._();

  static bool isRoleBlocked(String message) =>
      message.contains('当前身份暂不支持');

  /// 值不值得重试。身份问题不值得。
  static bool retryable(String message) => !isRoleBlocked(message);

  /// 给用户的下一步。身份问题要告诉他怎么换身份。
  static String? nextStep(String message) => isRoleBlocked(message)
      ? '在「设置」里申请成为俱乐部主理人或商家后即可使用'
      : null;
}
