// 关于页的商家视角:真源 `pages/shezhi/about/index.wxml` 根节点是
// `{{isMerchantView ? 'theme-merchant' : 'theme-dark'}}` —— 与父页 `/settings` 同源。
// App 侧那层浅色由路由 `_merchantLightIfMerchant` 供给(有没有漏包由
// `merchant_routes_are_light_test` 盯),而页面自己必须**跟着主题取值**:
// 写死的 `CyTokens.*` 是暗色编译期常量,在白底上就是白字白卡 ——
// 不报错、不抛异常、单测全绿,只有真去看那一屏才发现(见
// `light_pages_no_static_colors_test` 的实证)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/core/theme/cy_palette.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/settings/about_page.dart';

class _FixedAuth extends AuthController {
  _FixedAuth(this._state);

  final AuthState _state;

  @override
  AuthState build() => _state;
}

Future<void> _pump(WidgetTester tester, ThemeData theme) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(
          () => _FixedAuth(const AuthState(initialized: true)),
        ),
      ].cast(),
      child: MaterialApp(
        theme: theme,
        debugShowCheckedModeBanner: false,
        home: const AboutPage(),
      ),
    ),
  );
}

void main() {
  testWidgets('商家浅色下关于页取浅色调色板,不拿暗色常量冒充', (WidgetTester tester) async {
    await _pump(tester, AppTheme.merchantLight());
    await tester.pumpAndSettle();

    final TextStyle name = tester.widget<Text>(find.text('城瘾')).style!;
    expect(name.color, CyPalette.light.textPrimary);
    // 负控:同一个断言在旧写法(暗色常量)下必须判红。
    expect(name.color, isNot(CyPalette.dark.textPrimary));

    // 页面底色/卡片底同样来自调色板。
    expect(CyPalette.of(tester.element(find.text('城瘾'))).bgPage,
        CyPalette.light.bgPage);
    expect(find.text('我的二维码'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('玩家暗色下取值不变(与迁移前的暗色常量逐值等价)', (WidgetTester tester) async {
    await _pump(tester, AppTheme.dark());
    await tester.pumpAndSettle();

    final TextStyle name = tester.widget<Text>(find.text('城瘾')).style!;
    expect(name.color, CyPalette.dark.textPrimary);
  });
}
