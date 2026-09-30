import 'package:chengyin_app/core/widgets/status_view.dart';
import 'package:chengyin_app/data/models/publish_draft.dart';
import 'package:chengyin_app/feature/template/template_intro_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('模板引导页保留卡堆、两行主张与同一编辑器出口', (WidgetTester tester) async {
    String? target;
    await tester.pumpWidget(
      MaterialApp(
        home: TemplateIntroView(
          cards: <PublishTemplate>[
            PublishTemplate(
              id: 1,
              title: '街角密码',
              imgUrl: '',
              players: '2-6',
              duration: 45,
              raw: <String, dynamic>{},
            ),
            PublishTemplate(
              id: 2,
              title: '城市暗号',
              imgUrl: '',
              players: '3-8',
              duration: 55,
              raw: <String, dynamic>{},
            ),
          ],
          onExitIntro: (String route) => target = route,
        ),
      ),
    );

    expect(find.byKey(const Key('template-intro-card-stack')), findsOneWidget);
    expect(find.text('把你玩过的一段路'), findsOneWidget);
    expect(find.text('做成别人也能走的玩法'), findsOneWidget);

    await tester.tap(find.text('开始创建'));
    expect(target, '/template/new');
  });

  testWidgets('跳过和开始创建使用同一 redirect 出口', (WidgetTester tester) async {
    String? target;
    await tester.pumpWidget(
      MaterialApp(
        home: TemplateIntroView(
          cards: <PublishTemplate>[],
          onExitIntro: (String route) => target = route,
        ),
      ),
    );

    expect(
      find.byKey(const Key('template-intro-card-stack')),
      findsNothing,
      reason: '拉不到真实卡片就不塞假数据',
    );
    await tester.tap(find.text('跳过'));
    expect(target, '/template/new');
  });

  testWidgets('卡堆舞台按真源摆 载/错/空 三态,错态给得出重试', (WidgetTester tester) async {
    // 载:真源 <cy-skeleton type="card" count="3" />。
    await tester.pumpWidget(
      MaterialApp(
        home: TemplateIntroView(
          cards: const <PublishTemplate>[],
          cardsLoading: true,
          onExitIntro: (_) {},
        ),
      ),
    );
    expect(find.byType(CySkeleton), findsOneWidget);
    expect(find.byKey(const Key('template-intro-cards-empty')), findsNothing);
    expect(find.text('开始创建'), findsOneWidget, reason: '拉卡片不该拦住创建');

    // 错:标题点名失败的是什么,并给得出重试。
    int retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TemplateIntroView(
          cards: const <PublishTemplate>[],
          cardsError: '精选示例加载失败，请重试',
          onRetryCards: () => retries++,
          onExitIntro: (_) {},
        ),
      ),
    );
    expect(find.text('精选示例暂未加载'), findsOneWidget);
    expect(find.text('精选示例加载失败，请重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(retries, 1);

    // 空:真源原文,同样不拦创建。
    await tester.pumpWidget(
      MaterialApp(
        home: TemplateIntroView(
          cards: const <PublishTemplate>[],
          onExitIntro: (_) {},
        ),
      ),
    );
    expect(find.byKey(const Key('template-intro-cards-empty')), findsOneWidget);
    expect(find.text('暂时没有精选示例，你仍可直接创建自己的节点玩法。'), findsOneWidget);
    expect(find.text('开始创建'), findsOneWidget);
  });
}
