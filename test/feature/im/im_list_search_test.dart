// 会话列表的顶部内联搜索(§3.9 IM1 / N7 内联)。
//
// ★ 边界写死:「只筛已经拉回来的会话」。后端没有消息搜索端点,
//   做成"搜全部"就是给用户一个永远查不到东西的搜索框。

import 'package:chengyin_app/data/models/im.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'im_list_test_support.dart';

Future<void> _search(WidgetTester tester, String kw) async {
  await tester.enterText(find.byType(CupertinoTextField), kw);
  await tester.pumpAndSettle();
}

/// ★ 只找 `Text` 组件 —— 搜索框本身是个 EditableText,它里面的关键词
///   也会被 `find.text` 命中,于是「筛掉了没有」这件事会被搜到的那个字骗过去。
Finder _rowText(String s) =>
    find.byWidgetPredicate((Widget w) => w is Text && w.data == s);

void main() {
  testWidgets('按名字筛选；清空关键词后全部回来', (WidgetTester tester) async {
    await pumpImList(
      tester,
      list: <Conversation>[
        conv(id: 7, nickname: '阿林', preview: '周六见'),
        conv(id: 9, nickname: '小周', preview: '路线发你了'),
      ],
    );

    await _search(tester, '小周');
    expect(_rowText('小周'), findsOneWidget);
    expect(_rowText('阿林'), findsNothing);

    await _search(tester, '');
    expect(_rowText('小周'), findsOneWidget);
    expect(_rowText('阿林'), findsOneWidget);
  });

  testWidgets('摘要命中也算（名字记不住时按内容找）', (WidgetTester tester) async {
    await pumpImList(
      tester,
      list: <Conversation>[
        conv(id: 7, nickname: '阿林', preview: '周六见'),
        conv(id: 9, nickname: '小周', preview: '路线发你了'),
      ],
    );

    await _search(tester, '路线');
    expect(_rowText('小周'), findsOneWidget);
    expect(_rowText('阿林'), findsNothing);
  });

  testWidgets('筛不出东西时给空态，而不是一片空白', (WidgetTester tester) async {
    await pumpImList(tester, list: <Conversation>[conv(nickname: '阿林')]);

    await _search(tester, '查无此人');

    expect(find.text('没有匹配的会话'), findsOneWidget);
    // 空态图标是系统符号(Cupertino),不是 Material 图形 —— 搜索框自己也有一枚
    // 同名的放大镜(16pt),所以按 48pt 的空态尺寸认人。
    expect(
      find.byWidgetPredicate(
        (Widget w) =>
            w is Icon && w.icon == CupertinoIcons.search && w.size == 48,
      ),
      findsOneWidget,
      reason: '空态该用系统符号,别退回 Material 图形',
    );
    expect(_rowText('阿林'), findsNothing);
  });

  testWidgets('没有任何会话时不出搜索框（摆一个搜不了东西的框是噪音）', (WidgetTester tester) async {
    await pumpImList(tester, list: <Conversation>[]);

    expect(find.byKey(const Key('im-search')), findsNothing);
    expect(find.text('还没有私信'), findsOneWidget);
  });
}
