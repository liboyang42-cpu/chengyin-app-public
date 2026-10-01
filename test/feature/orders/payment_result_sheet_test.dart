// 支付结果面板(gap-spec-player #3 · 3d)—— 1:1 components/cy/result-sheet:
// loading 不可关;success 停 2s 自愈关闭、consent 在保存中先等它落定;
// fail 停留到人工关;unknown 不收面板话术,直接带值 pop 让宿主弹 modal。
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/orders/payment_result_sheet.dart';
import 'package:chengyin_app/feature/orders/payment_verifier.dart';

Future<void> _open(
  WidgetTester tester, {
  Future<PaymentVerifyOutcome> Function()? reconcile,
  String? presetFailMessage,
  bool presetSuccess = false,
  bool freeSignup = false,
  Widget? Function(ValueChanged<bool> onConsentBusy)? consent,
  Duration hold = paymentSuccessHold,
  void Function(PaymentSheetOutcome?)? onDone,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) => CupertinoButton(
          child: const Text('open'),
          onPressed: () async {
            final PaymentSheetOutcome? r = await showPaymentResultSheet(
              context,
              reconcile: reconcile,
              presetFailMessage: presetFailMessage,
              presetSuccess: presetSuccess,
              freeSignup: freeSignup,
              consent: consent,
              hold: hold,
            );
            onDone?.call(r);
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  // 面板入场动画(showCupertinoSheet 实测 >500ms 才见内容);loading 相有常驻
  // 转圈,pumpAndSettle 会挂,所有推进都用定长 pump。
  await tester.pump(const Duration(milliseconds: 800));
  // 入场动画跑完后还要再落一帧,面板内容才进 tree。
  await tester.pump();
}

void main() {
  testWidgets('loading 相:核对中话术,面板不给人工退场', (tester) async {
    // 永不完成的 completer:loading 相只要停在那儿。
    final completer = Completer<PaymentVerifyOutcome>();
    await _open(tester, reconcile: () => completer.future);
    expect(find.text('确认支付结果'), findsOneWidget);
    expect(find.text('正在和微信核对这笔付款。'), findsOneWidget);
    expect(find.text('这笔没有付成功'), findsNothing);
    expect(
      tester.widget<PopScope>(find.byType(PopScope)).canPop,
      isFalse,
      reason: '核对中不给退场',
    );
  });

  testWidgets('reconcile success → 支付成功文案,停满 hold 后自愈关闭', (tester) async {
    // reconcile 用可控 completer:否则 future 会在入场 pump 的同一拍里落地,
    // success 相和 hold 计时都被入场时长吃掉,断言就看不见「刚变成功」那一帧。
    final completer = Completer<PaymentVerifyOutcome>();
    PaymentSheetOutcome? done;
    await _open(
      tester,
      reconcile: () => completer.future,
      hold: const Duration(milliseconds: 100),
      onDone: (r) => done = r,
    );
    expect(find.text('确认支付结果'), findsOneWidget);
    completer.complete(const PaymentVerifyOutcome(status: 'success'));
    await tester.pump();
    expect(find.text('支付成功'), findsOneWidget);
    expect(find.text('票已放入票夹，可随时出示入场码'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 50));
    expect(done, isNull, reason: '没停满 2s(测试里 100ms)不自愈');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    expect(done!.result, PaymentSheetResult.success);
  });

  testWidgets('零元单 presetSuccess 用报名成功文案(freeSignup)', (tester) async {
    // hold 大于入场 pump(500):面板要活得过打开动画。
    PaymentSheetOutcome? done;
    await _open(
      tester,
      presetSuccess: true,
      freeSignup: true,
      hold: const Duration(milliseconds: 1200),
      onDone: (r) => done = r,
    );
    expect(find.text('报名成功'), findsOneWidget);
    expect(find.text('票已放入票夹，出发前 30 分钟到集合点核验'), findsOneWidget);
    // hold 是入场动画跑完那一刻才开始计时的。
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump(const Duration(milliseconds: 600));
    expect(done!.result, PaymentSheetResult.success);
  });

  testWidgets('默认 hold 与真源 SUCCESS_HOLD_MS=2000 同值', (tester) async {
    expect(paymentSuccessHold, const Duration(milliseconds: 2000));
  });

  testWidgets('reconcile failed → fail 相带原因,「知道了」带值关闭', (tester) async {
    PaymentSheetOutcome? done;
    await _open(
      tester,
      reconcile: () async =>
          const PaymentVerifyOutcome(status: 'failed', errMsg: '支付未完成'),
      onDone: (r) => done = r,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('这笔没有付成功'), findsOneWidget);
    expect(find.text('请查看订单确认最终状态，暂不要重复支付。'), findsOneWidget);
    expect(find.text('支付未完成'), findsOneWidget);
    expect(done, isNull, reason: 'fail 相不自愈,停留到人工关');
    await tester.tap(find.byKey(const Key('payment-result-close')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(done!.result, PaymentSheetResult.failed);
    expect(done!.why, '支付未完成');
  });

  testWidgets('reconcile unknown → 不收面板话术,直接带 unknown 关闭', (tester) async {
    PaymentSheetOutcome? done;
    await _open(
      tester,
      reconcile: () async => const PaymentVerifyOutcome(
        status: 'unknown',
        errMsg: paymentUnknownErrMessage,
      ),
      onDone: (r) => done = r,
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('这笔没有付成功'), findsNothing);
    expect(done!.result, PaymentSheetResult.unknown);
  });

  testWidgets('success 相 consent 在保存中 → 到点不关,等它落定', (tester) async {
    PaymentSheetOutcome? done;
    late ValueChanged<bool> busy;
    await _open(
      tester,
      presetSuccess: true,
      hold: const Duration(milliseconds: 1200),
      consent: (ValueChanged<bool> onBusy) {
        busy = onBusy;
        return const SizedBox(key: Key('consent-slot'));
      },
      onDone: (r) => done = r,
    );
    expect(
      find.byKey(const Key('consent-slot')),
      findsOneWidget,
      reason: 'consent 只挂在 success 相',
    );
    busy(true);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(done, isNull, reason: '勾了才停下等保存结果');
    expect(find.text('支付成功'), findsOneWidget);
    busy(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(done!.result, PaymentSheetResult.success);
  });

  testWidgets('fail 相不渲染 consent', (tester) async {
    await _open(
      tester,
      presetFailMessage: '支付未完成',
      consent: (_) {
        throw StateError('fail 相不该挂 consent');
      },
    );
    expect(find.text('这笔没有付成功'), findsOneWidget);
  });
}
