import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/api/official_api.dart';
import 'package:chengyin_app/feature/official/official_controller.dart';
import 'package:chengyin_app/feature/official/official_mine_page.dart';

/// 「无官方发布权限」是**权限态,不是故障**。
///
/// ★ 为什么要专门锁:把它渲染成「加载失败 + 重试」,没权限的用户会一直点重试,
///   而重试多少次都不会好 —— 界面在骗人。这类「文案说得通、行为不可能成立」的
///   缺陷是本项目最高频的一种,肉眼审查抓不到,只有把两种错误分开断言才抓得到。
Widget wrap(Object error) {
  return ProviderScope(
    overrides: [
      myPublishedProvider.overrideWith((ref) => Future<MyPublished>.error(error)),
    ],
    child: const MaterialApp(home: OfficialMinePage()),
  );
}

void main() {
  testWidgets('无发布权限 → 说明是权限问题,且不给重试按钮', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(OfficialApiException('无官方发布权限')));
    await tester.pumpAndSettle();

    expect(find.text('你没有官方发布权限'), findsOneWidget);
    expect(find.text('发布记录没能加载出来'), findsNothing);
    expect(find.text('重试'), findsNothing,
        reason: '重试解决不了没权限,给了就是骗用户');
  });

  testWidgets('真的网络故障 → 才是错误态,并且给重试', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(OfficialApiException('网络连接超时')));
    await tester.pumpAndSettle();

    expect(find.text('发布记录没能加载出来'), findsOneWidget);
    expect(find.text('网络连接超时'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('你没有官方发布权限'), findsNothing);
  });

  testWidgets('空数据 → 空态,不是错误态', (WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        myPublishedProvider.overrideWith((ref) async => const MyPublished()),
      ],
      child: const MaterialApp(home: OfficialMinePage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('还没有发布过内容'), findsOneWidget);
    expect(find.text('加载失败'), findsNothing);
  });
}
