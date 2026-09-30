// Wave-C 创建俱乐部四步向导(C40 类型 / C41 路线方向 / C42 资料 / C43 城市)。
//
// 四步各自的正文在同一个 StatefulWidget 里(`_step` 是本页局部状态),所以这四张
// 图**必须按顺序点过来拍** —— 单独 pump 第 3 步是拍不到的,也没有别的入口。
// 身份用主理人(role='club'):页面有预检,不是主理人会先被挡去「主理人申请」,
// 那样拍到的就不是向导而是拦截页。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_wave_c_club_create_golden_test.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/club/club_create_page.dart';

import 'golden_theme.dart';

class _FixedAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    user: User(id: 7, nickname: '阿兰', avatar: '', role: 'club'),
    initialized: true,
  );
}

Widget _app() {
  return ProviderScope(
    overrides: <dynamic>[
      authControllerProvider.overrideWith(() => _FixedAuth()),
    ].cast(),
    child: MaterialApp(
      theme: goldenTheme(),
      debugShowCheckedModeBanner: false,
      home: const ClubCreatePage(),
    ),
  );
}

Future<void> _shot(WidgetTester tester, String goldenPath) async {
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

void main() {
  testWidgets('C40 创建俱乐部:第 1 步 类型', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('俱乐部类型'), findsWidgets);
    await _shot(tester, 'goldens/page_club_create_type.png');
  });

  testWidgets('C41 创建俱乐部:第 2 步 路线方向', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('兴趣社群'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('路线方向'), findsWidgets);
    await _shot(tester, 'goldens/page_club_create_direction.png');
  });

  testWidgets('C42 创建俱乐部:第 3 步 资料', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('兴趣社群'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('城市定向'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('俱乐部资料'), findsWidgets);
    await _shot(tester, 'goldens/page_club_create_profile.png');
  });

  testWidgets('C43 创建俱乐部:第 4 步 所在城市', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('兴趣社群'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('城市定向'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    // 第 3 步第一个输入框就是俱乐部名称(本页没给 key,按顺序取)。
    await tester.enterText(find.byType(CupertinoTextField).first, '夜行俱乐部');
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('所在城市'), findsWidgets);
    await _shot(tester, 'goldens/page_club_create_city.png');
  });
}
