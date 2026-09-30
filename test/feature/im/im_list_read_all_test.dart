// 导航栏「全部已读」(小程序 im/list 右上角 ✓ 的等价物)。
//
// ★ 盯的是**回执诚实**:后端只有单会话 read,没有批量端点 ——
//   一条都没成功也弹「已全部标为已读」,是在向用户谎报一件没发生的事。
//   小程序那一页在同一处踩过(code!=200 也走 success())。

import 'package:chengyin_app/data/models/im.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'im_list_test_support.dart';

void main() {
  testWidgets('没有未读时按钮不可点，点了也不发请求', (WidgetTester tester) async {
    final FakeImApi api = FakeImApi();
    await pumpImList(tester, list: <Conversation>[conv(unread: 0)], api: api);

    await tester.tap(find.byKey(const Key('im-read-all')));
    await tester.pumpAndSettle();

    expect(api.readIds, isEmpty);
  });

  testWidgets('有未读时点一下把所有未读会话逐个标已读', (WidgetTester tester) async {
    final FakeImApi api = FakeImApi();
    await pumpImList(
      tester,
      list: <Conversation>[
        conv(id: 7, nickname: '阿林', unread: 2),
        conv(id: 9, nickname: '小周', unread: 1),
        conv(id: 11, nickname: '老陈', unread: 0),
      ],
      api: api,
    );

    await tester.tap(find.byKey(const Key('im-read-all')));
    await tester.pumpAndSettle();

    expect(api.readIds, <int>[7, 9], reason: '已读的不必再发一次');
    expect(find.text('已全部标为已读'), findsOneWidget);
  });

  testWidgets('部分失败时如实说还剩几条，不冒充全部成功', (WidgetTester tester) async {
    final FakeImApi api = FakeImApi()..failRead.add(9);
    await pumpImList(
      tester,
      list: <Conversation>[
        conv(id: 7, nickname: '阿林', unread: 1),
        conv(id: 9, nickname: '小周', unread: 1),
      ],
      api: api,
    );

    await tester.tap(find.byKey(const Key('im-read-all')));
    await tester.pumpAndSettle();

    expect(find.text('还有 1 条没标记成功，请重试'), findsOneWidget);
    expect(find.text('已全部标为已读'), findsNothing);
  });

  testWidgets('全部失败时直说失败', (WidgetTester tester) async {
    final FakeImApi api = FakeImApi()..failRead.addAll(<int>{7, 9});
    await pumpImList(
      tester,
      list: <Conversation>[
        conv(id: 7, nickname: '阿林', unread: 1),
        conv(id: 9, nickname: '小周', unread: 1),
      ],
      api: api,
    );

    await tester.tap(find.byKey(const Key('im-read-all')));
    await tester.pumpAndSettle();

    expect(find.text('标记已读失败，请重试'), findsOneWidget);
    expect(find.text('已全部标为已读'), findsNothing);
  });
}
