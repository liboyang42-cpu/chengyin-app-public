// 扫码内容 → 核销端点的路由表。
//
// ★★ App 此前**无条件调 scanDynamicCode**:商家扫优惠券码、团码、
//   旧版票码都会被打到错的端点,拿回一句莫名其妙的失败。
//
// 判据逐条对齐小程序 utils/verification-scan.js。
// ⚠️ 这里只做**路由**,不做校验 —— 真实性由服务端 HMAC 验签,
//   在前端加"看起来像不像真码"的判断会制造"已经验过"的错觉。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/verification_scan.dart';

void main() {
  test('★★ v1 团码 → 团码核销', () {
    final v = VerificationScan.resolve('v1.abc.group_88.sig');
    expect(v.kind, ScanKind.group);
    expect(v.code, 'v1.abc.group_88.sig', reason: '整串回传,不拆');
    expect(v.successTitle, '已记录接待该团');
  });

  test('★★ v1 活动/主题码 → 动态验票(整串回传,不拆 type)', () {
    for (final String t in <String>['activity', 'topic']) {
      final v = VerificationScan.resolve('v1.xyz.$t.sig');
      expect(v.kind, ScanKind.dynamicTicket);
      expect(v.code, 'v1.xyz.$t.sig',
          reason: '归属由服务端验签后决定,不能信任客户端拆出来的 type');
      expect(v.legacyType, isNull);
    }
  });

  test('★★★ v1 但类型不认识 → 「暂不支持」,不能说成「格式错误」', () {
    final v = VerificationScan.resolve('v1.xyz.future_kind.sig');
    expect(v.kind, ScanKind.invalid);
    expect(v.message, '暂不支持此动态码',
        reason: '"不支持"意味着该升级 App,"格式错误"意味着扫错了东西 —— '
            '合并成一句会把用户引到错的方向');
  });

  test('★★ JSON 优惠券码 → 券核销,只传内层 code', () {
    final v = VerificationScan.resolve('{"type":"coupon","code":"C123"}');
    expect(v.kind, ScanKind.coupon);
    expect(v.code, 'C123');
  });

  test('★★ JSON 旧版票码 → 旧接口,type 和 code 都要传', () {
    final v = VerificationScan.resolve('{"type":"topic","code":"T9"}');
    expect(v.kind, ScanKind.legacyTicket);
    expect(v.code, 'T9');
    expect(v.legacyType, 'topic', reason: '旧接口要 type,少传一个就核销不了');
  });

  test('★ 认不出来的一律不进任何核销端点', () {
    for (final String? s in <String?>[
      null,
      '',
      '   ',
      'https://example.com/x',
      '{"type":"coupon"}', // 缺 code
      '{"code":"C1"}', // 缺 type
      '{"type":"unknown","code":"X"}',
      '不是 JSON 也不是 v1',
      '[]', // 合法 JSON 但不是对象
    ]) {
      final v = VerificationScan.resolve(s);
      expect(v.kind, ScanKind.invalid, reason: '「$s」不该进核销');
      expect(v.message, '二维码格式错误');
    }
  });

  test('★ 前后空白不影响识别', () {
    expect(VerificationScan.resolve('  v1.a.topic.s  ').kind,
        ScanKind.dynamicTicket);
  });
}
