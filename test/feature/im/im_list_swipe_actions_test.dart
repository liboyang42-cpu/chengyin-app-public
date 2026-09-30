// 会话行的左右滑动操作(D9 / §3.9 IM2)。
//
// ★ 这一组盯的是「滑动只露出一层」这条纪律:划一下就执行的动作,
//   放在删除上等于把每一次误触直接变成后果。删除必须再点一次、
//   再过一次 cyConfirm。

import 'dart:io';

import 'package:chengyin_app/core/widgets/cy_swipe_actions.dart';
import 'package:chengyin_app/data/models/im.dart';
import 'package:chengyin_app/feature/im/conversation_swipe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'im_list_test_support.dart';

void main() {
  testWidgets('滑动操作钮只在展开时进入树（收起态不占语义树）', (WidgetTester tester) async {
    await pumpImList(tester, list: <Conversation>[conv(unread: 2)]);

    expect(find.text('标已读'), findsNothing);
    expect(find.text('免打扰'), findsNothing);
    expect(find.text('删除'), findsNothing);

    await tester.drag(find.text('阿林'), const Offset(200, 0));
    await tester.pumpAndSettle();

    expect(find.text('标已读'), findsOneWidget);
    expect(find.text('免打扰'), findsOneWidget);
  });

  testWidgets('无未读时不出现「标已读」；已静音显示「恢复提醒」', (WidgetTester tester) async {
    await pumpImList(
      tester,
      list: <Conversation>[conv(unread: 0, muted: true)],
    );

    await tester.drag(find.text('阿林'), const Offset(200, 0));
    await tester.pumpAndSettle();

    expect(find.text('标已读'), findsNothing);
    expect(find.text('恢复提醒'), findsOneWidget);
  });

  testWidgets('点「标已读」调 read 并让列表重取', (WidgetTester tester) async {
    final FakeImApi api = FakeImApi();
    await pumpImList(tester, list: <Conversation>[conv(unread: 2)], api: api);

    await tester.drag(find.text('阿林'), const Offset(200, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('标已读'));
    await tester.pumpAndSettle();

    expect(api.readIds, <int>[7]);
  });

  testWidgets('删除必须再过 cyConfirm：取消不删，确认才删', (WidgetTester tester) async {
    final FakeImApi api = FakeImApi();
    await pumpImList(tester, list: <Conversation>[conv()], api: api);

    await tester.drag(find.text('阿林'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('删除会话'), findsOneWidget);
    expect(find.text('删除后不会清除对方消息记录，确定删除这条会话吗？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(api.deletedIds, isEmpty, reason: '取消不能删');

    await tester.drag(find.text('阿林'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(api.deletedIds, <int>[7]);
  });

  testWidgets('同一时刻只开一行：开 B 行时 A 行自动收起', (WidgetTester tester) async {
    await pumpImList(
      tester,
      list: <Conversation>[
        conv(id: 7, nickname: '阿林', unread: 1),
        conv(id: 9, nickname: '小周', unread: 1),
      ],
    );

    await tester.drag(find.text('阿林'), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(find.text('标已读'), findsOneWidget);

    await tester.drag(find.text('小周'), const Offset(200, 0));
    await tester.pumpAndSettle();

    expect(
      find.text('标已读'),
      findsOneWidget,
      reason: '两行都开着 = 屏幕上两个「标已读」,分不清点的是谁',
    );
  });

  testWidgets('大字体 + 减弱动态下仍能滑出并点中删除', (WidgetTester tester) async {
    final FakeImApi api = FakeImApi();
    await pumpImList(
      tester,
      list: <Conversation>[conv()],
      api: api,
      textScaler: const TextScaler.linear(2),
      disableAnimations: true,
    );

    await tester.drag(find.text('阿林'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(api.deletedIds, <int>[7]);
    expect(tester.takeException(), isNull);
  });

  test('★ 滑动是 Flutter 自绘，行内不挂平台视图（§3.9 IM2）', () {
    final String src = File(
      'lib/feature/im/conversation_swipe.dart',
    ).readAsStringSync();
    // 会话行是列表里重复 N 份的东西 —— 每行挂一个 UIKit 视图会把滚动拖垮,
    // 而且这些视图是列表里最不该用平台视图的位置(它们随滚动不断创建/销毁)。
    for (final String banned in <String>[
      'UiKitView',
      'PlatformViewLink',
      'LiquidGlass',
    ]) {
      expect(src.contains(banned), isFalse, reason: banned);
    }
  });

  testWidgets('露出的操作钮走 iOS 原生滑动钮规格(CySwipeActionsRow,#393)', (
    WidgetTester tester,
  ) async {
    await pumpImList(tester, list: <Conversation>[conv(unread: 1)]);

    await tester.drag(find.text('阿林'), const Offset(200, 0));
    await tester.pumpAndSettle();

    // 钮触达区整行高(≥44pt),钮面是行高推导出的正圆/胶囊,不再是通栏色块。
    final double rowHeight = tester.getSize(find.byType(CySwipeRow)).height;
    final Finder action = find.byKey(const Key('swipe-action-read'));
    expect(action, findsOneWidget);
    expect(tester.getSize(action).height, rowHeight);
    expect(tester.getSize(action).shortestSide, greaterThanOrEqualTo(44));
    final Size surface = tester.getSize(
      find.byKey(const Key('swipe-action-surface-read')),
    );
    expect(surface.width, surface.height, reason: '高行里系统钮是正圆');
    expect(
      surface.width,
      CySwipeActionsRow.pillHeight(rowHeight),
      reason: '钮高由行高按系统常量推导',
    );
  });

  testWidgets('展开时点行 = 先收起，不误进会话（iOS 行为）', (WidgetTester tester) async {
    await pumpImList(tester, list: <Conversation>[conv(unread: 1)]);

    await tester.drag(find.text('阿林'), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(find.text('标已读'), findsOneWidget);

    // ⚠️ 点的是**屏幕位置**,不是 find.text —— 展开期间行内容被 IgnorePointer
    //   移出了命中测试,按组件点会落空(而落空恰恰说明修复生效了)。
    // 测试里没有 GoRouter:一旦误触发跳转,context.push 会直接抛。
    await tester.tapAt(tester.getCenter(find.text('阿林')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '点开着的行不该跳会话');
    expect(find.text('标已读'), findsNothing, reason: '第一下只负责收起');
  });
}
