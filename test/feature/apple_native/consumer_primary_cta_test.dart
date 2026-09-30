import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/growth.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/auth/login_page.dart';
import 'package:chengyin_app/feature/map/map_controller.dart';
import 'package:chengyin_app/feature/map/map_page.dart';
import 'package:chengyin_app/feature/p3/badges/badge_wall_controller.dart';
import 'package:chengyin_app/feature/p3/badges/badge_wall_logic.dart';
import 'package:chengyin_app/feature/p3/badges/badge_wall_page.dart';
import 'package:chengyin_app/feature/p3/growth/leaderboard_controller.dart';
import 'package:chengyin_app/feature/p3/growth/leaderboard_page.dart';
import 'package:chengyin_app/feature/search/city_node_search_page.dart';
import 'package:chengyin_app/feature/tickets/pass_page.dart';
import 'package:chengyin_app/feature/tickets/ticket_detail_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _PassActivityApi implements ActivityApi {
  @override
  Future<DynCode> issueDynamicCode(int registrationId) async => DynCode(
    code: 'CY.$registrationId.expired',
    expiresAt: DateTime.now().millisecondsSinceEpoch - 1000,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// p3 三页对游客是登录门(B1 报告 P1 修复),这些拍的是登录后的主 CTA。
class _FixedAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 1, nickname: '阿兰', avatar: '', role: 'player'),
  );
}

Widget _host(Widget child, {List<dynamic> overrides = const <dynamic>[]}) {
  return ProviderScope(
    key: UniqueKey(),
    overrides: <dynamic>[
      // 票卡详情/出码页对**游客**会换成登录门(#231 P1);这里考的是已登录
      // 用户在出码主 CTA 上的原生玻璃与路由文案,先把登录态摆好。
      authControllerProvider.overrideWith(_FixedAuth.new),
      ...overrides,
    ].cast(),
    child: MaterialApp(theme: ThemeData.dark(), home: child),
  );
}

RegistrationDetail _usableTicket() =>
    RegistrationDetail.fromJson(<String, dynamic>{
      'id': 12,
      'ownerType': 2,
      'ownerId': 8,
      'registrationNo': 'R12',
      'registrationStatus': 2,
      'verificationStatus': 0,
      'cmsActivity': <String, dynamic>{'name': '城市漫游'},
    });

void main() {
  testWidgets('登录页主操作与次操作都使用原生玻璃按钮', (WidgetTester tester) async {
    await tester.pumpWidget(_host(const LoginPage(intent: 'existing')));
    await tester.pump();

    final Finder wechat = find.widgetWithText(CyNativeButton, '微信登录');
    final Finder phone = find.widgetWithText(CyNativeButton, '手机号登录');
    expect(wechat, findsOneWidget);
    expect(phone, findsOneWidget);
    expect(
      tester.widget<CyNativeButton>(wechat).role,
      CyNativeButtonRole.primary,
    );
    expect(
      tester.widget<CyNativeButton>(wechat).borderRadius,
      CyTokens.radiusLg,
    );
    expect(
      tester.widget<CyNativeButton>(phone).role,
      CyNativeButtonRole.secondary,
    );
  });

  testWidgets('地图隐私同意后同路由换页，保持 Cupertino 按钮避免暗帧', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        const MapPage(),
        overrides: <dynamic>[
          mapPrivacyAgreementProvider.overrideWith((ref) async => false),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CyNativeButton), findsNothing);
    expect(
      find.ancestor(
        of: find.text('同意并启用地图'),
        matching: find.byType(CupertinoButton),
      ),
      findsOneWidget,
    );
  });

  testWidgets('城市节点首次搜索是同路由状态切换，不堆平台视图', (WidgetTester tester) async {
    await tester.pumpWidget(_host(const CityNodeSearchPage()));
    await tester.pump();

    expect(find.byKey(const Key('search-map-filter')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('使用当前位置搜索'),
        matching: find.byType(CupertinoButton),
      ),
      findsOneWidget,
    );
  });

  testWidgets('过期核销码刷新是同页换态，保持 Cupertino 主操作', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        const PassPage(registrationId: 12),
        overrides: <dynamic>[
          activityApiProvider.overrideWithValue(_PassActivityApi()),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(CyNativeButton), findsNothing);
    expect(
      find.ancestor(
        of: find.text('重新获取核销码'),
        matching: find.byType(CupertinoButton),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('票券详情的出码主 CTA 使用原生玻璃且保留路由文案', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        const TicketDetailPage(registrationId: 12),
        overrides: <dynamic>[
          ticketDetailProvider(12).overrideWith((ref) async => _usableTicket()),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final Finder native = find.byType(CyNativeButton);
    expect(native, findsOneWidget);
    expect(tester.widget<CyNativeButton>(native).label, '出示核销码');
    expect(tester.widget<CyNativeButton>(native).onPressed, isNotNull);
    expect(
      tester.widget<CyNativeButton>(native).borderRadius,
      CyTokens.radiusLg,
    );
  });

  testWidgets('勋章墙空态的跨路由主 CTA 使用原生玻璃', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        const BadgeWallPage(),
        overrides: <dynamic>[
          badgeWallProvider.overrideWith(
            (ref) async => const BadgeWallPageData(
              badges: <WallBadgeView>[],
              legend: <WallLegendEntry>[],
              unlockedCount: 0,
              lockedCount: 0,
              failure: null,
              failureDetail: '',
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final Finder native = find.byType(CyNativeButton);
    expect(native, findsOneWidget);
    expect(tester.widget<CyNativeButton>(native).label, '去探索');
    expect(
      tester.widget<CyNativeButton>(native).borderRadius,
      CyTokens.radiusLg,
    );
  });

  testWidgets('排行榜空态的跨路由主 CTA 使用原生玻璃', (WidgetTester tester) async {
    final GrowthLeaderboard board = GrowthLeaderboard.fromJson(
      <String, dynamic>{
        'metric': 'point',
        'period': 'total',
        'list': <dynamic>[],
        'me': <String, dynamic>{'score': 0},
      },
    );
    await tester.pumpWidget(
      _host(
        const LeaderboardPage(),
        overrides: <dynamic>[
          leaderboardProvider.overrideWith(
            (ref, query) async =>
                LeaderboardResult(data: buildLeaderboardData(board)),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final Finder native = find.byType(CyNativeButton);
    expect(native, findsOneWidget);
    expect(tester.widget<CyNativeButton>(native).label, '去探索');
    expect(
      tester.widget<CyNativeButton>(native).borderRadius,
      CyTokens.radiusLg,
    );
  });
}
