// 商家 / 账号 / 漫游 散页金图 · 批次2 —— F02 / F06 / F09 / F12 / F25–F29。
//
// 九个 shot 都是**空态 / 缺参 / 无权限 / 兜底**那一档:夹具只回答「后端明确说什么」,
// 不补造条目(这正是这些 shot 备注点名的口径:空态不伪造成员、无权限不显示 ¥0)。
//
// 主题:商家页恒浅(`merchantGoldenTheme`,与 app_router 的 _merchantLight 一致),
// 玩家页(勋章 / 漫游据点 / 地址)恒暗。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_golden_batch2_merchant_misc_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_aftercare_api.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/api/merchant_customer_detail_api.dart';
import 'package:chengyin_app/data/api/merchant_operator_api.dart';
import 'package:chengyin_app/data/api/merchant_review_api.dart';
import 'package:chengyin_app/data/api/roam_api.dart';
import 'package:chengyin_app/data/models/city_node_detail.dart';
import 'package:chengyin_app/data/models/merchant_finance.dart';
import 'package:chengyin_app/data/models/merchant_aftercare.dart';
import 'package:chengyin_app/data/models/merchant_operator.dart';
import 'package:chengyin_app/data/models/merchant_review.dart';
import 'package:chengyin_app/feature/account/address_edit_page.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/merchant/batch_detail_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_aftercare_detail_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_aftercare_list_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_customer_detail_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_operator_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_reviews_page.dart';
import 'package:chengyin_app/feature/p3/badges/badge_detail_logic.dart';
import 'package:chengyin_app/feature/p3/badges/badge_detail_page.dart';
import 'package:chengyin_app/feature/roam/roam_poi_detail_page.dart';

import '../support/fixed_auth.dart';
import 'golden_theme.dart';

Widget _app(List<dynamic> overrides, Widget home, {bool light = false}) =>
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        theme: light ? merchantGoldenTheme() : goldenTheme(),
        debugShowCheckedModeBanner: false,
        home: home,
      ),
    );

