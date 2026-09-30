import 'package:chengyin_app/feature/orders/payment_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyRegistrationStatus(/api/registration/info 回包)', () {
    test('paymentStatus=2 → success', () {
      expect(
        classifyRegistrationStatus(<String, dynamic>{'paymentStatus': 2}),
        RegistrationVerifyStatus.success,
      );
    });

    test('registrationStatus=2 → success(字符串也认,对齐 Number())', () {
      expect(
        classifyRegistrationStatus(<String, dynamic>{
          'registrationStatus': '2',
        }),
        RegistrationVerifyStatus.success,
      );
    });

    test('paymentStatus 3/4 或 registrationStatus 3 → failed', () {
      for (final int p in <int>[3, 4]) {
        expect(
          classifyRegistrationStatus(<String, dynamic>{'paymentStatus': p}),
          RegistrationVerifyStatus.failed,
        );
      }
      expect(
        classifyRegistrationStatus(<String, dynamic>{'registrationStatus': 3}),
        RegistrationVerifyStatus.failed,
      );
    });

    test('待支付/查不到 → pending(继续等,不下结论)', () {
      expect(
        classifyRegistrationStatus(<String, dynamic>{
          'paymentStatus': 1,
          'registrationStatus': 1,
        }),
        RegistrationVerifyStatus.pending,
      );
      expect(
        classifyRegistrationStatus(null),
        RegistrationVerifyStatus.pending,
      );
    });
  });

  // 节奏参数缩到毫秒级跑真 async,判据与时序语义与真源一致。
  final Duration fast = const Duration(milliseconds: 20);

  RegistrationPaymentVerifier build(
    Future<Map<String, dynamic>?> Function(int) requestStatus, {
    Duration total = const Duration(milliseconds: 120),
  }) => RegistrationPaymentVerifier(
    requestStatus: requestStatus,
    interval: fast,
    perRequestTimeout: const Duration(milliseconds: 40),
    totalDeadline: total,
  );

  test('一直 pending,到墙钟 deadline → unknown,文案逐字同源', () async {
    final outcome = await build(
      (_) async => <String, dynamic>{
        'paymentStatus': 1,
        'registrationStatus': 1,
      },
    ).verify(1);
    expect(outcome.status, 'unknown');
    expect(outcome.errMsg, '支付结果未知，请到订单查看，暂不要重复支付');
  });

  test('先 pending 后 success → 当场收敛为 success', () async {
    int calls = 0;
    final outcome = await build((_) async {
      calls++;
      return <String, dynamic>{
        'paymentStatus': calls >= 3 ? 2 : 1,
        'registrationStatus': 1,
      };
    }).verify(7);
    expect(outcome.status, 'success');
    expect(calls, greaterThanOrEqualTo(3));
  });

  test('failed 带不回 errMsg 时兜底「支付未完成」', () async {
    final outcome = await build(
      (_) async => <String, dynamic>{'paymentStatus': 3},
    ).verify(1);
    expect(outcome.status, 'failed');
    expect(outcome.errMsg, '支付未完成');
  });

  test('请求抛异常(断网)按 pending 处理,不提前判失败', () async {
    final outcome = await build((_) async => throw Exception('网络挂了')).verify(1);
    expect(outcome.status, 'unknown');
  });

  test('单请求超时(挂死)不炸轮询,到 deadline 给 unknown', () async {
    final outcome = await build(
      (_) => Future<Map<String, dynamic>>.delayed(const Duration(seconds: 5)),
      total: const Duration(milliseconds: 100),
    ).verify(1);
    expect(outcome.status, 'unknown');
  });

  test('abort 后立刻给 unknown,不再打扰服务端', () async {
    int calls = 0;
    final verifier = build((_) async {
      calls++;
      return <String, dynamic>{'paymentStatus': 1};
    });
    final future = verifier.verify(1);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    verifier.abort();
    final outcome = await future;
    expect(outcome.status, 'unknown');
    final atAbort = calls;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(calls, atAbort, reason: 'abort 后不该再发新请求');
  });

  test('总时限不小于单请求时限(真源 Math.max 纪律)', () {
    final verifier = RegistrationPaymentVerifier(
      requestStatus: (_) async => null,
      perRequestTimeout: const Duration(seconds: 5),
      totalDeadline: const Duration(seconds: 1),
    );
    expect(verifier.totalDeadline, const Duration(seconds: 5));
  });
}
