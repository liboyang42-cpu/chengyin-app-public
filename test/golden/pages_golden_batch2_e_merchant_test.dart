// 工作流 P24 金图补齐(批 2)· E 段(商家/编辑器域):据点报名 / 合作设置 /
// 门店相册 / 角色形象 / 发布活动 / 玩法引导 / 玩法详情 / 定价 / 券码 /
// 优惠券创建 / 据点核销码。
//
// 状态与夹具口径取自 `/tmp/shot-matrix-master.js` 同 id 行;字段名按**App 自己的
// 后端契约**写(小程序 fixture 是它那套字段名,照抄会让页面渲成空壳 —— E12 实证)。
// 主题:商家/编辑器域恒浅(merchantGoldenTheme),玩家域恒暗(goldenTheme)。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_golden_batch2_e_merchant_test.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/category_api.dart';
import 'package:chengyin_app/data/api/coupon_api.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/api/merchant_npc_api.dart';
import 'package:chengyin_app/data/api/roam_api.dart';
import 'package:chengyin_app/data/api/topic_api.dart';
import 'package:chengyin_app/data/models/category.dart';
import 'package:chengyin_app/data/models/city_node_detail.dart';
import 'package:chengyin_app/data/models/coupon.dart';
import 'package:chengyin_app/data/models/merchant_npc.dart';
import 'package:chengyin_app/data/models/pricing.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/coupon/coupon_code_page.dart';
import 'package:chengyin_app/feature/coupon/coupon_publish_sheet.dart';
import 'package:chengyin_app/feature/merchant/merchant_city_node_create_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_coop_profile_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_decor_gallery_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_npc_edit_page.dart';
import 'package:chengyin_app/feature/publish/publish_activity_page.dart';
import 'package:chengyin_app/feature/publish/publish_capability.dart';
import 'package:chengyin_app/feature/roam/city_node_voucher_page.dart';
import 'package:chengyin_app/feature/topic/topic_pricing_page.dart';
import '../feature/merchant/merchant_access_fixtures.dart';
import '../support/fixed_auth.dart';
import 'fake_image_http.dart';
import 'golden_theme.dart';

class _FakeMerchantApi implements MerchantApi {
  _FakeMerchantApi({
    this.info = const <String, dynamic>{},
    this.coop = const <String, dynamic>{},
  });

  final Map<String, dynamic> info;
  final Map<String, dynamic> coop;

  // E07 那页进屏先过服务端经营身份闸(`access()` → 无 `merchant:project:manage`
  // 就整页渲成错误态)。不桩这一条,拍到的「加载失败 + 重试」是夹具缺权限,
  // 不是页面行为。
  @override
  Future<MerchantAccess> access() async => ownerAccess();

  @override
  Future<Map<String, dynamic>> merchantInfo() async => info;

  @override
  Future<Map<String, dynamic>> coopProfile() async => coop;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('本快照只用到 access / merchantInfo / coopProfile');
}

class _FakeMerchantNpcApi implements MerchantNpcApi {
  _FakeMerchantNpcApi(this.profile);

  final MerchantNpcProfile profile;
  final bool voice = false;
  final bool avatar3d = false;

  @override
  Future<MerchantNpcProfile> myProfile() async => profile;

  @override
  Future<VoiceEnrollScript> voiceScript() async =>
      VoiceEnrollScript(available: voice);

  @override
  Future<NpcAvatarStatus> avatarStatus() async =>
      NpcAvatarStatus(available: avatar3d);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('本快照只用到 myProfile / voiceScript / avatarStatus');
}

class _FakeTopicApi implements TopicApi {
  _FakeTopicApi(this.preview);

  final PricingPreview preview;

  @override
  Future<PricingPreview> pricingPreview({
    required int topicId,
    required PricingSubType subType,
    double? leadCost,
    int? teamSize,
  }) async => preview;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('本快照只用到 pricingPreview');
}

class _FakeCouponApi implements CouponApi {
  _FakeCouponApi(this.qr);

  final CouponQr qr;

  @override
  Future<CouponQr> qrToken(int couponHistoryId) async => qr;

  @override
  Future<CouponStatus> status(int couponHistoryId) async =>
      const CouponStatus(useStatus: 0);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('本快照只用到 qrToken / status');
}

