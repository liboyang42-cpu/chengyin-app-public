import 'package:chengyin_app/core/role_provider.dart';
import 'package:chengyin_app/data/models/role_info.dart';
import 'package:chengyin_app/feature/assets/assets_page.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/coupon/my_published_coupons_page.dart';
import 'package:chengyin_app/feature/settings/about_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _LoggedOutAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

/// 「我发布的券」游客会落在页内登录门(b1-sim-coupon P1-1),
/// 这些溢出/统计用例测的是登录后的列表,给一个固定登录态。
class _SignedInAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 1, nickname: '店长', avatar: '', role: 'merchant'),
  );
}

RoleInfo _withdrawableRole() => RoleInfo.fromJson(<String, dynamic>{
  'role': 'player',
  'permission': <String, dynamic>{'withdrawable': true},
  'usage': <String, dynamic>{},
  'isClubLeader': false,
  'isMerchant': false,
  'ownedClubCount': 0,
  'maxOwnedClubs': 0,
  'ownedClubs': <dynamic>[],
  'joinedClubIds': <dynamic>[],
});

Widget _app({required Widget home, required List<dynamic> overrides}) {
  return ProviderScope(
    key: UniqueKey(),
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 568),
          textScaler: TextScaler.linear(2),
        ),
        child: home,
      ),
    ),
  );
}

void main() {
  testWidgets('Apple 原生导航壳在 iPhone SE 与 200% 字号下不溢出', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final cases = <({Widget page, List<dynamic> overrides, String title})>[
      (
        page: const AssetsPage(),
        overrides: <dynamic>[
          // 游客落在页内登录门(#276 P1-1);这里要拍的是登录后的账本壳。
          authControllerProvider.overrideWith(_SignedInAuth.new),
          pointsListProvider.overrideWith((_) async => const []),
          balanceListProvider.overrideWith((_) async => const []),
          walletStagesProvider.overrideWith((_) async => null),
          roleInfoProvider.overrideWith((_) async => _withdrawableRole()),
        ],
        title: '资产明细',
      ),
      (
        page: const MyPublishedCouponsPage(),
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_SignedInAuth.new),
          myPublishedCouponsProvider.overrideWith((_) async => const []),
        ],
        title: '我发布的券',
      ),
      (
        page: const AboutPage(),
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedOutAuth.new),
        ],
        title: '关于',
      ),
    ];

    for (final testCase in cases) {
      await tester.pumpWidget(
        _app(home: testCase.page, overrides: testCase.overrides),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoPageScaffold), findsOneWidget);
      expect(find.byType(CupertinoNavigationBar), findsOneWidget);
      expect(find.byType(Scaffold), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(find.text(testCase.title), findsOneWidget);
      expect(tester.takeException(), isNull, reason: testCase.title);
    }
  });

  testWidgets('资产页用 Apple 分段控件切换且默认仍落在积分', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        home: const AssetsPage(),
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_SignedInAuth.new),
          pointsListProvider.overrideWith((_) async => const []),
          balanceListProvider.overrideWith((_) async => const []),
          walletStagesProvider.overrideWith((_) async => null),
          roleInfoProvider.overrideWith((_) async => _withdrawableRole()),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsOneWidget);
    expect(find.byKey(const Key('assets-withdrawal-entry')), findsOneWidget);
    expect(find.text('提现'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(TabBarView), findsNothing);
    for (final String label in <String>['收益明细', '邀请记录', '提现']) {
      final Text text = tester.widget<Text>(find.text(label));
      expect(text.overflow, isNot(TextOverflow.fade));
    }
    expect(find.text('还没有积分流水'), findsOneWidget);
    expect(find.text('还没有余额流水'), findsNothing);

    await tester.tap(find.text('余额'));
    await tester.pumpAndSettle();

    expect(find.text('还没有余额流水'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('我发布的券在 iPhone SE 与 200% 字号下保留完整统计', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        home: const MyPublishedCouponsPage(),
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_SignedInAuth.new),
          myPublishedCouponsProvider.overrideWith(
            (_) async => <Map<String, dynamic>>[
              <String, dynamic>{
                'name': '开业九折券',
                'status': 1,
                'publishCount': 100,
                'receiveCount': 40,
                'useCount': 12,
                'startTime': '2026-08-01 00:00:00',
                'endTime': '2026-09-01 00:00:00',
              },
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('开业九折券'), findsOneWidget);
    expect(find.text('发行'), findsOneWidget);
    expect(find.text('已领'), findsOneWidget);
    expect(find.text('已核销'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
