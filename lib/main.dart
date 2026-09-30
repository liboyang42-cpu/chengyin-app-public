import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'core/network/provider_retry.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'feature/auth/auth_controller.dart';

Future<void> main() async {
  // bootstrap() 会经 flutter_secure_storage 读取 token(走 MethodChannel),
  // 必须先初始化绑定,否则启动即抛 "Binding has not yet been initialized" 卡死 splash。
  WidgetsFlutterBinding.ensureInitialized();
  // 后台播放 + 锁屏/控制中心控制(配 Info.plist 的 UIBackgroundModes=audio)。
  // 播放器挂 MediaItem tag 才会在锁屏显示标题/封面,见各 feature 播放点。
  await JustAudioBackground.init();
  // ★★ 锁竖屏。全站页面都是竖版布局(单列表单、底部固定 CTA),
  //   横过来只是被拉宽 + 每屏少一半内容,并没有横屏版设计。
  //   ⚠️ Info.plist 与 AndroidManifest 也要同步锁 —— 只在 Dart 里锁的话,
  //     **启动到首帧之间那段仍会按系统方向渲染**,审核员横着开 App
  //     会先看到一屏歪的。三处都锁才算数。
  //   ⚠️ 只锁 portraitUp,**不含 portraitDown**:倒竖屏会把底部固定 CTA
  //     甩到顶上,而全站都是「底部固定主按钮」的版式。
  //     四处必须同一个口径(2026-08-20 实测原本三个样):
  //     这里 · ios/Runner/Info.plist 的两个 orientations 键 ·
  //     AndroidManifest 的 screenOrientation。
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  // ★★★ 覆盖 Riverpod 3 的默认重试:它会把**任何** Exception 重试 10 次、
  //   退避到 6.4s,而本项目 API 层的业务失败一律 throw Exception ——
  //   于是后端故意拒绝的接口会被反复重打,且重试期间状态停在 AsyncLoading,
  //   全站写好的错误态要三十多秒才出得来。详见 chengyinRetry 的注释。
  final container = ProviderContainer(retry: chengyinRetry);
  // 启动即尝试用已存 token 恢复登录态(异步,期间路由停在 splash)。
  container.read(authControllerProvider.notifier).bootstrap();
  runApp(
    UncontrolledProviderScope(container: container, child: const ChengyinApp()),
  );
}

class ChengyinApp extends ConsumerWidget {
  const ChengyinApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final ThemeData materialTheme = AppTheme.dark();
    return CupertinoApp.router(
      title: '城瘾',
      debugShowCheckedModeBanner: false,
      color: materialTheme.scaffoldBackgroundColor,
      theme: CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: materialTheme.colorScheme.primary,
        // ★★ 必须与 primaryColor **成对**给。`CupertinoButton.filled` 的文字色读的是
        //   `primaryContrastingColor`(cupertino/button.dart),而 SDK 默认值恒为**白色**
        //   (`_kDefaultTheme`)。主按钮底色 actionPrimaryBg 本身就是 #F8F8F8 →
        //   少了这一行就是**白底白字**(2026-09-18 模拟器实测 ≈1.1:1;全仓 34 处
        //   `CupertinoButton.filled` 只有 4 处自己传了前景色,其余同险)。
        //   onPrimary 与 token `--cy-color-action-primary-fg` 同源 = #0A0A0A。
        primaryContrastingColor: materialTheme.colorScheme.onPrimary,
        scaffoldBackgroundColor: materialTheme.scaffoldBackgroundColor,
        barBackgroundColor: materialTheme.scaffoldBackgroundColor,
      ),
      // 根已经是 CupertinoApp,但页面里还有 57 处 Material 组件(RefreshIndicator
      // 等)要求 MaterialLocalizations,拿不到就直接断言崩。MaterialApp 时代提供的
      // 也是 DefaultMaterialLocalizations,这里补回来即行为不变;等 Material 组件
      // 清干净后可以删。
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        DefaultMaterialLocalizations.delegate,
      ],
      builder: (BuildContext context, Widget? child) =>
          Theme(data: materialTheme, child: child ?? const SizedBox.shrink()),
      routerConfig: router,
    );
  }
}
