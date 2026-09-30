// 合作域整页快照。这四页在小程序里同样走**浅色**(pages/coop/{list,finance,
// nearby,candidates} 都 @import merchant-light.wxss 且无条件 onShow 切浅色),
// App 这边一直是黑底。拍图是为了确认换底之后没留下「白卡白字」——
// 商家域换底时就撞到过:页面底色跟着主题走了,页面里硬编码的颜色没跟。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_coop_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/coop_candidate.dart';
import 'package:chengyin_app/data/models/coop_finance.dart';
import 'package:chengyin_app/data/models/coop_invite_row.dart';
import 'package:chengyin_app/data/models/coop_mybiz.dart';
import 'package:chengyin_app/data/models/coop_pool.dart';
import 'package:chengyin_app/data/models/coop_perk_template.dart';
import 'package:chengyin_app/feature/coop/coop_candidates_page.dart';
import 'package:chengyin_app/feature/coop/coop_finance_page.dart';
import 'package:chengyin_app/feature/coop/coop_list_page.dart';
import 'package:chengyin_app/feature/coop/coop_mybiz_page.dart';
import 'package:chengyin_app/feature/coop/coop_perk_template_page.dart';
import 'package:chengyin_app/feature/coop/coop_settlement_detail_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_coop_page.dart'
    show merchantInvitesProvider;
import 'golden_theme.dart';

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

