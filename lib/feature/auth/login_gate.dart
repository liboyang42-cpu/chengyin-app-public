import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_sheet.dart';
import '../../core/widgets/cy_widgets.dart';
import '../legal/legal_doc_page.dart';
import 'auth_controller.dart';
import '../../l10n/strings.dart';
import 'phone_login_sheet.dart';

/// 登录分界线助手:游客浏览免登录,执行需要账号的动作(报名/发布/加入俱乐部/
/// 打卡/加购等)前调用 [requireLogin],未登录就地弹登录弹窗,登完留在原页继续。
///
/// 用法:
/// ```dart
/// onPressed: () async {
///   if (!await requireLogin(context, ref)) return; // 用户没登录就放弃本次动作
///   ...真正的动作...
/// }
/// ```
Future<bool> requireLogin(BuildContext context, WidgetRef ref) async {
  if (ref.read(authControllerProvider).isLoggedIn) return true;
  await showLoginSheet(context);
  if (!context.mounted) return false;
  return ref.read(authControllerProvider).isLoggedIn;
}

/// 底部登录弹窗:微信 / 手机号 / Apple(Apple 仅 iOS)。登录成功自动关闭。
/// 承载走 B1 `native_flutter_sheet`(S2/S3:grabber、detent、下滑关闭由系统负责)。
typedef AppleSignInAvailability = Future<bool> Function();

Future<void> showLoginSheet(
  BuildContext context, {
  AppleSignInAvailability appleSignInAvailability = SignInWithApple.isAvailable,
}) {
  // B1:iOS 15+ 原生 sheet(26+ 真玻璃),其余回退 showCupertinoSheet。
  return showCyNativeSheet<void>(
    context,
    builder: (BuildContext context) =>
        _LoginSheet(appleSignInAvailability: appleSignInAvailability),
  );
}

class _LoginSheet extends ConsumerStatefulWidget {
  const _LoginSheet({required this.appleSignInAvailability});

  final AppleSignInAvailability appleSignInAvailability;

  @override
  ConsumerState<_LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends ConsumerState<_LoginSheet> {
  String? _error;

  /// 手机号表单在弹窗内页内展开(F1 / #213 回归):登录弹窗本身已是
  /// B1 原生承载,再 `showPhoneLoginSheet` 二次 present 会被原生
  /// `already_presented` 静默吞掉 = 死按钮。真源(index `tkbox`)的手机号
  /// 授权弹层也是同页单层展开,不开二层弹层。
  bool _phoneExpanded = false;

  /// 跑一个登录动作:失败在 Sheet 内就地告知;成功(已登录)关闭弹窗。
  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<String?> Function() action,
  ) async {
    final err = await action();
    if (!context.mounted) return;
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (ref.read(authControllerProvider).isLoggedIn) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authControllerProvider).loading;
    final notifier = ref.read(authControllerProvider.notifier);
    final CyPalette palette = CyPalette.of(context);
    return CupertinoPageScaffold(
      // 原生承载时透明,透出系统 sheet 背景(S3)。
      backgroundColor: isCyNativeSheet(context)
          ? CupertinoColors.transparent
          : palette.bgElevated,
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
                CySectionTitle(stringsOf(context).loginTitle),
                const SizedBox(height: CyTokens.space1_5),
                // 副标与 CySectionTitle 同侧左对齐:标题左、副标居中会显得
                // 落点是随手写的(critic 二遍判据)。协议行保持居中页脚形态。
                Text(
                  stringsOf(context).settingsResidualLoginBenefits,
                  style: CyType.caption1.copyWith(color: palette.textSecondary),
                ),
                const SizedBox(height: CyTokens.space5),
                if (_phoneExpanded)
                  _PhoneLoginFormInline(
                    onBack: () => setState(() => _phoneExpanded = false),
                    onLoggedIn: () => Navigator.of(context).pop(),
                  )
                else ...<Widget>[
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton.filled(
                      sizeStyle: CupertinoButtonSize.medium,
                      color: palette.actionPrimaryBg,
                      foregroundColor: palette.actionPrimaryFg,
                      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
                      minimumSize: const Size.fromHeight(CyTokens.btnH),
                      onPressed: loading
                          ? null
                          : () =>
                                _run(context, ref, notifier.loginWithWechatApp),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (loading)
                            CupertinoActivityIndicator(
                              color: palette.actionPrimaryFg,
                            )
                          else
                            const Icon(Icons.wechat, size: 20),
                          const SizedBox(width: CyTokens.space2),
                          Text(stringsOf(context).wechatLogin),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: CyTokens.space3),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton.tinted(
                      sizeStyle: CupertinoButtonSize.medium,
                      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
                      minimumSize: const Size.fromHeight(CyTokens.btnH),
                      onPressed: loading
                          ? null
                          : () => setState(() => _phoneExpanded = true),
                      child: Text(stringsOf(context).phoneLogin),
                    ),
                  ),
                  // ★ 判据用 Theme.of(context).platform,不用 dart:io 的 Platform.isIOS。
                  //   两者在真机上等价,但 `Platform.isIOS` **无法被测试覆写** ——
                  //   golden 跑在 macOS 上时它恒为 false,于是这个按钮
                  //   **从来没有进过任何一张基线图**(V8/V15)。
                  //   而它是 App Store 4.8 的强制项:提供了微信登录就必须提供 Apple 登录。
                  //   最该被盯住的按钮反而是唯一没人盯的,这条不能靠「真机上应该没问题」。
                  //   换成 Theme 的 platform 后,测试可用 debugDefaultTargetPlatformOverride
                  //   把它拍进基线。
                  AppleSignInControl(
                    loading: loading,
                    availability: widget.appleSignInAvailability,
                    onPressed: () =>
                        _run(context, ref, notifier.loginWithApple),
                  ),
                ],
                if (_error != null) ...<Widget>[
                  const SizedBox(height: CyTokens.space3),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: CyType.caption2.copyWith(
                        color: palette.statusDanger,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: CyTokens.space4),
                const LegalConsentLine(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 手机号登录表单项 —— 在登录弹窗内**页内展开**的落点(F1 修复):
/// 顶层自带「返回」+ 标题,内容复用 [CyPhoneLoginView](与独立半屏同款字段合同)。
class _PhoneLoginFormInline extends StatelessWidget {
  const _PhoneLoginFormInline({required this.onBack, required this.onLoggedIn});

  final VoidCallback onBack;
  final VoidCallback onLoggedIn;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            CupertinoButton(
              key: const Key('login-sheet-phone-back'),
              sizeStyle: CupertinoButtonSize.small,
              minimumSize: const Size(CyTokens.btnH, CyTokens.btnH),
              padding: EdgeInsets.zero,
              onPressed: onBack,
              child: const Icon(CupertinoIcons.chevron_left),
            ),
            Text(
              stringsOf(context).phoneLogin,
              style: CyType.headline.copyWith(color: palette.textPrimary),
            ),
          ],
        ),
        CyPhoneLoginView(onLoggedIn: onLoggedIn),
      ],
    );
  }
}

