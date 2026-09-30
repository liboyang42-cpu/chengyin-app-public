import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/merchant_marketing.dart';

void main() {
  group('★ 券核销率:没人领过 ≠ 核销率 0%', () {
    test('领取为 0 → null,界面不显示这一项', () {
      const m = MerchantMarketing(couponReceived: 0, couponVerified: 0);
      expect(m.verifyRate, isNull,
          reason: '显示「0%」会让商家以为券做得差,其实是根本没人领过');
    });
    test('有领取才算率', () {
      const m = MerchantMarketing(couponReceived: 10, couponVerified: 3);
      expect(m.verifyRate, 0.3);
    });
    test('领了但一张没核销 → 确实是 0%,这时该显示', () {
      const m = MerchantMarketing(couponReceived: 10, couponVerified: 0);
      expect(m.verifyRate, 0.0, reason: '这是真实的 0,与「没人领过」不同');
    });
  });

  group('漏斗百分比', () {
    FunnelStep s(String? rate) =>
        FunnelStep.fromJson(<String, dynamic>{'step': 'x', 'rate': rate});
    test('后端下发 0-1 小数 → 转百分比', () {
      expect(s('0.3500').ratePercent, '35%');
      expect(s('0.1234').ratePercent, '12.3%');
      expect(s('1').ratePercent, '100%');
    });
    test('后端给 "0"(base 为 0)→ 0%', () {
      expect(s('0').ratePercent, '0%');
    });
    test('解析不出来 → null,不冒充 0%', () {
      expect(s('abc').ratePercent, isNull);
      expect(s(null).ratePercent, isNull);
    });
    test('画图比例夹在 0-1', () {
      expect(s('0.5').ratio, 0.5);
      expect(s('2').ratio, 1.0);
      expect(s('-1').ratio, 0.0);
      expect(s('abc').ratio, 0.0);
    });
  });

  group('解析健壮性', () {
    test('子块缺失或不是对象 → 全 0,不抛', () {
      final m = MerchantMarketing.fromJson(<String, dynamic>{
        'coupons': 'oops',
        'content': null,
        'funnel': 'oops',
      });
      expect(m.couponCount, 0);
      expect(m.topicCount, 0);
      expect(m.funnel, isEmpty);
    });
    test('正常解析', () {
      final m = MerchantMarketing.fromJson(<String, dynamic>{
        'coupons': <String, dynamic>{'couponCount': 2, 'received': 40, 'verified': 8},
        'content': <String, dynamic>{'topicCount': 3, 'activityCount': 1},
        'funnel': <dynamic>[
          <String, dynamic>{'step': '曝光', 'count': 100, 'rate': '1'},
          <String, dynamic>{'step': '核销', 'count': 20, 'rate': '0.2'},
        ],
      });
      expect(m.couponReceived, 40);
      expect(m.verifyRate, 0.2);
      expect(m.funnel.length, 2);
      expect(m.funnel.last.ratePercent, '20%');
    });
  });
}