Future<void> _shot(WidgetTester tester, Widget app, String goldenPath) async {
  setGoldenViewport(tester, const Size(390, 900));
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

void main() {
  testWidgets('★ 合作财务:我的分成待结算(null 不是 0)', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        coopFinanceProvider.overrideWith(
          (ref) async => <CoopFinanceRow>[
            CoopFinanceRow.fromJson(<String, dynamic>{
              'topicId': 1,
              'topicName': '静安夜跑',
              'settled': true,
              'totalSales': '4820.00',
              'verifiedSales': '4210.00',
              'merchantTotal': '1200.00',
              'merchantPaid': '1200.00',
              'myIncome': '820.00',
              'myIncomeArrived': true,
            }),
            // ★ myIncome 缺席 = 分成还没算出来,不是「我赚了 0 元」。
            //   浅色底下这一格必须仍读得出「待结算」,不能变成一片空白。
            CoopFinanceRow.fromJson(<String, dynamic>{
              'topicId': 2,
              'topicName': '徐汇咖啡巡礼',
              'totalSales': '1560.00',
              'merchantTotal': '400.00',
            }),
          ],
        ),
      ], const CoopFinancePage()),
      'goldens/coop_finance.png',
    );
  });

  testWidgets('★ 主办分润详情:平台服务费与到账进度完整', (WidgetTester tester) async {
    const key = CoopSettlementRef(source: 'finance', recordId: '88');
    await _shot(
      tester,
      _app([
        coopSettlementDetailProvider(key).overrideWith(
          (ref) async => const CoopSettlementDetail.finance(
            CoopFinanceRow(
              topicId: 88,
              topicName: '夜游苏河',
              settled: true,
              totalSales: '300.00',
              verifiedSales: '200.00',
              platformAmount: '20.00',
              merchantTotal: '120.00',
              myIncome: '60.00',
              merchantPayableTime: '2026-08-29 12:30:00',
              merchantPayoutTime: '2026-08-30 09:15:00',
            ),
          ),
        ),
      ], const CoopSettlementDetailPage(source: 'finance', recordId: '88')),
      'goldens/coop_settlement_detail_finance.png',
    );
  });

  testWidgets('★ 承接分润详情:创建结算与实际到账进度完整', (WidgetTester tester) async {
    const key = CoopSettlementRef(source: 'ledger', recordId: '71');
    await _shot(
      tester,
      _app([
        coopSettlementDetailProvider(key).overrideWith(
          (ref) async => const CoopSettlementDetail.merchant(
            CoopSettlementRow(
              id: 71,
              topicId: 9,
              topicName: '沿江骑行日',
              amount: 38.5,
              status: 1,
              payeeType: 'merchant',
              shareMode: 1,
              shareRate: 15,
              verifiedHeads: 3,
              verifiedSales: 128,
              createTime: '2026-08-20 08:03:22',
              settleTime: '2026-08-21 10:30:00',
              payoutTime: '2026-08-22 09:16:00',
            ),
          ),
        ),
      ], const CoopSettlementDetailPage(source: 'ledger', recordId: '71')),
      'goldens/coop_settlement_detail_ledger.png',
    );
  });

  testWidgets('★ 常备权益:已失效模板要说清后果,不是内部术语', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        coopPerkTemplatesProvider.overrideWith(
          (ref) async => <CoopPerkTemplate>[
            CoopPerkTemplate.fromJson(<String, dynamic>{
              'id': 1,
              'perkType': 0,
              'name': '手冲咖啡一杯',
              'retailValue': 28.0,
              'unitCost': 9.5,
              'quota': 20,
            }),
            // usable=false(零售价缺失)—— 卡片要说「已失效 · 请重新添加」,
            // 不能显示内部术语「需删除重建」。
            CoopPerkTemplate.fromJson(<String, dynamic>{
              'id': 2,
              'perkType': 1,
              'name': '满100减20券',
              'quota': 0,
            }),
          ],
        ),
      ], const CoopPerkTemplatePage()),
      'goldens/coop_perk_templates.png',
    );
  });

  testWidgets('★ 合作与结算:没有评价 ≠ 评分是 0', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        coopMyBizProvider.overrideWith(
          (ref) async => CoopMyBiz.fromJson(<String, dynamic>{
            'credit': <String, dynamic>{
              'fulfillmentRate': 92,
              'violationCount': 1,
            },
            'review': <String, dynamic>{'avgRating': 0, 'reviewCount': 0},
            'settlements': <dynamic>[
              <String, dynamic>{
                'id': 1,
                'topicId': 12,
                'amount': 168.0,
                'status': 1,
                'payeeType': 'merchant',
                'shareMode': 1,
                'shareRate': 15,
                'verifiedHeads': 8,
              },
              // amount 缺席(待入账)—— 不能画成 ¥0.00。
              <String, dynamic>{'id': 2, 'topicId': 13, 'status': 0},
            ],
          }),
        ),
      ], const CoopMyBizPage()),
      'goldens/coop_mybiz.png',
    );
  });

  testWidgets('★ 我的合作:收到的邀约(联系方式受闸,不是每条都有)', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        // 带队申请这一路(`/api/coop/pool/received`)。★ 同样必须桩掉:
        // 不桩就是发真请求 + 转圈指示器让 pumpAndSettle 永远等不到静止。
        coopPoolAppliesProvider('received').overrideWith(
          (ref) async => <CoopPoolApply>[
            CoopPoolApply.fromJson(<String, dynamic>{
              'applyId': 31,
              'topicId': 12,
              'status': 0,
              'clubId': 7,
              'clubName': '夜行者俱乐部',
              'merchantNick': '老街咖啡',
              'topicName': '静安夜跑',
              'message': '带过 30 人,可自带补给',
              'startDate': '2026-10-01 09:00:00',
            }),
          ],
        ),
        coopPoolAppliesProvider('sent').overrideWith(
          (ref) async => const <CoopPoolApply>[],
        ),
        // 承接报名是本页的第三块(另一条端点)。这张快照只拍原来那两路,
        // 报名块自身由 test/feature/coop/coop_received_regs_test.dart 覆盖。
        coopReceivedRegsProvider.overrideWith(
          (ref) async => const <CoopReceivedRegistration>[],
        ),
        // 官方邀约(平台→商家)是同页的第四块,不桩就是真请求 + 转圈。
        // 这张基线快照拍的是原来的两路,块自身由 coop_received_regs_test.dart 覆盖。
        merchantInvitesProvider.overrideWith((ref) async => const []),
        coopInviteListProvider.overrideWith(
          (ref) async => CoopInviteList.fromJson(<String, dynamic>{
            'sent': <dynamic>[],
            'received': <dynamic>[
              <String, dynamic>{
                'id': 1,
                'inviteType': 0,
                'fromId': 5,
                'toType': 'merchant',
                'toId': 9,
                'topicId': 12,
                'status': 1,
                'shareMode': 1,
                'shareRate': 15,
                'partner': <String, dynamic>{
                  'name': '静安夜跑俱乐部',
                  'leaderName': '李四',
                  'phone': '13900002222',
                },
              },
              <String, dynamic>{
                'id': 2,
                'inviteType': 0,
                'fromId': 6,
                'toType': 'merchant',
                'toId': 9,
                'topicId': 13,
                'status': 0,
                'partner': <String, dynamic>{'name': '徐汇咖啡巡礼'},
              },
            ],
          }),
        ),
      ], const CoopListPage()),
      'goldens/coop_list.png',
    );
  });

  testWidgets('★ 候选池:候选报名要有「确认候选」按钮,不再是死列表', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        coopCandidatesProvider(7).overrideWith(
          (ref) async => CoopCandidates.fromJson(<String, dynamic>{
            'registrations': <dynamic>[
              <String, dynamic>{'id': 101, 'name': '临江咖啡馆'},
            ],
          }),
        ),
      ], const CoopCandidatesPage(topicId: 7)),
      'goldens/coop_candidates_registrations.png',
    );
  });
}
