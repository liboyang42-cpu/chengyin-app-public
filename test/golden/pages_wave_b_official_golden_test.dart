// Wave-B 官方活动:列表三档(B27 进行中 / B29 即将 / B28 我的空态)、
// B30 详情已结束态、B31 商家承接邀约收件箱。
//
// fixture 逐条对小程序 shot-matrix 的 data:
//   · B27 走 status=3(进行中档)、B29 走 status=1(即将档)—— 两档的**筛选判据**
//     不同(activityInBucket),只拍一档等于没验另一档的分支。
//   · B28 的 mine 空态:小程序注释写着「我的 tab 隐藏搜索」,这里的图就是那句的对照。
//   · B30 是**已结束**态:CTA 文案与可点性由 officialEventCta 推,不再本地编。
//   · B31 是商家视角,真机就是浅色(merchantGoldenTheme),拍暗底是假证据。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_wave_b_official_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/api/official_api.dart';
import 'package:chengyin_app/data/models/official_event.dart';
import 'package:chengyin_app/feature/official/official_events_page.dart';
import 'package:chengyin_app/feature/official/official_event_detail_page.dart';
import 'package:chengyin_app/feature/official/official_inbox_page.dart';
import 'package:chengyin_app/feature/official/official_publish_page.dart'
    show officialCanPublishProvider;
import 'package:chengyin_app/feature/official/official_controller.dart'
    show officialEventProvider, partyInboxProvider;

import 'golden_theme.dart';

Widget _app(List<dynamic> overrides, Widget home, {ThemeData? theme}) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: theme ?? goldenTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

Future<void> _shot(WidgetTester tester, String goldenPath) async {
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

const OfficialEvent _live = OfficialEvent(
  id: 7,
  title: '外滩夜行档案',
  city: '上海',
  status: 3,
  participants: 62,
);

const OfficialEvent _upcoming = OfficialEvent(
  id: 2901,
  title: '苏州河夜行计划',
  subtitle: '沿河点亮三处城市记忆',
  city: '上海',
  status: 1,
  participants: 42,
);

void main() {
  testWidgets('B27 官方活动:进行中档', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        officialCanPublishProvider.overrideWith((Ref ref) async => false),
        officialEventsProvider.overrideWith(
          (Ref ref) async => <OfficialEvent>[_live],
        ),
        myOfficialEventsProvider.overrideWith(
          (Ref ref) async => <OfficialEvent>[],
        ),
      ], const OfficialEventsPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('进行中 · 共 1 个活动'), findsOneWidget);
    await _shot(tester, 'goldens/page_official_events_live.png');
  });

  testWidgets('B28 官方活动:我的档空态', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        officialCanPublishProvider.overrideWith((Ref ref) async => false),
        officialEventsProvider.overrideWith(
          (Ref ref) async => <OfficialEvent>[],
        ),
        myOfficialEventsProvider.overrideWith(
          (Ref ref) async => <OfficialEvent>[],
        ),
      ], const OfficialEventsPage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('还没有参与的活动'), findsOneWidget);
    await _shot(tester, 'goldens/page_official_events_mine_empty.png');
  });

  testWidgets('B29 官方活动:即将档', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        officialCanPublishProvider.overrideWith((Ref ref) async => false),
        officialEventsProvider.overrideWith(
          (Ref ref) async => <OfficialEvent>[_upcoming],
        ),
        myOfficialEventsProvider.overrideWith(
          (Ref ref) async => <OfficialEvent>[],
        ),
      ], const OfficialEventsPage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('即将'));
    await tester.pumpAndSettle();
    expect(find.text('苏州河夜行计划'), findsOneWidget);
    await _shot(tester, 'goldens/page_official_events_upcoming.png');
  });

  testWidgets('B30 官方活动详情:已结束态', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        officialEventProvider(7).overrideWith(
          (Ref ref) async => const OfficialEvent(
            id: 7,
            title: '外滩夜行档案',
            city: '上海',
            status: 5,
            participants: 62,
            rewardJson: '[{"name":"参与纪念徽章"},{"name":"80 成长值"}]',
          ),
        ),
      ], const OfficialEventDetailPage(id: 7)),
    );
    await tester.pumpAndSettle();
    expect(find.text('活动已结束'), findsOneWidget);
    await _shot(tester, 'goldens/page_official_event_detail_ended.png');
  });

  testWidgets('B31 承接邀约收件箱:商家视角', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(
        <dynamic>[
          partyInboxProvider.overrideWith(
            (Ref ref) async => const <PartyInviteItem>[
              PartyInviteItem(
                partyId: 1,
                title: '外滩夜行档案',
                partyType: 'MERCHANT',
                eventTitle: '外滩夜行档案',
                status: 'INVITED',
                city: '上海',
              ),
            ],
          ),
        ],
        const OfficialInboxPage(),
        theme: merchantGoldenTheme(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('接受'), findsOneWidget);
    await _shot(tester, 'goldens/page_official_inbox_merchant.png');
  });
}
