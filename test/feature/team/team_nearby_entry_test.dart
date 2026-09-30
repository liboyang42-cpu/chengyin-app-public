// 「附近的队伍」入口门禁:漫游首屏那张横滑卡真的指到 `/team/nearby`。
//
// 真源 = 小程序 `pages/roam/index.js` 的 HANGOUT_INTRO_CARD(9-15 地图组队 P 方案):
// 它是横滑卡组的固定一员,**永远**排在已报名章节卡之后(小程序的默认卡组与
// 加载完报名卡后的 `cards.concat([HANGOUT_INTRO_CARD])` 都带着它),
// 标题 / 副标题逐字一致;不发轻查、不编数字。
// 判据只认「点了以后去哪」,不认卡片画得好不好看 —— 入口接不通时,
// 后面的队伍页(申请 / 撤回 / 审批 / 我的队伍)整条都是死代码。

import 'dart:io';

import 'package:chengyin_app/data/models/roam_session.dart';
import 'package:chengyin_app/feature/roam/roam_live_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _kNearbyTeamsRoute = '/team/nearby';
const Key _kCardKey = Key('roam-intro-card-nearby-teams');

Future<void> _pumpIntro(
  WidgetTester tester, {
  required List<RoamIntroTopic> topics,
  required ValueChanged<String> onOpenTopic,
}) async {
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
          onOpenTopic: onOpenTopic,
          onOpenOfficialEvents: () {},
          onDiscoverShops: () {},
          onOpenProfile: () {},
        ),
      ),
    ),
  );

}

/// 横滑条是懒构建的:卡排在尾部时首屏既看不见也还没建出来 ——
/// 先横向拖到它跟前,再断言文案、再点。不用 warnIfMissed 蒙混(那样点的是别人)。
Future<void> _tapCard(WidgetTester tester) async {
  await tester.dragUntilVisible(
    find.byKey(_kCardKey),
    find.byKey(const Key('roam-intro-cards')),
    const Offset(-300, 0),
  );
  await tester.pumpAndSettle();

  // 文案逐字对齐小程序 HANGOUT_INTRO_CARD。
  expect(find.text('附近的队伍'), findsOneWidget);
  expect(find.text('看看附近在招募的队伍'), findsOneWidget);

  await tester.tap(find.byKey(_kCardKey));
}

void main() {
  testWidgets('没报名任何章节时,横滑卡里也有「附近的队伍」并指向 /team/nearby', (
    WidgetTester tester,
  ) async {
    String? opened;
    await _pumpIntro(
      tester,
      topics: const <RoamIntroTopic>[],
      onOpenTopic: (String route) => opened = route,
    );
    await _tapCard(tester);
    expect(opened, _kNearbyTeamsRoute);
  });

  testWidgets('有已报名章节卡时,「附近的队伍」仍排在章节卡之后且指向同一路由', (
    WidgetTester tester,
  ) async {
    String? opened;
    await _pumpIntro(
      tester,
      topics: const <RoamIntroTopic>[
        RoamIntroTopic(
          title: '街角寻迹',
          subtitle: '按顺序走完整条路线',
          route: '/play/7',
          freeExplore: false,
        ),
      ],
      onOpenTopic: (String route) => opened = route,
    );
    expect(
      tester.getTopLeft(find.byKey(_kCardKey)).dx,
      greaterThan(
        tester.getTopLeft(find.byKey(const Key('roam-intro-topic-0'))).dx,
      ),
      reason: '小程序把这张卡 concat 在章节卡之后,顺序反了就不是 1:1',
    );
    await _tapCard(tester);
    expect(opened, _kNearbyTeamsRoute);
  });

  test('路由表:/team/nearby 构建 TeamNearbyPage,且排在 /team/:teamId 之前', () {
    final String router = File(
      'lib/core/router/app_router.dart',
    ).readAsStringSync();
    final int nearby = router.indexOf("path: '$_kNearbyTeamsRoute',");
    final int dynamicSegment = router.indexOf("path: '/team/:teamId',");
    expect(nearby, greaterThan(-1), reason: '入口指向的路由没登记');
    expect(dynamicSegment, greaterThan(-1));
    expect(
      nearby,
      lessThan(dynamicSegment),
      reason: '反过来的话 /team/nearby 会被动态段吃掉(teamId=nearby)',
    );
    expect(
      router.substring(nearby, dynamicSegment).contains('TeamNearbyPage('),
      isTrue,
      reason: '这条路由必须构建「附近的队伍」页',
    );
  });
}
