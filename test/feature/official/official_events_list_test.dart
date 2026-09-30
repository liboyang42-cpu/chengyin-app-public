// 官方活动列表的分档与过滤。
//
// ⚠️ 小程序那页路由名叫 `pages/activity/list`,但它**不是**活动目录 ——
//   utils/scene-registry.js:27 写着 `title: '官方活动'`。
//   App 的 /activities 是另一回事(走 /api/activity/list)。
//   两边同名不同物,照名字对会对错。

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/data/models/activity_status.dart';
import 'package:chengyin_app/data/models/official_event.dart';
import 'package:chengyin_app/feature/official/official_events_page.dart';
import 'package:chengyin_app/feature/official/official_publish_page.dart';

OfficialEvent _e({
  int id = 1,
  String title = '外滩夜行',
  String? subtitle,
  String? city,
  int status = 3,
}) => OfficialEvent.fromJson(<String, dynamic>{
  'id': id,
  'title': title,
  'subtitle': ?subtitle,
  'city': ?city,
  'status': status,
});

void main() {
  testWidgets('摘要行按小程序顺序打开我发布的与邀约', (WidgetTester tester) async {
    int mineOpens = 0;
    int inboxOpens = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          officialEventsProvider.overrideWith(
            (_) async => <OfficialEvent>[_e()],
          ),
          officialCanPublishProvider.overrideWith((_) async => true),
        ],
        child: MaterialApp(
          home: OfficialEventsPage(
            onOpenMine: () => mineOpens += 1,
            onOpenInbox: () => inboxOpens += 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const List<String> filters = <String>['进行中', '即将', '已结束', '我的'];
    for (var i = 1; i < filters.length; i++) {
      expect(
        tester.getTopLeft(find.text(filters[i - 1]).first).dx,
        lessThan(tester.getTopLeft(find.text(filters[i]).first).dx),
      );
    }

    final Finder mine = find.text('我发布的 ›');
    // 文案跟小程序 oe-inbox-link 逐字一致:就是「邀约 ›」。
    final Finder inbox = find.text('邀约 ›');
    expect(mine, findsOneWidget);
    expect(inbox, findsOneWidget);
    expect(tester.getTopLeft(mine).dx, lessThan(tester.getTopLeft(inbox).dx));
    expect(find.text('进行中 · 共 1 个活动'), findsOneWidget);
    expect(
      tester.getTopLeft(inbox).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('official-event-1'))).dy),
    );

    await tester.tap(mine);
    await tester.tap(inbox);
    expect(mineOpens, 1);
    expect(inboxOpens, 1);
  });

  testWidgets('默认入口分别落在已有我发布的与承接邀约一级页', (WidgetTester tester) async {
    final GoRouter router = GoRouter(
      initialLocation: '/official-events',
      routes: <RouteBase>[
        GoRoute(
          path: '/official-events',
          builder: (_, _) => const OfficialEventsPage(),
        ),
        GoRoute(
          path: '/official-mine',
          builder: (_, _) => const Text('ROUTE official-mine'),
        ),
        GoRoute(
          path: '/official-inbox',
          builder: (_, _) => const Text('ROUTE official-inbox'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          officialEventsProvider.overrideWith(
            (_) async => <OfficialEvent>[_e()],
          ),
          officialCanPublishProvider.overrideWith((_) async => true),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('我发布的 ›'));
    await tester.pumpAndSettle();
    expect(find.text('ROUTE official-mine'), findsOneWidget);

    router.go('/official-events');
    await tester.pumpAndSettle();
    await tester.tap(find.text('邀约 ›'));
    await tester.pumpAndSettle();
    expect(find.text('ROUTE official-inbox'), findsOneWidget);
  });

  group('★ 分档判据与小程序 applyFilter 同一把尺子', () {
    test('进行中 = 报名中(2) / 进行中(3)', () {
      expect(activityInBucket(2, ActivityBucket.live), isTrue);
      expect(activityInBucket(3, ActivityBucket.live), isTrue);
      expect(activityInBucket(1, ActivityBucket.live), isFalse);
    });
    test('即将 = status==1', () {
      expect(activityInBucket(1, ActivityBucket.upcoming), isTrue);
      expect(activityInBucket(2, ActivityBucket.upcoming), isFalse);
    });
    test('已结束 = status>=5', () {
      for (final int s in <int>[5, 6, 9]) {
        expect(activityInBucket(s, ActivityBucket.ended), isTrue, reason: '$s');
      }
      expect(
        activityInBucket(4, ActivityBucket.ended),
        isFalse,
        reason: '结算中(4)不算结束 —— 钱还没走完',
      );
    });
  });

  group('★★ 缺 id 或缺标题的行整条丢掉', () {
    test('留着会在列表里出现一张点不开的空卡,而用户看不出它为什么点不开', () {
      final List<OfficialEvent> rows = completeOnly(<OfficialEvent>[
        _e(),
        _e(id: 0, title: '没有 id'),
        _e(id: 2, title: '   '),
      ]);
      expect(rows.length, 1);
      expect(rows.single.id, 1);
    });
  });

  testWidgets('搜索在「我的」档隐藏,空态文案逐档对齐真源', (WidgetTester tester) async {
    // 真源 `pages/activity/list/index.wxml`:`<cy-search wx:if="{{tab !== 3}}" />`;
    // 空态逐档取自 `EMPTY_COPY`(index.js:35)—— 四档混成一句会让用户
    // 以为整个官方活动都没了。
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          officialEventsProvider.overrideWith((_) async => <OfficialEvent>[]),
          // 「我的」档是**另一条请求**(myEvents),不给替身会一直转圈。
          myOfficialEventsProvider.overrideWith((_) async => <OfficialEvent>[]),
          officialCanPublishProvider.overrideWith((_) async => false),
        ],
        child: const MaterialApp(home: OfficialEventsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('official-events-search')), findsOneWidget);
    expect(find.text('暂无进行中的活动'), findsOneWidget);
    expect(find.text('官方策展活动会第一时间出现在这里'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('official-events-search')),
      findsNothing,
      reason: '我的档真源不显示搜索框',
    );
    expect(find.text('还没有参与的活动'), findsOneWidget);
    expect(find.text('报名活动后会出现在这里'), findsOneWidget);
  });

  group('关键词是**前端过滤**,三个字段', () {
    final List<OfficialEvent> all = <OfficialEvent>[
      _e(id: 1, title: '外滩夜行', city: '上海'),
      _e(id: 2, title: '胡同寻宝', subtitle: '老北京线', city: '北京'),
    ];
    test('命标题', () => expect(filterOfficialEvents(all, '外滩').single.id, 1));
    test('命副标', () => expect(filterOfficialEvents(all, '老北京').single.id, 2));
    test('命城市', () => expect(filterOfficialEvents(all, '北京').single.id, 2));
    test('空关键词不过滤', () => expect(filterOfficialEvents(all, '  ').length, 2));
    test('大小写不敏感', () {
      final List<OfficialEvent> x = <OfficialEvent>[
        _e(id: 3, title: 'CityWalk'),
      ];
      expect(filterOfficialEvents(x, 'citywalk').length, 1);
    });
  });
}
