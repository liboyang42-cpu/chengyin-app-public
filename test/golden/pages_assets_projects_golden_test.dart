// 资产明细 / 我的发布 两页的整页快照。
//
// ⚠️ 看图时注意到收/支只有 +/- 符号、没有颜色区分。**没有改** ——
//   小程序侧没有对应的积分明细页(subpackageA/assetcenter 只有 earnings /
//   income-detail),这是 App 独有的页,没有可比对的参照。
//   符号本身已经表达了方向,加颜色是我的偏好而不是契约要求。
//   若将来要加,判据应取自 CyTokens.statusSuccess/statusDanger,
//   并且**不能靠颜色单独承载方向**(色觉障碍用户看不到)——符号必须保留。
//
// fixture 造语义边界:
//   · 积分流水:changeType **缺席**的那条 —— 不能落成"支出",
//     要靠金额符号判方向(模型注释里写死的规则,这里拍出来盯住渲染层);
//   · 我的发布:三种 bizType 混排 + 状态文案(含状态缺席那条)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/role_provider.dart';
import 'package:chengyin_app/data/models/asset_record.dart';
import 'package:chengyin_app/data/models/my_project.dart';
import 'package:chengyin_app/data/models/role_info.dart';
import 'package:chengyin_app/feature/assets/assets_page.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/publish/my_projects_page.dart';
import '../support/fixed_auth.dart';
import 'golden_theme.dart';

const RoleInfo _withdrawableRole = RoleInfo(
  role: 'player',
  permission: <String, dynamic>{'withdrawable': true},
  usage: <String, dynamic>{},
  isClubLeader: false,
  isMerchant: false,
  ownedClubCount: 0,
  maxOwnedClubs: 0,
  ownedClubs: <Map<String, dynamic>>[],
  joinedClubIds: <int>[],
);

Widget _app(List<dynamic> overrides, Widget home) => ProviderScope(
  overrides: overrides.cast(),
  child: MaterialApp(
    theme: goldenTheme(),
    debugShowCheckedModeBanner: false,
    home: home,
  ),
);

Future<void> _shot(
  WidgetTester t,
  Widget app,
  String path, {
  Size size = const Size(390, 1000),
}) async {
  setGoldenViewport(t, size);
  await t.pumpWidget(app);
  await t.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(path));
}

void main() {
  testWidgets('★★ 资产明细:changeType 缺席那条不能显示成支出', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(<dynamic>[
        // 资产页对游客是页内登录门(#276 P1-1),golden 拍的是登录后账本。
        authControllerProvider.overrideWith(
          () => FixedAuth(signedInAuthState()),
        ),
        roleInfoProvider.overrideWith((ref) async => _withdrawableRole),
        pointsListProvider.overrideWith(
          (ref) async => <PointsRecord>[
            PointsRecord.fromJson(<String, dynamic>{
              'id': 1,
              'changePoints': 20,
              'afterPoints': 120,
              'changeReason': '完成节点打卡',
              'changeType': 1,
              'createTime': '08-19 14:30',
            }),
            PointsRecord.fromJson(<String, dynamic>{
              'id': 2,
              'changePoints': -50,
              'afterPoints': 70,
              'changeReason': '兑换优惠券',
              'changeType': 2,
              'createTime': '08-19 15:02',
            }),
            // ★ changeType 缺席:方向只能看金额符号。
            //   落成"支出"的话,这笔 +30 会显示成扣分。
            PointsRecord.fromJson(<String, dynamic>{
              'id': 3,
              'changePoints': 30,
              'afterPoints': 100,
              'changeReason': '后端没下发方向的那条',
              'createTime': '08-19 16:10',
            }),
          ],
        ),
        balanceListProvider.overrideWith((ref) async => <BalanceRecord>[]),
        // 余额三段(余额 Tab 才可见,这张拍的是积分 Tab):不覆盖会在真机上
        // 发请求,测试环境该 request 永不完成,骨架动画让 pumpAndSettle 超时。
        walletStagesProvider.overrideWith((ref) async => null),
      ], const AssetsPage()),
      'goldens/page_assets_points.png',
    );

    // ★ golden 的差异只有 0.01%(一个 + 变 -),太容易被当成渲染噪声放过。
    //   再加一条文字断言:那条缺方向的记录必须是 +30,不是 -30。
    expect(
      find.text('+30'),
      findsOneWidget,
      reason: 'changeType 缺席时落成了支出 —— 一笔收入被显示成扣分',
    );
    expect(find.text('-30'), findsNothing);
  });

  testWidgets('★ 我的发布:三种类型混排', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(<dynamic>[
        myProjectsProvider.overrideWith(
          (ref) async => <MyProject>[
            MyProject.fromJson(<String, dynamic>{
              'id': 1,
              'bizType': 'topic',
              'title': '静安夜行',
              'projectTypeText': '经典定向',
              'stateText': '已上线',
            }),
            MyProject.fromJson(<String, dynamic>{
              'id': 2,
              'bizType': 'activity',
              'title': '周末城南骑行',
              'projectTypeText': '活动',
              'stateText': '报名中',
            }),
            // ★ 状态文案缺席 —— 别渲成空白
            MyProject.fromJson(<String, dynamic>{
              'id': 3,
              'bizType': 'template',
              'title': '一杯手冲的暗号',
            }),
          ],
        ),
      ], const MyProjectsPage()),
      'goldens/page_my_projects.png',
    );
  });

  testWidgets('★ 我的发布:空态', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(<dynamic>[
        myProjectsProvider.overrideWith((ref) async => <MyProject>[]),
      ], const MyProjectsPage()),
      'goldens/page_my_projects_empty.png',
    );
  });
}
