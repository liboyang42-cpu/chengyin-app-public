// 主题管理向两条端点的**报文级**门:
//   ① `/api/club/crm/topic-manage-stats` —— 管理身份与四项统计的真源
//      (小程序拍板1,2026-09-17:不再拿 isOwner 猜);
//   ② `/api/club/lead/edit-ops` —— HO-26 承接方领队改这一场的集合时间。
//
// 为什么不能只测 UI:三条 open-settings 一度被拼成 `'/api/.../$tail'`,
// 于是全仓 rg 搜不到路径、端点裁判(`tool/endpoint_parity.py`)判「App 没接」,
// 而 UI 测试全绿。判据只能是实际发出去的路径 + body + 回读。
//
// 口径对齐小程序 pages/club/topic-detail/index.js(@7bdeb58de):
//   ① POST + JSON,body `{clubId, topicId, activityId}`(没有这一场就传 null);
//   ② POST + JSON,body `{activityId, startDate: 'YYYY-MM-DD HH:mm:00'}`。

import 'dart:convert';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/club_api.dart' show ClubApiException;
import 'package:chengyin_app/data/api/club_topic_ops_api.dart';
import 'package:chengyin_app/data/models/club_topic_ops.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('管理向统计:路径是字面量,body 带 activityId(没有这一场就是 null)', () async {
    final harness = _build(<Object>[
      _ok(<String, dynamic>{
        'canDirect': true,
        'canManageSessions': true,
        'canViewVerify': false,
        'nodeCount': 5,
        'sessionHeadcount': 3,
        'pendingVerifyCount': 1,
        'verifiedByMeCount': 2,
      }),
    ]);

    final ClubTopicManageStats fromTopic = await harness.api.manageStats(
      clubId: 7,
      topicId: 88,
    );

    expect(harness.sent.single.path, '/api/club/crm/topic-manage-stats');
    expect(harness.sent.single.data, <String, dynamic>{
      'clubId': 7,
      'topicId': 88,
      'activityId': null,
    });
    expect(
      harness.sent.single.headers[Headers.contentTypeHeader],
      contains(Headers.jsonContentType),
    );
    expect(fromTopic.canDirect, isTrue);
    expect(fromTopic.canManageSessions, isTrue);
    // 字段没下发 / 下发 false 都是「不能」—— 不许兜底成 true。
    expect(fromTopic.canViewVerify, isFalse);
    expect(fromTopic.nodeCount, 5);
    expect(fromTopic.sessionHeadcount, 3);
    expect(fromTopic.pendingVerifyCount, 1);
    expect(fromTopic.verifiedByMeCount, 2);

    // 从场次进来:统计要按这一场的口径重拉。
    final harness2 = _build(<Object>[
      _ok(<String, dynamic>{'canDirect': true}),
    ]);
    await harness2.api.manageStats(clubId: 7, topicId: 88, activityId: 702);
    expect(harness2.sent.single.data, <String, dynamic>{
      'clubId': 7,
      'topicId': 88,
      'activityId': 702,
    });
  });

  test('管理身份:只有 true 算 true,1 也算(后端 Boolean 的两种写法)', () async {
    final harness = _build(<Object>[
      _ok(<String, dynamic>{
        'canDirect': 1,
        'canManageSessions': 0,
        'canViewVerify': 'true',
      }),
    ]);
    final stats = await harness.api.manageStats(clubId: 7, topicId: 88);
    expect(stats.canDirect, isTrue);
    expect(stats.canManageSessions, isFalse);
    expect(stats.canViewVerify, isTrue);

    // 整个 data 缺席 = 回执不完整,不许当成「全都没有权限」静默画出普通成员页。
    final broken = _build(<Object>[_ok(null)]);
    await expectLater(
      broken.api.manageStats(clubId: 7, topicId: 88),
      throwsA(
        isA<ClubApiException>().having(
          (ClubApiException error) => error.message,
          'message',
          '管理向统计回执不完整',
        ),
      ),
    );
  });

  test('改集合时间:路径是字面量,body 是 {activityId, 秒级 startDate}', () async {
    final harness = _build(<Object>[_ok('ok')]);

    await harness.api.editOps(
      activityId: 702,
      startDate: '2026-09-10 10:30:00',
    );

    expect(harness.sent.single.path, '/api/club/lead/edit-ops');
    expect(harness.sent.single.data, <String, dynamic>{
      'activityId': 702,
      'startDate': '2026-09-10 10:30:00',
    });
    expect(
      harness.sent.single.headers[Headers.contentTypeHeader],
      contains(Headers.jsonContentType),
    );
  });

  test('改集合时间:后端拒绝的原文原样抛出(已售锁定 / 不是承接方领队)', () async {
    final harness = _build(<Object>[
      <String, dynamic>{'code': 403, 'msg': '已有人报名，集合时间与地点不可改'},
    ]);

    await expectLater(
      harness.api.editOps(activityId: 702, startDate: '2026-09-10 10:30:00'),
      throwsA(
        isA<ClubApiException>().having(
          (ClubApiException error) => error.message,
          'message',
          '已有人报名，集合时间与地点不可改',
        ),
      ),
    );
  });
}

Map<String, dynamic> _ok(Object? data) => <String, dynamic>{
  'code': 200,
  'data': data,
};

({ClubTopicOpsApi api, List<RequestOptions> sent}) _build(
  List<Object> replies,
) {
  final DioClient client = DioClient(TokenStore(const FlutterSecureStorage()));
  final List<RequestOptions> sent = <RequestOptions>[];
  client.dio.httpClientAdapter = _QueueAdapter((RequestOptions request) {
    sent.add(request);
    final Object reply = replies.removeAt(0);
    if (reply is Exception) throw reply;
    return reply as Map<String, dynamic>;
  });
  return (api: ClubTopicOpsApi(client), sent: sent);
}

class _QueueAdapter implements HttpClientAdapter {
  _QueueAdapter(this.handler);

  final Map<String, dynamic> Function(RequestOptions request) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(handler(options)),
    200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
