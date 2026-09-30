// 可邀请的俱乐部(目录浏览,不接发邀请写动作——那属于合作招商域的
// /api/coop/invite 完整流程,不在这一批范围内)。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/merchant/merchant_clubs_page.dart';
import '../../golden/golden_theme.dart' show merchantGoldenTheme;

void main() {
  testWidgets('列出已开放俱乐部,展示名称/城市/人数', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          merchantClubsProvider('').overrideWith(
            (ref) async => <Map<String, dynamic>>[
              <String, dynamic>{
                'name': '夜跑俱乐部',
                'city': '上海',
                'memberCount': 128,
              },
            ],
          ),
        ].cast(),
        child: MaterialApp(
          theme: merchantGoldenTheme(),
          home: const MerchantClubsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('夜跑俱乐部'), findsOneWidget);
    expect(find.text('上海 · 128 位成员'), findsOneWidget);
  });

  testWidgets('搜索:回车后按新关键词请求,空态文案随关键词变化', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          merchantClubsProvider(
            '',
          ).overrideWith((ref) async => <Map<String, dynamic>>[]),
          merchantClubsProvider(
            '骑行',
          ).overrideWith((ref) async => <Map<String, dynamic>>[]),
        ].cast(),
        child: MaterialApp(
          theme: merchantGoldenTheme(),
          home: const MerchantClubsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂时没有已开放的俱乐部'), findsOneWidget);

    await tester.enterText(find.byType(CupertinoTextField), '骑行');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('没有匹配的俱乐部'), findsOneWidget);
  });
}
