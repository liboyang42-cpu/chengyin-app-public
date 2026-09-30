import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../models/npc.dart';
import '../models/shop_npc_models.dart';

/// 店铺分身对话的后端业务错误(AjaxResult.code != 200),携带后端原文 [message]。
///
/// ⚠️ 这条 msg 是**要端给玩家看的服务端原话**,不是只给日志看的:
/// 闸关时后端说的是「店铺分身对话还没开放」,把它换成自己编的「我有点忙」
/// 是假话,玩家会一直重试(样机 index.js:1372 注释)。
class ShopNpcException implements Exception {
  ShopNpcException(this.message);

  /// 后端 msg。后端没给话时是 null,由调用方 `replyTextOr` 回落到兜底句。
  final String? message;

  @override
  String toString() => message ?? '店铺分身没答上来';
}

/// NPC 陪伴 API: 出场 / 事件冒泡 / 自由追问 SSE / 店铺分身对话。
class AiNpcApi {
  AiNpcApi(this._client);

  final DioClient _client;

  /// 取出场 NPC。
  /// [scope] 'global' → 全局 NPC; 'activity' → 局内 NPC。
  Future<List<NpcProfile>> fetchProfiles({
    String scope = 'global',
    int? activityId,
  }) async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/ai/npc/profile',
      queryParameters: <String, dynamic>{
        'scope': scope,
        if (activityId != null) 'activityId': activityId,
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    final data = body['data'] as Map<String, dynamic>?;
    final list = data?['npcs'] as List<dynamic>? ?? [];
    return list
        .map((e) => NpcProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 取事件冒泡话术(查缓存,≤200ms)。
  Future<NpcLine> fetchEventLine({
    required int profileId,
    required String eventType,
    int? nodeId,
  }) async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/ai/npc/event',
      queryParameters: <String, dynamic>{
        'profileId': profileId,
        'eventType': eventType,
        if (nodeId != null) 'nodeId': nodeId,
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    final data = body['data'] as Map<String, dynamic>? ?? {};
    return NpcLine.fromJson(data);
  }

  /// 门店分身自由追问(自由探索屏④)。`POST /api/ai/npc/shop-chat`。
  ///
  /// [requestId] 由本端生成(uuid4),后端按 (user, requestId) 幂等 ——
  /// 网络抖动重发不会二次调用模型、不会二次计费。
  ///
  /// ⚠️ 后端这条闸(`feature.flag.shopNpcChat`)**默认关**,关时返回
  /// `code=403` +「店铺分身对话还没开放」。RuoYi 的 AjaxResult 走 **HTTP 200**
  /// + body.code,所以 dio 不会抛,必须自己判 code —— 只看 HTTP 状态码的话
  /// 闸关会被当成一次成功的空回答。
  ///
  /// 非 200 一律抛 [ShopNpcException] 并原样带上后端 msg;调用方用
  /// `replyTextOr` 把它端给玩家,别在这里吞掉。
  Future<ShopNpcReply> shopChat({
    required String requestId,
    required int nodeId,
    required String message,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/ai/npc/shop-chat',
      data: <String, dynamic>{
        'requestId': requestId,
        'nodeId': nodeId,
        'message': message,
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw ShopNpcException(body['msg'] as String?);
    }
    return ShopNpcReply.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 门店分身**语音**提问(自由探索屏④,按住说话)。`POST /api/ai/npc/voice-chat`。
  ///
  /// 走的是 [DioClient] 这个统一出口 —— 认证头由拦截器注入,不裸调 http。
  /// ⚠️ 样机注释:「裸调上传会同时漏掉生产写闸与认证头,而这条链路**是要花钱的
  /// 写操作**」(转写 + 模型两次计费)。
  ///
  /// ⚠️ **音频刻意不落盘**:后端 `voiceChat` 只把字节在内存里转成文字,不进 OSS
  /// (`ApiAiNpcController:253`)。所以这里也**不能**顺手复用
  /// `PlayApi.uploadImage` 那条 `/api/common/uploadOSS` ——
  /// 那条会把玩家的声音留在对象存储里,凭空多出一份没人管的声纹数据。
  ///
  /// 返回的 [ShopNpcReply.asr] 取自 **AjaxResult 顶层**的 `asr`
  /// (`ApiAiNpcController:296` `ok.put("asr", text)`),不在 data 里 ——
  /// 顺手写 `data['asr']` 会永远拿到 null 且不报错。
  ///
  /// 非 200 一律抛 [ShopNpcException] 并原样带上后端 msg(闸关时是
  /// 「店铺分身对话还没开放」,ASR 没接时是「语音识别还没接入，先打字问我」)。
  Future<ShopNpcReply> voiceChat({
    required String requestId,
    required int nodeId,
    required String filePath,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/ai/npc/voice-chat',
      data: FormData.fromMap(<String, dynamic>{
        // 字段名 'file' 由后端 @RequestPart("file") 钉死。
        'file': await MultipartFile.fromFile(
          filePath,
          filename: filePath.split('/').last,
        ),
        'nodeId': nodeId.toString(),
        'requestId': requestId,
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw ShopNpcException(body['msg'] as String?);
    }
    return ShopNpcReply.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      asr: body['asr'] as String?,
    );
  }

  /// 自由追问 SSE 流式。返回逐 delta 的 Stream。
  Stream<String> chatStream({
    required int activityId,
    required int profileId,
    required String message,
  }) {
    return _client.sse('/api/ai/npc/chat', <String, dynamic>{
      'activityId': activityId,
      'profileId': profileId,
      'message': message,
    });
  }
}
