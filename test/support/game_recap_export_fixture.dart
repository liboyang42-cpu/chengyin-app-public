/// 俱乐部复盘导出(`GET /api/game/session/recap/export`)的共用夹具。
///
/// ★ 形状照抄真源两端:后端 `GameSessionRuntimeServiceImpl.buildClubRecap`
///   就是这么长出来的,小程序 `utils/game-session-client.js` 的
///   `normalizeClubRecapExport` 就是照这个形状逐字段核。
///   模型用例与接口用例共用一份 —— 夹具一旦比真源窄,「校验通过」就成了假结论。
library;

/// 一份合法的导出载荷。每次调用返回新对象,调用方可原地改坏再喂给归一化。
Map<String, dynamic> gameRecapExportJson({int activityId = 41}) =>
    <String, dynamic>{
      'schemaVersion': 'GAME_RECAP_EXPORT_V1',
      'generatedAt': '2026-09-17 10:00:00',
      'activityId': activityId,
      'sessionId': 11,
      'recap': <String, dynamic>{
        'schemaVersion': 'GAME_RECAP_V1',
        'generatedAt': '2026-09-17 10:00:00',
        'metrics': <Map<String, dynamic>>[
          <String, dynamic>{
            'key': 'PAID_PLAYERS',
            'label': '付费玩家',
            'value': 12,
            'unit': '人',
          },
          <String, dynamic>{
            'key': 'FINISHED_TEAMS',
            'label': '完成队伍',
            'value': 2,
            'unit': '队',
          },
        ],
        'funnel': <String, dynamic>{
          'paidPlayers': 12,
          'arrivedPlayers': 10,
          'taskSubmitters': 9,
          'normalCompleters': 7,
          'fallbackCompleters': 1,
          'finishedTeams': 2,
        },
        'hints': <String, dynamic>{
          'level1Uses': 3,
          'level2Uses': 2,
          'answerReveals': 1,
        },
        'incidents': <String, dynamic>{
          'merchantPauseEvents': 0,
          'merchantFallbackCompletions': 1,
          'playerRejectedSubmissions': 2,
        },
        'collaboration': <String, dynamic>{
          'eligibleTeams': 4,
          'completedTeams': 3,
          'ratePercent': 75,
        },
        'takeovers': <String, dynamic>{'count': 1},
        'stations': <Map<String, dynamic>>[
          <String, dynamic>{
            'nodeId': 5,
            'nodeName': '钟楼',
            'arrivedPlayers': 10,
            'submissionCount': 8,
            'normalCompletedCount': 7,
            'fallbackCompletedCount': 1,
            'rejectedCount': 2,
            'pauseEventCount': 0,
          },
          <String, dynamic>{
            'nodeId': 6,
            'nodeName': '码头',
            'arrivedPlayers': 6,
            'submissionCount': 6,
            'normalCompletedCount': 5,
            'fallbackCompletedCount': 1,
            'rejectedCount': 0,
            'pauseEventCount': 1,
          },
        ],
        'exportAvailable': true,
      },
    };

/// 把 `recap` 改坏再交给归一化。
Map<String, dynamic> gameRecapExportWith(
  void Function(Map<String, dynamic> recap) mutate,
) {
  final Map<String, dynamic> export = gameRecapExportJson();
  mutate(export['recap'] as Map<String, dynamic>);
  return export;
}

/// 下面四个是给「改坏某个字段」用的取值助手。
List<Map<String, dynamic>> metricRows(Map<String, dynamic> recap) =>
    (recap['metrics'] as List<dynamic>).cast<Map<String, dynamic>>();

List<Map<String, dynamic>> stationRows(Map<String, dynamic> recap) =>
    (recap['stations'] as List<dynamic>).cast<Map<String, dynamic>>();

Map<String, dynamic> firstMetric(Map<String, dynamic> recap) =>
    metricRows(recap).first;

Map<String, dynamic> recapField(Map<String, dynamic> recap, String name) =>
    recap[name] as Map<String, dynamic>;

