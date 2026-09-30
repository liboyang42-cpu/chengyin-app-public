// 店铺分身对话(屏④)的模型与接口契约。
//
// ⚠️ fixture 一律喂**后端真实形状的 map**,不许用构造函数造对象 ——
//   构造函数造出来的对象只证明我会填字段,不证明 `fromJson` 会从后端那个形状里读到它。
//
// 后端真源:`ApiAiNpcController#shopChat`(:192)返回 `success(NpcChatResp)`,
// 即 `{code:200, msg:'操作成功', data:{...NpcChatResp}}`;
// 语音那条 `#voiceChat`(:294-296)在 **AjaxResult 顶层** 再 `put("asr", text)`,
// 所以 asr 与 safeText **不在同一层**。

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/ai_npc_api.dart';
import 'package:chengyin_app/data/models/shop_npc_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  test('safeText 优先于 text —— 后端拒绝时给的是安全兜底', () {
    final ShopNpcReply r = ShopNpcReply.fromJson(<String, dynamic>{
      'safeText': '这个不方便说',
      'text': '内部原文',
    });
    expect(r.text, '这个不方便说');
  });

  test('只有 text 时取 text', () {
    expect(ShopNpcReply.fromJson(<String, dynamic>{'text': '在的'}).text, '在的');
  });

  test('safeText 是空串时落到 text —— 样机是 JS 的 `||`,不是 `??`', () {
    // NpcChatResp 的 safeText 是 String 字段,拒绝路径之外可能是 ''(不是 null)。
    // 用 `??` 的话空串会赢,页面上就挂一条空回答。
    final ShopNpcReply r = ShopNpcReply.fromJson(<String, dynamic>{
      'safeText': '',
      'text': '九点关门',
    });
    expect(r.text, '九点关门');
  });

  test('两个都没有 ⇒ 空串,由调用方决定兜底文案(口径只能有一份)', () {
    expect(ShopNpcReply.fromJson(<String, dynamic>{}).text, isEmpty);
  });

  test('★ asr 不在 data 里 —— 后端把它 put 在 AjaxResult 顶层', () {
    // 谁要是顺手写 `j['asr']` 去读 data,会永远拿到 null 而**不报错**:
    // 玩家看不见自己被听成了什么,却没有任何征兆。
    final ShopNpcReply naive = ShopNpcReply.fromJson(<String, dynamic>{
      'safeText': '九点',
      'asr': '几点关门',
    });
    expect(
      naive.asr,
      isNull,
      reason: 'data 里的 asr 是不存在的形状;真的那份要由调用方从顶层取来传进来',
    );
    final ShopNpcReply real = ShopNpcReply.fromJson(<String, dynamic>{
      'safeText': '九点',
    }, asr: '几点关门');
    expect(real.asr, '几点关门');
  });

  // ⚠️ 这两条**故意**用构造函数,不是漏了 fromJson:
  //   `ShopNpcMessage` 是本端自己攒的一条消息(样机 index.js:1355 `msgs.concat([{id, role, text}])`),
  //   后端没有任何端点返回这个形状 —— 给它编一个 fromJson 才是造假 fixture。
  //   走 fromJson 的是 `ShopNpcReply`(上面那几条),那才是真的下行数据。
  test('★ 重答改写时 id 保持不变 —— 换 id 会让列表判成新节点,整条重新入场闪一下', () {
    const ShopNpcMessage before = ShopNpcMessage(
      id: 7,
      mine: false,
      text: '九点关门',
    );
    final ShopNpcMessage after = before.copyWithText('九点半关门');
    expect((after.id, after.mine, after.text), (7, false, '九点半关门'));
  });

  test('★ 闸关时把后端原话原样抛出来 —— 这条 msg 是要端给玩家看的', () async {
    // 后端 shopChatOn() 默认关,关时 AjaxResult.error(403, "店铺分身对话还没开放")。
    // RuoYi 的 AjaxResult 走 HTTP 200 + body.code=403,所以 dio 不会抛,得自己判 code。
    final DioClient client = _client();
    final _StubAdapter adapter = _StubAdapter(<String, dynamic>{
      'code': 403,
      'msg': '店铺分身对话还没开放',
    });
    client.dio.httpClientAdapter = adapter;

    await expectLater(
      AiNpcApi(client).shopChat(requestId: 'req-1', nodeId: 88, message: '几点关门'),
      throwsA(
        isA<ShopNpcException>().having(
          (ShopNpcException e) => e.message,
          'message',
          '店铺分身对话还没开放',
        ),
      ),
    );
  });

  test('★ requestId / nodeId / message 三个都要送到 —— 幂等靠 requestId', () async {
    final DioClient client = _client();
    final _StubAdapter adapter = _StubAdapter(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{'safeText': '九点关门', 'requestId': 'req-9'},
    });
    client.dio.httpClientAdapter = adapter;

    final ShopNpcReply r = await AiNpcApi(
      client,
    ).shopChat(requestId: 'req-9', nodeId: 88, message: '几点关门');

    expect(adapter.request.path, '/api/ai/npc/shop-chat');
    expect(adapter.request.method, 'POST');
    final Map<String, dynamic> sent =
        adapter.request.data as Map<String, dynamic>;
    expect((sent['requestId'], sent['nodeId'], sent['message']), (
      'req-9',
      88,
      '几点关门',
    ));
    expect(r.text, '九点关门');
  });

  test('★ 语音:asr 从 AjaxResult 顶层取,回答从 data 取', () async {
    // 后端 `#voiceChat` 先 success(NpcChatResp),再往**顶层** put("asr", text)。
    // 顺手写 `data['asr']` 会永远拿到 null 且不报错 —— 玩家看不见自己被听成了什么,
    // 却没有任何征兆。
    final DioClient client = _client();
    client.dio.httpClientAdapter = _StubAdapter(<String, dynamic>{
      'code': 200,
      'msg': '操作成功',
      'asr': '几点关门',
      'data': <String, dynamic>{'text': '九点'},
    });

    final ShopNpcReply r = await AiNpcApi(client).voiceChat(
      requestId: 'req-v1',
      nodeId: 88,
      filePath: _tempClip().path,
    );

    expect(r.asr, '几点关门');
    expect(r.text, '九点');
  });

  test('★ 语音走 multipart:file / nodeId / requestId 一个都不能少', () async {
    // 走的是 DioClient 这个统一出口(认证头由拦截器注入),不裸调 http ——
    // 这条链路是要花钱的写操作,漏了认证头就是 401,漏了 requestId 就没有幂等。
    final DioClient client = _client();
    final _StubAdapter adapter = _StubAdapter(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{'text': '九点'},
    });
    client.dio.httpClientAdapter = adapter;

    await AiNpcApi(client).voiceChat(
      requestId: 'req-v9',
      nodeId: 88,
      filePath: _tempClip().path,
    );

    expect(adapter.request.path, '/api/ai/npc/voice-chat');
    expect(adapter.request.method, 'POST');
    final FormData sent = adapter.request.data as FormData;
    // 后端 @RequestPart("file") + @RequestParam nodeId/requestId,名字都钉死。
    expect(sent.files.single.key, 'file');
    expect(
      Map<String, String>.fromEntries(sent.fields),
      <String, String>{'nodeId': '88', 'requestId': 'req-v9'},
    );
  });

  test('★ 语音闸关 / ASR 没接:抛后端原话,不吞', () async {
    // ASR 至今只有 Noop 实现(available()=false),所以线上这条**必然**走到这里。
    // 吞掉它换成自己编的话,玩家会一直按着说话重试。
    final DioClient client = _client();
    client.dio.httpClientAdapter = _StubAdapter(<String, dynamic>{
      'code': 500,
      'msg': '语音识别还没接入，先打字问我',
    });

    await expectLater(
      AiNpcApi(client).voiceChat(
        requestId: 'req-v2',
        nodeId: 88,
        filePath: _tempClip().path,
      ),
      throwsA(
        isA<ShopNpcException>().having(
          (ShopNpcException e) => e.message,
          'message',
          '语音识别还没接入，先打字问我',
        ),
      ),
    );
  });
}

/// 真建一个临时文件:`MultipartFile.fromFile` 会去读它,拿假路径连请求都发不出去。
File _tempClip() {
  final File f = File(
    '${Directory.systemTemp.path}/shop_npc_api_test_'
    '${DateTime.now().microsecondsSinceEpoch}.m4a',
  );
  f.writeAsBytesSync(<int>[0, 1, 2, 3]);
  addTearDown(() {
    if (f.existsSync()) f.deleteSync();
  });
  return f;
}

DioClient _client() => DioClient(TokenStore(const FlutterSecureStorage()));

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body);

  final Map<String, dynamic> body;
  late RequestOptions request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
