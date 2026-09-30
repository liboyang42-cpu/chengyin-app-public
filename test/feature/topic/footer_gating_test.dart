// 主题详情底部动作条的三分支门禁。
//
// ★ 对齐小程序 `pages/topic/index/index.wxml:330-339`,判据取自后端 `TopicInfoVO`:
//   - `lifecycle` **空 = 普通主题,照常售票**;1 招募中 / 2 定价中 = 未到售票态,不可购买
//   - `selfPlay == 1` 才开放自玩通行证
//
// ★ 这里特意守住一条容易写错的:开放与否看 **selfPlay 开关**,不看 selfPlayPrice 有没有值。
//   把判据写成「有价格就当开放」会让**招募中但已定价**的主题提前露出购买入口 —— 那是资金面的错。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:chengyin_app/feature/topic/topic_detail_controller.dart';
import 'package:chengyin_app/feature/topic/topic_detail_page.dart';

TopicDetail _topic({int? lifecycle, int? selfPlay, double? price}) =>
    TopicDetail.fromJson(<String, dynamic>{
      'id': 1,
      'name': '静安微旅行',
      'description': '测试用',
      if (lifecycle != null) 'lifecycle': lifecycle,
      if (selfPlay != null) 'selfPlay': selfPlay,
      if (price != null) 'selfPlayPrice': price,
      'chaptersList': <dynamic>[],
    });

Future<void> _pump(WidgetTester tester, TopicDetail d) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        topicDetailProvider(1).overrideWith((ref) async => d),
      ].cast(),
      child: const MaterialApp(home: TopicDetailPage(topicId: 1)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('招募中(lifecycle=1)→ 未开售,且不可点', (WidgetTester tester) async {
    await _pump(tester, _topic(lifecycle: 1));
    expect(find.text('招募中 · 未开售'), findsOneWidget);
    final CyNativeButton b = tester.widget(find.byType(CyNativeButton));
    expect(b.onPressed, isNull, reason: '未到售票态不该给购买入口');
    expect(find.text('去参加'), findsNothing);
  });

  testWidgets('定价中(lifecycle=2)→ 未开售', (WidgetTester tester) async {
    await _pump(tester, _topic(lifecycle: 2));
    expect(find.text('定价中 · 未开售'), findsOneWidget);
  });

  testWidgets('普通主题(lifecycle 空)→ 去参加', (WidgetTester tester) async {
    await _pump(tester, _topic());
    expect(find.text('去参加'), findsOneWidget);
  });

  testWidgets('开放自玩(selfPlay=1)→ 查看场次 + ¥X 随时开玩', (WidgetTester tester) async {
    await _pump(tester, _topic(selfPlay: 1, price: 149));
    expect(find.text('查看场次'), findsOneWidget);
    expect(find.text('¥149.00 随时开玩'), findsOneWidget);
  });

  testWidgets('★ 有价格但 selfPlay 未开 → 仍然只是「去参加」', (WidgetTester tester) async {
    // 判据是开关不是价格。写成「有价格就当开放」会让未开放自玩的主题露出购买入口。
    await _pump(tester, _topic(price: 149));
    expect(find.text('去参加'), findsOneWidget);
    expect(find.textContaining('随时开玩'), findsNothing);
  });

  testWidgets('★ 招募中即使已定价,也不许露出购买入口', (WidgetTester tester) async {
    await _pump(tester, _topic(lifecycle: 1, selfPlay: 1, price: 149));
    expect(find.text('招募中 · 未开售'), findsOneWidget);
    expect(find.textContaining('随时开玩'), findsNothing);
  });
}