class _FakeRoamApi implements RoamApi {
  _FakeRoamApi(this.voucher);

  final CityNodeVoucher voucher;

  @override
  Future<CityNodeVoucher> issueCityNodeCode(int poiId) async => voucher;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('本快照只用到 issueCityNodeCode');
}

class _FakeCategoryApi implements CategoryApi {
  _FakeCategoryApi(this.items);

  final List<Category> items;

  @override
  Future<List<Category>> list({String? type}) async => items;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('本快照只用到 list');
}

Widget _app(
  List<dynamic> overrides,
  Widget home, {
  bool light = true,
  ThemeData? theme,
}) {
  // `theme` 给创建域那些既非商家恒浅、也非玩家恒暗的用例(见 E15):
  // 商家档靠投影起层,创建域档是零投影 + 细线,两者不能互相顶替。
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: theme ?? (light ? merchantGoldenTheme() : goldenTheme()),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

Future<void> _shot(
  WidgetTester tester,
  Widget app,
  String goldenPath, {
  bool settle = true,
  bool settleImages = false,
}) async {
  setGoldenViewport(tester, const Size(390, 780));
  await tester.pumpWidget(app);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // 有 Timer.periodic 的页不能 pumpAndSettle(它会一直有新帧);
    // 零时长的 pump 不推进时钟 ⇒ 倒计时读数与图片解码前的相位都可复现。
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }
  if (settleImages) await settleNetworkImages(tester);
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

void main() {
  testWidgets('E07 据点报名 · 店铺坐标 + 待配玩法', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(<dynamic>[
        merchantApiProvider.overrideWithValue(
          _FakeMerchantApi(
            info: <String, dynamic>{
              'name': '河畔咖啡',
              'address': '苏州河南岸 12 号',
              'locationLat': 31.234,
              'locationLng': 121.49,
            },
          ),
        ),
      ], const MerchantCityNodeCreatePage()),
      'goldens/page_merchant_city_node_create.png',
    );
  });

  testWidgets('E08 合作设置 · 已填档案', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(<dynamic>[
        merchantApiProvider.overrideWithValue(
          _FakeMerchantApi(
            coop: <String, dynamic>{
              'capacity': '20',
              'availableTime': '周五至周日 18:00-22:00',
              'chargeType': 1,
              'demand': '适合 8-20 人夜行集合，需提前一天确认。',
              'suitActivityTypes': '城市定向,自由探索',
              'coopOpen': 1,
            },
          ),
        ),
      ], const MerchantCoopProfilePage()),
      'goldens/page_merchant_coop_profile.png',
    );
  });

  testWidgets('E09 门店相册 · 两张图待保存', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(<dynamic>[
        merchantApiProvider.overrideWithValue(
          _FakeMerchantApi(
            coop: <String, dynamic>{
              'gallery': <String>[
                'https://example.invalid/g1.jpg',
                'https://example.invalid/g2.jpg',
              ],
            },
          ),
        ),
      ], const MerchantDecorGalleryPage()),
      'goldens/page_merchant_decor_gallery.png',
    );
  });

  testWidgets('E11 店铺角色 · 已配形象', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(<dynamic>[
        merchantNpcApiProvider.overrideWithValue(
          _FakeMerchantNpcApi(
            MerchantNpcProfile.fromJson(<String, dynamic>{
              'configured': true,
              'profileId': 7,
              'name': '小店长',
              'persona': '爱聊城市传说的咖啡师',
              'greeting': '来一杯手冲？',
              'knowledge': '本店招牌是河岸冷萃。',
              'auditStatus': 1,
              'enabled': 1,
              'statusText': '已过审 · 已开启',
              'hasVoice': true,
            }),
          ),
        ),
      ], const MerchantNpcEditPage()),
      'goldens/page_merchant_npc_edit.png',
    );
  });

  testWidgets('E15 发布活动 · 第一步基本信息', (WidgetTester tester) async {
    await _shot(
      tester,
      // ★ /publish/activity 在真机上走 `_topicEditorLight`(D10⑥「主题编辑器=浅色」,
      //   零投影 + 细线描边),不是商家那档恒浅 —— 用错档会拍出用户看不到的画面。
      _app(<dynamic>[
        publishCapabilityProvider.overrideWith(
          (Ref ref) async => PublishCapability.fromJson(<String, dynamic>{
            'role': 'club',
            'quota': <String, dynamic>{
              'maxThemes': 10,
              'themesOnline': 2,
              'themesRemaining': 8,
            },
          }),
        ),
        categoryApiProvider.overrideWithValue(
          _FakeCategoryApi(<Category>[
            Category.fromJson(<String, dynamic>{
              'id': 3,
              'categoryName': '城市夜行',
            }),
          ]),
        ),
      ], const PublishActivityPage(), theme: topicEditorGoldenTheme()),
      'goldens/page_publish_activity.png',
    );
  });

  testWidgets('E24 主题定价 · 有人带终价确认', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(<dynamic>[
        topicApiProvider.overrideWithValue(
          _FakeTopicApi(
            PricingPreview.fromJson(<String, dynamic>{
              'priceMin': 49,
              'cityReferencePrice': 79,
              'cityReferenceSampleSize': 12,
              'cityReferenceLabel': '上海同类已开售均价',
            }),
          ),
        ),
      ], const TopicPricingPage(topicId: 301)),
      'goldens/page_topic_pricing.png',
    );
  });

  testWidgets('E27 优惠券动态码 · 可用', (WidgetTester tester) async {
    // ★ 假 HttpClient 必须在本用例体内还原:addTearDown 跑在 binding 的
    //   「painting debug 变量未被改过」检查**之后**,会报
    //   `The value of a painting debug variable was changed by the test`。
    await installFakeNetworkImages(tester);
    try {
      await _shot(
        tester,
        // 这页对游客给页内登录门(b1-sim-coupon P1-1):不钉登录态,拍到的
        // 会是「登录后查看核销码」而不是用例要拍的可用码。
        _app(<dynamic>[
          authControllerProvider.overrideWith(
            () => FixedAuth(signedInAuthState()),
          ),
          couponApiProvider.overrideWithValue(
            _FakeCouponApi(
              CouponQr.fromJson(<String, dynamic>{
                'qrcodeUrl': 'https://example.invalid/qr-8801.png',
                'expiresIn': 60,
                'useStatus': 0,
                'couponName': '到店立减 10 元',
                'description': '核销时出示此码',
                'endTime': '2026-09-30 23:59',
              }),
            ),
          ),
        ], const CouponCodePage(couponHistoryId: 8801)),
        'goldens/page_coupon_code.png',
        settle: false,
        settleImages: true,
      );
      // 倒计时是 Timer.periodic:拍照后把页面拆掉,让 dispose 收掉它。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      restoreFakeNetworkImages();
    }
  });

  testWidgets('E29 优惠券创建 · 空表单', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 780));
    await tester.pumpWidget(_app(<dynamic>[], _SheetHost()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-coupon-sheet')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_coupon_publish_sheet.png'),
    );
  });

  testWidgets('E30 据点核销码 · 出码成功', (WidgetTester tester) async {
    await installFakeNetworkImages(tester);
    try {
      await _shot(
        tester,
        _app(
          <dynamic>[
            roamApiProvider.overrideWithValue(
              _FakeRoamApi(
                CityNodeVoucher.fromJson(<String, dynamic>{
                  'code': 'CY-701-8392',
                  'qrcodeUrl': 'https://example.invalid/qr-701.png',
                  'ttlMs': 236000,
                }),
              ),
            ),
          ],
          const CityNodeVoucherPage(poiId: 701, name: '河畔咖啡'),
          light: false,
        ),
        'goldens/page_city_node_voucher.png',
        settle: false,
        settleImages: true,
      );
      // 倒计时是 Timer.periodic:拍照后把页面拆掉,让 dispose 收掉它。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      restoreFakeNetworkImages();
    }
  });
}

/// 优惠券创建 sheet 的宿主:半屏需要真实 Navigator + 一个真的打开动作。
class _SheetHost extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: CupertinoButton(
        key: const Key('open-coupon-sheet'),
        onPressed: () => showCouponPublishSheet(context),
        child: const Text('发券'),
      ),
    ),
  );
}
