import 'dart:convert';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/activity_waitlist_api.dart';
import 'package:chengyin_app/data/models/activity_waitlist.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  test('读取候补状态只发活动与票种范围，OFFERED 保留兑现凭据', () async {
    final harness = _build(<Object>[
      _ok(<String, dynamic>{
        'id': 19,
        'activityId': 7,
        'ticketId': 11,
        'memberId': 42,
        'state': 'OFFERED',
        'offerToken': 'secret-token',
        'offerExpiresAt': '2026-09-09 12:00:00',
        'eligibilityState': 'ELIGIBLE',
        'waitlistJoinAllowed': true,
      }),
    ]);

    final ActivityWaitlistStatus status = await harness.api.status(
      activityId: 7,
      ticketId: 11,
    );

    expect(harness.sent.single.path, '/api/club/event-ops/waitlist/status');
    expect(harness.sent.single.data, <String, dynamic>{
      'activityId': 7,
      'ticketId': 11,
    });
    expect(status.state, ActivityWaitlistState.offered);
    expect(status.offerId, 19);
    expect(status.offerToken, 'secret-token');
    expect(status.hasActiveOffer, isTrue);
  });

  test('OFFERED 缺 token 不得当成可报名状态', () async {
    final harness = _build(<Object>[
      _ok(<String, dynamic>{
        'id': 19,
        'activityId': 7,
        'ticketId': 11,
        'state': 'OFFERED',
        'offerExpiresAt': '2026-09-09 12:00:00',
        'eligibilityState': 'ELIGIBLE',
        'waitlistJoinAllowed': true,
      }),
    ]);

    await expectLater(
      harness.api.status(activityId: 7, ticketId: 11),
      throwsA(
        isA<ActivityWaitlistException>().having(
          (ActivityWaitlistException error) => error.message,
          'message',
          '候补状态回执不完整',
        ),
      ),
    );
  });

  test('加入候补后必须再读 status，且回读与写回执是同一条队列记录', () async {
    final harness = _build(<Object>[
      _ok(<String, dynamic>{
        'id': 19,
        'activityId': 7,
        'ticketId': 11,
        'state': 'WAITING',
      }),
      _ok(_status(state: 'WAITING', id: 19)),
    ]);

    final ActivityWaitlistStatus status = await harness.api.join(
      activityId: 7,
      ticketId: 11,
    );

    expect(status.state, ActivityWaitlistState.waiting);
    expect(harness.sent.map((RequestOptions request) => request.path), <String>[
      '/api/club/event-ops/waitlist/join',
      '/api/club/event-ops/waitlist/status',
    ]);
  });

  test('加入写入结果未知时，只有 status 已排队才能判成功', () async {
    final harness = _build(<Object>[
      StateError('connection reset'),
      _ok(_status(state: 'WAITING', id: 19)),
    ]);

    final ActivityWaitlistStatus status = await harness.api.join(
      activityId: 7,
      ticketId: 11,
    );

    expect(status.state, ActivityWaitlistState.waiting);
    expect(harness.sent, hasLength(2));
  });

  test('加入被服务端明确拒绝时，不用旧排队读回冒充成功', () async {
    final harness = _build(<Object>[
      <String, dynamic>{'code': 403, 'msg': '仅俱乐部成员可候补'},
      _ok(_status(state: 'WAITING', id: 19)),
    ]);

    await expectLater(
      harness.api.join(activityId: 7, ticketId: 11),
      throwsA(
        isA<ActivityWaitlistException>().having(
          (ActivityWaitlistException error) => error.message,
          'message',
          '仅俱乐部成员可候补',
        ),
      ),
    );
    expect(harness.sent, hasLength(2));
  });

  test('加入回执的活动范围错了，即使随后读到旧排队也不能冒充本次成功', () async {
    final harness = _build(<Object>[
      _ok(<String, dynamic>{
        'id': 88,
        'activityId': 999,
        'ticketId': 11,
        'state': 'WAITING',
      }),
      _ok(_status(state: 'WAITING', id: 19)),
    ]);

    await expectLater(
      harness.api.join(activityId: 7, ticketId: 11),
      throwsA(
        isA<ActivityWaitlistException>().having(
          (ActivityWaitlistException error) => error.message,
          'message',
          '候补服务回执不完整',
        ),
      ),
    );
    expect(harness.sent, hasLength(2));
  });

  test('退出写入结果未知且 status 仍在排队时，不伪造成功', () async {
    final harness = _build(<Object>[
      StateError('connection reset'),
      _ok(_status(state: 'WAITING', id: 19)),
    ]);

    await expectLater(
      harness.api.cancel(activityId: 7, ticketId: 11),
      throwsA(
        isA<ActivityWaitlistException>().having(
          (ActivityWaitlistException error) => error.message,
          'message',
          '退出候补结果未知，请刷新候补状态',
        ),
      ),
    );
  });

  test('非法活动或票种 id 在本地拦截，不发请求', () async {
    final harness = _build(const <Object>[]);

    await expectLater(
      harness.api.status(activityId: 0, ticketId: 11),
      throwsA(isA<ActivityWaitlistException>()),
    );
    await expectLater(
      harness.api.join(activityId: 7, ticketId: -1),
      throwsA(isA<ActivityWaitlistException>()),
    );
    expect(harness.sent, isEmpty);
  });
}

Map<String, dynamic> _ok(Object data) => <String, dynamic>{
  'code': 200,
  'data': data,
};

Map<String, dynamic> _status({required String state, int? id}) =>
    <String, dynamic>{
      'id': ?id,
      'activityId': 7,
      'ticketId': 11,
      'memberId': 42,
      'state': state,
      'eligibilityState': 'ELIGIBLE',
      'waitlistJoinAllowed': true,
    };

({ActivityWaitlistApi api, List<RequestOptions> sent}) _build(
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
  return (
    api: ActivityWaitlistApi(client, now: () => DateTime(2026, 9, 9, 10)),
    sent: sent,
  );
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
