import 'dart:convert';

/// 扫码内容 → 该走哪个核销端点。
///
/// 对齐小程序 `utils/verification-scan.js`,逐条同口径。
///
/// ★★★ 它自己的注释原话:「`v1.*` **只用 type 前缀决定调用哪个端点**;
///   真实性仍由服务端 HMAC 校验,**前端绝不把它当鉴权依据**」。
///   ⇒ 这里做的只是**路由**,不是校验。别在这儿加"看起来像不像真码"的判断,
///     那会给人一种前端已经验过的错觉。
///
/// ★★ App 此前**无条件调 scanDynamicCode** —— 优惠券码、团码、旧版票码
///   扫了都会被打到错的端点,商家看到的是一句莫名其妙的失败。
enum ScanKind {
  /// 团码:记录接待该团。
  group,

  /// 动态票码(v1.*.activity / v1.*.topic)。归属由服务端验签后决定。
  dynamicTicket,

  /// 优惠券。
  coupon,

  /// 旧版票码(JSON,要连 type 一起回传)。
  legacyTicket,

  /// 认不出来。
  invalid,
}

class VerificationScan {
  const VerificationScan({
    required this.kind,
    this.code = '',
    this.legacyType,
    this.message,
    this.loadingTitle = '',
    this.successTitle = '',
  });

  final ScanKind kind;
  final String code;

  /// 只有 [ScanKind.legacyTicket] 用:旧接口要 type + code 一起传。
  final String? legacyType;

  /// 认不出来时给用户看的话。
  final String? message;

  final String loadingTitle;
  final String successTitle;

  static const VerificationScan _bad = VerificationScan(
    kind: ScanKind.invalid,
    message: '二维码格式错误',
  );

  static VerificationScan resolve(String? raw) {
    final String code = (raw ?? '').trim();
    if (code.isEmpty) return _bad;

    if (code.startsWith('v1.')) {
      final List<String> parts = code.split('.');
      final String type = parts.length >= 3 ? parts[2] : '';
      if (type.startsWith('group_')) {
        return VerificationScan(
          kind: ScanKind.group,
          code: code,
          loadingTitle: '核销中…',
          successTitle: '已记录接待该团',
        );
      }
      if (type == 'activity' || type == 'topic') {
        // ★ 类型与报名单归属由 scan_dynamic_code 在**服务端验签后**决定,
        //   不能信任客户端回传 —— 所以这里只传整串 code,不拆出 type。
        return VerificationScan(
          kind: ScanKind.dynamicTicket,
          code: code,
          loadingTitle: '验票中…',
          successTitle: '验票成功',
        );
      }
      // ★ 认得出是 v1 动态码、但类型不认识 —— 说清楚是"不支持",
      //   不要和"格式错误"混:前者意味着该升级 App,后者意味着扫错了东西。
      return const VerificationScan(
        kind: ScanKind.invalid,
        message: '暂不支持此动态码',
      );
    }

    try {
      final Object? parsed = jsonDecode(code);
      if (parsed is! Map<String, dynamic>) return _bad;
      final String type = (parsed['type'] ?? '').toString();
      final String inner = (parsed['code'] ?? '').toString();
      if (type.isEmpty || inner.isEmpty) return _bad;
      if (type == 'coupon') {
        return VerificationScan(
          kind: ScanKind.coupon,
          code: inner,
          loadingTitle: '核销中…',
          successTitle: '核销成功',
        );
      }
      if (type == 'activity' || type == 'topic') {
        return VerificationScan(
          kind: ScanKind.legacyTicket,
          code: inner,
          legacyType: type,
          loadingTitle: '验票中…',
          successTitle: '验票成功',
        );
      }
    } catch (_) {
      // 非 JSON 的动态码上面已经处理;其余格式不进入任何核销端点。
    }
    return _bad;
  }
}
