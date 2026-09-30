import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/cy_palette.dart';
import '../../l10n/strings.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../legal/legal_doc_page.dart';
import 'auth_controller.dart';
import 'phone_login_sheet.dart';
import '../../core/widgets/cy_native_notice.dart';

class LoginPage extends ConsumerWidget {
  const LoginPage({super.key, this.intent});

  /// Onboarding intent only. Authentication and permissions remain server-owned.
  final String? intent;

  bool get _hasIntent => const <String>{
    'player',
    'merchant',
    'existing',
  }.contains(intent);

  /// 跑一个登录动作:失败(返回非空文案)弹原生通知;成功/取消(null)静默。
  /// 登录成功后由 go_router 监听 auth 变化自动跳转,无需手动导航。
  Future<void> _runLogin(
    BuildContext context,
    Future<String?> Function() action,
  ) async {
    final error = await action();
    if (error != null && context.mounted) {
      CyNativeNotice.show(context, error, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = ref.watch(authControllerProvider).loading;
    final strings = stringsOf(context);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Spacer(),
                      Text(
                        strings.appName,
                        textAlign: TextAlign.center,
                        // ★ 中文大字不加负字距:小程序注释明写「中文大字不加负字距」,
                        //   Flutter 大字号默认带负 letterSpacing,不置零中文会挤在一起。
                        // T3:强调用 bold(700)。w800 属堆重,已全仓退役。
                        style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontSize: CyTokens.typeDisplay,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                          color: CyPalette.of(context).textPrimary,
                        ),
                      ),
                      const SizedBox(height: CyTokens.space2),
                      Text(
                        strings.appTagline,
                        textAlign: TextAlign.center,
                        style: CyType.subhead.copyWith(
                          color: CyPalette.of(context).textSecondary,
                        ),
                      ),
                      const Spacer(),
                      if (!_hasIntent) ...<Widget>[
                        CyNativeButton(
                          label: strings.playerRegistration,
                          onPressed: () => context.go('/login?intent=player'),
                        ),
                        const SizedBox(height: CyTokens.space3),
                        CyNativeButton(
                          label: strings.merchantRegistration,
                          role: CyNativeButtonRole.secondary,
                          onPressed: () => context.go('/login?intent=merchant'),
                        ),
                        const SizedBox(height: CyTokens.space3),
                        CupertinoButton(
                          onPressed: () => context.go('/login?intent=existing'),
                          child: Text(strings.existingAccountLogin),
                        ),
                      ] else ...<Widget>[
                        Text(
                          switch (intent) {
                            'merchant' => strings.merchantRegistration,
                            'player' => strings.playerRegistration,
                            _ => strings.loginTitle,
                          },
                          style: CyType.title3,
                          textAlign: TextAlign.center,
                        ),
                        if (intent == 'merchant') ...<Widget>[
                          const SizedBox(height: CyTokens.space2),
                          Text(
                            strings.merchantRegistrationExplanation,
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: CyTokens.space3),
                        CyNativeButton(
                          label: strings.wechatLogin,
                          loading: loading,
                          borderRadius: CyTokens.radiusLg,
                          onPressed: loading
                              ? null
                              : () => _runLogin(
                                  context,
                                  () => ref
                                      .read(authControllerProvider.notifier)
                                      .loginWithWechatApp(),
                                ),
                          icon: const CyNativeButtonIcon(
                            sfSymbol: 'bubble.left.and.bubble.right.fill',
                            fallback: CupertinoIcons.chat_bubble_2_fill,
                          ),
                        ),
                        const SizedBox(height: CyTokens.space3),
                        CyNativeButton(
                          label: strings.phoneLogin,
                          role: CyNativeButtonRole.secondary,
                          borderRadius: CyTokens.radiusLg,
                          onPressed: loading ? null : () => showPhoneLoginSheet(context),
                        ),
                        // iOS 合规:用了微信第三方登录,须提供 Sign in with Apple(指南 4.8)。
                        // 仅 iOS 显示。
                        // ★ 判据用 Theme.of(context).platform,不用 dart:io 的 Platform.isIOS。
                        //   两者在真机上等价,但 `Platform.isIOS` **无法被测试覆写** ——
                        //   golden 跑在 macOS 上时它恒为 false,于是这个按钮
                        //   **从来没有进过任何一张基线图**(V8/V15)。
                        //   而它是 App Store 4.8 的强制项:提供了微信登录就必须提供 Apple 登录。
                        //   最该被盯住的按钮反而是唯一没人盯的,这条不能靠「真机上应该没问题」。
                        //   换成 Theme 的 platform 后,测试可用 debugDefaultTargetPlatformOverride
                        //   把它拍进基线。
                        if (Theme.of(context).platform == TargetPlatform.iOS) ...<Widget>[
                          const SizedBox(height: CyTokens.space3),
                          CyNativeButton(
                            label: strings.appleLogin,
                            role: CyNativeButtonRole.secondary,
                            borderRadius: CyTokens.radiusLg,
                            onPressed: loading
                                ? null
                                : () => _runLogin(
                                    context,
                                    () => ref
                                        .read(authControllerProvider.notifier)
                                        .loginWithApple(),
                                  ),
                            icon: const CyNativeButtonIcon(
                              sfSymbol: 'apple.logo',
                              fallback: CupertinoIcons.device_phone_portrait,
                            ),
                          ),
                        ],
                        CupertinoButton(
                          onPressed: loading ? null : () => context.go('/login'),
                          child: Text(strings.chooseAgain),
                        ),
                      ],
                      const SizedBox(height: CyTokens.space6),
                      const LegalConsentLine(),
                      const SizedBox(height: CyTokens.space5),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
