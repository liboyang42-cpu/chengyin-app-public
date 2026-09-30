// 俱乐部复盘导出的归一化(`normalizeClubRecapExport` = 真源
// `utils/game-session-client.js` 同名函数)。
//
// 判据是**小程序剪贴板里那份 JSON**:`director.js copyRecap` 复制的不是原始
// 响应,而是 normalize 之后的**白名单**结构。三条缺一不可:
//   ① 字段与顺序照真源 —— 导出的 JSON 和小程序那份逐字对齐;
//   ② 白名单 —— 后端将来多下发一个字段(phone/memberId/…),不跟着进剪贴板;
//   ③ 逐字段核 —— 任一处不合格整份拒绝(调用方写「复盘导出数据无效」),
//      坏数据宁可复制失败,也不进剪贴板。

import 'dart:convert';

import 'package:chengyin_app/data/models/game_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/game_recap_export_fixture.dart';

void main() {
  test('★ 合法载荷:字段与顺序照真源 —— 就是小程序剪贴板里那一份', () {
    final Map<String, dynamic>? normalized = normalizeClubRecapExport(
      gameRecapExportJson(),
      activityId: 41,
    );

    expect(normalized, isNotNull);
    expect(normalized!.keys.toList(), <String>[
      'schemaVersion',
      'generatedAt',
      'activityId',
      'sessionId',
      'recap',
    ]);
    final Map<String, dynamic> recap =
        normalized['recap'] as Map<String, dynamic>;
    expect(recap.keys.toList(), <String>[
      'schemaVersion',
      'generatedAt',
      'metrics',
      'funnel',
      'hints',
      'incidents',
      'collaboration',
      'takeovers',
      'stations',
      'exportAvailable',
    ]);
    expect(firstMetric(recap).keys.toList(), <String>[
      'key',
      'label',
      'value',
      'unit',
    ]);
    expect(stationRows(recap).first.keys.toList(), <String>[
      'nodeId',
      'nodeName',
      'arrivedPlayers',
      'submissionCount',
      'normalCompletedCount',
      'fallbackCompletedCount',
      'rejectedCount',
      'pauseEventCount',
    ]);
    expect(normalized['generatedAt'], '2026-09-17 10:00:00');
    expect(normalized['sessionId'], 11);
    expect(recap['exportAvailable'], isTrue);
  });

  test('★ 白名单:服务端多下发什么,都不跟着进剪贴板', () {
    final Map<String, dynamic> export = gameRecapExportJson();
    export['serverHint'] = '/api/game/session/recap/export';
    export['operatorName'] = '张三';
    final Map<String, dynamic> recap = export['recap'] as Map<String, dynamic>;
    recap['memberIds'] = <int>[1, 2];
    firstMetric(recap)['traceId'] = 'trace-9';
    stationRows(recap).first['memberName'] = '阿青';
    stationRows(recap).first['longitude'] = 121.4;

    final String text = jsonEncode(
      normalizeClubRecapExport(export, activityId: 41),
    );

    for (final String leaked in <String>[
      'serverHint',
      'operatorName',
      'memberIds',
      'traceId',
      'memberName',
      'longitude',
      '121.4',
    ]) {
      expect(text.contains(leaked), isFalse, reason: '$leaked 不该进剪贴板');
    }
  });

  test('真源同款宽容:key 转大写、label 去空白、空 unit 保留', () {
    final Map<String, dynamic>? normalized = normalizeClubRecapExport(
      gameRecapExportWith((Map<String, dynamic> recap) {
        firstMetric(recap)
          ..['key'] = ' paid_players '
          ..['label'] = ' 付费玩家 '
          ..['unit'] = '';
      }),
      activityId: 41,
    );

    final Map<String, dynamic> metric = firstMetric(
      normalized!['recap'] as Map<String, dynamic>,
    );
    expect(metric['key'], 'PAID_PLAYERS');
    expect(metric['label'], '付费玩家');
    expect(metric['unit'], '');
  });

  test('逐字段核:任一处不合格整份拒绝', () {
    for (final MapEntry<String, Map<String, dynamic>> entry
        in brokenGameRecapExports().entries) {
      expect(
        normalizeClubRecapExport(entry.value, activityId: 41),
        isNull,
        reason: '${entry.key}:坏数据不得写进剪贴板',
      );
    }
  });

  test('不是对象一律拒绝', () {
    for (final Object? raw in <Object?>[
      null,
      'GAME_RECAP_EXPORT_V1',
      <dynamic>[],
    ]) {
      expect(normalizeClubRecapExport(raw, activityId: 41), isNull);
    }
  });
}
