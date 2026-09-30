import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/official/official_publish_page.dart';

void main() {
  test('活动 payload 字段、枚举与集体奖励逐字对齐小程序', () {
    final DateTime start = DateTime(2026, 8, 24);
    final DateTime end = DateTime(2026, 8, 31);
    final Map<String, dynamic> body = buildOfficialEventBody(
      title: '成都点亮日',
      subtitle: '一起走进街区',
      city: '成都',
      category: 'challenge',
      startDate: start,
      endDate: end,
      collective: true,
      metric: 'complete_count',
      threshold: '1000',
      xp: '50',
      badge: true,
    );

    expect(body.keys.toSet(), <String>{
      'title',
      'subtitle',
      'city',
      'category',
      'activityStart',
      'activityEnd',
      'settleTime',
      'collectiveEnabled',
      'collectiveMetric',
      'collectiveThreshold',
      'rewardJson',
    });
    expect(body['activityStart'], start.millisecondsSinceEpoch);
    expect(body['activityEnd'], end.millisecondsSinceEpoch);
    expect(body['settleTime'], end.millisecondsSinceEpoch);
    expect(body['collectiveEnabled'], 1);
    expect(body['collectiveMetric'], 'complete_count');
    expect(body['collectiveThreshold'], 1000);
    expect(jsonDecode(body['rewardJson'] as String), <String, dynamic>{
      'settleXp': 50,
      'settleBadge': true,
    });
  });

  test('通知 payload 固定受众/渠道顺序，支持一起发与分开发', () {
    final Map<String, dynamic> unified = buildOfficialBroadcastBody(
      eventId: 77,
      activityTitle: '成都点亮日',
      city: '成都',
      audience: <String>{'merchant', 'player'},
      copyMode: 1,
      unifiedTitle: '',
      unifiedSub: '本周六见',
      playerTitle: '',
      playerSub: '',
      clubTitle: '',
      clubSub: '',
      merchantTitle: '',
      merchantSub: '',
      channels: <String>{'subscribe', 'inapp'},
    );
    expect(unified, <String, dynamic>{
      'eventId': 77,
      'title': '成都点亮日',
      'audience': 'player,merchant',
      'copyMode': 1,
      'contentJson': '{"title":"成都点亮日","sub":"本周六见"}',
      'channels': 'inapp,subscribe',
      'city': '成都',
    });

    final Map<String, dynamic> split = buildOfficialBroadcastBody(
      activityTitle: '活动标题不应成为分开发标题',
      city: '',
      audience: <String>{'club', 'player'},
      copyMode: 2,
      unifiedTitle: '',
      unifiedSub: '',
      playerTitle: '玩家标题',
      playerSub: '玩家内容',
      clubTitle: '俱乐部标题',
      clubSub: '俱乐部内容',
      merchantTitle: '不应上送',
      merchantSub: '不应上送',
      channels: <String>{},
    );
    expect(split['eventId'], isNull);
    expect(split['title'], '官方通知');
    expect(split['audience'], 'player,club');
    expect(split['channels'], 'inapp');
    expect(jsonDecode(split['contentJson'] as String), <String, dynamic>{
      'player': <String, dynamic>{'title': '玩家标题', 'sub': '玩家内容'},
      'club': <String, dynamic>{'title': '俱乐部标题', 'sub': '俱乐部内容'},
    });
  });

  test('校验与小程序一致：发活动只必填标题，只发通知必选受众', () {
    expect(
      officialPublishBlocker(
        mode: 'activity',
        activityTitle: ' ',
        audience: <String>{},
      ),
      '输入活动标题',
    );
    expect(
      officialPublishBlocker(
        mode: 'activity',
        activityTitle: '有标题',
        audience: <String>{},
      ),
      isNull,
    );
    expect(
      officialPublishBlocker(
        mode: 'notice',
        activityTitle: '',
        audience: <String>{},
      ),
      '请选择通知对象',
    );
    expect(
      officialPublishBlocker(
        mode: 'notice',
        activityTitle: '',
        audience: <String>{'player'},
      ),
      isNull,
    );
  });
}
