import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../data/api/account_api.dart';
import '../../data/models/activity.dart';
import '../payment/wechat_payment.dart';
import 'topic_self_play_service.dart';

/// 自玩通行证承载层。购买行为在本 Sheet 内完成，不绕去活动列表。
Future<void> showTopicSelfPlaySheet(
  BuildContext context, {
  required int topicId,
}) {
  return showCupertinoSheet<void>(
    context: context,
    showDragHandle: true,
    topGap: 0.08,
    scrollableBuilder:
        (BuildContext context, ScrollController scrollController) =>
            _TopicSelfPlaySheet(
              topicId: topicId,
              scrollController: scrollController,
            ),
  );
}

class _TopicSelfPlaySheet extends ConsumerStatefulWidget {
  const _TopicSelfPlaySheet({
    required this.topicId,
    required this.scrollController,
  });

  final int topicId;
  final ScrollController scrollController;

  @override
  ConsumerState<_TopicSelfPlaySheet> createState() =>
      _TopicSelfPlaySheetState();
}

class _TopicSelfPlaySheetState extends ConsumerState<_TopicSelfPlaySheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  bool _consented = false;
  bool _busy = false;
  RegistrationCreateResult? _pending;
  bool _readyForTicketWallet = false;
  String? _status;
  String? _requestId;

  String? get _inputBlocker {
    if (_name.text.trim().isEmpty) return '请输入真实姓名';
    if (!RegExp(r'^1\d{10}$').hasMatch(_phone.text.trim())) {
      return '请输入正确的手机号';
    }
    return null;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    CyNativeNotice.show(context, message, isError: true);
  }

  Future<void> _submit() async {
    final String? blocker = _inputBlocker;
    if (blocker != null) {
      _toast(blocker);
      return;
    }
    if (!_consented || _busy) {
      return;
    }
    if (!wechatPaymentFlowGate.tryAcquire()) {
      _toast('已有一笔支付正在处理中，请完成后再试');
      return;
    }
    setState(() => _busy = true);
    try {
      _requestId ??= AccountApi.newRequestId();
      final result = await ref
          .read(topicSelfPlayServiceProvider)
          .createPass(
            topicId: widget.topicId,
            realName: _name.text.trim(),
            phone: _phone.text.trim(),
            requestId: _requestId!,
          );
      if (!mounted) return;
      setState(() => _pending = result);
      if (!result.needsPayment) {
        setState(() {
          _readyForTicketWallet = true;
          _status = '通行证已创建';
        });
        return;
      }
      await _pay(result.payParams!);
    } catch (error) {
      _toast(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      wechatPaymentFlowGate.release();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryPay() async {
    final pending = _pending;
    if (pending == null || _busy) return;
    if (!wechatPaymentFlowGate.tryAcquire()) {
      _toast('已有一笔支付正在处理中，请完成后再试');
      return;
    }
    setState(() => _busy = true);
    try {
      final params = await ref
          .read(topicSelfPlayServiceProvider)
          .payApp(pending.registrationId);
      await _pay(params);
    } catch (error) {
      _toast(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      wechatPaymentFlowGate.release();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pay(Map<String, String> params) async {
    final outcome = await const WechatPayment().pay(params);
    if (!mounted) return;
    switch (outcome) {
      case WechatPayOutcome.success:
        setState(() {
          _readyForTicketWallet = true;
          _status = '支付已提交，正在确认到账';
        });
      case WechatPayOutcome.cancelled:
        setState(() => _status = '已取消支付，可继续支付');
      case WechatPayOutcome.failed:
        setState(() => _status = '支付未完成，若已扣款请稍后查看票夹');
      case WechatPayOutcome.unknown:
        setState(() => _status = '支付结果待确认，请勿重复建单');
    }
  }

  void _openTickets() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push('/tickets');
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    final VoidCallback? primaryAction = _readyForTicketWallet
        ? _openTickets
        : _pending != null
        ? (_busy ? null : _retryPay)
        : (_busy || !_consented ? null : _submit);
    final BoxDecoration inputDecoration = BoxDecoration(
      color: palette.inputBgEmpty,
      border: Border.all(color: palette.borderSubtle),
      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
    );
    final TextStyle? inputStyle = textTheme.bodyMedium?.copyWith(
      color: palette.textPrimary,
    );
    final TextStyle? placeholderStyle = textTheme.bodyMedium?.copyWith(
      color: palette.textPlaceholder,
    );

    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      resizeToAvoidBottomInset: true,
      navigationBar: const CupertinoNavigationBar(middle: Text('自玩通行证')),
      child: SafeArea(
        top: false,
        child: ListView(
          controller: widget.scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space4,
            CyTokens.pageX,
            CyTokens.space5 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: <Widget>[
            Text(
              '购买后 90 天内可随时开玩本路线。请遵守安全须知，注意交通与人身安全。',
              style: textTheme.bodyMedium?.copyWith(
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: CyTokens.space4),
            Text(
              '真实姓名',
              style: textTheme.titleSmall?.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: CyTokens.space2),
            CupertinoTextField(
              key: const Key('self-play-real-name'),
              controller: _name,
              enabled: _pending == null,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              autofillHints: const <String>[AutofillHints.name],
              autocorrect: true,
              enableSuggestions: true,
              clearButtonMode: OverlayVisibilityMode.editing,
              placeholder: '请输入真实姓名',
              placeholderStyle: placeholderStyle,
              style: inputStyle,
              padding: const EdgeInsets.all(CyTokens.space3),
              decoration: inputDecoration,
            ),
            const SizedBox(height: CyTokens.space4),
            Text(
              '联系手机号',
              style: textTheme.titleSmall?.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: CyTokens.space2),
            CupertinoTextField(
              key: const Key('self-play-phone'),
              controller: _phone,
              enabled: _pending == null,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              autofillHints: const <String>[AutofillHints.telephoneNumber],
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              autocorrect: false,
              enableSuggestions: false,
              placeholder: '请输入联系手机号',
              placeholderStyle: placeholderStyle,
              style: inputStyle,
              padding: const EdgeInsets.all(CyTokens.space3),
              decoration: inputDecoration,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: CyTokens.space3),
            CupertinoListTile(
              padding: EdgeInsets.zero,
              onTap: _pending != null
                  ? null
                  : () => setState(() => _consented = !_consented),
              title: Text(
                '我同意将姓名与手机号用于本次路线的联系与核销',
                style: textTheme.bodySmall?.copyWith(
                  color: palette.textPrimary,
                ),
              ),
              trailing: CupertinoSwitch(
                value: _consented,
                onChanged: _pending != null
                    ? null
                    : (bool value) => setState(() => _consented = value),
              ),
            ),
            if (_status != null) ...<Widget>[
              const SizedBox(height: CyTokens.space2),
              Text(
                _status!,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: CyTokens.space3),
            CupertinoButton(
              key: const Key('self-play-primary-action'),
              minimumSize: const Size.fromHeight(44),
              color: palette.actionPrimaryBg,
              disabledColor: palette.bgSubtle,
              foregroundColor: primaryAction == null
                  ? palette.textPlaceholder
                  : palette.actionPrimaryFg,
              onPressed: primaryAction,
              child: _busy
                  ? const CupertinoActivityIndicator()
                  : Text(
                      _readyForTicketWallet
                          ? '查看票夹'
                          : _pending != null
                          ? '继续支付'
                          : '确认购买',
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
