import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../data/api/account_api.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';
import '../legal/legal_doc_page.dart';
import '../legal/legal_docs.dart';

/// 关于页。对齐小程序 `pages/shezhi/about/index`:
/// 应用信息(logo / 名称 / 版本 / 标语)→ 我的二维码→
/// 用户服务协议 / 联系我们。
final playerCodeProvider = FutureProvider.autoDispose<String>((ref) {
  return ref.watch(accountApiProvider).playerCode();
}, retry: (int _, Object _) => null);

enum _ContactAction { call, copy }

typedef ContactUriLauncher = Future<bool> Function(Uri uri);
typedef ContactTextCopier = Future<void> Function(String text);

Future<bool> _launchContactUri(Uri uri) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> _copyContactText(String text) {
  return Clipboard.setData(ClipboardData(text: text));
}

class AboutPage extends ConsumerWidget {
  const AboutPage({
    super.key,
    this.launchContactUri = _launchContactUri,
    this.copyContactText = _copyContactText,
  });

  static const String _contactPhone = '15229020419';

  final ContactUriLauncher launchContactUri;
  final ContactTextCopier copyContactText;

  static void _toast(BuildContext context, String message) {
    CyNativeNotice.show(context, message);
  }

  static Future<_ContactAction?> _showContactActions(BuildContext context) {
    return showCupertinoModalPopup<_ContactAction>(
      context: context,
      builder: (BuildContext sheetContext) => CupertinoActionSheet(
        title: const Text('联系我们'),
        message: const Text('客服电话 15229020419'),
        actions: <CupertinoActionSheetAction>[
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.of(sheetContext).pop(_ContactAction.call),
            child: const Text('拨打 15229020419'),
          ),
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.of(sheetContext).pop(_ContactAction.copy),
            child: const Text('复制电话号码'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Future<void> _contact(BuildContext context) async {
    final _ContactAction? action = await _showContactActions(context);
    if (action == null || !context.mounted) return;

    switch (action) {
      case _ContactAction.call:
        final bool launched = await launchContactUri(
          Uri(scheme: 'tel', path: _contactPhone),
        );
        if (!launched && context.mounted) {
          _toast(context, '无法打开电话应用');
        }
      case _ContactAction.copy:
        await copyContactText(_contactPhone);
        if (context.mounted) {
          _toast(context, '电话号码已复制');
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool loggedIn = ref.watch(authControllerProvider).isLoggedIn;
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.only(bottom: CyTokens.space7),
            children: <Widget>[
              const CyPageTitle('关于'),
              const _AppInfo(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.pageX,
                  vertical: CyTokens.space5,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '我的二维码',
                      style: TextStyle(
                        fontSize: CyTokens.typeCardTitle,
                        fontWeight: FontWeight.w600,
                        color: CyPalette.of(context).textPrimary,
                      ),
                    ),
                    const SizedBox(height: CyTokens.space1_5),
                    Text(
                      '用于在活动现场展示你的城瘾玩家身份。',
                      style: TextStyle(
                        fontSize: CyTokens.typeBody,
                        height: CyTokens.leadingNormal,
                        color: CyPalette.of(context).textSecondary,
                      ),
                    ),
                    const SizedBox(height: CyTokens.space3),
                    if (loggedIn)
                      const _PlayerCodePanel()
                    else
                      _PlayerCodeLoginGate(
                        onPressed: () async {
                          if (!await requireLogin(context, ref) ||
                              !context.mounted) {
                            return;
                          }
                          ref.invalidate(playerCodeProvider);
                        },
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
                child: Column(
                  children: <Widget>[
                    CyCell(
                      title: '用户服务协议',
                      subtitle: '查看服务条款',
                      leading: Icon(
                        CupertinoIcons.doc_text,
                        size: 20,
                        color: CyPalette.of(context).textSecondary,
                      ),
                      onTap: () => context.push(
                        LegalDocPage.routeOf(LegalDocType.userAgreement),
                      ),
                    ),
                    CyCell(
                      title: '联系我们',
                      subtitle: '客服电话 15229020419',
                      leading: Icon(
                        CupertinoIcons.phone,
                        size: 20,
                        color: CyPalette.of(context).textSecondary,
                      ),
                      onTap: () => _contact(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerCodeLoginGate extends StatelessWidget {
  const _PlayerCodeLoginGate({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _PlayerCodeSurface(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            CupertinoIcons.qrcode,
            size: 42,
            color: CyPalette.of(context).textTertiary,
          ),
          const SizedBox(height: CyTokens.space2),
          CupertinoButton.tinted(
            sizeStyle: CupertinoButtonSize.small,
            onPressed: onPressed,
            child: const Text('登录后查看'),
          ),
        ],
      ),
    );
  }
}

class _PlayerCodePanel extends ConsumerWidget {
  const _PlayerCodePanel();

  String _message(Object error) {
    final String message = error
        .toString()
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .trim();
    return message.isEmpty ? '个人码暂不可用，请稍后重试' : message;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<String> code = ref.watch(playerCodeProvider);
    return _PlayerCodeSurface(
      child: code.when(
        loading: () => const Center(child: CupertinoActivityIndicator()),
        error: (Object error, StackTrace stackTrace) => _CodeFailure(
          message: _message(error),
          onRetry: () => ref.invalidate(playerCodeProvider),
        ),
        data: (String qr) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Semantics(
              image: true,
              label: '我的城瘾玩家身份码',
              child: Image.network(
                qr,
                key: const Key('player-code-image'),
                width: 104,
                height: 104,
                fit: BoxFit.contain,
                errorBuilder:
                    (BuildContext context, Object error, StackTrace? stack) {
                      return SizedBox(
                        width: 104,
                        height: 104,
                        child: Center(
                          child: Text(
                            '身份码图片加载失败',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: CyTokens.typeCaption,
                              color: CyPalette.of(context).textSecondary,
                            ),
                          ),
                        ),
                      );
                    },
              ),
            ),
            CupertinoButton(
              sizeStyle: CupertinoButtonSize.small,
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
              onPressed: () => ref.invalidate(playerCodeProvider),
              child: const Text('刷新身份码'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeFailure extends StatelessWidget {
  const _CodeFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: CyTokens.typeCaption,
              color: CyPalette.of(context).textSecondary,
            ),
          ),
          CupertinoButton(
            sizeStyle: CupertinoButtonSize.small,
            onPressed: onRetry,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

class _PlayerCodeSurface extends StatelessWidget {
  const _PlayerCodeSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150, // 300rpx，保留小程序几何高度。
      width: double.infinity,
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgElevated,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        border: Border.all(color: CyPalette.of(context).borderSubtle),
      ),
      child: child,
    );
  }
}

/// `.about-app`:logo + 名称 + 版本 + 标语,垂直居中。
class _AppInfo extends StatelessWidget {
  const _AppInfo();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: CyTokens.space5),
      child: Column(
        children: <Widget>[
          Container(
            width: 64, // 128rpx
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CyPalette.of(context).bgElevated,
            ),
            alignment: Alignment.center,
            child: Text(
              '瘾',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: CyPalette.of(context).textPrimary,
              ),
            ),
          ),
          const SizedBox(height: CyTokens.space3),
          Text(
            '城瘾',
            style: TextStyle(
              fontSize: CyTokens.typeDisplay,
              height: CyTokens.leadingTight,
              fontWeight: FontWeight.w700,
              color: CyPalette.of(context).textPrimary,
            ),
          ),
          const SizedBox(height: CyTokens.space1),
          // ★ 版本号随 pubspec 一起维护;接入 package_info 后改为运行时读取。
          Text(
            '版本 1.0.0',
            style: TextStyle(
              fontSize: CyTokens.typeLabel,
              color: CyPalette.of(context).textSecondary,
            ),
          ),
          const SizedBox(height: CyTokens.space2),
          Text(
            '发现城市，也发现新的自己',
            style: TextStyle(
              fontSize: CyTokens.typeBody,
              color: CyPalette.of(context).textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
