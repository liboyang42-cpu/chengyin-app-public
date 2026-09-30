// 官方活动详情:奖励与集体进度**不许替主办方许愿**。
//
// ★ 真源 `pages/activity/official-detail/index.wxml` 的 F22 裁决:
//   只展示后端 rewardJson 里真实配置的奖励;没有配置就如实说明。
//   App 原来兜底成「🏅 参与即有惊喜」—— 一条奖都没配的活动,
//   页面却承诺了奖,而结算时发不出来。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/official_event.dart';
import 'package:chengyin_app/feature/official/official_controller.dart';
import 'package:chengyin_app/feature/official/official_event_detail_page.dart';

Future<void> _pump(WidgetTester t, OfficialEvent e) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        officialEventProvider(e.id).overrideWith((Ref ref) async => e),
      ].cast(),
      child: MaterialApp(home: OfficialEventDetailPage(id: e.id)),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('★★ 没配奖励:如实说没配,不摆默认承诺', (WidgetTester t) async {
    await _pump(t, const OfficialEvent(id: 1, title: '城市定向周', status: 2));
    expect(find.text('活动奖励'), findsOneWidget);
    expect(find.text('主办方尚未配置奖励，页面不承诺任何奖励。'), findsOneWidget);
    expect(
      find.textContaining('参与即有惊喜'),
      findsNothing,
      reason: '主办方一个字都没配,页面替它许一个奖 = 结算时兑现不了',
    );
  });

  testWidgets('★ 配了奖励:按配置列出,并写明以结算为准', (WidgetTester t) async {
    await _pump(
      t,
      const OfficialEvent(
        id: 2,
        title: '城市定向周',
        status: 2,
        rewardJson: '{"settleBadge":1,"settleXp":300}',
      ),
    );
    expect(find.text('🏅 限定徽章'), findsOneWidget);
    expect(find.text('✨ 300 成长值'), findsOneWidget);
    expect(find.textContaining('完成活动任务后按上方配置发放'), findsOneWidget);
    expect(find.textContaining('实际发放结果以活动结算为准'), findsOneWidget);
    expect(find.text('主办方尚未配置奖励，页面不承诺任何奖励。'), findsNothing);
  });

  testWidgets('★★ 集体进度没配集体券:只说"进度仅供了解",不承诺发放', (WidgetTester t) async {
    await _pump(
      t,
      const OfficialEvent(
        id: 3,
        title: '全城点亮',
        status: 3,
        collective: CollectiveProgress(
          enabled: true,
          current: 12,
          threshold: 100,
          pct: 12,
        ),
      ),
    );
    expect(find.text('当前未配置集体奖励，全城进度仅供了解'), findsOneWidget);
    expect(find.textContaining('达标全员解锁奖励'), findsNothing);
  });

  testWidgets('★ 集体进度配了集体券:才敢承诺达标后发放', (WidgetTester t) async {
    await _pump(
      t,
      const OfficialEvent(
        id: 4,
        title: '全城点亮',
        status: 3,
        rewardJson: '{"collectiveCouponId":9}',
        collective: CollectiveProgress(
          enabled: true,
          current: 12,
          threshold: 100,
          pct: 12,
        ),
      ),
    );
    expect(find.text('开启且集体达标、本人保持有效报名并完成全部任务后发放集体奖励'), findsOneWidget);
  });

  testWidgets('★ 报名人数说的是「人已报名」(真源 od-fact-sub)', (WidgetTester t) async {
    await _pump(
      t,
      const OfficialEvent(id: 5, title: '城市定向周', status: 2, participants: 18),
    );
    expect(find.text('人已报名'), findsOneWidget);
    expect(find.text('人参与'), findsNothing);
  });
}