Future<void> _shot(
  WidgetTester tester,
  Widget app,
  String goldenPath, {
  bool settle = true,
}) async {
  setGoldenViewport(tester, const Size(390, 844));
  await tester.pumpWidget(app);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

// ── 假 API ──────────────────────────────────────────────────────────

/// F25 售后待回应:后端明确说这一档为空。
class _FakeAftercareApi implements MerchantAftercareGateway {
  @override
  Future<MerchantAftercarePage> listPage({
    required MerchantAftercareBucket bucket,
    required int pageNum,
    required int pageSize,
  }) async => MerchantAftercarePage(
    bucket: bucket,
    pageNum: pageNum,
    pageSize: pageSize,
    total: 0,
    hasMore: false,
    items: const <MerchantAftercareListItem>[],
  );

  @override
  Future<MerchantAftercareDetail> detail({required int refundId}) async =>
      throw MerchantApiException('这张退款单不存在或已被处理');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('本快照只用到读接口: $invocation');
}

/// F27 口碑管理:一屏没有任何评价。
class _FakeReviewApi implements MerchantReviewGateway {
  @override
  Future<MerchantReviewPage> managePage({
    required int pageNum,
    required int pageSize,
  }) async => MerchantReviewPage(
    pageNum: pageNum,
    pageSize: pageSize,
    total: 0,
    hasMore: false,
    averageRating: 0,
    items: const <MerchantReviewItem>[],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('本快照只用到读接口: $invocation');
}

/// F28 客户详情:身份是激活的,但**没有 CRM 查看权限** —— 这一格不能显示 ¥0。
class _FakeCustomerApi implements MerchantCustomerDetailGateway {
  @override
  Future<MerchantCustomerAccess> access() async => const MerchantCustomerAccess(
    active: true,
    merchantId: 1,
    roleCode: 'STAFF',
    permissions: <String>{},
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('无权限态不该再去读详情: $invocation');
}

/// F29 经营团队:没有员工、没有待接受邀请。
class _FakeOperatorApi implements MerchantOperatorGateway {
  @override
  Future<MerchantOperatorAccess> access() async => const MerchantOperatorAccess(
    active: true,
    merchantId: 1,
    merchantName: '河畔咖啡',
    merchantLogo: '',
    roleCode: 'OWNER',
    permissions: <String>{},
    canManageOperators: true,
  );

  @override
  Future<List<MerchantAssignableRole>> roles() async =>
      const <MerchantAssignableRole>[];

  @override
  Future<MerchantTeam> team() async => const MerchantTeam(
    operators: <MerchantOperator>[],
    invites: <MerchantOperatorInvite>[],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('本快照只用到读接口: $invocation');
}

/// F12 据点详情:后端明确说这个据点不存在(缺参打到的就是这条)。
class _FakeRoamApi implements RoamApi {
  @override
  Future<CityNodeDetail> nodeDetail(int poiId) async =>
      throw Exception('节点不存在');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('缺参态不该再读别的: $invocation');
}

void main() {
  testWidgets('F02 勋章 3D · 静态兜底', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        <dynamic>[],
        const BadgeDetailPage(
          params: BadgeDetailParams(
            name: '夜行者',
            sub: '在夜里走过三条河岸',
            img: '',
            style: 'glow',
            rarity: 2,
          ),
        ),
      ),
      'goldens/page_badge_detail_fallback.png',
    );
  });

  testWidgets('F06 对公批次明细 · 缺 batchId', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        <dynamic>[
          batchDetailProvider(0).overrideWith(
            (Ref ref) => Future<PublicTransferBatchDetail>.error(
              MerchantApiException('缺少批次号,请从账本重新进入'),
            ),
          ),
        ],
        const BatchDetailPage(batchId: 0),
        light: true,
      ),
      'goldens/page_batch_detail_missing_param.png',
    );
  });

  testWidgets('F09 参与人信息 · 新建空表单', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(<dynamic>[], const AddressEditPage()),
      'goldens/page_address_edit_new.png',
    );
  });

  testWidgets('F12 据点详情 · 缺 poiId', (WidgetTester tester) async {
    await _shot(
      tester,
      // ★ 这页对游客给页内登录门(#208 范式)。不钉登录态,拍到的会是
      //   「登录后查看这个据点」而不是用例要拍的缺参态。
      _app(<dynamic>[
        roamApiProvider.overrideWithValue(_FakeRoamApi()),
        authControllerProvider.overrideWith(() => FixedAuth(signedInAuthState())),
      ], const RoamPoiDetailPage(poiId: 0)),
      'goldens/page_roam_poi_detail_missing_param.png',
    );
  });

  testWidgets('F25 售后待回应 · 空态', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        <dynamic>[],
        MerchantAftercareListPage(
          api: _FakeAftercareApi(),
          onOpenDetail: (_) {},
        ),
        light: true,
      ),
      'goldens/page_merchant_aftercare_empty.png',
    );
  });

  testWidgets('F26 售后详情 · 缺 refundId', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        <dynamic>[],
        MerchantAftercareDetailPage(
          api: _FakeAftercareApi(),
          refundId: 0,
          evidencePicker: null,
          requestIdFactory: () => 'golden-request',
          confirmEvidencePurpose: (BuildContext context) async => true,
          openSystemSettings: () async => true,
        ),
        light: true,
      ),
      'goldens/page_merchant_aftercare_detail_missing_param.png',
    );
  });

  testWidgets('F27 口碑管理 · 空态', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        <dynamic>[],
        MerchantReviewsPage(
          api: _FakeReviewApi(),
          requestIdFactory: (_) => 'golden-request',
        ),
        light: true,
      ),
      'goldens/page_merchant_reviews_empty.png',
    );
  });

  testWidgets('F28 客户详情 · 无 CRM 权限', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        <dynamic>[],
        MerchantCustomerDetailPage(
          api: _FakeCustomerApi(),
          customerMemberId: 1,
        ),
        light: true,
      ),
      'goldens/page_merchant_customer_detail_permission.png',
    );
  });

  testWidgets('F29 经营团队 · 无员工空态', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        <dynamic>[],
        MerchantOperatorPage(api: _FakeOperatorApi()),
        light: true,
      ),
      'goldens/page_merchant_team_empty.png',
    );
  });
}
