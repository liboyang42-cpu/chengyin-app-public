import 'dart:convert';
import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/game_session_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/game_recap_export_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  test('商家投影和入口使用后端真实 GET 契约', () async {
    final sent = <RequestOptions>[];
    final api = _api(
      sent,
      (o) => o.path.endsWith('/merchant/entries')
          ? <String, dynamic>{
              'code': 200,
              'data': <Map<String, dynamic>>[
                <String, dynamic>{
                  'activityId': 7,
                  'topicId': 3,
                  'activityName': '夜游',
                  'stationCount': 1,
                },
              ],
            }
          : <String, dynamic>{'code': 200, 'data': _projection()},
    );

    expect((await api.loadMerchantEntries()).single.activityId, 7);
    final view = await api.loadMerchantView(activityId: 7);
    expect(view.perspective, 'MERCHANT');
    expect(sent[1].queryParameters, <String, dynamic>{
      'activityId': 7,
      'perspective': 'MERCHANT',
    });
  });

  test('商家投影身份、session 与 revision 只接受安全整数', () {
    final invalidFields = <Map<String, dynamic>>[
      <String, dynamic>{'activityId': 7.5},
      <String, dynamic>{'activityId': 9007199254740992},
      <String, dynamic>{'sessionId': 2.5},
      <String, dynamic>{'sessionId': 9007199254740992},
      <String, dynamic>{'revision': 3.5},
      <String, dynamic>{'revision': 9007199254740992},
    ];
    for (final Map<String, dynamic> override in invalidFields) {
      expect(
        () => MerchantGameProjection.fromJson(<String, dynamic>{
          ..._projection(),
          ...override,
        }),
        throwsFormatException,
        reason: '$override 不得进入投影',
      );
    }
  });

  test('写命令不把 HTTP 200 当成成功，必须读到匹配 APPLIED 回执', () async {
    final sent = <RequestOptions>[];
    final api = _api(sent, (o) {
      if (o.path.endsWith('/command')) {
        return <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{'accepted': true},
        };
      }
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'activityId': 7,
          'requestId': 'req_12345678',
          'action': 'STATION_ACCEPT',
          'outcome': 'APPLIED',
          'receiptId': 9001,
          'revision': 4,
        },
      };
    });
    final command = GameSessionCommand(
      activityId: 7,
      nodeId: 9,
      requestId: 'req_12345678',
      expectedRevision: 3,
      action: 'STATION_ACCEPT',
      payload: const <String, dynamic>{},
    );

    final receipt = await api.submitAndReadReceipt(command);
    expect(receipt.outcome, GameReceiptOutcome.applied);
    expect(sent.map((e) => e.path), <String>[
      '/api/game/session/command',
      '/api/game/session/receipt',
    ]);
  });

  test('回执身份不匹配必须失败关闭', () async {
    final api = _api(
      <RequestOptions>[],
      (o) => o.path.endsWith('/command')
          ? <String, dynamic>{'code': 200}
          : <String, dynamic>{
              'code': 200,
              'data': <String, dynamic>{
                'activityId': 8,
                'requestId': 'req_12345678',
                'action': 'STATION_ACCEPT',
                'outcome': 'APPLIED',
                'receiptId': 9001,
                'revision': 4,
              },
            },
    );
    expect(
      () => api.submitAndReadReceipt(
        GameSessionCommand(
          activityId: 7,
          nodeId: 9,
          requestId: 'req_12345678',
          expectedRevision: 3,
          action: 'STATION_ACCEPT',
          payload: const <String, dynamic>{},
        ),
      ),
      throwsA(isA<GameSessionContractException>()),
    );
  });

  test('入口清单只要混入一条无效授权数据就整体失败', () async {
    final api = _api(
      <RequestOptions>[],
      (_) => <String, dynamic>{
        'code': 200,
        'data': <Map<String, dynamic>>[
          <String, dynamic>{
            'activityId': 7,
            'topicId': 3,
            'activityName': '夜游',
            'stationCount': 1,
          },
          <String, dynamic>{
            'activityId': 8,
            'topicId': 0,
            'activityName': '伪造入口',
            'stationCount': 1,
          },
        ],
      },
    );
    expect(
      api.loadMerchantEntries,
      throwsA(isA<GameSessionContractException>()),
    );
  });

  test('玩家视角用 PLAYER 拉取，PENDING 回执保留给控制器回读', () async {
    final sent = <RequestOptions>[];
    final api = _api(sent, (o) {
      if (o.path.endsWith('/view')) {
        return <String, dynamic>{'code': 200, 'data': _playerProjection()};
      }
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'activityId': 7,
          'requestId': 'req_12345678',
          'action': 'PLAYER_HINT',
          'outcome': 'PENDING',
          'receiptId': null,
          'revision': 3,
        },
      };
    });

    final view = await api.loadPlayerView(activityId: 7);
    final receipt = await api.readPlayerReceipt(
      activityId: 7,
      requestId: 'req_12345678',
      expectedAction: 'PLAYER_HINT',
    );

    expect(view.role.code, 'detective');
    expect(sent.first.queryParameters['perspective'], 'PLAYER');
    expect(receipt.outcome, GameReceiptOutcome.pending);
  });

  test('玩家终态回执只接受精确 APPLIED 与严格身份整数', () async {
    final invalidReceipts = <Map<String, dynamic>>[
      <String, dynamic>{'outcome': 'COMMITTED'},
      <String, dynamic>{'outcome': 'applied'},
      <String, dynamic>{'action': ''},
      <String, dynamic>{'action': 'player_hint'},
      <String, dynamic>{'action': 'PLAYER_REVEAL'},
      <String, dynamic>{'activityId': 7.5},
      <String, dynamic>{'activityId': 9007199254740992},
      <String, dynamic>{'receiptId': '9001'},
      <String, dynamic>{'receiptId': 9001.5},
      <String, dynamic>{'receiptId': 9007199254740992},
      <String, dynamic>{'revision': 4.5},
      <String, dynamic>{'revision': 9007199254740992},
    ];
    for (final override in invalidReceipts) {
      final api = _api(
        <RequestOptions>[],
        (_) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'activityId': 7,
            'requestId': 'req_12345678',
            'action': 'PLAYER_HINT',
            'outcome': 'APPLIED',
            'receiptId': 9001,
            'revision': 4,
            ...override,
          },
        },
      );

      expect(
        () => api.readPlayerReceipt(
          activityId: 7,
          requestId: 'req_12345678',
          expectedAction: 'PLAYER_HINT',
        ),
        throwsA(isA<GameSessionContractException>()),
        reason: '$override 不得被当成权威回执',
      );
    }
  });

  test('玩家 PENDING 回执中已出现的 action/receiptId/revision 也必须严格', () async {
    final invalidReceipts = <Map<String, dynamic>>[
      <String, dynamic>{'action': 'player_hint'},
      <String, dynamic>{'receiptId': 1.5},
      <String, dynamic>{'revision': 3.5},
    ];
    for (final Map<String, dynamic> override in invalidReceipts) {
      final api = _api(
        <RequestOptions>[],
        (_) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'activityId': 7,
            'requestId': 'req_12345678',
            'action': 'PLAYER_HINT',
            'outcome': 'PENDING',
            'receiptId': null,
            'revision': 3,
            ...override,
          },
        },
      );
      expect(
        () => api.readPlayerReceipt(
          activityId: 7,
          requestId: 'req_12345678',
          expectedAction: 'PLAYER_HINT',
        ),
        throwsA(isA<GameSessionContractException>()),
        reason: '$override 不得被当成可信 pending',
      );
    }
  });

  test('商家终态回执不容忍大小写、小数或超界整数', () async {
    final invalidReceipts = <Map<String, dynamic>>[
      <String, dynamic>{'outcome': 'applied'},
      <String, dynamic>{'action': 'station_accept'},
      <String, dynamic>{'activityId': 7.5},
      <String, dynamic>{'receiptId': '9001'},
      <String, dynamic>{'receiptId': 9001.5},
      <String, dynamic>{'receiptId': 9007199254740992},
      <String, dynamic>{'revision': 4.5},
      <String, dynamic>{'revision': 9007199254740992},
    ];
    for (final override in invalidReceipts) {
      final api = _api(
        <RequestOptions>[],
        (_) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'activityId': 7,
            'requestId': 'req_12345678',
            'action': 'STATION_ACCEPT',
            'outcome': 'APPLIED',
            'receiptId': 9001,
            'revision': 4,
            ...override,
          },
        },
      );

      expect(
        () => api.readReceipt(
          activityId: 7,
          requestId: 'req_12345678',
          expectedAction: 'STATION_ACCEPT',
        ),
        throwsA(isA<GameSessionContractException>()),
        reason: '$override 不得被当成权威回执',
      );
    }
  });

  test('玩家入口保留服务端 reasonCode，不靠文案猜是否未开放', () async {
    final api = _api(
      <RequestOptions>[],
      (_) => <String, dynamic>{
        'code': 500,
        'msg': '本场游戏尚未准备',
        'data': <String, dynamic>{'reasonCode': 'GAME_SESSION_NOT_PREPARED'},
      },
    );

    try {
      await api.loadPlayerView(activityId: 7);
      fail('应该保留业务拒绝');
    } on GameSessionContractException catch (error) {
      expect(error.reasonCode, 'GAME_SESSION_NOT_PREPARED');
      expect(error.message, '本场游戏尚未准备');
    }
  });

  test('READY 站点不因其他站点产生的全局 STATION_PAUSE 而获得暂停权限', () {
    final Map<String, dynamic> raw = _projection();
    raw['availableActions'] = <String>['STATION_PAUSE'];
    final Map<String, dynamic> merchant =
        raw['merchant']! as Map<String, dynamic>;
    final List<Map<String, dynamic>> stations =
        merchant['stations']! as List<Map<String, dynamic>>;
    stations.first['status'] = 'READY';

    final MerchantGameProjection projection = MerchantGameProjection.fromJson(
      raw,
    );

    expect(
      projection.allowsStationAction(
        'STATION_PAUSE',
        projection.stations.single,
      ),
      isFalse,
    );
  });

  test('俱乐部视角用 CLUB 拉取，复盘能否导出只认服务端下发的两个事实', () async {
    final sent = <RequestOptions>[];
    final api = _api(
      sent,
      (_) => <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'activityId': 7,
          'sessionId': 11,
          'perspective': 'CLUB',
          'status': 'ENDED',
          'revision': 3,
          'recap': <String, dynamic>{'exportAvailable': true},
        },
      },
    );

    final ClubRecapState state = await api.loadClubView(activityId: 7);

    expect(state.recapAvailable, isTrue);
    expect(state.exportAvailable, isTrue);
    expect(sent.single.path, '/api/game/session/view');
    expect(sent.single.queryParameters, <String, dynamic>{
      'activityId': 7,
      'perspective': 'CLUB',
    });
  });

  test('俱乐部视角:没复盘不算可导出，坏身份一律失败关闭', () async {
    Future<ClubRecapState> load(Object? data) {
      final api = _api(
        <RequestOptions>[],
        (_) => <String, dynamic>{'code': 200, 'data': data},
      );
      return api.loadClubView(activityId: 7);
    }

    final ClubRecapState empty = await load(<String, dynamic>{
      'activityId': 7,
      'sessionId': 11,
      'perspective': 'CLUB',
      'revision': 3,
    });
    expect(empty.recapAvailable, isFalse, reason: '没下发的指标不能当成零');
    expect(empty.exportAvailable, isFalse);

    // 「未准备」态允许没有 sessionId,别把这一种判成坏回执。
    final ClubRecapState notPrepared = await load(<String, dynamic>{
      'activityId': 7,
      'perspective': 'CLUB',
      'status': 'NOT_PREPARED',
      'revision': 0,
    });
    expect(notPrepared.recapAvailable, isFalse);

    final List<Object?> broken = <Object?>[
      null,
      <String, dynamic>{}, // 没有 perspective / revision / sessionId
      <String, dynamic>{
        'activityId': 8,
        'sessionId': 11,
        'perspective': 'CLUB',
        'revision': 3,
      },
      <String, dynamic>{
        'activityId': 7,
        'sessionId': 11,
        'perspective': 'MERCHANT',
        'revision': 3,
      },
      <String, dynamic>{
        'activityId': 7,
        'sessionId': 11,
        'perspective': 'CLUB',
        'revision': 3.5,
      },
      <String, dynamic>{
        'activityId': 7,
        'perspective': 'CLUB',
        'status': 'ENDED',
        'revision': 3,
      }, // 结束了却没有 sessionId
    ];
    for (final Object? data in broken) {
      await expectLater(
        load(data),
        throwsA(isA<GameSessionContractException>()),
        reason: '$data 不得被当成一局在跑的复盘',
      );
    }
  });

  test('复盘导出走 GET,交出去的是归一化后的白名单,坏数据不进剪贴板', () async {
    final sent = <RequestOptions>[];
    final Map<String, dynamic> envelope = gameRecapExportJson(activityId: 7);
    final api = _api(
      sent,
      (_) => <String, dynamic>{'code': 200, 'data': envelope},
    );

    final Map<String, dynamic> payload = await api.loadClubRecapExport(
      activityId: 7,
    );

    expect(sent.single.path, '/api/game/session/recap/export');
    expect(sent.single.queryParameters, <String, dynamic>{'activityId': 7});
    expect(payload.keys.toList(), <String>[
      'schemaVersion',
      'generatedAt',
      'activityId',
      'sessionId',
      'recap',
    ]);
    expect(payload['sessionId'], 11);

    for (final Map<String, dynamic> broken in <Map<String, dynamic>>[
      <String, dynamic>{...envelope, 'schemaVersion': 'GAME_RECAP_V1'},
      <String, dynamic>{...envelope, 'activityId': 8},
      <String, dynamic>{...envelope, 'sessionId': null},
      <String, dynamic>{...envelope, 'recap': null},
      gameRecapExportWith(
        (Map<String, dynamic> recap) =>
            ((recap['metrics'] as List<dynamic>).first
                    as Map<String, dynamic>)['value'] =
                -1,
      ),
    ]) {
      final bad = _api(
        <RequestOptions>[],
        (_) => <String, dynamic>{'code': 200, 'data': broken},
      );
      await expectLater(
        bad.loadClubRecapExport(activityId: 7),
        throwsA(isA<GameSessionContractException>()),
        reason: '$broken 不得进剪贴板',
      );
    }
  });
}

