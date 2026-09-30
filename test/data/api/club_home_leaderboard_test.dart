// 俱乐部首页四段 + 贡献榜 + 群聊。
//
// 这一批的坑全在**语义**上,不在传输上 —— 每一条都是「HTTP 200、界面照渲、内容是错的」:
//   ① 排行榜的 pace / completionDuration,**null ≠ 0**。
//      兜成 0 的人会以「0.0 min/km」稳居榜首,而他恰恰是没有有效计时的那个。
//   ② leaderboard 的 body 键是 `id` 不是 `clubId`,传错走「缺少俱乐部ID」。
//   ③ 首页的 events 是后端**手搭的 Map**(title/cover),不是主题实体(name/imgUrl)。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/models/club.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  ({ClubApi api, List<RequestOptions> sent}) build(Map<String, dynamic> reply) {
    final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
    final List<RequestOptions> sent = <RequestOptions>[];
    c.dio.httpClientAdapter = _StubAdapter((RequestOptions o) {
      sent.add(o);
      return reply;
    });
    return (api: ClubApi(c), sent: sent);
  }

  group('首页四段', () {
    test('★ 四段各归各位,别混成一个扁平列表', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'owned': <dynamic>[
            <String, dynamic>{'id': 1, 'name': '我的团', 'isOwner': true},
          ],
          'joined': <dynamic>[
            <String, dynamic>{'id': 2, 'name': '加入的', 'isJoined': true},
          ],
          'nearby': <dynamic>[
            <String, dynamic>{'id': 3, 'name': '附近的'},
          ],
          'events': <dynamic>[
            <String, dynamic>{
              'id': 9,
              'title': '周末城南',
              'cover': 'https://x/c.png',
              'clubId': 1,
            },
          ],
        },
      });
      final ClubHome h = await r.api.home();
      expect(h.owned.single.name, '我的团');
      expect(h.joined.single.name, '加入的');
      expect(h.nearby.single.name, '附近的');
      expect(h.isEmpty, isFalse);
    });

    test('★ events 用 title/cover 解析 —— 照主题实体的 name/imgUrl 解会全空', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'events': <dynamic>[
            <String, dynamic>{
              'id': 9,
              'title': '周末城南',
              'cover': 'https://x/c.png',
              'clubId': 1,
            },
          ],
        },
      });
      final ClubHomeEvent e = (await r.api.home()).events.single;
      expect(e.title, '周末城南');
      expect(e.cover, 'https://x/c.png');
      expect(e.clubId, 1);
    });

    test('四段都空 → isEmpty,不是异常', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      expect((await r.api.home()).isEmpty, isTrue);
    });
  });

  group('贡献榜', () {
    test('★ body 键是 id 不是 clubId', () async {
      final r = build(<String, dynamic>{'code': 200, 'data': <dynamic>[]});
      await r.api.leaderboard(42, sort: ClubRankSort.pace);
      final Map<String, dynamic> sent = (r.sent.single.data as Map)
          .cast<String, dynamic>();
      expect(
        sent['id'],
        42,
        reason: '后端读的是 body.get("id");传 clubId 会走「缺少俱乐部ID」',
      );
      expect(sent.containsKey('clubId'), isFalse);
      expect(sent['sortBy'], 'pace');
    });

    test('★★ pace 为 null 时必须保持 null —— 兜成 0 的人会稳居配速榜首', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <dynamic>[
          <String, dynamic>{
            'memberId': 7,
            'nickname': '零里程的人',
            'score': 0,
            'mileage': 0,
            'durationMin': 0,
            'clearCount': 0,
            'hostedCount': 0,
            'pace': null,
            'completionDuration': null,
          },
        ],
      });
      final ClubRankRow row = (await r.api.leaderboard(1)).single;
      expect(row.pace, isNull, reason: '0.0 min/km = 无限快,会把没有有效计时的人捧成第一');
      expect(row.completionDuration, isNull, reason: '0 不是「0 分钟完成」,是「没有有效计时」');
      // 而真正该是 0 的计数字段确实是 0,不能一刀切全变 null。
      expect(row.clearCount, 0);
      expect(row.mileage, 0);
    });

    test('有配速时照收', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <dynamic>[
          <String, dynamic>{
            'memberId': 7,
            'score': 12.5,
            'mileage': 8.2,
            'durationMin': 49.2,
            'clearCount': 3,
            'hostedCount': 1,
            'pace': 6.0,
            'completionDuration': 49.2,
          },
        ],
      });
      final ClubRankRow row = (await r.api.leaderboard(1)).single;
      expect(row.pace, 6.0);
      expect(row.hostedCount, 1);
    });

    test('四个排序维度的 wire 值和后端白名单一致', () {
      // 后端 comparatorFor 只认这三个字符串,其余回落 composite。
      expect(ClubRankSort.values.map((s) => s.wire).toSet(), <String>{
        'composite',
        'mileage',
        'pace',
        'duration',
      });
    });
  });

  group('群聊', () {
    test('★ 非成员进群聊 → 原文提示,不是「打不开」', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '加入俱乐部后才能进群聊'});
      await expectLater(
        r.api.chatConversationId(1),
        throwsA(predicate((Object e) => e.toString().contains('加入俱乐部后才能进群聊'))),
      );
    });

    test('群聊拿到会话号', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'conversationId': 3001},
      });
      expect(await r.api.chatConversationId(1), 3001);
    });
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
