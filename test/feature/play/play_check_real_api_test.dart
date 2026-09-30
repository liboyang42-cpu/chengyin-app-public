import 'dart:convert';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/play_check.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// R14 旅程检定四端点 × **真实 PlayApi × stub HTTP adapter**:
/// 线路格式(GET query / POST 表单三字段、字符串化)与 AjaxResult 解析
/// 必须走真实路径 —— 页面层测试挡在假 API 后面,看不见这些。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RoutingAdapter adapter;
  late PlayApi api;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
    adapter = _RoutingAdapter();
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    client.dio.httpClientAdapter = adapter;
    api = PlayApi(client);
  });

  test('encounter GET:topicId+nodeId 走 query;视图原样交给 pick 层', () async {
    adapter.on(
      '/api/play/encounter',
      (_) => <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'allowedActions': <String>['check'],
          'check': <String, dynamic>{
            'checkId': 9,
            'skill': '观察',
            'tier': 'hard',
          },
        },
      },
    );
    final Map<String, dynamic> data = await api.encounter(
      topicId: 23,
      nodeId: 17,
    );
    final RequestOptions sent = adapter.sentFor('/api/play/encounter').single;
    expect(sent.method, 'GET');
    expect(sent.queryParameters['topicId'], 23);
    expect(sent.queryParameters['nodeId'], 17);
    expect(JourneyCheckProblem.fromEncounter(data)?.checkId, '9');
  });

  test('encounter 非 200 抛 PlayException 携带后端原文 —— 页面按静默口径吞掉', () async {
    adapter.on(
      '/api/play/encounter',
      (_) => <String, dynamic>{'code': 500, 'msg': '节点不存在'},
    );
    await expectLater(
      api.encounter(topicId: 23, nodeId: 17),
      throwsA(
        isA<PlayException>().having(
          (PlayException e) => e.message,
          'message',
          '节点不存在',
        ),
      ),
    );
  });

  for (final ({String path, Future<JourneyCheckReceipt> Function() call}) c
      in <({String path, Future<JourneyCheckReceipt> Function() call})>[
        (
          path: '/api/play/check/roll',
          call: () => api.rollCheck(topicId: 23, nodeId: 17, checkId: '9'),
        ),
        (
          path: '/api/play/check/reroll',
          call: () => api.rerollCheck(topicId: 23, nodeId: 17, checkId: '9'),
        ),
        (
          path: '/api/play/check/settle',
          call: () => api.settleCheck(topicId: 23, nodeId: 17, checkId: '9'),
        ),
      ]) {
    test('${c.path}:表单三字段字符串化,回执按 checkReceiptView 同口径解析', () async {
      adapter.on(
        c.path,
        (_) => <String, dynamic>{
          'code': '200',
          'data': <String, dynamic>{
            'tier': 'hard',
            'dc': 3,
            'dice': <dynamic>[4],
            'kept': 4,
            'total': 2,
            'success': false,
            'settled': false,
            'luck': 1,
          },
        },
      );
      final JourneyCheckReceipt r = await c.call();
      final RequestOptions sent = adapter.sentFor(c.path).single;
      expect(sent.method, 'POST');
      expect(_formField(sent, 'topicId'), '23');
      expect(_formField(sent, 'nodeId'), '17');
      expect(_formField(sent, 'checkId'), '9');
      expect(r.dice, <int>[4]);
      expect(r.settled, isFalse);
      expect(r.luck, 1);
    });
  }

  test('roll 被「已结算」拒绝:msg 原样上抛(真源靠 /已结算/ 走幂等 settle 回读)', () async {
    adapter.on(
      '/api/play/check/roll',
      (_) => <String, dynamic>{'code': 409, 'msg': '这次检定已结算，不能再掷'},
    );
    await expectLater(
      api.rollCheck(topicId: 23, nodeId: 17, checkId: '9'),
      throwsA(
        isA<PlayException>()
            .having((PlayException e) => e.code, 'code', 409)
            .having((PlayException e) => e.message, 'message', contains('已结算')),
      ),
    );
  });
}

class _RoutingAdapter implements HttpClientAdapter {
  final Map<String, Map<String, dynamic> Function(RequestOptions)> _handlers =
      <String, Map<String, dynamic> Function(RequestOptions)>{};
  final List<RequestOptions> sent = <RequestOptions>[];

  void on(
    String path,
    Map<String, dynamic> Function(RequestOptions options) handler,
  ) {
    _handlers[path] = handler;
  }

  List<RequestOptions> sentFor(String path) =>
      sent.where((RequestOptions r) => r.path == path).toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent.add(options);
    final handler = _handlers[options.path];
    return ResponseBody.fromString(
      jsonEncode(
        handler == null
            ? <String, dynamic>{
                'code': 404,
                'msg': 'unexpected ${options.path}',
              }
            : handler(options),
      ),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String _formField(RequestOptions request, String key) =>
    (request.data as FormData).fields
        .firstWhere((MapEntry<String, String> e) => e.key == key)
        .value;
