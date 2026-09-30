// Wave-C/D 表单与券码:C25 路线详情缺参 · C04/C05/C06 商家入驻
// 三步 · C38 主理人申请表 · D17/D18 券码出示(正常 / 二维码失败)。
//
// 每条对小程序 shot-matrix 的 state:
//   · C04/C06 是**同一页的正负对照**:填了名称+手机 → 主按钮可点;
//     什么都没填 → 主按钮禁用 + 一行说清缺什么。只拍一张看不出这段逻辑。
//   · C05 是第二步(经营信息),不填满就不会有「提交」的假象。
//   · C38 的判据来自 `/api/role/info` 的 canCreateClub,不自己从 role 推。
//   · D18 的二维码失败**只换码卡**,页面其余部分(券名/有效期)留着 ——
//     整屏报错会让用户以为券没了。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_wave_cd_form_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/coupon_api.dart';
import 'package:chengyin_app/data/models/coupon.dart';
import 'package:chengyin_app/data/models/role_info.dart';
import 'package:chengyin_app/core/role_provider.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/club/club_apply_page.dart';
import 'package:chengyin_app/feature/coupon/coupon_code_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_apply_page.dart';
import 'package:chengyin_app/feature/topic/topic_detail_controller.dart';
import 'package:chengyin_app/feature/topic/topic_detail_page.dart';

import '../support/fixed_auth.dart';
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

/// 券码页只要这两条:换码 + 核销状态。其余方法本页不碰。
class _FakeCouponApi implements CouponApi {
  _FakeCouponApi({this.qrError, this.useStatus = 1});

  final Object? qrError;

  /// 待使用(0)还是已核销(1)决定页面走亮码态还是结果页 —— 必须可注入,
  /// 否则 qrError 分支被 `_useStatus != 0 → _buildResult()` 短路,永远拍不到。
  final int useStatus;

  @override
  Future<CouponQr> qrToken(int couponHistoryId) async {
    if (qrError != null) throw qrError!;
    return CouponQr.fromJson(<String, dynamic>{
      'qrcodeUrl': 'https://cdn.example.com/qr.png',
      'expiresIn': 60,
      'useStatus': useStatus,
      'couponName': '到店立减 10 元',
    });
  }

  @override
  Future<CouponStatus> status(int couponHistoryId) async =>
      CouponStatus.fromJson(<String, dynamic>{'useStatus': useStatus});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const RoleInfo _playerRole = RoleInfo(
  role: 'player',
  permission: <String, dynamic>{'canCreateClub': true},
  usage: <String, dynamic>{},
  isClubLeader: false,
  isMerchant: false,
  ownedClubCount: 0,
  maxOwnedClubs: 2,
  ownedClubs: <Map<String, dynamic>>[],
  joinedClubIds: <int>[],
);

void main() {
  testWidgets('C25 路线详情:缺主题编号', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        topicDetailProvider(
          0,
        ).overrideWith((Ref ref) async => throw Exception('缺少主题信息')),
      ], const TopicDetailPage(topicId: 0)),
    );
    await tester.pumpAndSettle();
    expect(find.text('没能打开这条路线'), findsOneWidget);
    await _shot(tester, 'goldens/page_topic_detail_missing_param.png');
  });

  testWidgets('C04 商家入驻:第一步已填(主按钮可点)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(
        <dynamic>[
          merchantApplicationProvider.overrideWith((Ref ref) async => null),
        ],
        const MerchantApplyPage(),
        theme: merchantGoldenTheme(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('merchant-apply-name')),
      '城瘾示例店',
    );
    await tester.enterText(
      find.byKey(const Key('merchant-apply-phone')),
      '13800138000',
    );
    await tester.pumpAndSettle();
    await _shot(tester, 'goldens/page_merchant_apply_step1.png');
  });

  testWidgets('C05 商家入驻:第二步(经营信息)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(
        <dynamic>[
          merchantApplicationProvider.overrideWith((Ref ref) async => null),
        ],
        const MerchantApplyPage(),
        theme: merchantGoldenTheme(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('merchant-apply-name')),
      '城瘾示例店',
    );
    await tester.enterText(
      find.byKey(const Key('merchant-apply-phone')),
      '13800138000',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('merchant-apply-next')));
    await tester.pumpAndSettle();
    expect(find.text('入驻申请 · 经营信息'), findsOneWidget);
    await _shot(tester, 'goldens/page_merchant_apply_step2.png');
  });

  testWidgets('C06 商家入驻:必填未完成(主按钮禁用)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(
        <dynamic>[
          merchantApplicationProvider.overrideWith((Ref ref) async => null),
        ],
        const MerchantApplyPage(),
        theme: merchantGoldenTheme(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('请填写品牌名称'), findsOneWidget);
    await _shot(tester, 'goldens/page_merchant_apply_step1_blocked.png');
  });

  testWidgets('C38 主理人申请:申请表', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        roleInfoProvider.overrideWith((Ref ref) async => _playerRole),
      ], const ClubApplyPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('主理人实名'), findsWidgets);
    await _shot(tester, 'goldens/page_club_apply_form.png');
  });

  // 页内有登录门(build 观测 authControllerProvider 后才启动状态机):
  // 不 override 登录态,两张 shot 会双双拍「去登录」页而**照样绿** ——
  // b1-reverify-round95 实证旧基线正是这种假覆盖(成对 blob 相同的根因)。
  // 登录后 useStatus=1 会起倒计时/轮询周期定时器,pumpAndSettle 永不安稳,
  // 一律用有界 pump。
  testWidgets('D17 券码出示:已核销态', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        authControllerProvider.overrideWith(
          () => FixedAuth(signedInAuthState()),
        ),
        couponApiProvider.overrideWithValue(_FakeCouponApi()),
      ], const CouponCodePage(couponHistoryId: 1)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, 'goldens/page_coupon_code_normal.png');
  });

  // 二维码失败与核销状态是两条链路(真源 onRefreshFail):券仍待使用时换码失败,
  // 只把码卡切错误态,页体/倒计时骨架留在屏上 —— 故 useStatus 必须给 0。
  testWidgets('D18 券码出示:二维码失败只换码卡', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        authControllerProvider.overrideWith(
          () => FixedAuth(signedInAuthState()),
        ),
        couponApiProvider.overrideWithValue(
          _FakeCouponApi(qrError: Exception('二维码暂时没能生成'), useStatus: 0),
        ),
      ], const CouponCodePage(couponHistoryId: 1)),
    );
    await tester.pump(); // 让 qrToken 的 Future 落地 → _qrState=error
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, 'goldens/page_coupon_code_error.png');
  });
}
