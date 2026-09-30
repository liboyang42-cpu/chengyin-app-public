// 已报名的人看到的主行动,跟小程序的 actionFor 状态机走:
// 查看报名 / 查看足迹 / 继续探索 —— 点了落票夹,不是直接进游玩。
//
// ★ 这条闸的前身是「开始游玩」。那时详情页有一键进游玩流程的按钮,而没票的人
//   点进去后端必然拒绝 —— 一个只会通向错误的按钮不是功能,是缺陷。
//   逐屏对齐 #30 时,主行动换成了小程序
//   `components/cy/scene-play-activity-detail/index.js` 的 actionFor()(第 61–69 行),
//   入口也不再由详情页给:小程序那边「play 统一从票夹进入」
//   (见 components/cy/profile/index.js 的 FE-19 D-4),App 这边同样只从
//   票夹 / 漫游(带 registrationId)进 —— 详情页不再有「开始游玩」这个词。
//
// ★ 守住的东西没变:**没有本活动的有效报名,就不许出现已报名的入口**。
//   判据仍是报名列表里有没有 ownerType=2 + ownerId=本活动 的记录;
//   拉取失败时退回「立即报名」,不猜、不把人送去必然报错的流程。
//
// ★ 为什么判据是「有没有票」而不是 productType:生产上 `cms_topic.product_type`
//   仍是 null(#741 的回填只处理 id=23 一个主题,且填成 ①),按它挡**不生效**。
//   「持票」既可靠,又贴合 ③ 的履约形态 —— ③ 是核销,不是游玩。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/feature/activity/activity_controller.dart';
import 'package:chengyin_app/feature/activity/activity_detail_page.dart';

const int _kActivityId = 77;

ActivityDetail _activity() => ActivityDetail.fromJson(<String, dynamic>{
  'id': _kActivityId,
  'name': '静安探店日 · 第一期',
  'description': '测试用',
});

MyRegistration _reg(int ownerId) =>
    MyRegistration.fromJson(<String, dynamic>{
      'id': 1,
      'ownerType': 2,
      'ownerId': ownerId,
      'registrationStatus': 2,
      'cmsActivity': <String, dynamic>{'name': 'x'},
    });

Future<void> _pump(
  WidgetTester tester, {
  required Future<List<MyRegistration>> Function() joined,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        activityDetailProvider(
          _kActivityId,
        ).overrideWith((ref) async => _activity()),
        myJoinedActivitiesProvider.overrideWith((ref) => joined()),
      ].cast(),
      child: const MaterialApp(
        home: ActivityDetailPage(activityId: _kActivityId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  /// 已报名态的三种文案。出现任一个 = 详情页把「已报名」入口摆出来了。
  const List<String> registeredLabels = <String>[
    '查看报名',
    '查看足迹',
    '继续探索',
  ];

  void expectNoRegisteredEntry() {
    for (final String label in registeredLabels) {
      expect(find.text(label), findsNothing, reason: '没票却出现了「$label」入口');
    }
  }

  testWidgets('没票 → 只给「立即报名」', (WidgetTester tester) async {
    await _pump(tester, joined: () async => <MyRegistration>[]);
    expect(find.text('立即报名'), findsOneWidget);
    expectNoRegisteredEntry();
  });

  testWidgets('持有**别的**活动的票 → 仍只给「立即报名」', (WidgetTester tester) async {
    await _pump(tester, joined: () async => <MyRegistration>[_reg(999)]);
    expect(find.text('立即报名'), findsOneWidget);
    expectNoRegisteredEntry();
  });

  testWidgets('持有本活动的票 → 主行动换成已报名文案', (WidgetTester tester) async {
    await _pump(
      tester,
      joined: () async => <MyRegistration>[_reg(_kActivityId)],
    );
    // 夹具没有场次时间 → actionFor 的默认态(进行中):「继续探索」。
    expect(find.text('继续探索'), findsOneWidget);
    expect(find.text('立即报名'), findsNothing);
  });

  testWidgets('报名列表拉取失败(如游客 401)→ 退回「立即报名」,不把人送去必然报错的流程', (
    WidgetTester tester,
  ) async {
    await _pump(tester, joined: () async => throw Exception('401'));
    expect(find.text('立即报名'), findsOneWidget);
    expectNoRegisteredEntry();
  });
}
