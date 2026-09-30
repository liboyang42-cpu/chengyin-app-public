// 搜索必须能找到线上确实存在的活动。
//
// ★ 回归的实测(2026-09-18,截图 act-05):
//   搜「美术馆」→「没有找到相关活动」,而线上确有「一个人的美术馆下午」。
//   根因不在搜索:三档恒空(列表按不存在的 status 分档),搜索自然搜不出东西。
//   这里用稳定的 fixture 日期锁住「有数据时搜索能搜到」这条链路。
//
// ⚠️ fixture 日期必须落在**稳定档**(此处 2020 年起 / 2030 年止),
//   否则测试会随日子自己烂掉 —— 同 test/golden/no_clock_dependent_goldens_test.dart
//   的判据。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/feature/activity/activity_controller.dart';
import 'package:chengyin_app/feature/activity/activity_list_page.dart';

import '../../golden/golden_theme.dart';

final List<Activity> _rows = <Activity>[
  Activity(
    id: 9,
    name: '一个人的美术馆下午',
    addressName: '西岸美术馆',
    startDate: '2020-01-01 13:00:00',
    endDate: '2030-12-31 20:00:00',
  ),
  Activity(
    id: 13,
    name: '滨江骑行十五公里：一个人的江边',
    addressName: '徐汇滨江',
    startDate: '2030-01-01 09:00:00',
    endDate: '2030-12-31 20:00:00',
  ),
];

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        activityListProvider.overrideWith((ref) async => _rows),
      ].cast(),
      child: MaterialApp(
        theme: goldenTheme(),
        debugShowCheckedModeBanner: false,
        home: const ActivityListPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('搜「美术馆」能找到活动,不再是「没有找到相关活动」', (WidgetTester tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(CupertinoTextField), '美术馆');
    await tester.pumpAndSettle();

    expect(find.text('一个人的美术馆下午'), findsOneWidget);
    expect(find.text('没有找到相关活动'), findsNothing);
    // 计数行取小程序口径(index.js:219)。
    expect(find.text('「美术馆」1 个结果'), findsOneWidget);
    // 搜索是**当前档内**过滤:还没开始的那条不出现。
    expect(find.text('滨江骑行十五公里：一个人的江边'), findsNothing);
  });

  testWidgets('搜不存在的词仍给「没有找到相关活动」', (WidgetTester tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(CupertinoTextField), '不存在的关键词');
    await tester.pumpAndSettle();

    expect(find.text('没有找到相关活动'), findsOneWidget);
    expect(find.text('一个人的美术馆下午'), findsNothing);
  });
}
