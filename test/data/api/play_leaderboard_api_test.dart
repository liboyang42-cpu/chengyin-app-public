// 同行者榜接口 `/api/play/leaderboard`。
//
// 活动场次(activityId)与自玩主题(topicId)是两个**互斥会话**,后端只认其中一个;
// 客户端接错(两个都发/都不发)会静默拿到错的榜。除了互斥门禁,
// 这里把榜单自洽性(名次从 1 连续、me 与行一致)也钉住——
// 这类回执坏掉时页面照常渲染,只是名次全错,肉眼看不出来。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/play_leaderboard_api.dart';
import 'package:chengyin_app/data/models/play_leaderboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  ({PlayLeaderboardApi api, List<RequestOptions> sent}) build(
    Map<String, dynamic> Function(RequestOptions) reply,
  ) {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final List<RequestOptions> sent = <RequestOptions>[];
    client.dio.httpClientAdapter = _StubAdapter((RequestOptions options) {
      sent.add(options);
      return reply(options);
    });
    return (api: PlayLeaderboardApi(client), sent: sent);
  }

  Map<String, dynamic> entry({
    int? rank = 1,
    int memberId = 11,
    String nickname = '阿岚',
    int score = 5,
  }) => <String, dynamic>{
    if (rank != null) 'rank': rank,
    'memberId': memberId,
    'nickname': nickname,
    'score': score,
  };

  Map<String, dynamic> board({
    List<Map<String, dynamic>>? list,
    Map<String, dynamic>? me,
  }) => <String, dynamic>{
    'list': list ?? <Map<String, dynamic>>[entry()],
    'me': me ?? entry(),
  };

  test('activityId 与 topicId 必须二选一，否则本地拒绝不发请求', () async {
    final r = build((_) => <String, dynamic>{'code': 200, 'data': board()});
    await expectLater(
      r.api.fetch(activityId: 3, topicId: 9),
      throwsA(isA<PlayLeaderboardException>()),
    );
    await expectLater(r.api.fetch(), throwsA(isA<PlayLeaderboardException>()));
    await expectLater(
      r.api.fetch(activityId: 0),
      throwsA(isA<PlayLeaderboardException>()),
    );
    expect(r.sent, isEmpty);
  });

  test('query 只带选中的那个会话 id', () async {
    final r = build(
      (_) => <String, dynamic>{'code': 200, 'data': board()},
    );
    final PlayLeaderboard boardData = await r.api.fetch(topicId: 42);
    expect(boardData.me.displayName, '阿岚');
    expect(r.sent.single.path, '/api/play/leaderboard');
    expect(r.sent.single.queryParameters, <String, Object?>{'topicId': 42});
  });

  test('★ 名次必须从 1 连续——跳号回执按不完整拒绝', () async {
    final r = build(
      (_) => <String, dynamic>{
        'code': 200,
        'data': board(
          list: <Map<String, dynamic>>[
            entry(rank: 1, memberId: 11),
            entry(rank: 3, memberId: 12),
          ],
          me: entry(rank: 1, memberId: 11),
        ),
      },
    );
    await expectLater(
      r.api.fetch(activityId: 3),
      throwsA(isA<PlayLeaderboardException>()),
    );
  });

  test('★ me 在榜上时名次与分数必须与行一致', () async {
    final r = build(
      (_) => <String, dynamic>{
        'code': 200,
        'data': board(
          list: <Map<String, dynamic>>[entry(rank: 1, memberId: 11, score: 5)],
          me: entry(rank: 1, memberId: 11, score: 6),
        ),
      },
    );
    await expectLater(
      r.api.fetch(activityId: 3),
      throwsA(isA<PlayLeaderboardException>()),
    );
  });

  test('★ 名次缺省时 memberId 不许出现在榜上——否则名次是丢的', () async {
    final r = build(
      (_) => <String, dynamic>{
        'code': 200,
        'data': board(
          list: <Map<String, dynamic>>[entry(rank: 1, memberId: 11)],
          me: entry(rank: null, memberId: 11),
        ),
      },
    );
    await expectLater(
      r.api.fetch(activityId: 3),
      throwsA(isA<PlayLeaderboardException>()),
    );
  });

  test('me 在榜外(未上榜)允许没有名次，读回 rank 为空', () async {
    final r = build(
      (_) => <String, dynamic>{
        'code': 200,
        'data': board(
          list: <Map<String, dynamic>>[entry(rank: 1, memberId: 11)],
          me: entry(rank: null, memberId: 99),
        ),
      },
    );
    final PlayLeaderboard result = await r.api.fetch(activityId: 3);
    expect(result.me.rank, isNull);
    expect(result.me.memberId, 99);
  });

  test('★ 同一 memberId 出现两次按不完整拒绝', () async {
    final r = build(
      (_) => <String, dynamic>{
        'code': 200,
        'data': board(
          list: <Map<String, dynamic>>[
            entry(rank: 1, memberId: 11),
            entry(rank: 2, memberId: 11),
          ],
          me: entry(rank: 1, memberId: 11),
        ),
      },
    );
    await expectLater(
      r.api.fetch(activityId: 3),
      throwsA(isA<PlayLeaderboardException>()),
    );
  });

  test('业务码非 200 时带后端 msg', () async {
    final r = build(
      (_) => <String, dynamic>{'code': 403, 'msg': '这场还没结束'},
    );
    await expectLater(
      r.api.fetch(activityId: 3),
      throwsA(
        isA<PlayLeaderboardException>().having(
          (PlayLeaderboardException e) => e.message,
          'message',
          '这场还没结束',
        ),
      ),
    );
  });
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.onRequest);
  final Map<String, dynamic> Function(RequestOptions) onRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(onRequest(options)),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
