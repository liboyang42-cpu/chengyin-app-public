// 工作流 P24 金图补齐(批 2)· D/E 段:收益明细 / 消息列表 / 官方活动详情 /
// 附近商家 / 核销详情 / 玩法命名 六页。
//
// 一条 shot = 一张图,状态与夹具口径取自 `/tmp/shot-matrix-master.js` 的同 id 行
// (note 里的验收点)。App 侧一律「implements 真 Api + 只覆写本页会调的方法」,
// 不打网络、不造假页面;clock/时区敏感的字段(倒计时、相对时间)不进夹具 ——
// 那类基准图会自己烂掉(test/golden/no_clock_dependent_goldens_test.dart 有闸)。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_golden_batch2_d_e_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/im_api.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/api/merchant_predict_api.dart';
import 'package:chengyin_app/data/api/official_api.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/data/models/balance_detail.dart';
import 'package:chengyin_app/data/models/im.dart';
import 'package:chengyin_app/data/models/merchant_finance.dart';
import 'package:chengyin_app/data/models/nearby_merchant.dart';
import 'package:chengyin_app/data/models/official_event.dart';
import 'package:chengyin_app/feature/account/income_detail_page.dart';
import 'package:chengyin_app/feature/coop/nearby_merchants_page.dart';
import 'package:chengyin_app/feature/im/im_list_page.dart';
import 'package:chengyin_app/feature/official/official_event_detail_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_redemption_detail_page.dart';
import 'golden_theme.dart';

/// 只覆写本页真正会调的那一个方法;别的真被调到就炸出来,而不是静默返假数据。
class _FakeRegistrationApi implements RegistrationApi {
  _FakeRegistrationApi({
    this.rows = const <BalanceDetail>[],
    this.fail = false,
  });

  final List<BalanceDetail> rows;
  final bool fail;

  @override
  Future<({List<BalanceDetail> rows, num? total})> incomeDetail({
    IncomeEventFilter filter = IncomeEventFilter.all,
    int pageNum = 1,
    int pageSize = 10,
  }) async {
    if (fail) throw Exception('网络请求失败');
    return (rows: rows, total: null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('本快照只用到 incomeDetail');
}

class _FakeImApi implements ImApi {
  _FakeImApi(this.rows);

  final List<Conversation> rows;

  @override
  Future<List<Conversation>> conversations() async => rows;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('本快照只用到 conversations');
}

class _FakeOfficialApi implements OfficialApi {
  _FakeOfficialApi({this.event});

  final OfficialEvent? event;

  @override
  Future<OfficialEvent> detail(int id) async {
    final OfficialEvent? e = event;
    if (e == null) throw Exception('官方活动没能加载出来');
    return e;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('本快照只用到 detail');
}

class _FakeMerchantApi implements MerchantApi {
  _FakeMerchantApi({this.redemption});

  final MerchantRedemptionView? redemption;

  @override
  Future<MerchantRedemptionView> redemptionDetail({
    required String recordId,
    String recordType = 'redemption',
  }) async {
    final MerchantRedemptionView? v = redemption;
    if (v == null) throw Exception('加载失败');
    return v;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('本快照只用到 redemptionDetail');
}

Widget _app(List<dynamic> overrides, Widget home, {bool merchant = false}) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: merchant ? merchantGoldenTheme() : goldenTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

Future<void> _shot(WidgetTester tester, Widget app, String goldenPath) async {
  setGoldenViewport(tester, const Size(390, 780));
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

BalanceDetail _balance({
  required int id,
  String? amount,
  String? reason,
  int? changeType,
  int? eventType,
  String? createTime,
}) => BalanceDetail.fromJson(<String, dynamic>{
  'id': id,
  if (amount != null) 'changeBalance': amount,
  if (reason != null) 'changeReason': reason,
  if (changeType != null) 'changeType': changeType,
  if (eventType != null) 'eventType': eventType,
  if (createTime != null) 'createTime': createTime,
});

Conversation _conv(Map<String, dynamic> json) => Conversation.fromJson(json);

void main() {
  testWidgets('D30 收益明细 · 全部收益空态', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(<dynamic>[
        registrationApiProvider.overrideWithValue(_FakeRegistrationApi()),
      ], const IncomeDetailPage()),
      'goldens/page_income_detail_empty.png',
    );
  });

  testWidgets('D31 收益明细 · 错误态', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(<dynamic>[
        registrationApiProvider.overrideWithValue(
          _FakeRegistrationApi(fail: true),
        ),
      ], const IncomeDetailPage()),
      'goldens/page_income_detail_error.png',
    );
  });

  testWidgets('D32 收益明细 · 创作收益筛后空态', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 780));
    await tester.pumpWidget(
      _app(<dynamic>[
        registrationApiProvider.overrideWithValue(_FakeRegistrationApi()),
      ], const IncomeDetailPage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('创作收益'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_income_detail_create_empty.png'),
    );
  });

