// 官方活动详情的事实条:真源 `pages/activity/official-detail/index.wxml` 的
// `od-facts` 六格(参与 / 我的进度 / 活动周期 / 开放时间 / 活动范围 / 活动任务)。
// 少一格,用户就得靠猜活动什么时候开、开多久、算不算任务。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/official_event.dart';
import 'package:chengyin_app/feature/official/official_controller.dart';
import 'package:chengyin_app/feature/official/official_event_detail_page.dart';

Future<void> _pump(WidgetTester t, OfficialEvent e) async {
  await t.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));
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
  test('活动周期:不足一天按小时上进,满一天按天上进,缺一头就是待公布', () {
    OfficialEvent at(String? start, String? end) => OfficialEvent(
      id: 1,
      title: 'x',
      activityStart: start == null ? null : DateTime.parse(start),
      activityEnd: end == null ? null : DateTime.parse(end),
    );

    expect(
      officialEventDurationText(at('2026-09-20 09:00', '2026-09-23 09:00')),
      '3天',
    );
    expect(
      officialEventDurationText(at('2026-09-20 09:00', '2026-09-20 10:30')),
      '2小时',
    );
    expect(
      officialEventDurationText(at('2026-09-20 09:00', '2026-09-20 09:20')),
      '1小时',
    );
    expect(officialEventDurationText(at('2026-09-20 09:00', null)), '待公布');
    // 时间填反了(结束早于开始)不是「-1天」,是「待公布」。
    expect(
      officialEventDurationText(at('2026-09-23 09:00', '2026-09-20 09:00')),
      '待公布',
    );
  });

  test('开放时间:两头都有一头一带上,都没有才说待公布', () {
    expect(
      officialEventDateRange(
        OfficialEvent(
          id: 1,
          title: 'x',
          activityStart: DateTime.parse('2026-09-20 09:00'),
          activityEnd: DateTime.parse('2026-09-22 18:00'),
        ),
      ),
      '9月20日–9月22日',
    );
    expect(
      officialEventDateRange(
        OfficialEvent(
          id: 1,
          title: 'x',
          activityStart: DateTime.parse('2026-09-20 09:00'),
        ),
      ),
      '9月20日',
    );
    expect(
      officialEventDateRange(const OfficialEvent(id: 1, title: 'x')),
      '待公布',
    );
  });

  testWidgets('事实条六格按真源出齐(含总时长/北京时间/活动范围/项任务)', (WidgetTester t) async {
    await _pump(
      t,
      OfficialEvent(
        id: 7,
        title: '城市定向周',
        status: 2,
        city: '上海',
        participants: 18,
        signed: true,
        activityStart: DateTime.parse('2026-09-20 09:00'),
        activityEnd: DateTime.parse('2026-09-23 09:00'),
        contractVersion: 2,
        missions: const <OfficialMission>[
          OfficialMission(missionCode: 'A', title: '到达', complete: true),
          OfficialMission(missionCode: 'B', title: '打卡'),
        ],
      ),
    );

    expect(find.text('参与'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(find.text('人已报名'), findsOneWidget);
    expect(find.text('我的进度'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('有效任务'), findsOneWidget);
    expect(find.text('活动周期'), findsOneWidget);
    expect(find.text('3天'), findsOneWidget);
    expect(find.text('总时长'), findsOneWidget);
    expect(find.text('开放时间'), findsOneWidget);
    expect(find.text('9月20日–9月23日'), findsOneWidget);
    expect(find.text('北京时间'), findsOneWidget);
    expect(find.text('活动范围'), findsOneWidget);
    expect(find.text('上海'), findsWidgets);
    expect(find.text('活动任务'), findsOneWidget);
    expect(find.text('项任务'), findsOneWidget);
    // 主办方行:官方活动是平台办的,不写这一行用户分不清谁办的。
    expect(find.text('城瘾官方 · 发起'), findsOneWidget);
  });

  testWidgets('没报名的旧契约活动:不摆「我的进度」空格,活动范围副行落状态文案', (WidgetTester t) async {
    await _pump(
      t,
      const OfficialEvent(id: 8, title: '城市定向周', status: 1, participants: 3),
    );

    expect(find.text('参与'), findsOneWidget);
    expect(find.text('我的进度'), findsNothing);
    expect(find.text('有效任务'), findsNothing);
    // 没有倒计时就用状态文案兜底,不空着。
    expect(find.text('即将开始'), findsWidgets);
    // 城市没填时活动范围是「全国」,不是空白。
    expect(find.text('全国'), findsOneWidget);
    // 没有任务/内容卡就不摆「项任务」。
    expect(find.text('项任务'), findsNothing);
  });
}
