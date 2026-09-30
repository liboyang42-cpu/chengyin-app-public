import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/payment/wechat_payment.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';

void main() {
  test('微信配置必须同时具备真实 AppId 与合法 Universal Link', () {
    expect(
      hasCompleteWechatAppConfiguration(
        appId: 'wx1234567890',
        universalLink: 'https://api.example.invalid/app/',
      ),
      isTrue,
    );
    expect(
      hasCompleteWechatAppConfiguration(
        appId: 'wx1234567890',
        universalLink: '',
      ),
      isFalse,
    );
    expect(
      hasCompleteWechatAppConfiguration(
        appId: 'wxYOURAPPID',
        universalLink: 'https://api.example.invalid/app/',
      ),
      isFalse,
    );
  });

  test('全局支付闸门在释放前拒绝第二个会话', () {
    final gate = WechatPaymentGate();
    expect(gate.tryAcquire(), isTrue);
    expect(gate.tryAcquire(), isFalse);
    gate.release();
    expect(gate.tryAcquire(), isTrue);
  });
  test('微信 App 支付七字段缺一即 fail closed', () async {
    const Map<String, String> complete = <String, String>{
      'appId': 'wx-app',
      'partnerId': 'merchant',
      'prepayId': 'prepay',
      'packageValue': 'Sign=WXPay',
      'nonceStr': 'nonce',
      'timeStamp': '1700000000',
      'sign': 'signature',
    };

    for (final String key in complete.keys) {
      final Map<String, String> incomplete = <String, String>{...complete}
        ..remove(key);
      expect(
        await const WechatPayment().pay(incomplete),
        WechatPayOutcome.failed,
        reason: '缺 $key 时不得用空串或默认值调起 SDK',
      );
    }
  });

  test('timeStamp 必须是正整数', () async {
    const Map<String, String> params = <String, String>{
      'appId': 'wx-app',
      'partnerId': 'merchant',
      'prepayId': 'prepay',
      'packageValue': 'Sign=WXPay',
      'nonceStr': 'nonce',
      'timeStamp': 'not-a-number',
      'sign': 'signature',
    };

    expect(await const WechatPayment().pay(params), WechatPayOutcome.failed);
  });

  test('★ 未配置 SDK:请求根本没发出去 → failed,不是「结果待确认」', () async {
    // B1 真跑报告 P2-3:未配置曾返回 unknown,用户被推到
    // 「支付结果待确认…不要重复支付」——可这里既没扣款可能,
    // 也没有等待中的结果可确认。判据同 sent==false:没发出去就是 failed。
    // appid 配齐的机器上这一分支不可达,跳过而不是伪造。
    if (isWechatConfigured) return;
    const Map<String, String> complete = <String, String>{
      'appId': 'wx-app',
      'partnerId': 'merchant',
      'prepayId': 'prepay',
      'packageValue': 'Sign=WXPay',
      'nonceStr': 'nonce',
      'timeStamp': '1700000000',
      'sign': 'signature',
    };

    expect(
      await const WechatPayment().pay(complete),
      WechatPayOutcome.failed,
      reason: '未配置时不得返回 unknown —— 那会渲染成「不要重复支付」的误导文案',
    );
  });
}
