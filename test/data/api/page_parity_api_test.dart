import 'dart:convert';
import 'dart:io';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/page_parity_api.dart';
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

  ({PageParityApi api, List<RequestOptions> sent}) build(
    Map<String, dynamic> Function(RequestOptions) reply,
  ) {
    final client = DioClient(TokenStore(const FlutterSecureStorage()));
    final sent = <RequestOptions>[];
    client.dio.httpClientAdapter = _StubAdapter((RequestOptions options) {
      sent.add(options);
      return reply(options);
    });
    return (api: PageParityApi(client), sent: sent);
  }

  test('组队创建传 ownerType=2 并严格回读 teamId', () async {
    final r = build(
      (_) => <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'teamId': 18},
      },
    );
    expect(await r.api.createActivityTeam(activityId: 7, maxMembers: 3), 18);
    expect(r.sent.single.path, '/api/team/create');
    expect((r.sent.single.data as Map)['ownerType'], 2);
    expect((r.sent.single.data as Map)['ownerId'], 7);
    expect((r.sent.single.data as Map)['maxMembers'], 3);
  });

  test('售后列表使用小程序同名 query，回应使用 JSON', () async {
    final r = build(
      (_) => <String, dynamic>{'code': 200, 'data': <String, dynamic>{}},
    );
    await r.api.aftercareList(bucket: 'PROCESSING', pageNum: 2);
    await r.api.respondAftercare(81, <String, dynamic>{'decision': 'AGREE'});
    expect(r.sent.first.path, '/api/merchant/aftercare/list');
    expect(r.sent.first.method, 'POST');
    expect(r.sent.first.queryParameters['bucket'], 'PROCESSING');
    expect(r.sent.first.queryParameters['pageNum'], 2);
    expect(r.sent.last.path, '/api/merchant/aftercare/respond');
    expect(r.sent.last.queryParameters['refundId'], 81);
    expect((r.sent.last.data as Map)['decision'], 'AGREE');
  });

  test('邀请码、评价和客户详情使用小程序原始合同', () async {
    final r = build(
      (_) => <String, dynamic>{'code': 200, 'data': <String, dynamic>{}},
    );
    await r.api.teamInfo(inviteCode: 'ABCD');
    await r.api.teamJoin('ABCD');
    await r.api.reviews(manage: false, merchantRowId: 8);
    await r.api.customerDetail(9);
    expect((r.sent[0].data as Map)['inviteCode'], 'ABCD');
    expect((r.sent[1].data as Map)['inviteCode'], 'ABCD');
    expect(r.sent[2].method, 'POST');
    expect(r.sent[2].path, '/api/merchant/reviews/public');
    expect(r.sent[2].queryParameters, <String, dynamic>{
      'merchantRowId': 8,
      'pageNum': 1,
      'pageSize': 20,
    });
    expect(r.sent[2].uri.queryParameters['merchantRowId'], '8');
    expect(r.sent[3].method, 'POST');
  });

  test('游戏站点读 MERCHANT 投影，写入统一 command 端点', () async {
    final r = build(
      (_) => <String, dynamic>{'code': 200, 'data': <String, dynamic>{}},
    );
    await r.api.gameSession(9);
    await r.api.gameCommand(<String, dynamic>{'action': 'STATION_ACCEPT'});
    await r.api.gameReceipt(activityId: 9, requestId: 'request-123');
    expect(r.sent.first.path, '/api/game/session/view');
    expect(r.sent.first.queryParameters, <String, dynamic>{
      'activityId': 9,
      'perspective': 'MERCHANT',
    });
    expect(r.sent[1].path, '/api/game/session/command');
    expect(r.sent.last.path, '/api/game/session/receipt');
    expect(r.sent.last.queryParameters['requestId'], 'request-123');
  });

  test('圆桌轻互动保留小程序 stage/value 合同', () async {
    final r = build(
      (_) => <String, dynamic>{'code': 200, 'data': <String, dynamic>{}},
    );
    await r.api.answerCircle(<String, dynamic>{
      'sessionId': 3,
      'stage': 'SELF_MOMENT',
      'value': '这一刻',
    });
    expect(r.sent.single.path, '/api/circle-theme/session/answer');
    expect(r.sent.single.data, <String, dynamic>{
      'sessionId': 3,
      'stage': 'SELF_MOMENT',
      'value': '这一刻',
    });
  });

  test('经营团队动作不允许任意拼接路径', () async {
    final r = build(
      (_) => <String, dynamic>{'code': 200, 'data': <String, dynamic>{}},
    );
    await r.api.operatorMutation('invite/revoke', <String, dynamic>{});
    expect(r.sent.single.path, '/api/merchant/operators/invite/revoke');
    expect(
      () => r.api.operatorMutation('../unknown', <String, dynamic>{}),
      throwsA(isA<PageParityApiException>()),
    );
  });

  test('兼容小程序后端的字符串成功码', () async {
    final r = build(
      (_) => <String, dynamic>{
        'code': '200',
        'data': <String, dynamic>{'teamId': 19},
      },
    );
    expect(await r.api.createActivityTeam(activityId: 7, maxMembers: 2), 19);
  });

  test('评价写入必须回读与本次意图匹配的终态回执', () async {
    final responses = <Map<String, dynamic>>[
      <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'reviewId': 41,
          'status': 'PENDING_REVIEW',
          'version': 0,
          'replayed': false,
          'auditTaskId': 81,
        },
      },
      <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'reviewId': 41,
          'status': 'VISIBLE',
          'version': 3,
          'replayed': false,
        },
      },
      <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'reviewId': 41,
          'status': 'PENDING_PLATFORM_REVIEW',
          'replayed': false,
          'auditTaskId': 82,
        },
      },
    ];
    final r = build((_) => responses.removeAt(0));

    expect(
      (await r.api.createReview(<String, dynamic>{
        'merchantRowId': 5,
        'registrationId': 9,
        'rating': 5,
        'content': '很好',
        'imageUrls': const <String>[],
        'requestId': 'mr-create-stable',
      }))['reviewId'],
      41,
    );
    expect(
      (await r.api.replyReview(<String, dynamic>{
        'reviewId': 41,
        'expectedVersion': 2,
        'content': '谢谢',
        'requestId': 'mr-reply-stable',
      }))['version'],
      3,
    );
    expect(
      (await r.api.reportReview(<String, dynamic>{
        'reviewId': 41,
        'expectedVersion': 3,
        'reason': '不实内容',
        'requestId': 'mr-report-stable',
      }, manage: false))['status'],
      'PENDING_PLATFORM_REVIEW',
    );
  });

  test('评价回执缺失、身份不匹配或状态不对都不得显示成功', () async {
    final responses = <Map<String, dynamic>>[
      <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'status': 'PENDING_REVIEW',
          'version': 0,
          'replayed': false,
          'auditTaskId': 81,
        },
      },
      <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'reviewId': 99,
          'status': 'VISIBLE',
          'version': 3,
          'replayed': false,
        },
      },
      <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'reviewId': 41,
          'status': 'VISIBLE',
          'replayed': false,
          'auditTaskId': 82,
        },
      },
    ];
    final r = build((_) => responses.removeAt(0));

    await expectLater(
      r.api.createReview(<String, dynamic>{'requestId': 'mr-create-stable'}),
      throwsA(isA<PageParityApiException>()),
    );
    await expectLater(
      r.api.replyReview(<String, dynamic>{
        'reviewId': 41,
        'expectedVersion': 2,
        'requestId': 'mr-reply-stable',
      }),
      throwsA(isA<PageParityApiException>()),
    );
    await expectLater(
      r.api.reportReview(<String, dynamic>{
        'reviewId': 41,
        'requestId': 'mr-report-stable',
      }, manage: false),
      throwsA(isA<PageParityApiException>()),
    );
  });

  test('售后凭证上传回读 fileName 而非公开 URL', () async {
    final r = build(
      (_) => <String, dynamic>{
        'code': 200,
        'fileName': 'merchant_aftercare_evidence/2026/09/proof.jpg',
      },
    );
    final Directory temp = await Directory.systemTemp.createTemp(
      'aftercare-evidence-',
    );
    final File proof = File('${temp.path}/proof.jpg');
    await proof.writeAsBytes(const <int>[1, 2, 3]);
    addTearDown(() => temp.delete(recursive: true));
    expect(
      await r.api.uploadAftercareEvidence(proof.path),
      'merchant_aftercare_evidence/2026/09/proof.jpg',
    );
    final FormData data = r.sent.single.data as FormData;
    expect(r.sent.single.path, '/api/common/uploadOSS');
    expect(
      data.fields.any(
        (field) =>
            field.key == 'bizType' &&
            field.value == 'merchant_aftercare_evidence',
      ),
      isTrue,
    );
  });

  test('供给复核走小程序同名字段 topicId/scope,复核规则的话原样透传', () async {
    final r = build(
      (_) => <String, dynamic>{'code': 200, 'data': <String, dynamic>{}},
    );
    await r.api.reviewCircleInstance(topicId: 12, scope: 'MERCHANT');
    expect(r.sent.single.path, '/api/circle-theme/instance/review');
    expect(r.sent.single.method, 'POST');
    expect((r.sent.single.data as Map)['topicId'], 12);
    expect((r.sent.single.data as Map)['scope'], 'MERCHANT');

    // 主办方不带 scope 时送空串(小程序 data.operationScope 为 undefined)。
    await r.api.reviewCircleInstance(topicId: 12);
    expect((r.sent.last.data as Map)['scope'], '');

    // 「少于 3 家 / 资料过期」是复核规则的正常回话 —— 不许改写成「网络异常请重试」。
    final failure = build(
      (_) => <String, dynamic>{'code': 500, 'msg': '当前有效商家不足 3 家,城市实例暂不开放'},
    );
    await expectLater(
      failure.api.reviewCircleInstance(topicId: 12),
      throwsA(
        isA<PageParityApiException>().having(
          (PageParityApiException e) => e.message,
          'message',
          '当前有效商家不足 3 家,城市实例暂不开放',
        ),
      ),
    );
  });
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.reply);
  final Map<String, dynamic> Function(RequestOptions) reply;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(reply(options)),
    200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
