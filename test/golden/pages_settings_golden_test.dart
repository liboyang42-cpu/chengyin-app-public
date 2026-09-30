// 设置域整页快照:设置页(玩家/商家两视角)+ 关于页。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_settings_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/settings/about_page.dart';
import 'package:chengyin_app/feature/settings/settings_page.dart';
import 'golden_theme.dart';

/// 固定登录态:不让 AuthController 走网络 bootstrap。
class _FixedAuth extends AuthController {
  _FixedAuth(this._state);

  final AuthState _state;

  @override
  AuthState build() => _state;
}

AuthState _authed(String role) => AuthState(
  user: User(id: 1, nickname: '阿兰', avatar: '', role: role),
  initialized: true,
);

/// [merchantView] 为真时用浅色主题 —— 设置页是**条件浅色**的 8 页之一
/// (小程序 pages/shezhi:47 `if (isMerchantView) merchantPageShow()`)。
/// 真机上这层由路由 `_merchantLightIfMerchant()` 供给;这里直接渲页面、
/// 绕过了路由,所以得自己给,否则拍到的是「没人会看到的黑底商家设置页」。
/// ⚠️ 路由那层有没有漏包,靠 `merchant_routes_are_light_test` 判,不靠这张图。
Widget _app(List<dynamic> overrides, Widget home,
    {bool merchantView = false}) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: merchantView ? merchantGoldenTheme() : goldenTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

void main() {
  testWidgets('设置页:玩家视角(主理人/商家入口可见)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 820));
    await tester.pumpWidget(
      _app(
        <dynamic>[
          authControllerProvider.overrideWith(() => _FixedAuth(_authed('player'))),
        ],
        const SettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    // 玩家视角下「成为俱乐部主理人 / 成为商家」必须都在(与小程序条件一致)。
    expect(find.text('成为俱乐部主理人'), findsOneWidget);
    expect(find.text('成为商家'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_settings.png'),
    );
  });

  testWidgets('设置页:商家视角(主理人/商家入口隐藏)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 820));
    await tester.pumpWidget(
      _app(
        <dynamic>[
          authControllerProvider.overrideWith(
            () => _FixedAuth(_authed('merchant')),
          ),
        ],
        const SettingsPage(),
        merchantView: true,
      ),
    );
    await tester.pumpAndSettle();
    // 商家视角:两个申请入口必须消失。
    expect(find.text('成为俱乐部主理人'), findsNothing);
    expect(find.text('成为商家'), findsNothing);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_settings_merchant.png'),
    );
  });

  testWidgets('关于页', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 820));
    await tester.pumpWidget(
      _app(
        <dynamic>[
          authControllerProvider.overrideWith(
            () => _FixedAuth(const AuthState(initialized: true)),
          ),
        ],
        const AboutPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('城瘾'), findsOneWidget);
    expect(find.text('我的二维码'), findsOneWidget);
    expect(find.text('登录后查看'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_settings_about.png'),
    );
  });
}