/// 逐字段核用的坏载荷表:**每一条都必须被拒**(归一化返回 null)。
///
/// 与 `test/data/models/game_session_recap_export_test.dart` 共用一份,
/// 也拿整表跟真源 JS 归一化器做差分 —— 两边都判 null 才算「照真源」。
Map<String, Map<String, dynamic>> brokenGameRecapExports() =>
    <String, Map<String, dynamic>>{
      '不是这一场': gameRecapExportJson(activityId: 42),
      '信封版本不对': <String, dynamic>{
        ...gameRecapExportJson(),
        'schemaVersion': 'GAME_RECAP_V1',
      },
      'sessionId 缺失': <String, dynamic>{
        ...gameRecapExportJson(),
        'sessionId': null,
      },
      'sessionId 为 0': <String, dynamic>{
        ...gameRecapExportJson(),
        'sessionId': 0,
      },
      'sessionId 非整数': <String, dynamic>{
        ...gameRecapExportJson(),
        'sessionId': 2.5,
      },
      'generatedAt 不是秒级': <String, dynamic>{
        ...gameRecapExportJson(),
        'generatedAt': '2026-09-17 10:00',
      },
      'generatedAt 日期不存在': <String, dynamic>{
        ...gameRecapExportJson(),
        'generatedAt': '2026-02-30 10:00:00',
      },
      'generatedAt 不是字符串': <String, dynamic>{
        ...gameRecapExportJson(),
        'generatedAt': 20260917,
      },
      '没有 recap': <String, dynamic>{...gameRecapExportJson(), 'recap': null},
      'recap 版本不对': gameRecapExportWith(
        (Map<String, dynamic> recap) =>
            recap['schemaVersion'] = 'GAME_RECAP_V2',
      ),
      'recap generatedAt 为空': gameRecapExportWith(
        (Map<String, dynamic> recap) => recap['generatedAt'] = '',
      ),
      'exportAvailable 不是布尔': gameRecapExportWith(
        (Map<String, dynamic> recap) => recap['exportAvailable'] = 'true',
      ),
      'metrics 不是数组': gameRecapExportWith(
        (Map<String, dynamic> recap) => recap['metrics'] = 'nope',
      ),
      'metrics 里塞了非对象': gameRecapExportWith(
        (Map<String, dynamic> recap) =>
            recap['metrics'] = <dynamic>[...metricRows(recap), 'x'],
      ),
      'stations 不是数组': gameRecapExportWith(
        (Map<String, dynamic> recap) => recap['stations'] = 'nope',
      ),
      'metric key 非法': gameRecapExportWith(
        (Map<String, dynamic> recap) => firstMetric(recap)['key'] = '1BAD',
      ),
      'metric key 为空': gameRecapExportWith(
        (Map<String, dynamic> recap) => firstMetric(recap)['key'] = '',
      ),
      'metric key 超长': gameRecapExportWith(
        (Map<String, dynamic> recap) => firstMetric(recap)['key'] = 'A' * 65,
      ),
      'metric label 超长': gameRecapExportWith(
        (Map<String, dynamic> recap) => firstMetric(recap)['label'] = 'x' * 121,
      ),
      'metric label 不是字符串': gameRecapExportWith(
        (Map<String, dynamic> recap) => firstMetric(recap)['label'] = 7,
      ),
      'metric value 为负': gameRecapExportWith(
        (Map<String, dynamic> recap) => firstMetric(recap)['value'] = -1,
      ),
      'metric value 非整数': gameRecapExportWith(
        (Map<String, dynamic> recap) => firstMetric(recap)['value'] = 1.5,
      ),
      'metric value 超安全整数': gameRecapExportWith(
        (Map<String, dynamic> recap) =>
            firstMetric(recap)['value'] = 9007199254740992,
      ),
      'metric unit 不是字符串': gameRecapExportWith(
        (Map<String, dynamic> recap) => firstMetric(recap)['unit'] = 12,
      ),
      'metric unit 超长': gameRecapExportWith(
        (Map<String, dynamic> recap) => firstMetric(recap)['unit'] = 'x' * 33,
      ),
      'metric key 重复': gameRecapExportWith((Map<String, dynamic> recap) {
        metricRows(recap)[1]['key'] = firstMetric(recap)['key'];
      }),
      'station nodeId 为 0': gameRecapExportWith(
        (Map<String, dynamic> recap) => stationRows(recap).first['nodeId'] = 0,
      ),
      'station nodeName 为空': gameRecapExportWith(
        (Map<String, dynamic> recap) =>
            stationRows(recap).first['nodeName'] = '  ',
      ),
      'station 缺一个计数': gameRecapExportWith(
        (Map<String, dynamic> recap) =>
            stationRows(recap).first.remove('submissionCount'),
      ),
      'station 计数为负': gameRecapExportWith(
        (Map<String, dynamic> recap) =>
            stationRows(recap).first['rejectedCount'] = -1,
      ),
      'station nodeId 重复': gameRecapExportWith(
        (Map<String, dynamic> recap) => stationRows(recap)[1]['nodeId'] = 5,
      ),
      'funnel 缺字段': gameRecapExportWith(
        (Map<String, dynamic> recap) =>
            recapField(recap, 'funnel').remove('finishedTeams'),
      ),
      'funnel 值为负': gameRecapExportWith(
        (Map<String, dynamic> recap) =>
            recapField(recap, 'funnel')['paidPlayers'] = -1,
      ),
      'hints 缺字段': gameRecapExportWith(
        (Map<String, dynamic> recap) =>
            recapField(recap, 'hints').remove('level1Uses'),
      ),
      'incidents 缺字段': gameRecapExportWith(
        (Map<String, dynamic> recap) =>
            recapField(recap, 'incidents').remove('merchantPauseEvents'),
      ),
      'collaboration 缺字段': gameRecapExportWith(
        (Map<String, dynamic> recap) =>
            recapField(recap, 'collaboration').remove('ratePercent'),
      ),
      '完成率超过 100': gameRecapExportWith(
        (Map<String, dynamic> recap) =>
            recapField(recap, 'collaboration')['ratePercent'] = 101,
      ),
      '完成队伍多于合格队伍': gameRecapExportWith(
        (Map<String, dynamic> recap) => recapField(recap, 'collaboration')
          ..['eligibleTeams'] = 2
          ..['completedTeams'] = 3,
      ),
      'takeovers 缺 count': gameRecapExportWith(
        (Map<String, dynamic> recap) =>
            recapField(recap, 'takeovers').remove('count'),
      ),
    };
