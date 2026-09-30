import 'package:chengyin_app/core/map/map_launcher.dart';
import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/roam_api.dart';
import 'package:chengyin_app/data/api/topic_api.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/pricing.dart';
import 'package:chengyin_app/data/models/roam_merchant_info.dart';
import 'package:chengyin_app/feature/topic/topic_pricing_partner_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

DioClient _dummyClient() => DioClient(TokenStore(const FlutterSecureStorage()));

/// 生产实测:游客态这些端点回 HTTP 401(见 topic_guest_401_test.dart 抬头)。
DioException _unauthorized(String path) => DioException(
  requestOptions: RequestOptions(path: path),
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: path),
    statusCode: 401,
  ),
);

DioException _connectionError(String path) => DioException(
  requestOptions: RequestOptions(path: path),
  type: DioExceptionType.connectionError,
);

/// preview 只回 `toType/toId + 条款`,名称逐行另换 —— 阵容行 fixture。
const PricingLineupRow _clubRow = PricingLineupRow(
  toType: 'club',
  toId: 7,
  shareMode: 1,
  shareRate: '15',
);
const PricingLineupRow _merchantRow = PricingLineupRow(
  toType: 'merchant',
  toId: 31,
  shareMode: 2,
  fixedFee: '20',
);

class _FakeTopicApi extends TopicApi {
  _FakeTopicApi({this.lineup = const <PricingLineupRow>[], this.failure})
    : super(_dummyClient());

  final List<PricingLineupRow> lineup;
  Object? failure;
  int previewCalls = 0;
  int? requestedTopicId;
  PricingSubType? requestedSubType;

  @override
  Future<PricingPreview> pricingPreview({
    required int topicId,
    required PricingSubType subType,
    double? leadCost,
    int? teamSize,
  }) async {
    previewCalls++;
    requestedTopicId = topicId;
    requestedSubType = subType;
    if (failure != null) throw failure!;
    return PricingPreview(priceMin: 100, lineup: lineup);
  }
}

class _FakeClubApi extends ClubApi {
  _FakeClubApi({this.failure, this.club}) : super(_dummyClient());

  Object? failure;
  final Club? club;
  int calls = 0;
  int? requestedId;

  @override
  Future<Club> detail(int id) async {
    calls++;
    requestedId = id;
    if (failure != null) throw failure!;
    return club ??
        Club(
          id: id,
          name: '夜骑俱乐部',
          description: '沿着城市夜色骑行',
          leaderName: '阿岚',
          city: '上海',
          clubType: '兴趣社群',
          memberCount: 28,
          level: 3,
        );
  }
}

const RoamMerchantInfo _defaultMerchant = RoamMerchantInfo(
  id: 31,
  memberId: 203,
  name: '梧桐咖啡',
  description: '街角的城市客厅',
  categories: <String>['咖啡', '甜品'],
  capacity: 36,
  suitActivityTypes: 'CityWalk · 咖啡路线',
  availableTime: '周二至周日 10:00-18:00',
  chargeType: 1,
  demand: '希望获得稳定客流',
  businessTime: '09:30-21:00',
  address: '武康路 100 号',
  latitude: 31.2101,
  longitude: 121.4321,
);

class _FakeRoamApi extends RoamApi {
  _FakeRoamApi({this.failure, this.merchant = _defaultMerchant})
    : super(_dummyClient());

  Object? failure;
  final RoamMerchantInfo merchant;
  int calls = 0;
  int? requestedId;

  @override
  Future<(RoamMerchantInfo, RoamFeatured?)> publicMerchantDetail(int id) async {
    calls++;
    requestedId = id;
    if (failure != null) throw failure!;
    return (merchant, null);
  }
}

