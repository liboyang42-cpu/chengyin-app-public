import 'package:chengyin_app/feature/orders/checkout_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isOrderExpiredFailure(来源①: /pay 对过期待支付单的拒绝)', () {
    test('业务 code 410 即判过期(HTTP 仍是 200)', () {
      expect(isOrderExpiredFailure(code: 410, message: ''), isTrue);
    });

    test('未升级 jar 没有 code 时按文案兜底', () {
      expect(isOrderExpiredFailure(code: null, message: '订单已过期,请重新报名'), isTrue);
    });

    test('409 价格已更新不是过期', () {
      expect(isOrderExpiredFailure(code: 409, message: '价格已更新，请重新确认'), isFalse);
    });

    test('code null + 空文案不判', () {
      expect(isOrderExpiredFailure(code: null, message: ''), isFalse);
    });
  });

  group('isTerminalOrderConflict(来源②: /create 对终态单的 409)', () {
    test('409 +「该幂等键对应的报名已…」判终态冲突', () {
      expect(
        isTerminalOrderConflict(code: 409, message: '该幂等键对应的报名已取消/已过期，请重新发起报名'),
        isTrue,
      );
    });

    test('同码 409 的「价格已更新」不判 —— 那是重报价,不是重建', () {
      expect(
        isTerminalOrderConflict(code: 409, message: '价格已更新，请重新确认'),
        isFalse,
      );
    });

    test('非 409 不带文案', () {
      expect(
        isTerminalOrderConflict(code: 410, message: '该幂等键对应的报名已取消/已过期，请重新发起报名'),
        isFalse,
      );
    });
  });

  test('重建仍失败给后端原文或逐字同源的兜底句', () {
    expect(orderExpiredUserMessage, '订单已过期,请重新报名');
  });

  group('isPriceChangedFailure', () {
    test('409 → 走重报价分支', () {
      expect(isPriceChangedFailure(code: 409), isTrue);
    });
    test('非 409 不重报价', () {
      expect(isPriceChangedFailure(code: 410), isFalse);
      expect(isPriceChangedFailure(code: null), isFalse);
    });
  });

  group('routeCheckoutFailure(两条重建来源与重报价的分流)', () {
    test('终态 409 优先判重建,不落进重报价', () {
      expect(
        routeCheckoutFailure(code: 409, message: '该幂等键对应的报名已取消/已过期，请重新发起报名'),
        CheckoutFailureRoute.rebuild,
      );
    });

    test('410 过期 → 重建', () {
      expect(
        routeCheckoutFailure(code: 410, message: ''),
        CheckoutFailureRoute.rebuild,
      );
    });

    test('普通 409 价格已更新 → 重报价,不重建', () {
      expect(
        routeCheckoutFailure(code: 409, message: '价格已更新，请重新确认'),
        CheckoutFailureRoute.priceChanged,
      );
    });

    test('其它错误不分流(交给原有兜底文案)', () {
      expect(routeCheckoutFailure(code: 500, message: '服务开小差了'), isNull);
      expect(routeCheckoutFailure(code: null, message: ''), isNull);
    });
  });
}
