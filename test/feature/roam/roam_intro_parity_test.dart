import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/data/models/roam_session.dart';
import 'package:chengyin_app/feature/roam/roam_live_page.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('报名卡按活动/主题真 ID 分流，并过滤不可游玩的票态', () {
    final activity = MyRegistration.fromJson(<String, dynamic>{
      'id': 7,
      'ownerType': 1,
      'ownerId': 31,
      'activityId': 42,
      'topicId': 31,
      'registrationStatus': 2,
      'cmsTopic': <String, dynamic>{'name': '夜行上海', 'productType': 1},
    });
    final topicOnly = MyRegistration.fromJson(<String, dynamic>{
      'id': 8,
      'ownerType': 1,
      'ownerId': 32,
      'topicId': 32,
      'registrationStatus': 2,
      'cmsTopic': <String, dynamic>{'name': '城市散步', 'productType': 2},
    });
    final cancelled = MyRegistration.fromJson(<String, dynamic>{
      'id': 9,
      'ownerType': 1,
      'ownerId': 33,
      'registrationStatus': 3,
    });

    expect(
      roamIntroTopicFromRegistration(activity)?.route,
      '/play/42?registrationId=7',
    );
    expect(
      roamIntroTopicFromRegistration(topicOnly)?.route,
      '/play/0?topicId=32&registrationId=8',
    );
    expect(roamIntroTopicFromRegistration(cancelled), isNull);
  });

  testWidgets('漫游默认根保留开始/护照、横滑卡、地图、GO 与待机状态', (WidgetTester tester) async {
    var starts = 0;
    var ruleOpens = 0;
    var profileOpens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoamIntroView(
            sessions: const <RoamSession>[],
            topics: const <RoamIntroTopic>[],
            onStart: () => starts += 1,
            onStartAndShoot: () {},
            onOpenRules: () => ruleOpens += 1,
            onOpenHistory: () {},
            onOpenStampAlbum: () {},
            onOpenBadges: () {},
            onOpenTopic: (_) {},
            onOpenOfficialEvents: () {},
            onDiscoverShops: () {},
            onOpenProfile: () => profileOpens += 1,
          ),
        ),
      ),
    );

    expect(find.text('漫游'), findsOneWidget);
    expect(find.text('开始漫游'), findsOneWidget);
    expect(find.text('漫游护照'), findsOneWidget);
    expect(find.byKey(const Key('roam-intro-cards')), findsOneWidget);
    expect(find.byKey(const Key('roam-intro-map')), findsOneWidget);
    expect(find.byKey(const Key('roam-go')), findsOneWidget);
    // 真源 pages/roam/index.wxml 的 GO 区没有状态行,App 不许自己加。
    expect(find.text('尚未开始 · 等待定位'), findsNothing);
    await tester.tap(find.byKey(const Key('roam-profile')));
    expect(profileOpens, 1);

    await tester.tap(find.byKey(const Key('roam-go')));
    await tester.tap(find.byKey(const Key('roam-intro-card-free')));
    expect(starts, 1);
    expect(ruleOpens, 1);
  });

  testWidgets('介绍卡亮岛 chrome 1:1 真源:星白卡底+压深底投影+浅灰图标槽', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoamIntroView(
            sessions: const <RoamSession>[],
            topics: const <RoamIntroTopic>[],
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

    final containers = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byKey(const Key('roam-intro-card-free')),
            matching: find.byType(Container),
          ),
        )
        .toList();
    final cardDeco = (containers.first.decoration! as BoxDecoration);
    // 真源 pages/roam/index.wxss:747-748:卡底=主 CTA 星白 + 压深底投影（ds-ok 亮岛,非误用）。
    expect(cardDeco.color, const Color(0xFFF8F8F8));
    expect(cardDeco.boxShadow!.single.color, const Color(0x66000000));
    expect(cardDeco.boxShadow!.single.offset, const Offset(0, 1));
    expect(cardDeco.boxShadow!.single.blurRadius, 8);
    // 真源 :751 白卡内的浅灰图标槽 #F2F2F2(textPrimary@8% 压在星白上不可见)。
    // main 落地口径:不硬写 #F2F2F2,用主 CTA 反色 fg@8% 压暗还原同一浅灰槽
    // (8% × 近黑 压在 #F8F8F8 卡底 = #F2F2F2 等效),取色一律走 token。
    final slotDeco = (containers[1].decoration! as BoxDecoration);
    expect(
      slotDeco.color,
      CyTokens.actionPrimaryFg.withValues(alpha: 0.08),
      reason: '浅灰图标槽按 token 反色压暗实现,不回退成硬编码色值',
    );
  });

  testWidgets('漫游护照按小程序顺序展示真实汇总与三个入口', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoamIntroView(
            sessions: const <RoamSession>[
              RoamSession(
                ts: 1,
                distance: 1.2,
                shops: 2,
                photos: <String>['stamp.jpg'],
              ),
            ],
            topics: const <RoamIntroTopic>[],
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

    await tester.tap(find.text('漫游护照'));
    await tester.pumpAndSettle();

    expect(find.text('1.2'), findsOneWidget);
    expect(find.byKey(const Key('roam-passport-history')), findsOneWidget);
    expect(find.byKey(const Key('roam-passport-stamps')), findsOneWidget);
    expect(find.byKey(const Key('roam-passport-badges')), findsOneWidget);
    expect(find.text('活跃日'), findsOneWidget);
    expect(
      find.byKey(const Key('roam-passport-official-events')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('roam-passport-discover-shops')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('roam-go')),
      findsNothing,
      reason: '护照是回看信息，不应出现出发按钮',
    );
  });

  testWidgets('已报名主题优先于自由漫游 fallback，并保留游玩目标', (WidgetTester tester) async {
    String? openedRoute;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoamIntroView(
            sessions: const <RoamSession>[],
            topics: const <RoamIntroTopic>[
              RoamIntroTopic(
                title: '街角寻迹',
                subtitle: '按顺序走完整条路线',
                route: '/play/7',
                freeExplore: false,
              ),
            ],
            onStart: () {},
            onStartAndShoot: () {},
            onOpenRules: () {},
            onOpenHistory: () {},
            onOpenStampAlbum: () {},
            onOpenBadges: () {},
            onOpenTopic: (String route) => openedRoute = route,
            onOpenOfficialEvents: () {},
            onDiscoverShops: () {},
            onOpenProfile: () {},
          ),
        ),
      ),
    );

    expect(find.text('街角寻迹'), findsOneWidget);
    expect(find.byKey(const Key('roam-intro-card-free')), findsNothing);
    await tester.tap(find.byKey(const Key('roam-intro-topic-0')));
    expect(openedRoute, '/play/7');
  });

  // ★ gap-spec-roam 附C:4633:源 HANGOUT_INTRO_CARD 恒 concat 在卡列尾
  //   (pages/roam/index.js:289-292,751),「附近的队伍」此前在 App 无入口。
  testWidgets('「附近的队伍」尾卡:回落态与已报名态都恒在并可点', (WidgetTester tester) async {
    var teamOpens = 0;
    Future<void> pump(List<RoamIntroTopic> topics) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoamIntroView(
            key: UniqueKey(),
            sessions: const <RoamSession>[],
            topics: topics,
            onStart: () {},
            onStartAndShoot: () {},
            onOpenRules: () {},
            onOpenHistory: () {},
            onOpenStampAlbum: () {},
            onOpenBadges: () {},
            // main 侧的尾卡走 onOpenTopic('/team/nearby'),不带独立回调。
            onOpenTopic: (String route) {
              if (route == '/team/nearby') teamOpens += 1;
            },
            onOpenOfficialEvents: () {},
            onDiscoverShops: () {},
            onOpenProfile: () {},
          ),
        ),
      ),
    );

    // 横滑 ListView 只建视口+cacheExtent 内的卡,尾卡要先拖到位。
    final Finder teamCard = find.byKey(
      const Key('roam-intro-card-nearby-teams'),
    );
    final Finder cardRail = find.byKey(const Key('roam-intro-cards'));
    Future<void> revealTeamsCard() async {
      await tester.dragUntilVisible(teamCard, cardRail, const Offset(-200, 0));
      await tester.pumpAndSettle();
    }

    await pump(const <RoamIntroTopic>[]);
    await revealTeamsCard();
    expect(find.text('附近的队伍'), findsOneWidget);
    await tester.tap(teamCard);
    expect(teamOpens, 1);

    await pump(const <RoamIntroTopic>[
      RoamIntroTopic(
        title: '街角寻迹',
        subtitle: '按顺序走完整条路线',
        route: '/play/7',
        freeExplore: false,
      ),
    ]);
    expect(find.text('街角寻迹'), findsOneWidget);
    await revealTeamsCard();
    expect(teamCard, findsOneWidget, reason: '有报名时尾卡排在章节卡之后,不能消失');
  });
}