  testWidgets('D46 收益明细 · 有流水(金额/方向/缺值一屏)', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(<dynamic>[
        registrationApiProvider.overrideWithValue(
          _FakeRegistrationApi(
            rows: <BalanceDetail>[
              _balance(
                id: 1,
                amount: '12.00',
                reason: '外滩夜行 · 第一章',
                changeType: 1,
                eventType: 1,
                createTime: '2026-08-07 09:31',
              ),
              _balance(
                id: 2,
                amount: '30.00',
                reason: '提现申请',
                changeType: 2,
                eventType: 3,
                createTime: '2026-08-06 18:02',
              ),
            ],
          ),
        ),
      ], const IncomeDetailPage()),
      'goldens/page_income_detail_list.png',
    );
  });

  testWidgets('D34 消息列表 · 一条私信会话', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(<dynamic>[
        imApiProvider.overrideWithValue(
          _FakeImApi(<Conversation>[
            _conv(<String, dynamic>{
              'conversationId': 9,
              'type': 1,
              'unread': 1,
              'lastMsgText': '明晚一起？',
              'lastMsgAt': '2026-01-15 19:20',
              'counterparty': <String, dynamic>{
                'nickname': '周行',
                'avatar': 'https://example.invalid/d_profile.jpg',
              },
            }),
          ]),
        ),
        merchantCanSettlePredictProvider.overrideWith((Ref ref) async => false),
      ], const ImListPage()),
      'goldens/page_im_list_dm.png',
    );
  });

  testWidgets('D35 消息列表 · 系统通知会话', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(<dynamic>[
        imApiProvider.overrideWithValue(
          _FakeImApi(<Conversation>[
            _conv(<String, dynamic>{
              'conversationId': 2,
              'type': 2,
              'unread': 0,
              'lastMsgText': '报名已确认',
              'lastMsgAt': '2026-01-15 09:00',
              'counterparty': <String, dynamic>{
                'nickname': '系统通知',
                'avatar': '',
              },
            }),
          ]),
        ),
        merchantCanSettlePredictProvider.overrideWith((Ref ref) async => false),
      ], const ImListPage()),
      'goldens/page_im_list_system.png',
    );
  });

  testWidgets('E01 官方活动详情 · 进行中(任务/奖励/集体进度)', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(<dynamic>[
        officialApiProvider.overrideWithValue(
          _FakeOfficialApi(
            event: OfficialEvent.fromJson(<String, dynamic>{
              'id': 101,
              'title': '外滩夜行计划',
              'subtitle': '和全城玩家一起点亮城市',
              'city': '上海',
              'status': 3,
              'participants': 136,
              'signed': true,
              'contractVersion': 2,
              'story': '在夜色里重新认识外滩的建筑与人。',
              'rewardJson': '{"settleBadge":1,"settleXp":80}',
              'collective': <String, dynamic>{
                'enabled': true,
                'current': 136,
                'threshold': 200,
              },
              'missions': <dynamic>[
                <String, dynamic>{
                  'missionCode': 'ARRIVAL',
                  'title': '到达外滩观景台',
                  'description': '到达现场后验证',
                  'missionType': 'ARRIVAL_VERIFIED',
                  'complete': true,
                  'canVerifyArrival': false,
                },
                <String, dynamic>{
                  'missionCode': 'THEME',
                  'title': '完成建筑线索路线',
                  'description': '完成绑定主题后自动同步',
                  'missionType': 'THEME_VERIFIED_FINISH',
                  'complete': false,
                  'canVerifyArrival': false,
                },
              ],
            }),
          ),
        ),
      ], const OfficialEventDetailPage(id: 101)),
      'goldens/page_official_event_normal.png',
    );
  });

  testWidgets('E02 官方活动详情 · 网络失败', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(<dynamic>[
        officialApiProvider.overrideWithValue(_FakeOfficialApi()),
      ], const OfficialEventDetailPage(id: 0)),
      'goldens/page_official_event_error.png',
    );
  });

  testWidgets('E03 附近商家 · 距离从近到远', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        <dynamic>[
          nearbyMerchantsProvider.overrideWith(
            (Ref ref) async => <NearbyMerchant>[
              NearbyMerchant.fromJson(<String, dynamic>{
                'id': 11,
                'memberId': 42,
                'name': '河畔咖啡',
                'address': '苏州河南岸 12 号',
                'distance': 240,
                'canCall': true,
                'phone': '13800000000',
              }),
              NearbyMerchant.fromJson(<String, dynamic>{
                'id': 12,
                'memberId': 43,
                'name': '外滩空间',
                'address': '中山东一路 3 号',
                'distance': 1800,
              }),
            ],
          ),
        ],
        const NearbyMerchantsPage(),
        merchant: true,
      ),
      'goldens/page_nearby_merchants_list.png',
    );
  });

  testWidgets('E12 核销详情 · 摘要 + 结算时间线', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        <dynamic>[
          merchantApiProvider.overrideWithValue(
            _FakeMerchantApi(
              // ★ 值必须是**后端契约的枚举键**,不是界面文案:#263 之后
              //   `canReadFinance` 读 displayState、时间线读
              //   settlementRoute == 'CHAPTER_OFFER'。填中文会让整页退化成
              //   「无资金投影」的紧凑卡,快照就拍不到用例声称的摘要 + 时间线。
              redemption: MerchantRedemptionView.fromJson(<String, dynamic>{
                'recordKey': 'redemption:7001',
                'recordType': 'redemption',
                'recordId': '7001',
                'topicName': '外滩夜行',
                'chapterName': '第一章',
                'storeName': '河畔咖啡',
                'customerDisplayName': '林**',
                'verificationCodeTail': '8392',
                'settlementAmount': '12.00',
                'fulfillmentState': 'ACTIVE',
                'settlementState': 'PENDING',
                'settlementRoute': 'CHAPTER_OFFER',
                'displayState': 'PENDING_SETTLEMENT',
                'occurredAt': '2026-09-01 12:30:45',
                'unitFee': 4,
                'headCount': 3,
              }),
            ),
          ),
        ],
        const MerchantRedemptionDetailPage(
          recordType: 'redemption',
          recordId: '7001',
        ),
        merchant: true,
      ),
      'goldens/page_merchant_redemption_detail.png',
    );
  });
}