Widget _app({
  required TopicPricingPartnerPage page,
  _FakeTopicApi? topics,
  ClubApi? clubs,
  RoamApi? roam,
  double textScale = 1,
  List<dynamic> extraOverrides = const <dynamic>[],
}) {
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => page),
      GoRoute(
        path: '/club/:id',
        builder: (_, state) => Text('club-${state.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/user/:id',
        builder: (_, state) => Text('user-${state.pathParameters['id']}'),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      if (topics != null) topicApiProvider.overrideWithValue(topics),
      if (clubs != null) clubApiProvider.overrideWithValue(clubs),
      if (roam != null) roamApiProvider.overrideWithValue(roam),
      ...extraOverrides,
    ],
    child: CupertinoApp.router(
      routerConfig: router,
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  );
}

ProviderContainer _container({
  _FakeTopicApi? topics,
  ClubApi? clubs,
  RoamApi? roam,
}) => ProviderContainer(
  retry: (int _, Object _) => null,
  overrides: [
    if (topics != null) topicApiProvider.overrideWithValue(topics),
    if (clubs != null) clubApiProvider.overrideWithValue(clubs),
    if (roam != null) roamApiProvider.overrideWithValue(roam),
  ],
);

void main() {
  group('阵容模型', () {
    test('fromJson 只保留 toType/toId 齐全的行,条款值原样带出', () {
      final PricingPreview preview = PricingPreview.fromJson(<String, dynamic>{
        'priceMin': 100,
        'lineup': <dynamic>[
          <String, dynamic>{
            'toType': 'club',
            'toId': 7,
            'shareMode': 1,
            'shareRate': '15',
          },
          <String, dynamic>{'toType': '', 'toId': 8, 'shareMode': 0},
          <String, dynamic>{'toType': 'merchant', 'toId': 0, 'shareMode': 0},
          <String, dynamic>{
            'toType': 'merchant',
            'toId': '31',
            'shareMode': '2',
            'fixedFee': 0,
          },
        ],
      });
      expect(
        preview.lineup.map((PricingLineupRow r) => '${r.toType}:${r.toId}'),
        <String>['club:7', 'merchant:31'],
      );
      expect(preview.lineup.last.shareMode, 2);
      expect(preview.lineup.last.fixedFee, '0');
    });

    test('定价页条款摘要与兜底名,逐字对齐小程序 termsText', () {
      expect(_clubRow.termsText, '分成型 · 15%');
      expect(
        const PricingLineupRow(
          toType: 'club',
          toId: 7,
          shareMode: 1,
          shareRate: '',
        ).termsText,
        '分成型 · —',
      );
      expect(_merchantRow.termsText, '固定 · ¥20/人');
      expect(
        const PricingLineupRow(
          toType: 'merchant',
          toId: 31,
          shareMode: 2,
        ).termsText,
        '固定 · ¥—/人',
      );
      expect(
        const PricingLineupRow(toType: 'club', toId: 7, shareMode: 0).termsText,
        '引流型',
      );
      expect(_clubRow.fallbackName, '合作俱乐部');
      expect(_merchantRow.fallbackName, '承接商家');
    });

    test('normalizedTerms:认不出的条款不出(不按 0 放行);0 是合法金额', () {
      PricingLineupRow row(int mode, {String? rate, String? fee}) =>
          PricingLineupRow(
            toType: 'club',
            toId: 7,
            shareMode: mode,
            shareRate: rate,
            fixedFee: fee,
          );

      expect(row(1, rate: '200').terms, isNull);
      expect(row(1, rate: '').terms, isNull);
      expect(row(2, fee: '-1').terms, isNull);
      expect(row(3).terms, isNull);
      expect(row(1, rate: '12.5').terms!.shareRateDisplay, '12.5%');
      expect(row(2, fee: '0').terms!.fixedFeeDisplay, '¥0/人');
      expect(row(0).terms!.settlementName, '引流型');
      expect(row(1, rate: '15').terms!.footnote, '开售后条款冻结，按实际票款参与分成结算。');
      expect(row(2, fee: '20').terms!.footnote, '开售后条款冻结，按实际核销人头结算。');
      expect(row(0).terms!.footnote, '开售后阵容冻结；引流型合作不产生现金分成。');
    });
  });

  group('两步链 provider', () {
    test('preview(self) 找到行后才拉俱乐部公开档案', () async {
      final _FakeTopicApi topics = _FakeTopicApi(
        lineup: const <PricingLineupRow>[_clubRow],
      );
      final _FakeClubApi clubs = _FakeClubApi();
      final ProviderContainer container = _container(
        topics: topics,
        clubs: clubs,
      );
      addTearDown(container.dispose);

      final TopicPricingPartnerData data = await container.read(
        topicPricingPartnerProvider(
          const TopicPricingPartnerLookup(toType: 'club', toId: 7, topicId: 99),
        ).future,
      );
      expect(topics.requestedTopicId, 99);
      expect(topics.requestedSubType, PricingSubType.self);
      expect(clubs.requestedId, 7);
      expect(data.terms.shareMode, 1);
      expect(data.profile.name, '夜骑俱乐部');
      expect(
        data.profile.details.map(
          (PricingPartnerDetailRow r) => '${r.label}:${r.value}',
        ),
        containsAll(<String>['主理人:阿岚', '所在城市:上海', '成员数:28 人', '等级:L3']),
      );
    });

    test('merchant 行走公开商家档案,地址行带地图入口', () async {
      final _FakeTopicApi topics = _FakeTopicApi(
        lineup: const <PricingLineupRow>[_merchantRow],
      );
      final _FakeRoamApi roam = _FakeRoamApi();
      final ProviderContainer container = _container(
        topics: topics,
        roam: roam,
      );
      addTearDown(container.dispose);

      final TopicPricingPartnerData data = await container.read(
        topicPricingPartnerProvider(
          const TopicPricingPartnerLookup(
            toType: 'merchant',
            toId: 31,
            topicId: 99,
          ),
        ).future,
      );
      expect(roam.requestedId, 31);
      expect(data.profile.memberId, 203);
      expect(data.profile.latitude, 31.2101);
      expect(data.profile.longitude, 121.4321);
      expect(
        data.profile.details.map(
          (PricingPartnerDetailRow r) => '${r.label}:${r.value}',
        ),
        containsAll(<String>[
          '品类:咖啡 · 甜品',
          '可容纳:36 人',
          '适合路线:CityWalk · 咖啡路线',
          '可承接时段:周二至周日 10:00-18:00',
          '收费方式:收费承接',
          '合作诉求:希望获得稳定客流',
          '营业时间:09:30-21:00',
          '门店地址:武康路 100 号',
        ]),
      );
      expect(
        data.profile.details
            .singleWhere((PricingPartnerDetailRow r) => r.label == '门店地址')
            .opensLocation,
        isTrue,
      );
    });

    test('阵容里没有这一行 → 点名「不在生效阵容」,且不去拉公开档案', () async {
      final _FakeTopicApi topics = _FakeTopicApi(
        lineup: const <PricingLineupRow>[_merchantRow],
      );
      final _FakeClubApi clubs = _FakeClubApi();
      final ProviderContainer container = _container(
        topics: topics,
        clubs: clubs,
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(
          topicPricingPartnerProvider(
            const TopicPricingPartnerLookup(
              toType: 'club',
              toId: 7,
              topicId: 99,
            ),
          ).future,
        ),
        throwsA(
          predicate<Object>(
            (Object e) => e.toString().contains('该合作方不在当前主题的生效阵容中，条款无法展示。'),
          ),
        ),
      );
      expect(clubs.calls, 0);
    });

    test('条款非法 → 「合作条款信息不完整」,不猜测、不拉档案', () async {
      final _FakeTopicApi topics = _FakeTopicApi(
        lineup: const <PricingLineupRow>[
          PricingLineupRow(
            toType: 'club',
            toId: 7,
            shareMode: 1,
            shareRate: '200',
          ),
        ],
      );
      final _FakeClubApi clubs = _FakeClubApi();
      final ProviderContainer container = _container(
        topics: topics,
        clubs: clubs,
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(
          topicPricingPartnerProvider(
            const TopicPricingPartnerLookup(
              toType: 'club',
              toId: 7,
              topicId: 99,
            ),
          ).future,
        ),
        throwsA(
          predicate<Object>(
            (Object e) => e.toString().contains('合作条款信息不完整，请稍后重试。'),
          ),
        ),
      );
      expect(clubs.calls, 0);
    });

    test('401 三段都原样抛出(preview / club / merchant),不改写成故障', () async {
      final ProviderContainer preview401 = _container(
        topics: _FakeTopicApi(
          failure: _unauthorized('/api/topic/pricing/preview'),
        ),
      );
      addTearDown(preview401.dispose);
      await expectLater(
        preview401.read(
          topicPricingPartnerProvider(
            const TopicPricingPartnerLookup(
              toType: 'club',
              toId: 7,
              topicId: 99,
            ),
          ).future,
        ),
        throwsA(
          predicate(
            (Object e) => e is DioException && e.response?.statusCode == 401,
            '401 的 DioException',
          ),
        ),
      );

      final ProviderContainer club401 = _container(
        topics: _FakeTopicApi(lineup: const <PricingLineupRow>[_clubRow]),
        clubs: _FakeClubApi(failure: _unauthorized('/api/club/detail')),
      );
      addTearDown(club401.dispose);
      await expectLater(
        club401.read(
          topicPricingPartnerProvider(
            const TopicPricingPartnerLookup(
              toType: 'club',
              toId: 7,
              topicId: 99,
            ),
          ).future,
        ),
        throwsA(
          predicate(
            (Object e) => e is DioException && e.response?.statusCode == 401,
          ),
        ),
      );

      final ProviderContainer merchant401 = _container(
        topics: _FakeTopicApi(lineup: const <PricingLineupRow>[_merchantRow]),
        roam: _FakeRoamApi(
          failure: _unauthorized('/api/merchant/public-detail'),
        ),
      );
      addTearDown(merchant401.dispose);
      await expectLater(
        merchant401.read(
          topicPricingPartnerProvider(
            const TopicPricingPartnerLookup(
              toType: 'merchant',
              toId: 31,
              topicId: 99,
            ),
          ).future,
        ),
        throwsA(
          predicate(
            (Object e) => e is DioException && e.response?.statusCode == 401,
          ),
        ),
      );
    });

    test('承载层失败给真源兜底文案;短中文业务句原样放行', () async {
      final ProviderContainer connFail = _container(
        topics: _FakeTopicApi(
          failure: _connectionError('/api/topic/pricing/preview'),
        ),
      );
      addTearDown(connFail.dispose);
      await expectLater(
        connFail.read(
          topicPricingPartnerProvider(
            const TopicPricingPartnerLookup(
              toType: 'club',
              toId: 7,
              topicId: 99,
            ),
          ).future,
        ),
        throwsA(
          predicate<Object>(
            (Object e) => e.toString().contains('合作条款加载失败，请稍后重试。'),
          ),
        ),
      );

      final ProviderContainer bizMsg = _container(
        topics: _FakeTopicApi(failure: Exception('主题已下架，无法查看条款')),
      );
      addTearDown(bizMsg.dispose);
      await expectLater(
        bizMsg.read(
          topicPricingPartnerProvider(
            const TopicPricingPartnerLookup(
              toType: 'club',
              toId: 7,
              topicId: 99,
            ),
          ).future,
        ),
        throwsA(
          predicate<Object>(
            (Object e) => e.toString().contains('主题已下架，无法查看条款'),
          ),
        ),
      );

      final ProviderContainer clubFail = _container(
        topics: _FakeTopicApi(lineup: const <PricingLineupRow>[_clubRow]),
        clubs: _FakeClubApi(failure: _connectionError('/api/club/detail')),
      );
      addTearDown(clubFail.dispose);
      await expectLater(
        clubFail.read(
          topicPricingPartnerProvider(
            const TopicPricingPartnerLookup(
              toType: 'club',
              toId: 7,
              topicId: 99,
            ),
          ).future,
        ),
        throwsA(
          predicate<Object>(
            (Object e) => e.toString().contains('未能读取合作俱乐部资料，请稍后重试。'),
          ),
        ),
      );

      final ProviderContainer merchantFail = _container(
        topics: _FakeTopicApi(lineup: const <PricingLineupRow>[_merchantRow]),
        roam: _FakeRoamApi(
          failure: _connectionError('/api/merchant/public-detail'),
        ),
      );
      addTearDown(merchantFail.dispose);
      await expectLater(
        merchantFail.read(
          topicPricingPartnerProvider(
            const TopicPricingPartnerLookup(
              toType: 'merchant',
              toId: 31,
              topicId: 99,
            ),
          ).future,
        ),
        throwsA(
          predicate<Object>(
            (Object e) => e.toString().contains('未能读取承接商家资料，请稍后重试。'),
          ),
        ),
      );
    });

    test('资料缺名称 → 点名缺名称,不被兜底成「未能读取」', () async {
      final ProviderContainer club = _container(
        topics: _FakeTopicApi(lineup: const <PricingLineupRow>[_clubRow]),
        clubs: _FakeClubApi(club: Club(id: 7, name: '')),
      );
      addTearDown(club.dispose);
      await expectLater(
        club.read(
          topicPricingPartnerProvider(
            const TopicPricingPartnerLookup(
              toType: 'club',
              toId: 7,
              topicId: 99,
            ),
          ).future,
        ),
        throwsA(
          predicate<Object>(
            (Object e) => e.toString().contains('合作俱乐部资料缺少名称，请稍后重试。'),
          ),
        ),
      );

      final ProviderContainer merchant = _container(
        topics: _FakeTopicApi(lineup: const <PricingLineupRow>[_merchantRow]),
        roam: _FakeRoamApi(merchant: const RoamMerchantInfo(id: 31)),
      );
      addTearDown(merchant.dispose);
      await expectLater(
        merchant.read(
          topicPricingPartnerProvider(
            const TopicPricingPartnerLookup(
              toType: 'merchant',
              toId: 31,
              topicId: 99,
            ),
          ).future,
        ),
        throwsA(
          predicate<Object>(
            (Object e) => e.toString().contains('承接商家资料缺少名称，请稍后重试。'),
          ),
        ),
      );
    });
  });

  group('页面', () {
    testWidgets('俱乐部:档案 + 分成型条款 + 冻结时间,查看落 /club/:id', (tester) async {
      const TopicPricingPartnerPage page = TopicPricingPartnerPage(
        toType: 'club',
        toId: 7,
        topicId: 99,
      );
      await tester.pumpWidget(
        _app(
          page: page,
          topics: _FakeTopicApi(lineup: const <PricingLineupRow>[_clubRow]),
          clubs: _FakeClubApi(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('合作俱乐部'), findsOneWidget);
      expect(find.text('阵容已锁定，以下为该合作方在本主题中的结算条款。'), findsOneWidget);
      expect(find.text('夜骑俱乐部'), findsOneWidget);
      expect(find.text('沿着城市夜色骑行'), findsOneWidget);
      expect(find.text('主理人'), findsOneWidget);
      expect(find.text('阿岚'), findsOneWidget);
      expect(find.text('合作条款'), findsOneWidget);
      expect(find.text('结算方式'), findsOneWidget);
      expect(find.text('分成型'), findsOneWidget);
      expect(find.text('分成比例'), findsOneWidget);
      expect(find.text('15%'), findsOneWidget);
      expect(find.text('冻结时间'), findsOneWidget);
      expect(find.text('开售即冻结'), findsOneWidget);
      expect(find.text('开售后条款冻结，按实际票款参与分成结算。'), findsOneWidget);
      // 条款不来自 query:旧的「条款摘要」汇总行已删。
      expect(find.text('条款摘要'), findsNothing);

      await tester.tap(find.text('查看'));
      await tester.pumpAndSettle();
      expect(find.text('club-7'), findsOneWidget);
    });

    testWidgets('商家:固定型 ¥20/人 + 核销人头脚注,查看用 memberId 不用 merchantId', (
      tester,
    ) async {
      const TopicPricingPartnerPage page = TopicPricingPartnerPage(
        toType: 'merchant',
        toId: 31,
        topicId: 99,
      );
      await tester.pumpWidget(
        _app(
          page: page,
          topics: _FakeTopicApi(lineup: const <PricingLineupRow>[_merchantRow]),
          roam: _FakeRoamApi(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('承接商家'), findsOneWidget);
      expect(find.text('固定型'), findsOneWidget);
      expect(find.text('固定合作费'), findsOneWidget);
      expect(find.text('¥20/人'), findsOneWidget);
      expect(find.text('开售后条款冻结，按实际核销人头结算。'), findsOneWidget);
      expect(find.text('可容纳'), findsOneWidget);
      expect(find.text('营业时间'), findsOneWidget);

      await tester.tap(find.text('查看'));
      await tester.pumpAndSettle();
      expect(find.text('user-203'), findsOneWidget);
      expect(find.text('user-31'), findsNothing);
    });

    testWidgets('引流型:没有比例/费用行,脚注点明不产生现金分成', (tester) async {
      const TopicPricingPartnerPage page = TopicPricingPartnerPage(
        toType: 'club',
        toId: 7,
        topicId: 99,
      );
      await tester.pumpWidget(
        _app(
          page: page,
          topics: _FakeTopicApi(
            lineup: const <PricingLineupRow>[
              PricingLineupRow(toType: 'club', toId: 7, shareMode: 0),
            ],
          ),
          clubs: _FakeClubApi(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('结算方式'), findsOneWidget);
      expect(find.text('引流型'), findsOneWidget);
      expect(find.text('分成比例'), findsNothing);
      expect(find.text('固定合作费'), findsNothing);
      expect(find.text('开售后阵容冻结；引流型合作不产生现金分成。'), findsOneWidget);
    });

    testWidgets('有坐标才开放系统地图入口,没有坐标仍显示地址', (tester) async {
      double? openedLat;
      double? openedLng;
      String? openedName;
      String? openedAddress;
      Future<MapLaunchResult> fakeLauncher({
        required double? lat,
        required double? lng,
        required String name,
        String? address,
        required bool isIOS,
      }) async {
        openedLat = lat;
        openedLng = lng;
        openedName = name;
        openedAddress = address;
        return MapLaunchResult.opened;
      }

      const TopicPricingPartnerPage page = TopicPricingPartnerPage(
        toType: 'merchant',
        toId: 31,
        topicId: 99,
      );
      await tester.pumpWidget(
        _app(
          page: page,
          topics: _FakeTopicApi(lineup: const <PricingLineupRow>[_merchantRow]),
          roam: _FakeRoamApi(),
          extraOverrides: <dynamic>[
            topicPricingPartnerMapLauncherProvider.overrideWithValue(
              fakeLauncher,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('partner-open-location')));
      await tester.pump();
      expect(openedLat, 31.2101);
      expect(openedLng, 121.4321);
      expect(openedName, '梧桐咖啡');
      expect(openedAddress, '武康路 100 号');
    });

    testWidgets('商家没有坐标时仍显示地址,但不伪造地图入口', (tester) async {
      const TopicPricingPartnerPage page = TopicPricingPartnerPage(
        toType: 'merchant',
        toId: 31,
        topicId: 99,
      );
      await tester.pumpWidget(
        _app(
          page: page,
          topics: _FakeTopicApi(lineup: const <PricingLineupRow>[_merchantRow]),
          roam: _FakeRoamApi(
            merchant: const RoamMerchantInfo(
              id: 31,
              memberId: 203,
              name: '梧桐咖啡',
              address: '武康路 100 号',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('武康路 100 号'), findsOneWidget);
      expect(find.byKey(const Key('partner-open-location')), findsNothing);
    });

    testWidgets('缺参链接 → 「合作链接已失效」,一个接口都不请求', (tester) async {
      final _FakeTopicApi topics = _FakeTopicApi(
        lineup: const <PricingLineupRow>[_clubRow],
      );
      // 没有 topicId:即使 toType/toId 齐全也不算有效链接(小程序同口径)。
      const TopicPricingPartnerPage noTopic = TopicPricingPartnerPage(
        toType: 'club',
        toId: 7,
      );
      await tester.pumpWidget(
        _app(page: noTopic, topics: topics, clubs: _FakeClubApi()),
      );
      await tester.pumpAndSettle();
      expect(find.text('合作链接已失效'), findsOneWidget);
      expect(find.text('合作链接无效或已失效，请从主题定价页重新进入。'), findsOneWidget);
      expect(find.text('返回上一页'), findsOneWidget);
      expect(find.text('重试'), findsNothing);
      expect(topics.previewCalls, 0);

      const TopicPricingPartnerPage badType = TopicPricingPartnerPage(
        toType: 'unknown',
        toId: 7,
        topicId: 99,
      );
      await tester.pumpWidget(
        _app(page: badType, topics: topics, clubs: _FakeClubApi()),
      );
      await tester.pumpAndSettle();
      expect(find.text('合作方'), findsOneWidget);
      expect(find.text('合作链接已失效'), findsOneWidget);
      expect(topics.previewCalls, 0);
    });

    testWidgets('preview 401 → 登录引导(不是「加载失败」死路)', (tester) async {
      const TopicPricingPartnerPage page = TopicPricingPartnerPage(
        toType: 'club',
        toId: 7,
        topicId: 99,
      );
      await tester.pumpWidget(
        _app(
          page: page,
          topics: _FakeTopicApi(
            failure: _unauthorized('/api/topic/pricing/preview'),
          ),
          clubs: _FakeClubApi(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('登录后查看合作方档案'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);
      expect(find.text('合作信息加载失败'), findsNothing);
    });

    testWidgets('档案失败 → 合作信息加载失败 + 兜底文案;重试真的重新走链', (tester) async {
      const TopicPricingPartnerPage page = TopicPricingPartnerPage(
        toType: 'club',
        toId: 7,
        topicId: 99,
      );
      final _FakeClubApi clubs = _FakeClubApi(
        failure: _connectionError('/api/club/detail'),
      );
      await tester.pumpWidget(
        _app(
          page: page,
          topics: _FakeTopicApi(lineup: const <PricingLineupRow>[_clubRow]),
          clubs: clubs,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('合作信息加载失败'), findsOneWidget);
      expect(find.text('未能读取合作俱乐部资料，请稍后重试。'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('返回上一页'), findsNothing);

      clubs.failure = null;
      final int callsBefore = clubs.calls;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(clubs.calls, greaterThan(callsBefore));
      expect(find.text('夜骑俱乐部'), findsOneWidget);
    });

    testWidgets('200% Dynamic Type 下原生列表仍可滚动且不溢出', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const TopicPricingPartnerPage page = TopicPricingPartnerPage(
        toType: 'merchant',
        toId: 31,
        topicId: 99,
      );
      await tester.pumpWidget(
        _app(
          page: page,
          textScale: 2,
          topics: _FakeTopicApi(
            lineup: const <PricingLineupRow>[
              PricingLineupRow(
                toType: 'merchant',
                toId: 31,
                shareMode: 1,
                shareRate: '12.5',
              ),
            ],
          ),
          roam: _FakeRoamApi(
            merchant: const RoamMerchantInfo(
              id: 31,
              memberId: 203,
              name: '梧桐咖啡与城市文化空间',
              description: '这是一段用于验证大字号换行和滚动手感的公开档案介绍。',
              categories: <String>['咖啡', '甜品', '城市文化活动'],
              address: '上海市徐汇区武康路一百号',
              latitude: 31.2101,
              longitude: 121.4321,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(CupertinoScrollbar), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
