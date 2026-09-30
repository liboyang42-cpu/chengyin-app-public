// 账户域三页快照:提现记录 / 我的收藏 / 我走过的。
//
// 这三页此前零 golden 覆盖,且都属于「用户会反复回来看」的页面 ——
// 长得不对不会崩,但每次打开都别扭。
//
// fixture 一律造边界形态:
//   提现记录:四种状态同屏 + 短账号(不该做半截掩码)
//   我的收藏:无封面 + 超长标题
//   我走过的:进度 0 / 进行中 / 已完成 —— 三档的说法必须不同
//
// 更新基准图:flutter test --update-goldens test/golden/pages_account_extra_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/completed_play.dart';
import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/data/models/withdrawal.dart';
import 'package:chengyin_app/feature/account/my_likes_page.dart';
import 'package:chengyin_app/feature/play/my_plays_page.dart';
import 'package:chengyin_app/feature/withdrawal/withdrawal_page.dart';
import 'package:chengyin_app/feature/withdrawal/withdrawal_records_page.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';

import '../support/fixed_auth.dart';
import 'golden_theme.dart';

Widget _app(List<dynamic> overrides, Widget home) {
  return ProviderScope(
    overrides: <dynamic>[
      // 提现记录页有页内登录门(roam #208 模式),golden 拍的是登录后的正文。
      authControllerProvider.overrideWith(() => FixedAuth(signedInAuthState())),
      ...overrides,
    ].cast(),
    child: MaterialApp(
      theme: goldenTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

Future<void> _shot(WidgetTester tester, Widget app, String goldenPath) async {
  setGoldenViewport(tester, const Size(390, 860));
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

/// 提现记录页 A5 后正文改走 CyType(family=null),快照宿主是 MaterialApp,
/// 裸 TextStyle 会落到 flutter_test 默认族上变豆腐 —— 补回真机 CupertinoApp
/// 的那层字族继承(口径同 pages_official_points_golden_test.dart:_pointsApp)。
/// ⚠️ 只包提现记录这一页:另两页基线未动,不借这趟车改它们的渲染。
Widget _cyTypeHome(Widget home) => DefaultTextStyle(
  style: const TextStyle(fontFamily: 'Roboto'),
  child: home,
);

void main() {
  testWidgets('提现记录:四种状态同屏 + 短账号不做半截掩码', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        withdrawalRecordsProvider.overrideWith(
          (ref) async => <WithdrawalRecord>[
            WithdrawalRecord.fromJson(<String, dynamic>{
              'id': 1,
              'amount': 200.0,
              'status': 0,
              'bankName': '招商银行',
              'bankAccount': '6225880123456789',
              'createTime': '2026-08-18 10:20:00',
            }),
            WithdrawalRecord.fromJson(<String, dynamic>{
              'id': 2,
              'amount': 88.5,
              'status': 1,
              'bankName': '工商银行',
              'bankAccount': '6222021234567890',
              'createTime': '2026-08-15 09:00:00',
            }),
            // ★ 被驳回:必须能看到原因,只写「失败」等于没说
            WithdrawalRecord.fromJson(<String, dynamic>{
              'id': 3,
              'amount': 500.0,
              'status': 2,
              'bankName': '建设银行',
              'bankAccount': '6217001234567890',
              'createTime': '2026-08-12 16:40:00',
              'remark': '开户名与实名信息不一致',
            }),
            // ★ 账号本来就短 —— 不该渲成「****」把全部盖掉
            WithdrawalRecord.fromJson(<String, dynamic>{
              'id': 4,
              'amount': 12.0,
              'status': 0,
              'bankName': '测试行',
              'bankAccount': '1234',
              'createTime': '2026-08-19 08:00:00',
            }),
          ],
        ),
      ], _cyTypeHome(const WithdrawalRecordsPage())),
      'goldens/page_withdrawal_records.png',
    );
  });

  testWidgets('我的收藏:无封面 + 超长标题', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        myLikesProvider.overrideWith(
          (ref) async => <Topic>[
            Topic.fromJson(<String, dynamic>{
              'id': 1,
              'name': '静安微旅行',
              'introduction': '两小时走完六个小马路口。',
            }),
            Topic.fromJson(<String, dynamic>{
              'id': 2,
              'name': '一个特别特别长的主题名字用来检验收藏列表里的标题会不会把卡片撑坏',
              'introduction': '副标题也来一段长的,看两行截断之后省略号落在哪里。',
            }),
          ],
        ),
      ], const MyLikesPage()),
      'goldens/page_my_likes.png',
    );
  });

  testWidgets('★ 我走过的:未开始 / 进行中 / 已完成 三档说法必须不同', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        myCompletedPlaysProvider.overrideWith(
          (ref) async => <CompletedPlay>[
            CompletedPlay.fromJson(<String, dynamic>{
              'name': '静安夜跑',
              'activityId': 1,
              'total': 6,
              'doneCount': 6,
              'completed': true,
            }),
            CompletedPlay.fromJson(<String, dynamic>{
              'name': '徐汇咖啡巡礼',
              'activityId': 2,
              'total': 8,
              'doneCount': 3,
            }),
            // ★ 一个点都没走:「0/5」和「还没开始」是两种说法,
            //   渲成 0/5 会让人以为已经在进行中了
            CompletedPlay.fromJson(<String, dynamic>{
              'name': '刚领还没走的一条',
              'activityId': 3,
              'total': 5,
              'doneCount': 0,
            }),
          ],
        ),
      ], const MyPlaysPage()),
      'goldens/page_my_plays.png',
    );
  });
}
