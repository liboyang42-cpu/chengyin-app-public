// 「我的点位」卡片上的三个入口:出示打卡码 / 店内海报码 / 点位角色。
//
// ★★ 这一页的风险与招商承接页同型:**摆一个点下去必被服务端拒的按钮**。
//   现场码与海报码的判据同小程序
//   (`pages/topic/merchantinfo/merchantinfo.js:2032`:showCheckinQr 只在
//    confirmed / running 时为真)—— 点位没过审就摆一张扫了也没用的码,
//   商家会以为现场已经能接待了,而玩家扫出来什么都不是。
//
// ★ 三种东西各有各的端点,不能拿一张码当两张用:
//   live-checkin-code(现场,秒级过期)· poster-code(店内长期,可存相册)·
//   chapter-node/npc/*(点位角色,是另一套端点,不复用门店形象)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/models/merchant_recruit.dart';
import 'package:chengyin_app/feature/merchant/merchant_recruit_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_recruit_state.dart';

const int kTopic = 42;

class _FakeMerchantApi implements MerchantApi {
  @override
  Future<Map<String, dynamic>> chapterNodeLiveCheckinCode(int nodeId) async =>
      <String, dynamic>{
        'qrcodeUrl': 'https://x/live.png',
        'code': 'CY-LIVE',
        'ttlMs': 60000,
      };

  @override
  Future<Map<String, dynamic>> chapterNodePosterCode(int nodeId) async =>
      <String, dynamic>{'qrcodeUrl': 'https://x/p.png', 'code': 'CY-P'};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MyChapterNode node({int? audit, String? reason}) =>
    MyChapterNode.fromJson(<String, dynamic>{
      'id': 5,
      'name': '南京西路店',
      'nodeAuditStatus': audit,
      'nodeAuditReason': reason,
    });

Widget app(int? audit) => ProviderScope(
  overrides: [
    merchantRecruitProvider(kTopic).overrideWith(
      (ref) async => RecruitState(
        mode: RecruitMode.chapterRecruit,
        topicName: '梧桐区寻味',
        nodes: <MyChapterNode>[node(audit: audit)],
      ),
    ),
    merchantUpcomingRunsProvider(kTopic).overrideWith(
      (ref) async => <UpcomingRun>[],
    ),
    merchantApiProvider.overrideWithValue(_FakeMerchantApi()),
  ],
  child: const MaterialApp(home: MerchantRecruitPage(topicId: kTopic)),
);

void main() {
  testWidgets('★★ 已通过的点位三个入口都给', (WidgetTester tester) async {
    await tester.pumpWidget(app(1));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recruit-node-live-code-5')), findsOneWidget);
    expect(find.byKey(const Key('recruit-node-poster-code-5')), findsOneWidget);
    expect(find.byKey(const Key('recruit-node-npc-5')), findsOneWidget);
  });

  testWidgets('★★ 待审核的点位不摆码,并说清为什么', (WidgetTester tester) async {
    await tester.pumpWidget(app(0));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recruit-node-live-code-5')), findsNothing);
    expect(find.byKey(const Key('recruit-node-poster-code-5')), findsNothing);
    expect(
      find.byKey(const Key('recruit-node-npc-5')),
      findsOneWidget,
      reason: '点位角色不受审核态限制 —— 先把角色配好,过审就能用',
    );
    expect(find.textContaining('通过审核后'), findsOneWidget);
  });

  testWidgets('★ 审核状态读不出来时:不摆码,且说"状态没读出来"而不是"没过审"',
      (WidgetTester tester) async {
    await tester.pumpWidget(app(null));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recruit-node-live-code-5')), findsNothing);
    expect(
      find.textContaining('要等审核状态读出来'),
      findsOneWidget,
      reason: '把"没读到"说成"没过审",商家会去重提交一遍',
    );
  });

  testWidgets('★★ 「出示打卡码」真的打得到现场码弹层', (WidgetTester tester) async {
    await tester.pumpWidget(app(1));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('recruit-node-live-code-5')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('现场打卡码'),
      findsOneWidget,
      reason: '接口接了但页面够不着 = 等于没接',
    );
    expect(find.byKey(const Key('chapter-node-code-refresh')), findsOneWidget);
  });

  testWidgets('★ 「店内海报码」打的是另一张码(海报码没有倒计时)', (WidgetTester tester) async {
    await tester.pumpWidget(app(1));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('recruit-node-poster-code-5')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('本站打卡码'), findsOneWidget);
    expect(find.byKey(const Key('chapter-node-code-save')), findsOneWidget);
    expect(find.byKey(const Key('chapter-node-code-refresh')), findsNothing);
  });
}
