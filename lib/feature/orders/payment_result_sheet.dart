import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import 'payment_verifier.dart';
import '../../l10n/strings.dart';

/// SDK 回来之后、页面之上的结果面板 —— 1:1 `components/cy/result-sheet`
/// (baoming.js `showPaymentResult`):loading 核对中不可关;success 停 2s
/// 自愈关闭(真源 SUCCESS_HOLD_MS=2000;consent 在保存中先等它落定 ——
/// 「勾了才停下等保存结果」);fail 停留到用户关掉;unknown **不收面板话术**,
/// 直接 pop 让宿主弹「支付结果待确认」modal(真源收面板 + showModalDialog)。
enum PaymentSheetResult { success, failed, unknown }

/// fail/success 关闭时带回来的结果(why 供页面常驻 submitError)。
class PaymentSheetOutcome {
  const PaymentSheetOutcome(this.result, {this.why = ''});

  final PaymentSheetResult result;
  final String why;
}

const Duration paymentSuccessHold = Duration(milliseconds: 2000);

/// [reconcile] reads authoritative server status after every SDK outcome.
/// Presets remain available for existing callers and isolated previews; the
/// registration and orders payment flows always use server reconciliation.
Future<PaymentSheetOutcome?> showPaymentResultSheet(
  BuildContext context, {
  Future<PaymentVerifyOutcome> Function()? reconcile,
  String? presetFailMessage,
  bool presetSuccess = false,
  bool freeSignup = false,
  Widget? Function(ValueChanged<bool> onConsentBusy)? consent,
  Duration hold = paymentSuccessHold,
}) {
  return showCupertinoSheet<PaymentSheetOutcome>(
    context: context,
    showDragHandle: true,
    topGap: 0.55,
    scrollableBuilder: (BuildContext context, ScrollController controller) =>
        _PaymentResultSheet(
          scrollController: controller,
          reconcile: reconcile,
          presetFailMessage: presetFailMessage,
          presetSuccess: presetSuccess,
          freeSignup: freeSignup,
          consent: consent,
          hold: hold,
        ),
  );
}

enum _Phase { loading, success, fail }

class _PaymentResultSheet extends StatefulWidget {
  const _PaymentResultSheet({
    required this.scrollController,
    required this.reconcile,
    required this.presetFailMessage,
    required this.presetSuccess,
    required this.freeSignup,
    required this.consent,
    required this.hold,
  });

  final ScrollController scrollController;
  final Future<PaymentVerifyOutcome> Function()? reconcile;
  final String? presetFailMessage;
  final bool presetSuccess;
  final bool freeSignup;
  final Widget? Function(ValueChanged<bool> onConsentBusy)? consent;
  final Duration hold;

  @override
  State<_PaymentResultSheet> createState() => _PaymentResultSheetState();
}

class _PaymentResultSheetState extends State<_PaymentResultSheet> {
  _Phase _phase = _Phase.loading;
  String _why = '';
  bool _consentBusy = false;
  bool _holdDone = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final String? presetFail = widget.presetFailMessage;
    if (presetFail != null) {
      _phase = _Phase.fail;
      _why = presetFail;
    } else if (widget.presetSuccess) {
      _phase = _Phase.success;
    }
    switch (_phase) {
      case _Phase.loading:
        widget.reconcile!().then(_onOutcome);
      case _Phase.success:
        _scheduleHold();
      case _Phase.fail:
        break;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onOutcome(PaymentVerifyOutcome outcome) {
    if (!mounted) return;
    switch (outcome.status) {
      case 'success':
        setState(() => _phase = _Phase.success);
        _scheduleHold();
      case 'failed':
        setState(() {
          _phase = _Phase.fail;
          _why = outcome.hasLocalFailureMessage
              ? stringsOf(context).registrationOrdersPaymentNotCompleted
              : outcome.errMsg;
        });
      default:
        _close(PaymentSheetOutcome(PaymentSheetResult.unknown));
    }
  }

  void _scheduleHold() {
    _timer?.cancel();
    _timer = Timer(widget.hold, () {
      if (_consentBusy) {
        _holdDone = true;
        return;
      }
      _close(PaymentSheetOutcome(PaymentSheetResult.success));
    });
  }

  void _onConsentBusy(bool busy) {
    if (!mounted) return;
    setState(() => _consentBusy = busy);
    if (!busy && _holdDone) {
      _close(PaymentSheetOutcome(PaymentSheetResult.success));
    }
  }

  void _close(PaymentSheetOutcome outcome) {
    _timer?.cancel();
    if (mounted) Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final (String title, String sub) = switch (_phase) {
      _Phase.loading => (stringsOf(context).registrationOrdersVerifyPayment, stringsOf(context).registrationOrdersVerifyPaymentHint),
      _Phase.success =>
        widget.freeSignup
            ? (stringsOf(context).registrationOrdersRegistrationSuccessful, stringsOf(context).registrationOrdersFreeTicketHint)
            : (stringsOf(context).registrationOrdersPaymentSuccessful, stringsOf(context).registrationOrdersPaidTicketHint),
      _Phase.fail => (stringsOf(context).registrationOrdersThisPaymentWasNotCompleted, stringsOf(context).registrationOrdersFailedPaymentHint),
    };
    final CyPalette palette = CyPalette.of(context);
    final Widget? consent = _phase == _Phase.success
        ? widget.consent?.call(_onConsentBusy)
        : null;
    return PopScope(
      // 只有 fail 相留在原地给人工退场(真源 fail 无动作,drag/mask 关);
      // loading 不给退场,success 只由 2s 自愈关闭带值 pop ——
      // 所以宿主收到 null 只可能是 fail 相被滑掉,按 failed 处理即可。
      canPop: _phase == _Phase.fail,
      child: CupertinoPageScaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          key: const Key('payment-result-sheet'),
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(
              CyTokens.pageX,
              CyTokens.space3,
              CyTokens.pageX,
              CyTokens.space6,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: switch (_phase) {
                    _Phase.loading => const CupertinoActivityIndicator(
                      radius: 14,
                    ),
                    _Phase.success => const Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      key: Key('payment-result-success'),
                      size: 52,
                      // 真源徽章色=status-success(result-sheet.wxss)。
                      color: CyTokens.statusSuccess,
                    ),
                    // 真源失败态是 info「i」不是感叹号(result-sheet.wxml),
                    // 徽章色=result-fail-badge(≈statusDanger)。
                    _Phase.fail => const Icon(
                      CupertinoIcons.info_circle,
                      size: 52,
                      color: CyTokens.statusDanger,
                    ),
                  },
                ),
                const SizedBox(height: CyTokens.space3),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: CyTokens.space1),
                Text(
                  sub,
                  textAlign: TextAlign.center,
                  style: CyType.body.copyWith(color: palette.textSecondary),
                ),
                if (_phase == _Phase.fail && _why.isNotEmpty) ...<Widget>[
                  const SizedBox(height: CyTokens.space2),
                  Text(
                    _why,
                    textAlign: TextAlign.center,
                    style: CyType.footnote.copyWith(
                      color: palette.statusWarning,
                    ),
                  ),
                ],
                if (consent != null) ...<Widget>[
                  const SizedBox(height: CyTokens.space4),
                  consent,
                ],
                if (_phase == _Phase.fail) ...<Widget>[
                  const SizedBox(height: CyTokens.space4),
                  CyNativeButton(
                    key: const Key('payment-result-close'),
                    label: stringsOf(context).registrationOrdersGotIt,
                    onPressed: () => _close(
                      PaymentSheetOutcome(PaymentSheetResult.failed, why: _why),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
