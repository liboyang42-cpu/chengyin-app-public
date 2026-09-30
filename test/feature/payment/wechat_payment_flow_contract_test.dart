import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _method(String source, String signature, String nextSignature) {
  final int start = source.indexOf(signature);
  final int end = source.indexOf(nextSignature, start + signature.length);
  expect(start, greaterThanOrEqualTo(0), reason: '找不到 $signature');
  expect(end, greaterThan(start), reason: '找不到 $nextSignature');
  return source.substring(start, end);
}

void _expectGateBefore(
  String source,
  String backendCall, {
  String gateCall = 'wechatPaymentFlowGate.tryAcquire()',
  String releaseCall = 'wechatPaymentFlowGate.release()',
}) {
  final int gate = source.indexOf(gateCall);
  final int call = source.indexOf(backendCall);
  expect(gate, greaterThanOrEqualTo(0), reason: '建单前缺全局支付闸门');
  expect(call, greaterThan(gate), reason: '$backendCall 发生在全局支付闸门之前');
  expect(source, contains(releaseCall));
}

void main() {
  test('所有微信支付入口都在建单或取支付参数前占用同一个全局闸门', () {
    final String activity = File(
      'lib/feature/activity/activity_detail_page.dart',
    ).readAsStringSync();
    _expectGateBefore(
      _method(activity, 'Future<void> _submit()', 'Future<void> _retryPay()'),
      '.createRegistration(',
    );
    _expectGateBefore(
      _method(activity, 'Future<void> _retryPay()', 'Future<void> _pay('),
      '.payApp(',
    );

    final String topic = File(
      'lib/feature/topic/topic_self_play_sheet.dart',
    ).readAsStringSync();
    _expectGateBefore(
      _method(topic, 'Future<void> _submit()', 'Future<void> _retryPay()'),
      '.createPass(',
    );
    _expectGateBefore(
      _method(topic, 'Future<void> _retryPay()', 'Future<void> _pay('),
      '.payApp(',
    );

    final String orders = File(
      'lib/feature/orders/orders_page.dart',
    ).readAsStringSync();
    _expectGateBefore(
      _method(orders, 'Future<void> _pay(', 'Future<void> _cancel('),
      '.payApp(',
    );

    final String coop = File(
      'lib/feature/coop/coop_list_page.dart',
    ).readAsStringSync();
    expect(coop, contains('(ref) => wechatPaymentFlowGate'));
    _expectGateBefore(
      _method(coop, 'Future<void> _payDeposit()', 'Future<void> _contact()'),
      '.createDeposit(',
      gateCall: 'gate.tryAcquire()',
      releaseCall: 'gate.release()',
    );
  });

  test('公开支付实现把 SDK 构造包在静态互斥的 acquire/release 之间', () {
    final String source = File(
      'lib/feature/payment/wechat_payment.dart',
    ).readAsStringSync();
    final int acquire = source.indexOf('_sdkGate.tryAcquire()');
    final int sdk = source.indexOf('final fluwx = Fluwx()');
    final int release = source.indexOf('_sdkGate.release()');
    expect(acquire, greaterThanOrEqualTo(0));
    expect(sdk, greaterThan(acquire));
    expect(release, greaterThan(sdk));
  });
}
