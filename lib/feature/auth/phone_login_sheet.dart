import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_sheet.dart';
import '../../core/widgets/cy_widgets.dart';
import 'auth_controller.dart';
import '../../l10n/strings.dart';

/// 打开手机号登录弹层。
Future<void> showPhoneLoginSheet(BuildContext context) {
  // B1:iOS 15+ 原生 sheet(26+ 真玻璃),其余回退 showCupertinoSheet。
  return showCyNativeSheet<void>(
    context,
    builder: (BuildContext context) => const _PhoneLoginSheet(),
  );
}

class _PhoneLoginSheet extends StatelessWidget {
  const _PhoneLoginSheet();

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      // 原生承载时透明,透出系统 sheet 背景(S3)。
      backgroundColor: isCyNativeSheet(context)
          ? CupertinoColors.transparent
          : CyPalette.of(context).bgElevated,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            // .cy-sheet:space-4 上 / page-x 左右 / space-5 + 安全区 下。
            padding: const EdgeInsets.only(
              left: CyTokens.pageX,
              right: CyTokens.pageX,
              top: CyTokens.space4,
              bottom: CyTokens.space5,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // 抓手由 sheet presenter 自带(S2);这里留等高空间保持标题落点。
                const SizedBox(height: CyTokens.space4),
                CySectionTitle(stringsOf(context).phoneLogin),
                // 登录成功只关弹窗,留在原页继续刚才的动作(报名/发布等)。
                // 若是从 /login 整页进来的,路由 redirect 会把已登录用户收敛到 /map。
                CyPhoneLoginView(onLoggedIn: () => Navigator.of(context).pop()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 手机号登录表单主体(手机号 / 验证码 / 获取验证码 / 登录 / 三态发码钮 / 反馈行)。
///
/// 两种落点共用:[showPhoneLoginSheet] 的独立半屏,和登录门弹窗里的
/// **页内展开** —— 登录弹窗本身已是 B1 原生承载,再 present 一层会被
/// 原生 `already_presented` 静默吞掉(F1 / #213 回归),所以登录门里
/// 手机号表单只能展开在既有弹窗内部,不开二层弹窗。
/// 登录成功经 [onLoggedIn] 交回调用方收敛(gate 关整弹窗 / 半屏 pop 自己)。
class CyPhoneLoginView extends ConsumerStatefulWidget {
  const CyPhoneLoginView({super.key, required this.onLoggedIn});

  final VoidCallback onLoggedIn;

  @override
  ConsumerState<CyPhoneLoginView> createState() => _CyPhoneLoginViewState();
}

class _CyPhoneLoginViewState extends ConsumerState<CyPhoneLoginView> {
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _code = TextEditingController();
  String? _feedback;
  bool _feedbackIsError = false;
  bool _smsSending = false;
  bool _smsSent = false;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _showFeedback(String msg, {required bool isError}) {
    if (!mounted) return;
    setState(() {
      _feedback = msg;
      _feedbackIsError = isError;
    });
  }

  Future<void> _sendCode() async {
    if (_smsSending) return;
    final phone = _phone.text.trim();
    if (phone.length != 11) {
      _showFeedback(stringsOf(context).phoneNumberHint, isError: true);
      return;
    }
    setState(() => _smsSending = true);
    try {
      await ref.read(authApiProvider).sendSmsCode(phone);
      if (!mounted) return;
      setState(() {
        _smsSending = false;
        _smsSent = true;
      });
      _showFeedback(stringsOf(context).smsCodeSent, isError: false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _smsSending = false);
      final String message = error
          .toString()
          .replaceFirst(RegExp(r'^Exception:\s*'), '')
          .trim();
      _showFeedback(
        message.isEmpty ? stringsOf(context).smsSendFailed : message,
        isError: true,
      );
    }
  }

  Future<void> _login() async {
    final phone = _phone.text.trim();
    final code = _code.text.trim();
    if (phone.length != 11) {
      _showFeedback(stringsOf(context).phoneNumberHint, isError: true);
      return;
    }
    if (code.isEmpty) {
      _showFeedback(stringsOf(context).enterVerificationCode, isError: true);
      return;
    }
    final err = await ref
        .read(authControllerProvider.notifier)
        .loginWithPhone(phone, code);
    if (!mounted) return;
    if (err == null) {
      TextInput.finishAutofillContext();
      widget.onLoggedIn();
    } else {
      _showFeedback(err, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authControllerProvider).loading;
    final CyPalette palette = CyPalette.of(context);
    final BoxDecoration fieldDecoration = BoxDecoration(
      color: palette.inputBgEmpty,
      border: Border.all(color: palette.borderStrong),
      borderRadius: BorderRadius.circular(CyTokens.radiusSm),
    );
    final TextStyle fieldStyle = CyType.body.copyWith(
      color: palette.textPrimary,
    );
    final TextStyle placeholderStyle = CyType.body.copyWith(
      color: palette.textSecondary,
    );
    return AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 标题由落点(独立半屏 `_PhoneLoginSheet` / 登录门页内展开)自己给,
          // 这里只留一段等高呼吸位。
          const SizedBox(height: CyTokens.space4),
          CyField(
            label: stringsOf(context).phoneNumber,
            child: CupertinoTextField(
              controller: _phone,
              autofillHints: const <String>[AutofillHints.telephoneNumber],
              keyboardType: TextInputType.phone,
              maxLength: 11,
              clearButtonMode: OverlayVisibilityMode.editing,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: fieldDecoration,
              style: fieldStyle,
              placeholderStyle: placeholderStyle,
              cursorColor: palette.brand,
              // hint 给格式而不是重复上面的 label —— 同一件事说两遍,
              // 而且 hint 一输入就消失,重复的那份等于白占。
              placeholder: stringsOf(context).phoneNumberHint,
              padding: const EdgeInsets.symmetric(
                horizontal: CyTokens.space3,
                vertical: CyTokens.space3_5,
              ),
            ),
          ),
          CyField(
            label: stringsOf(context).verificationCode,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: CupertinoTextField(
                    controller: _code,
                    autofillHints: const <String>[AutofillHints.oneTimeCode],
                    keyboardType: TextInputType.number,
                    // 小程序注销页那个验证码框是 maxlength="6",这里原先没限位,
                    // 能一直输下去 —— 对齐成同样的 6 位。
                    maxLength: 6,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: fieldDecoration,
                    style: fieldStyle,
                    placeholderStyle: placeholderStyle,
                    cursorColor: palette.brand,
                    placeholder: stringsOf(context).smsCodeHint,
                    padding: const EdgeInsets.symmetric(
                      horizontal: CyTokens.space3,
                      vertical: CyTokens.space3_5,
                    ),
                  ),
                ),
                const SizedBox(width: CyTokens.space3),
                // 真源(scene-settings-deregister)的「获取验证码」是行尾
                // 文字动作(text-title 色、无底),不是灰胶囊 —— 灰胶囊和
                // 禁用态在暗底上几乎分不出来。
                Flexible(child: CupertinoButton(
                  sizeStyle: CupertinoButtonSize.medium,
                  minimumSize: const Size(0, CyTokens.btnH),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  onPressed: _smsSending ? null : _sendCode,
                  child: Text(
                    _smsSending ? stringsOf(context).sendingCode : (_smsSent ? stringsOf(context).resendCode : stringsOf(context).getCode),
                    style: CyType.subhead.copyWith(
                      color: _smsSending
                          ? palette.textDisabled
                          : palette.textPrimary,
                    ),
                  ),
                )),
              ],
            ),
          ),
          if (_feedback != null) ...<Widget>[
            const SizedBox(height: CyTokens.space1),
            Semantics(
              liveRegion: true,
              child: Text(
                _feedback!,
                key: const Key('phone-login-feedback'),
                textAlign: TextAlign.center,
                style: CyType.caption2.copyWith(
                  color: _feedbackIsError
                      ? palette.statusDanger
                      : palette.statusSuccess,
                ),
              ),
            ),
          ],
          const SizedBox(height: CyTokens.space2),
          SizedBox(
            width: double.infinity,
            child: Semantics(
              button: true,
              enabled: !loading,
              label: stringsOf(context).signIn,
              value: loading ? stringsOf(context).signingIn : null,
              liveRegion: loading,
              onTap: loading ? null : _login,
              excludeSemantics: true,
              child: CupertinoButton.filled(
                sizeStyle: CupertinoButtonSize.medium,
                color: palette.actionPrimaryBg,
                foregroundColor: palette.actionPrimaryFg,
                borderRadius: BorderRadius.circular(CyTokens.radiusLg),
                minimumSize: const Size.fromHeight(CyTokens.btnH),
                onPressed: loading ? null : _login,
                child: loading
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          CupertinoActivityIndicator(
                            color: palette.actionPrimaryFg,
                          ),
                          const SizedBox(width: CyTokens.space2),
                          Text(stringsOf(context).signIn),
                        ],
                      )
                    : Text(stringsOf(context).signIn),
              ),
            ),
          ),
          const SizedBox(height: CyTokens.space2),
          Text(
            stringsOf(context).codeExpiresInFiveMinutes,
            textAlign: TextAlign.center,
            style: CyType.caption2.copyWith(color: palette.textDisabled),
          ),
        ],
      ),
    );
  }
}
