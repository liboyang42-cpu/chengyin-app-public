// 商家侧零散页面快照:订单 / 店铺资料 / 公开主页 / 增值服务 / 可邀请的俱乐部 /
// 我发布的券。六个页面此前接口写好了但没人调,现在接上了,先看一眼长什么样。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_merchant_misc_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/coupon/my_published_coupons_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_clubs_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_edit_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_orders_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_public_home_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_subscription_page.dart';
import 'golden_theme.dart';

class _FixedAuth extends AuthController {
  _FixedAuth(this.fixed);
  final AuthState fixed;

  @override
  AuthState build() => fixed;
}

/// 券页现在对游客给页内登录门(b1-sim-coupon P1-1),基线拍的是登录态。
final List<dynamic> _signedIn = <dynamic>[
  authControllerProvider.overrideWith(
    () => _FixedAuth(
      AuthState(
        user: User(id: 1, nickname: '店长', avatar: '', role: 'merchant'),
        initialized: true,
      ),
    ),
  ),
];

Widget _app(List<dynamic> overrides, Widget home) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: merchantGoldenTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

/// ★ [goldenPath] 必须是字面量,别插值拼接——no_orphan_goldens_test 靠源码里的
/// 字面量文件名判断基线有没有人引用。
Future<void> _shot(WidgetTester tester, Widget app, String goldenPath) async {
  setGoldenViewport(tester, const Size(390, 900));
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

void main() {
  testWidgets('订单:三种状态同屏(含售后)', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        merchantOrdersProvider.overrideWith(
          (ref) async => <Map<String, dynamic>>[
            <String, dynamic>{
              'orderSn': '2026081900001',
              'status': 0,
              'createTime': '2026-08-19 10:00:00',
              // payAmount 缺席 —— 该显示破折号
            },
            <String, dynamic>{
              'orderSn': '2026081800002',
              'status': 4,
              'createTime': '2026-08-18 09:00:00',
              'payAmount': 128.0,
            },
            <String, dynamic>{
              'orderSn': '2026081700003',
              'status': 4,
              'createTime': '2026-08-17 20:00:00',
              'payAmount': 38.5,
              'aftersaleStatus': 3,
            },
          ],
        ),
      ], const MerchantOrdersPage()),
      'goldens/merchant_orders.png',
    );
  });

  testWidgets('店铺资料:已填的六个字段', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        merchantInfoProvider.overrideWith(
          (ref) async => <String, dynamic>{
            'id': 42,
            'memberId': 100096,
            'name': '静安咖啡',
            'description': '一杯咖啡的城市',
            'derivatives': '手冲挂耳',
            'website': 'https://example.com',
            'preference': '咖啡 · 甜点',
            'logo': '',
          },
        ),
      ], const MerchantEditPage()),
      'goldens/merchant_edit.png',
    );
  });

  testWidgets('★ 公开主页:businessStatus 缺席时不宣称营业状态', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        merchantPublicHomeProvider(7).overrideWith(
          (ref) async => <String, dynamic>{
            'id': 7,
            'name': '静安咖啡',
            'slogan': '一杯咖啡的城市',
            'cityRole': '夜归人的最后一站',
            'address': '南京西路 1266 号',
            'gallery': 'a.jpg;b.jpg',
            'tags': '安静;适合工作',
          },
        ),
      ], const MerchantPublicHomePage(memberId: 7)),
      'goldens/merchant_public_home.png',
    );
  });

  testWidgets('★ 增值服务:endDate 缺席显永久有效', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        merchantSubscriptionsProvider.overrideWith(
          (ref) async => <Map<String, dynamic>>[
            <String, dynamic>{
              'subscriptionType': 'premium_template',
              'maxUsage': 3,
              'usedCount': 1,
            },
          ],
        ),
        merchantCommerceCapabilitiesProvider.overrideWith(
          (ref) async => <String, dynamic>{
            'selfCheckoutEnabled': false,
            'premiumTemplate': <String, dynamic>{
              'limit': 2,
              'used': 1,
              'remaining': 1,
            },
            'cityNode': <String, dynamic>{
              'limit': 3,
              'used': 0,
              'remaining': 3,
            },
          },
        ),
      ], const MerchantSubscriptionPage()),
      'goldens/merchant_subscription.png',
    );
  });

  testWidgets('可邀请的俱乐部:名称/城市/人数', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        merchantClubsProvider('').overrideWith(
          (ref) async => <Map<String, dynamic>>[
            <String, dynamic>{
              'name': '夜跑俱乐部',
              'city': '上海',
              'memberCount': 128,
            },
            // 人数缺席 —— 不该拼出孤零零的「· 」
            <String, dynamic>{'name': '骑行社', 'city': '杭州'},
          ],
        ),
      ], const MerchantClubsPage()),
      'goldens/merchant_clubs.png',
    );
  });

  testWidgets('我发布的券:发行/已领/已核销三个数', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        ..._signedIn,
        myPublishedCouponsProvider.overrideWith(
          (ref) async => <Map<String, dynamic>>[
            <String, dynamic>{
              'name': '开业九折券',
              'status': 1,
              'couponType': 1,
              'description': '全场饮品第二杯半价',
              'publishCount': 100,
              'receiveCount': 40,
              'useCount': 12,
              'startTime': '2026-08-01 00:00:00',
              'endTime': '2026-09-01 00:00:00',
            },
          ],
        ),
      ], const MyPublishedCouponsPage()),
      'goldens/my_published_coupons.png',
    );
  });
}
