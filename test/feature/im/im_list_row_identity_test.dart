// 会话行的「这一行是谁」表达(§3.9 IM1 + 小程序 im/list 的行内身份)。
//
// ★ 这三件事都是**同一类错误**的不同面:会话行长得一样,但背后的东西
//   并不是同一种 —— 系统通知不是人、官方客服不是普通私信、免打扰不是没收到。
//   不区分就等于让用户按错误的预期点进去。

import 'package:chengyin_app/core/theme/cy_palette.dart';
import 'package:chengyin_app/data/models/im.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'im_list_test_support.dart';

void main() {
  testWidgets('系统通知用铃铛图标头，不拿空圆冒充某个人', (WidgetTester tester) async {
    await pumpImList(
      tester,
      list: <Conversation>[
        conv(
          id: 7,
          type: kImTypeSystem,
          nickname: '',
          preview: '报名通过',
          unread: 1,
        ),
      ],
    );

    expect(find.byIcon(CupertinoIcons.bell), findsOneWidget);
    expect(find.text('系统通知'), findsOneWidget);
  });

  testWidgets('官方客服会话带「官方」标签', (WidgetTester tester) async {
    await pumpImList(
      tester,
      list: <Conversation>[
        conv(id: 7, type: kImTypeMerchant, nickname: '城瘾客服'),
      ],
    );

    expect(find.text('官方'), findsOneWidget);
  });

  testWidgets('普通私信没有「官方」标签（标签不能变成随处可见的装饰）', (WidgetTester tester) async {
    await pumpImList(tester, list: <Conversation>[conv()]);

    expect(find.text('官方'), findsNothing);
  });

  testWidgets('免打扰会话显示静音图标', (WidgetTester tester) async {
    await pumpImList(tester, list: <Conversation>[conv(muted: true)]);

    expect(find.byIcon(CupertinoIcons.bell_slash), findsOneWidget);
  });

  testWidgets('分隔线只出现在行与行之间，最后一行没有', (WidgetTester tester) async {
    await pumpImList(
      tester,
      list: <Conversation>[
        conv(id: 7, nickname: '阿林'),
        conv(id: 9, nickname: '小周'),
      ],
    );

    expect(find.byKey(const Key('im-separator')), findsOneWidget);

    // ★ 分隔线走**系统语义色**(§3.6 分工:分隔线属系统层),不是品牌 token ——
    //   换成品牌色看着一样,但换了外观 / 开了「增加对比度」时不会跟着系统走。
    final Finder separator = find.byKey(const Key('im-separator'));
    expect(
      tester.widget<Container>(separator).color,
      CupertinoColors.separator.resolveFrom(tester.element(separator)),
    );
  });

  testWidgets('未读会话的摘要提到主色（靠整行轻重分已读/未读）', (WidgetTester tester) async {
    await pumpImList(
      tester,
      list: <Conversation>[
        conv(id: 7, nickname: '阿林', preview: '未读的那条', unread: 3),
        conv(id: 9, nickname: '小周', preview: '读过的那条', unread: 0),
      ],
    );

    final BuildContext context = tester.element(find.text('阿林'));
    final CyPalette p = CyPalette.of(context);
    final Color? unreadColor = tester
        .widget<Text>(find.text('未读的那条'))
        .style
        ?.color;
    final Color? readColor = tester
        .widget<Text>(find.text('读过的那条'))
        .style
        ?.color;

    expect(unreadColor, p.textPrimary);
    expect(readColor, p.textSecondary);
  });
}
