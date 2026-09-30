// 输入条的材质分支(§3.9 IM5 / 手册 M8):
// 底部输入条是**浮动功能层** —— iOS 26+ 挂原生玻璃容器,iOS 13–25 回退实色条。
//
// ★ 为什么要有这两条:`LiquidGlassContainer` 在非 iOS 26 上 build 出的是
//   `SizedBox()`(平台不支持就整个不画)—— 分支判错时页面上**输入条直接消失**,
//   而这在别的用例里不会被发现(它们只断言文案/请求)。所以两个分支各回读一次。

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

import 'im_chat_test_support.dart';

void main() {
  testWidgets('iOS 26+:输入条走原生玻璃容器,不走自绘实色条', (WidgetTester tester) async {
    await pumpChat(tester, api: FakeImChatApi(), liquidGlassSupported: true);

    expect(find.byKey(const Key('im-input-bar-glass')), findsOneWidget);
    expect(find.byType(LiquidGlassContainer), findsOneWidget);
    expect(
      find.byKey(const Key('im-input-bar-solid')),
      findsNothing,
      reason: '玻璃与实色条是二选一,叠着出现就是玻璃叠玻璃(M4)',
    );
  });

  testWidgets('iOS 13–25:回退实色条,输入框与「+」照旧在', (WidgetTester tester) async {
    await pumpChat(tester, api: FakeImChatApi(), liquidGlassSupported: false);

    expect(find.byKey(const Key('im-input-bar-solid')), findsOneWidget);
    expect(find.byType(LiquidGlassContainer), findsNothing);
    expect(find.byType(CupertinoTextField), findsOneWidget);
    expect(find.byKey(const Key('im-plus')), findsOneWidget);
  });
}