/// Sign in with Apple 的 Flutter 标准外观控件。
///
/// 这里复用已依赖的 [SignInWithAppleButton]，不把它误报为 UIKit
/// `ASAuthorizationAppleIDButton`：该包的授权流是原生的，按钮却是 Flutter
/// `CupertinoButton` 绘制。真 UIKit 按钮需要另外的 PlatformView bridge，
/// 不在登录 Sheet 内自建一套高风险桥接。
class AppleSignInControl extends StatefulWidget {
  const AppleSignInControl({
    super.key,
    required this.loading,
    required this.availability,
    required this.onPressed,
  });

  final bool loading;
  final AppleSignInAvailability availability;
  final Future<void> Function() onPressed;

  @override
  State<AppleSignInControl> createState() => _AppleSignInControlState();
}

class _AppleSignInControlState extends State<AppleSignInControl> {
  Future<bool>? _availability;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _startAvailabilityCheckIfNeeded();
  }

  @override
  void didUpdateWidget(covariant AppleSignInControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.availability != widget.availability) {
      _availability = null;
      _startAvailabilityCheckIfNeeded();
    }
  }

  void _startAvailabilityCheckIfNeeded() {
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      _availability ??= widget.availability();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform != TargetPlatform.iOS) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<bool>(
      future: _availability,
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();

        // 包内图标和文字会随 height 等比缩放；随 Dynamic Type 增高
        // 可以保留 Apple 规定的内容比例，同时不低于 44pt。
        final double scaledHeight =
            44 * MediaQuery.textScalerOf(context).scale(19) / 19;
        final double height = scaledHeight.clamp(44, 60).toDouble();
        final bool enabled = !widget.loading;
        final SignInWithAppleButtonStyle appleStyle =
            Theme.of(context).brightness == Brightness.dark
            ? SignInWithAppleButtonStyle.white
            : SignInWithAppleButtonStyle.black;

        return Padding(
          padding: const EdgeInsets.only(top: CyTokens.space3),
          child: Semantics(
            button: true,
            enabled: enabled,
            label: stringsOf(context).appleLogin,
            child: ExcludeSemantics(
              child: SignInWithAppleButton(
                height: height,
                style: appleStyle,
                text: stringsOf(context).appleLogin,
                onPressed: enabled ? widget.onPressed : null,
              ),
            ),
          ),
        );
      },
    );
  }
}
