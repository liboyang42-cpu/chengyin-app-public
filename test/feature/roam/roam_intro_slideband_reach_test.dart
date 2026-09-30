// 出发页横滑带「第三卡指头可达性」回归(b1-sim-roam-4 N8 判定钉)。
//
// 报告口径:模拟器合成 swipe 6 次左滑停在 offset≈310pt,第三卡
// (附近的队伍 / #154 入口)只露右缘一条,疑似滑不进可视区。
// 本测用 drag 通道(与真指头同一 pan 识别器)在 390/430 两档实拖到
// 极限,断言第三卡右缘落进横滑带可视区 —— 证明布局可达性没有缺陷;
// 模拟器上的停点属合成手势通道限制(见 REPORT-fix-b1-roam-slideband-3rd)。
//
// ⚠️ 测试绑定里 setSurfaceSize 不改变树内 MediaQuery.sizeOf,
// 必须用 view.physicalSize + devicePixelRatio=1(_IntroCard 按屏宽算卡宽)。

import 'package:chengyin_app/data/models/roam_session.dart';
import 'package:chengyin_app/feature/roam/roam_live_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpIntro(
  WidgetTester tester, {
  required double width,
  List<RoamIntroTopic> topics = const <RoamIntroTopic>[],
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RoamIntroView(
          sessions: const <RoamSession>[],
          topics: topics,
          onStart: () {},
          onStartAndShoot: () {},
          onOpenRules: () {},
          onOpenHistory: () {},
          onOpenStampAlbum: () {},
          onOpenBadges: () {},
          onOpenTopic: (_) {},
          onOpenOfficialEvents: () {},
          onDiscoverShops: () {},
          onOpenProfile: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const List<List<RoamIntroTopic>> kCardSets = <List<RoamIntroTopic>>[
    // 未报名:默认双卡 + 入口卡(报告 roam4-08 的三卡态)
    <RoamIntroTopic>[],
    // 已报名:章节卡在前、入口卡垫底 —— 入口卡排到更尾部,可达性更难
    <RoamIntroTopic>[
      RoamIntroTopic(
        title: '街角寻迹',
        subtitle: '按顺序走完整条路线',
        route: '/play/7',
        freeExplore: false,
      ),
    ],
  ];

  for (final double width in <double>[390, 430]) {
    for (int set = 0; set < kCardSets.length; set++) {
      final List<RoamIntroTopic> topics = kCardSets[set];
      final String scene = topics.isEmpty ? '默认双卡' : '单章节卡';
      testWidgets('${width.toInt()}pt 宽·$scene:横滑带拖到极限后「附近的队伍」整卡右缘进入可视区', (
        WidgetTester tester,
      ) async {
        await _pumpIntro(tester, width: width, topics: topics);
        final Finder band = find.byKey(const Key('roam-intro-cards'));
        final Finder third = find.byKey(
          const Key('roam-intro-card-nearby-teams'),
        );
        final ScrollableState scrollable = tester.state<ScrollableState>(
          find.descendant(of: band, matching: find.byType(Scrollable)).first,
        );
        // 真指头慢拖:分段移动并 pump,覆盖懒构建估算被修正的过程,
        // 直到落在真实 maxScrollExtent(静止态读数会从估算值回落到内容真值)。
        final TestGesture finger = await tester.startGesture(
          tester.getCenter(band),
        );
        for (int i = 0; i < 60; i++) {
          await finger.moveBy(const Offset(-15, 0));
          await tester.pump();
        }
        await finger.removePointer();
        await tester.pumpAndSettle();

        final double max = scrollable.position.maxScrollExtent;
        expect(
          scrollable.position.pixels,
          moreOrLessEquals(max, epsilon: 1),
          reason: '按住慢拖 900pt 仍未到 maxScrollExtent($max),说明滚动被别处吃掉',
        );
        expect(third, findsOneWidget);
        final Rect bandRect = tester.getRect(band);
        final Rect thirdRect = tester.getRect(third);
        expect(
          thirdRect.right,
          lessThanOrEqualTo(bandRect.right + 1),
          reason:
              '第三卡右缘 ${thirdRect.right} 应在横滑带可视区右缘 '
              '${bandRect.right} 之内 —— N8 回归:滑到极限仍露边条就是布局缺陷',
        );
        expect(thirdRect.left, greaterThanOrEqualTo(bandRect.left));
      });
    }
  }
}
