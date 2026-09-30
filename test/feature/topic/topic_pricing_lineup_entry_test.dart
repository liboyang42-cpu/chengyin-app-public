import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/roam_api.dart';
import 'package:chengyin_app/data/api/topic_api.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/pricing.dart';
import 'package:chengyin_app/data/models/roam_merchant_info.dart';
import 'package:chengyin_app/feature/topic/topic_pricing_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

DioClient _dummyClient() => DioClient(TokenStore(const FlutterSecureStorage()));

class _PreviewTopicApi extends TopicApi {
  _PreviewTopicApi(this.preview) : super(_dummyClient());

  final PricingPreview preview;
  int calls = 0;

  @override
  Future<PricingPreview> pricingPreview({
    required int topicId,
    required PricingSubType subType,
    double? leadCost,
    int? teamSize,
  }) async {
    calls++;
    return preview;
  }
}

class _NamedClubApi extends ClubApi {
  _NamedClubApi() : super(_dummyClient());

  @override
  Future<Club> detail(int id) async => Club(id: id, name: '夜骑俱乐部');
}

/// 名称补齐是**静默**的:档案接口挂了也只留兜底名,不能把定价页拖进错误态。
class _FailingRoamApi extends RoamApi {
  _FailingRoamApi() : super(_dummyClient());

  @override
  Future<(RoamMerchantInfo, RoamFeatured?)> publicMerchantDetail(int id) async {
    throw DioException(
      requestOptions: RequestOptions(path: '/api/merchant/public-detail'),
      type: DioExceptionType.connectionError,
    );
  }
}

Widget _app({required PricingPreview preview, ClubApi? clubs, RoamApi? roam}) {
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const TopicPricingPage(topicId: 7)),
      GoRoute(
        path: '/topic/pricing/partner',
        builder: (_, state) {
          final q = state.uri.queryParameters;
          return Text('partner-${q['topicId']}-${q['toType']}-${q['toId']}');
        },
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      topicApiProvider.overrideWithValue(_PreviewTopicApi(preview)),
      if (clubs != null) clubApiProvider.overrideWithValue(clubs),
      if (roam != null) roamApiProvider.overrideWithValue(roam),
    ],
    child: CupertinoApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('阵容非空才出「合作阵容」卡:名称异步补齐,补不上的留兜底', (tester) async {
    final preview = PricingPreview(
      priceMin: 100,
      lineup: const <PricingLineupRow>[
        PricingLineupRow(
          toType: 'club',
          toId: 7,
          shareMode: 1,
          shareRate: '15',
        ),
        PricingLineupRow(
          toType: 'merchant',
          toId: 31,
          shareMode: 2,
          fixedFee: '20',
        ),
      ],
    );
    await tester.pumpWidget(
      _app(preview: preview, clubs: _NamedClubApi(), roam: _FailingRoamApi()),
    );
    await tester.pumpAndSettle();
    // 阵容卡在 ListView 折叠线以下,不滚不 build。
    await tester.scrollUntilVisible(
      find.text('合作阵容'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('合作阵容'), findsOneWidget);
    expect(find.text('阵容已锁定，点开可查该合作方在本主题中的结算条款。'), findsOneWidget);
    // club 名补齐成功;merchant 档案挂了 → 静默留兜底名,定价主路径不受影响。
    expect(find.text('夜骑俱乐部'), findsOneWidget);
    expect(find.text('承接商家'), findsOneWidget);
    expect(find.text('分成型 · 15%'), findsOneWidget);
    expect(find.text('固定 · ¥20/人'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('确认终价并开售'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('确认终价并开售'), findsOneWidget);
  });

  testWidgets('后端没回阵容就不出卡(旧主题零回归)', (tester) async {
    await tester.pumpWidget(_app(preview: const PricingPreview(priceMin: 100)));
    await tester.pumpAndSettle();
    expect(find.text('合作阵容'), findsNothing);
  });

  testWidgets('点阵容行 → partner 路由只带 topicId/toType/toId 三参(条款不进 query)', (
    tester,
  ) async {
    final preview = PricingPreview(
      priceMin: 100,
      lineup: const <PricingLineupRow>[
        PricingLineupRow(
          toType: 'club',
          toId: 7,
          shareMode: 1,
          shareRate: '15',
        ),
      ],
    );
    await tester.pumpWidget(_app(preview: preview, clubs: _NamedClubApi()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('lineup-club-7')),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.byKey(const Key('lineup-club-7')));
    await tester.pumpAndSettle();
    expect(find.text('partner-7-club-7'), findsOneWidget);
  });
}
