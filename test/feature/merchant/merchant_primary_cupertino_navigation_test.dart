import 'package:chengyin_app/core/merchant_access_provider.dart';
import 'package:chengyin_app/data/models/merchant_apply.dart';
import 'package:chengyin_app/data/models/merchant_city_node.dart';
import 'package:chengyin_app/data/models/merchant_dashboard.dart';
import 'package:chengyin_app/data/models/nearby_merchant.dart';
import 'package:chengyin_app/feature/coop/nearby_merchants_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_city_node_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_coop_profile_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_home_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_registrations_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'merchant_access_fixtures.dart' show ownerAccess;

void main() {
  final cases =
      <({Widget page, List<dynamic> overrides, String title, String anchor})>[
        (
          page: const MerchantHomePage(),
          overrides: <dynamic>[
            // 工作台根挂在 access/me 上,先给店主身份。
            merchantAccessProvider.overrideWith((_) async => ownerAccess()),
            merchantDashboardProvider.overrideWith(
              (_) async => const MerchantDashboard(),
            ),
            merchantTodoProvider.overrideWith(
              (_) async => const MerchantTodo(),
            ),
            merchantEventsProvider.overrideWith(
              (_) async => const <Map<String, dynamic>>[],
            ),
            merchantUnreadProvider.overrideWith((_) async => 0),
          ],
          title: '商家工作台',
          anchor: '累计收入',
        ),
        (
          page: const MerchantCityNodePage(),
          overrides: <dynamic>[
            cityNodesProvider.overrideWith((_) async => const CityNodeHome()),
          ],
          title: '成为节点',
          anchor: '把门店变成漫游地图上的互动据点',
        ),
        (
          page: const MerchantRegistrationsPage(),
          overrides: <dynamic>[
            merchantRegistrationsProvider(
              RegistrationListFilter.all,
            ).overrideWith((_) async => const <TopicRegistration>[]),
          ],
          title: '我的报名',
          anchor: '还没有报名记录',
        ),
        (
          page: const MerchantCoopProfilePage(),
          overrides: <dynamic>[
            coopProfileProvider.overrideWith(
              (_) async => const <String, dynamic>{},
            ),
          ],
          title: '承接设置',
          anchor: '暂时无法编辑承接设置',
        ),
        (
          page: const NearbyMerchantsPage(),
          overrides: <dynamic>[
            nearbyMerchantsProvider.overrideWith(
              (_) async => const <NearbyMerchant>[],
            ),
          ],
          title: '附近商家',
          anchor: '附近暂时没有商家',
        ),
      ];

  for (final testCase in cases) {
    testWidgets('${testCase.title}使用 iOS 原生页面导航且保留标题', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: testCase.overrides.cast(),
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.iOS),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(390, 844),
                textScaler: TextScaler.linear(2),
              ),
              child: testCase.page,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoPageScaffold), findsOneWidget);
      expect(find.byType(CupertinoNavigationBar), findsOneWidget);
      expect(find.byType(Scaffold), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(find.text(testCase.title), findsOneWidget);
      expect(find.text(testCase.anchor), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(testCase.anchor)).dy,
        greaterThanOrEqualTo(
          tester.getBottomLeft(find.byType(CupertinoNavigationBar)).dy,
        ),
        reason: '${testCase.title} 正文不能被透明导航栏遮住',
      );
      expect(tester.takeException(), isNull, reason: testCase.title);
    });
  }
}