GameSessionApi _api(
  List<RequestOptions> sent,
  Map<String, dynamic> Function(RequestOptions) respond,
) {
  final client = DioClient(TokenStore(const FlutterSecureStorage()));
  client.dio.httpClientAdapter = _StubAdapter((o) {
    sent.add(o);
    return respond(o);
  });
  return GameSessionApi(client);
}

Map<String, dynamic> _projection() => <String, dynamic>{
  'perspective': 'MERCHANT',
  'sessionId': 2,
  'activityId': 7,
  'status': 'RUNNING',
  'revision': 3,
  'availableActions': <String>['STATION_ACCEPT'],
  'merchant': <String, dynamic>{
    'fallbackOptions': <dynamic>[],
    'stations': <Map<String, dynamic>>[
      <String, dynamic>{
        'stationId': 8,
        'nodeId': 9,
        'nodeName': '密码站',
        'stationCode': 'A1',
        'status': 'INVITED',
        'revision': 3,
        'preparationChecklist': <dynamic>[],
        'playerTask': null,
        'capacity': null,
        'pendingVerificationCount': 0,
      },
    ],
  },
};

Map<String, dynamic> _playerProjection() => <String, dynamic>{
  'perspective': 'PLAYER',
  'sessionId': 2,
  'activityId': 7,
  'status': 'RUNNING',
  'revision': 3,
  'availableActions': <String>['CONFIRM_ROLE', 'PLAYER_HINT'],
  'player': <String, dynamic>{
    'teamId': 5,
    'role': <String, dynamic>{
      'code': 'detective',
      'name': '侦探',
      'status': 'ASSIGNED',
      'publicBrief': '寻找真相',
    },
    'nodes': <dynamic>[],
    'mySubmissions': <dynamic>[],
    'teamActions': <dynamic>[],
    'story': <String, dynamic>{
      'visibleVariables': <String, dynamic>{},
      'ending': null,
    },
  },
};

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.respond);
  final Map<String, dynamic> Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode(respond(options))),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
