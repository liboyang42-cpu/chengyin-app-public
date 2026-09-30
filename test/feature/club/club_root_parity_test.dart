import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_post.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_feed_page.dart';
import 'package:chengyin_app/feature/club/club_list_page.dart';
import 'package:chengyin_app/core/theme/cy_tokens.dart';

class _LoggedOutAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

Future<void> _pump(
  WidgetTester tester, {
  bool merchant = false,
  void Function(ClubDestination, int?)? onDestination,
  ClubHome home = const ClubHome(
    owned: <Club>[],
    joined: <Club>[],
    nearby: <Club>[],
    events: <ClubHomeEvent>[],
  ),
  ClubFeed feed = const ClubFeed(),
  int? joiningClubId,
  int imUnread = 0,
  Size viewport = const Size(390, 900),
  double bottomPadding = 0,
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
  bool highContrast = false,
}) async {
  await tester.binding.setSurfaceSize(viewport);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: EdgeInsets.only(bottom: bottomPadding),
            textScaler: textScaler,
            disableAnimations: disableAnimations,
            highContrast: highContrast,
          ),
          child: child!,
        ),
        home: ClubRootView(
          home: AsyncData<ClubHome>(home),
          feed: AsyncData<ClubFeed>(feed),
          isMerchantViewer: merchant,
          joiningClubId: joiningClubId,
          imUnread: imUnread,
          onDestination: onDestination ?? (_, _) {},
          onOpenMessages: () {},
          onRetryHome: () {},
          onRetryFeed: () {},
        ),
      ),
    ),
  );
  if (joiningClubId == null) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  testWidgets('消息图标在 VoiceOver 中是唯一、有名称且可点的按钮', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pump(tester);

    // 标签逐字对齐源 pages/talent/list/index.wxml:12 aria-label="站内消息"。
    final Finder action = find.bySemanticsLabel('站内消息');
    expect(action, findsOneWidget);
    final data = tester.getSemantics(action).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
    semantics.dispose();
  });

  // ★ gap-spec-roam 附C:2356/§4-16:unreadTotalProvider 此前全库零消费者。
  //   源口径 pages/talent/list/index.wxml:14 —— >0 显数字、>99 显 99+、0 不显。
  testWidgets('站内消息角标:未读 0 不显、7 显 7、150 显 99+', (WidgetTester tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('club-im-unread')), findsNothing);

    await _pump(tester, imUnread: 7);
    expect(find.byKey(const Key('club-im-unread')), findsOneWidget);
    expect(find.text('7'), findsOneWidget);

    await _pump(tester, imUnread: 150);
    expect(find.text('99+'), findsOneWidget);
    expect(find.text('150'), findsNothing);
  });

  testWidgets('有未读时 VoiceOver 念出条数', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pump(tester, imUnread: 3);
    expect(find.bySemanticsLabel('站内消息,3 条未读'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('俱乐部在 200% Dynamic Type 下保留一级切换与创建入口', (
    WidgetTester tester,
  ) async {
    await _pump(tester, textScaler: const TextScaler.linear(2));

    expect(tester.takeException(), isNull);
    expect(find.text('帖文'), findsOneWidget);
    expect(find.text('俱乐部'), findsOneWidget);
    expect(find.text('创建你自己的俱乐部'), findsOneWidget);
  });

  testWidgets('创建与俱乐部卡片主动作在默认字号下也不小于 44pt', (WidgetTester tester) async {
    await _pump(
      tester,
      home: ClubHome(
        owned: <Club>[],
        joined: <Club>[],
        nearby: <Club>[
          Club(id: 9, name: '城市散步社', isJoined: false, isOwner: false),
        ],
        events: const <ClubHomeEvent>[],
      ),
    );

    for (final String label in <String>['创建俱乐部', '加入']) {
      final Finder action = find
          .ancestor(
            of: find.text(label),
            matching: find.byType(CupertinoButton),
          )
          .first;
      await tester.ensureVisible(action);
      expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('320x568、200% 字号下俱乐部切换和创建入口仍可达', (WidgetTester tester) async {
    await _pump(
      tester,
      viewport: const Size(320, 568),
      textScaler: const TextScaler.linear(2),
      disableAnimations: true,
      highContrast: true,
    );

    expect(tester.takeException(), isNull);
    for (final String label in <String>['帖文', '俱乐部', '创建你自己的俱乐部']) {
      expect(find.text(label), findsOneWidget);
    }
    final Finder create = find.widgetWithText(CupertinoButton, '创建俱乐部');
    await tester.ensureVisible(create);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(create).height, greaterThanOrEqualTo(44));
  });

  testWidgets('Liquid Glass 底栏内边距会保留在列表尾部', (WidgetTester tester) async {
    await _pump(tester, bottomPadding: 100);

    final ListView list = tester.widget<ListView>(find.byType(ListView).first);
    expect(
      list.padding!.resolve(TextDirection.ltr).bottom,
      greaterThanOrEqualTo(100 + CyTokens.space8),
    );
  });

  testWidgets('玩家俱乐部根页保留创建入口、我的/附近与两种独立空态', (WidgetTester tester) async {
    await _pump(tester);

    expect(find.text('帖文'), findsOneWidget);
    expect(find.text('俱乐部'), findsOneWidget);
    expect(find.text('创建你自己的俱乐部'), findsOneWidget);
    expect(find.text('我创建或加入的俱乐部'), findsOneWidget);
    expect(find.text('还没有加入俱乐部'), findsOneWidget);
    expect(find.text('发现本城正在组织探索的同好'), findsOneWidget);
    expect(find.text('附近还没有其他俱乐部'), findsOneWidget);
  });

  testWidgets('帖文 tab 文案对齐小程序且空态区分未加入俱乐部', (WidgetTester tester) async {
    await _pump(tester);

    expect(find.text('帖子'), findsNothing);
    await tester.tap(find.text('帖文'));
    await tester.pumpAndSettle();

    expect(find.text('这里还没有帖文'), findsOneWidget);
    expect(find.text('帖文来自你加入的俱乐部，加入或创建一个俱乐部后即可看到'), findsOneWidget);
  });

  testWidgets('商家视角把创建入口替换为合作邀约入口', (WidgetTester tester) async {
    await _pump(tester, merchant: true);

    expect(find.text('俱乐部邀约情况 · 接受 / 拒绝合作'), findsOneWidget);
    expect(find.text('查看'), findsOneWidget);
    expect(find.text('创建你自己的俱乐部'), findsNothing);
    expect(find.text('我的'), findsNothing);
  });

  testWidgets('俱乐部卡主操作保留管理与加入目的地', (WidgetTester tester) async {
    final destinations = <(ClubDestination, int?)>[];
    await _pump(
      tester,
      onDestination: (ClubDestination destination, int? id) {
        destinations.add((destination, id));
      },
      home: ClubHome(
        owned: <Club>[Club(id: 11, name: '我的社群', isOwner: true)],
        joined: <Club>[],
        nearby: <Club>[Club(id: 22, name: '附近同好')],
        events: const <ClubHomeEvent>[],
      ),
    );

    await tester.tap(find.text('管理'));
    await tester.pump();
    await tester.ensureVisible(find.text('加入'));
    await tester.tap(find.text('加入'));
    await tester.pump();

    expect(destinations, <(ClubDestination, int?)>[
      (ClubDestination.manage, 11),
      (ClubDestination.join, 22),
    ]);
  });

  testWidgets('帖文正文进入所属俱乐部，加入提交中禁止重复点击', (WidgetTester tester) async {
    final destinations = <(ClubDestination, int?)>[];
    await _pump(
      tester,
      joiningClubId: 22,
      onDestination: (ClubDestination destination, int? id) {
        destinations.add((destination, id));
      },
      home: ClubHome(
        owned: const <Club>[],
        joined: const <Club>[],
        nearby: <Club>[Club(id: 22, name: '附近同好')],
        events: const <ClubHomeEvent>[],
      ),
      feed: const ClubFeed(
        clubCount: 1,
        rows: <ClubPost>[ClubPost(id: 3, clubId: 9, content: '俱乐部正文')],
      ),
    );

    await tester.tap(find.text('帖文'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('俱乐部正文'));
    await tester.pump();
    expect(destinations, <(ClubDestination, int?)>[(ClubDestination.club, 9)]);

    await tester.tap(find.text('俱乐部'));
    await tester.pump();
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    await tester.tap(find.byType(CupertinoActivityIndicator));
    await tester.pump();
    expect(
      destinations.where((entry) => entry.$1 == ClubDestination.join),
      isEmpty,
    );
  });

  testWidgets('游客创建俱乐部先停在登录 Sheet', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_LoggedOutAuth.new),
          clubHomeProvider.overrideWith(
            (ref) async => const ClubHome(
              owned: <Club>[],
              joined: <Club>[],
              nearby: <Club>[],
              events: <ClubHomeEvent>[],
            ),
          ),
          clubFeedProvider.overrideWith((ref) async => const ClubFeed()),
        ],
        child: const MaterialApp(home: ClubListPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建俱乐部').first);
    await tester.pumpAndSettle();
    expect(find.text('登录城瘾'), findsOneWidget);
  });
}
