import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';

/// 启动恢复登录态期间的过渡页。
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '城瘾',
              // ★ 中文大字不加负字距:与小程序 `.cy-h1` 的 letter-spacing:0 对齐,
              //   否则大字号中文默认负字距会挤在一起(T5)。
              // T3:强调用 bold(700)。w800 属堆重,已全仓退役。
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontSize: CyTokens.typeDisplay,
                height: 1.15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                color: CyPalette.of(context).textPrimary,
              ),
            ),
            const SizedBox(height: CyTokens.space5),
            const CupertinoActivityIndicator(),
          ],
        ),
      ),
    );
  }
}
