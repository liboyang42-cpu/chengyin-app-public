import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/points_api.dart';
import 'package:chengyin_app/data/models/coupon.dart';
import 'package:chengyin_app/data/models/points_record.dart';
import 'package:chengyin_app/feature/coupon/my_coupons_page.dart';
import 'package:chengyin_app/feature/participation/participation_api.dart';
import 'package:chengyin_app/feature/participation/participation_models.dart';
import 'package:chengyin_app/feature/participation/participation_page.dart';
import 'package:chengyin_app/feature/points/points_hero.dart';
import 'package:chengyin_app/feature/points/points_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _EmptyPointsApi implements PointsApi {
  const _EmptyPointsApi();

  @override
  Future<List<PointsRecord>> list({
    int? changeType,
    int pageNum = 1,
    int pageSize = 20,
  }) async => <PointsRecord>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyParticipationRepository implements ParticipationRepository {
  const _EmptyParticipationRepository();

  @override
  Future<ParticipationDetail> detail(int id) =>
      throw UnsupportedError('空列表不会打开详情');

  @override
  Future<List<ParticipationRecord>> list() async => <ParticipationRecord>[];
}

Future<void> _pump(
  WidgetTester tester, {
  required Widget page,
  required List<dynamic> overrides,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(home: page),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectNativeRoot(String title) {
  expect(find.byType(CupertinoPageScaffold), findsOneWidget);
  expect(find.byType(CupertinoNavigationBar), findsOneWidget);
  expect(find.byType(AppBar), findsNothing);
  expect(find.text(title), findsOneWidget);
}

void main() {
  testWidgets('我的优惠券使用 Apple 原生一级导航并保留页内标题', (WidgetTester tester) async {
    await _pump(
      tester,
      page: const MyCouponsPage(),
      overrides: <dynamic>[
        myCouponsProvider.overrideWith((Ref ref) async => <CouponRecord>[]),
      ],
    );

    _expectNativeRoot('我的优惠券');
  });

  testWidgets('积分明细使用 Apple 原生一级导航并保留页内标题', (WidgetTester tester) async {
    await _pump(
      tester,
      page: const PointsPage(),
      overrides: <dynamic>[
        pointsApiProvider.overrideWithValue(const _EmptyPointsApi()),
        pointsStatProvider.overrideWith((Ref ref) async => null),
      ],
    );

    _expectNativeRoot('积分明细');
  });

  testWidgets('我的参与使用 Apple 原生一级导航并保留页内标题', (WidgetTester tester) async {
    await _pump(
      tester,
      page: const ParticipationPage(liquidGlassSupported: false),
      overrides: <dynamic>[
        participationRepositoryProvider.overrideWithValue(
          const _EmptyParticipationRepository(),
        ),
      ],
    );

    _expectNativeRoot('我的参与');
  });
}
