// 快照专用主题:只给按钮文字补一个「已加载中文字形」的族名。
//
// ★ 为什么需要:主题 textTheme 的样式带着 Typography 给的真实族名
//   (flutter_test_config 把中文字体覆盖到了那些族名上),而按钮的 textStyle
//   是裸 `const TextStyle(fontSize, fontWeight)` —— family 为 null,
//   测试环境回退内置测试字体 ⇒ 快照里**按钮文案全是方框**,
//   看不出超长中文是否截断、字号是否协调,而按钮正是最容易被文案撑爆的地方。
//
// ★ 为什么不改 lib/:真机上 family=null 走系统字体(iOS 苹方)本就正确,
//   显式钉死族名反而会破坏系统字体。这是测试环境的缺陷,修在测试侧。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/theme/app_theme.dart';

/// flutter_test 默认的 dpr。基线图因此是 `size × 3` 像素。
const double _kGoldenDpr = 3.0;

/// 把快照视口设成 [size] —— 渲染画布和 `MediaQuery` **一起**设。
///
/// ★ 为什么不用 `tester.binding.setSurfaceSize`:它只改渲染画布,**不改
///   `MediaQuery`**。页面读到的 `MediaQuery.of(context).size` 仍是 flutter_test
///   的默认 800×600(而且 800×600 是**横屏**)。凡是按视口比例排版的页面 ——
///   `sizeOf(context).height * 0.72` 这种半屏弹层、`22vh` 这种留白 —— 都会照
///   600 算,而基线会把这个错误固化成「期望」。
///
///   实证(2026-09-09,屏③ 章节故事流):上留白 22vh 照 600 算成 132pt,
///   正确值是 844 × 0.22 = 185.7pt。第一版基线就是错的,差点入库。
///   ⚠️ **错的基线比没有基线更糟** —— 它长得跟证据一模一样。
///
/// 只设 `tester.view` 就够:`TestWidgetsFlutterBinding` 在没有 surfaceSize
/// 覆盖时,渲染画布取的正是 `view.physicalSize / devicePixelRatio`。
void setGoldenViewport(WidgetTester tester, Size size) {
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  tester.view.devicePixelRatio = _kGoldenDpr;
  tester.view.physicalSize = size * _kGoldenDpr;
}

/// flutter_test_config 把中文字体注册到了这个族名下。
const String _kLoadedFamily = 'Roboto';

ButtonStyle _withFont(ButtonStyle? style) {
  return (style ?? const ButtonStyle()).copyWith(
    textStyle: WidgetStateProperty.resolveWith<TextStyle>(
      (Set<WidgetState> states) =>
          (style?.textStyle?.resolve(states) ?? const TextStyle())
              .copyWith(fontFamily: _kLoadedFamily),
    ),
  );
}

/// 与 [AppTheme.dark] 完全一致,只把按钮字族换成测试环境有中文字形的那个。
ThemeData goldenTheme() => withGoldenFont(AppTheme.dark());

/// 商家工作台浅色主题的快照版。★ 商家页在真机上就是浅色的
/// (app_router.dart:_merchantLight),用 [goldenTheme] 拍出来的黑底是
/// **没人会看到的画面**,基准图会变成假证据。
ThemeData merchantGoldenTheme() => withGoldenFont(AppTheme.merchantLight());

/// 创建域(主题编辑器)浅色主题的快照版。同上:`/publish*` 与
/// `/template/{new,edit,intro}` 在真机上恒浅(app_router.dart:_topicEditorLight,
/// 决策 D10⑥),这些页必须用它拍 —— 否则基准图里的黑底同样是假证据。
///
/// ⚠️ 恒浅路由在真机上还是**两层**(`Theme` + 它自己挂的 `CupertinoTheme`):
///   Material `Theme` 换不动祖先的 Cupertino 主题(见 app_router 里的注释)。
///   测试里把浅色主题直接当 app 主题用时,两者天然是一致的,所以这里一层就够。
ThemeData topicEditorGoldenTheme() =>
    withGoldenFont(AppTheme.topicEditorLight());

ThemeData withGoldenFont(ThemeData base) {
  return base.copyWith(
    filledButtonTheme:
        FilledButtonThemeData(style: _withFont(base.filledButtonTheme.style)),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: _withFont(base.outlinedButtonTheme.style)),
  );
}
