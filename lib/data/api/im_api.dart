import '../../core/network/request_session_scope.dart';
import 'package:dio/dio.dart';
import '../../core/network/dio_client.dart';
import '../models/im.dart';

/// IM 接口失败。★ 带 [errorCode] 上来 —— 页面只按它判「组局已结束」这类**终态**
/// (对齐小程序 im/chat:`response.errorCode === 'HANGOUT_CLOSED'`),
/// 而不是去解析 msg 文案(文案会改,码不会)。
/// 口径照抄 `team_map_api.dart` 的 `TeamMapApiException`。
class ImApiException implements Exception {
  const ImApiException(this.message, {this.errorCode = '', this.localReason});

  final String message;
  final ImLocalFailure? localReason;

  /// 后端回执顶层的 errorCode(如 HANGOUT_CLOSED),没有就空串。
  final String errorCode;

  @override
  String toString() => message;
}

/// 站内消息(IM)接口。对齐后端 `ApiImController`(/api/im)+ `ImServiceImpl`。
/// data 形态:
/// - conversations → success(List)        裸 List(在 body.data)。
/// - messages      → success(Map)          {list,nextCursor,hasMore}。
/// - send          → success(ImMessage)    对象。
/// - read          → success()             无 data。
/// 后端形参为表单 String,用 FormData。
class ImApi {
  ImApi(this._client);
  final DioClient _client;

  /// 我的会话列表:`POST /api/im/conversations`(无参,取当前登录用户)。
  Future<List<Conversation>> conversations() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/im/conversations',
      options: RequestSessionScope.options(),
      data: FormData.fromMap(<String, dynamic>{}),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    final rows = (body['data'] as List<dynamic>?) ?? <dynamic>[];
    return rows
        .map((dynamic e) => Conversation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 会话消息分页:`POST /api/im/messages`(参数 conversation_id、cursor_id、size)。
  /// 返回的 list 已按时间正序(旧→新)。cursorId=0 表示拉最新一页。
  Future<ChatPage> messages(
    int conversationId, {
    int cursorId = 0,
    int size = 30,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/im/messages',
      options: RequestSessionScope.options(),
      data: FormData.fromMap(<String, dynamic>{
        'conversation_id': conversationId.toString(),
        'cursor_id': cursorId.toString(),
        'size': size.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    // ★ 这一条用带 errorCode 的抛法:加载会话消息是唯一会收到
    //   HANGOUT_CLOSED(组局已结束)的回执,页面据此进终态而不是「网络错误」。
    _ensureOkTyped(body);
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return ChatPage.fromJson(data);
  }

  /// 发送消息:`POST /api/im/send`(conversation_id、msg_type、content
  /// 以及卡片用的 extra_json)。返回新建的 `ChatMessage`。
  ///
  /// ⚠️ [extraJson] 此前**没有** —— 而 kMsgCard(3) 与 ChatMessage.extraJson
  ///   一直都在:常量有、模型有、就是发不出去。
  ///   于是 App 只能发文本和图,发不了路线/活动卡片。
  ///   小程序那边 `sendCard` 发的正是 `msg_type:3 + extra_json`。
  Future<ChatMessage> send(
    int conversationId, {
    required String content,
    int msgType = kMsgText,
    String? extraJson,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/im/send',
      options: RequestSessionScope.options(),
      data: FormData.fromMap(<String, dynamic>{
        'conversation_id': conversationId.toString(),
        'msg_type': msgType.toString(),
        'content': content,
        // 只在真有内容时发 —— 空串会被后端存成一个解析不出东西的卡片。
        if ((extraJson ?? '').isNotEmpty) 'extra_json': extraJson,
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return ChatMessage.fromJson(data);
  }

  /// 标记会话已读:`POST /api/im/read`(参数 conversation_id)。无返回数据。
  Future<void> read(int conversationId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/im/read',
      options: RequestSessionScope.options(),
      data: FormData.fromMap(<String, dynamic>{
        'conversation_id': conversationId.toString(),
      }),
    );
    _ensureOk(resp.data ?? <String, dynamic>{});
  }

  /// 上传聊天图片到 OSS:multipart 单文件,字段名固定为 `file`。
  ///
  /// ★ 与 `PlayApi.uploadImage` / `PublishApi.uploadFile` 是同一条
  ///   `/api/common/uploadOSS` 口径(照抄,不新造):成功取 body 顶层
  ///   `url`,失败抛异常。小程序那边 `app.chooseImage` 走的也正是这条 ——
  ///   传完把 URL 作为 `msg_type=2` 的 content 发出去(`/api/im/send`)。
  Future<String> uploadImage(String filePath) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/common/uploadOSS',
      options: RequestSessionScope.options(),
      data: FormData.fromMap(<String, dynamic>{
        'file': await MultipartFile.fromFile(filePath),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    final String url = (body['url'] ?? '').toString();
    // 空 URL 就当失败:发一条 content 为空的图片消息,比报错更难解释。
    if (url.isEmpty) throw const ImApiException('上传失败，请重试', localReason: ImLocalFailure.uploadMissingUrl);
    return url;
  }

  /// 未读消息总数:`POST /api/im/unread-total`(无参,取当前登录用户)。
  /// 后端 success(int) → data 直接是数字。未登录/失败抛异常,上层不显红点。
  Future<int> unreadTotal() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/im/unread-total',
      options: RequestSessionScope.options(),
      data: FormData.fromMap(<String, dynamic>{}),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body);
    return (body['data'] as num?)?.toInt() ?? 0;
  }

  /// 同 [_ensureOk],但把后端 errorCode 原样带给调用方。
  void _ensureOkTyped(Map<String, dynamic> body) {
    final code = (body['code'] as num?)?.toInt();
    if (code != 200) {
      throw ImApiException(
        (body['msg'] as String?) ?? '请求失败',
        errorCode: (body['errorCode'] ?? '').toString().trim(),
        localReason: body['msg'] == null ? ImLocalFailure.request : null,
      );
    }
  }

  /// AjaxResult 非 200 → 抛异常进 error 态(不兜底假数据)。
  void _ensureOk(Map<String, dynamic> body) {
    final code = (body['code'] as num?)?.toInt();
    if (code != 200) {
      throw ImApiException((body['msg'] as String?) ?? '请求失败',
        localReason: body['msg'] == null ? ImLocalFailure.request : null);
    }
  }

  /// 拉黑 / 取消拉黑:`POST /api/im/block` · `/api/im/unblock`(参数 target_member_id)。
  ///
  /// ★ Apple 审核指南 1.2 要求 UGC 应用必须能**屏蔽滥用用户**。
  Future<String> block(int targetMemberId, {bool blocked = true}) async =>
      (await blockReceipt(targetMemberId, blocked: blocked)).legacyMessage;

  Future<ImReceipt> blockReceipt(int targetMemberId, {bool blocked = true}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      blocked ? '/api/im/block' : '/api/im/unblock',
      options: RequestSessionScope.options(),
      data: FormData.fromMap(
        <String, dynamic>{'target_member_id': targetMemberId.toString()},
      ),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw ImApiException((body['msg'] as String?) ?? '操作失败',
        localReason: body['msg'] == null ? ImLocalFailure.operation : null);
    }
    return ImReceipt(blocked ? ImReceiptKind.blocked : ImReceiptKind.unblocked, serverMessage: body['msg'] as String?);
  }

  /// 举报一条消息:`POST /api/im/report`(message_id + reason)。
  ///
  /// ★ Apple 1.2 要求 UGC 能举报**具体内容**。此前 App 只有「拉黑这个人」——
  ///   拉黑解决的是「别再骚扰我」,举报解决的是「这条内容该被处理」,
  ///   两件事不能互相顶替:被拉黑的人对别人还是照发。
  ///
  /// ⚠️ 举报的是**消息**不是会话 —— 后端参数就是 message_id。
  Future<String> reportMessage(int messageId, String reason) async =>
      (await reportMessageReceipt(messageId, reason)).legacyMessage;

  Future<ImReceipt> reportMessageReceipt(int messageId, String reason) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/im/report',
      options: RequestSessionScope.options(),
      data: FormData.fromMap(<String, dynamic>{
        'message_id': messageId.toString(),
        'reason': reason,
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw ImApiException((body['msg'] as String?) ?? '举报失败',
        localReason: body['msg'] == null ? ImLocalFailure.report : null);
    }
    // ⚠️ 与广场举报同一条纪律:后端只入审核队列,**不立即删消息**。
    //    提示不能说「已删除」。
    return ImReceipt(ImReceiptKind.reported, serverMessage: body['msg'] as String?);
  }

  /// 会话免打扰:`POST /api/im/mute`(conversation_id + muted)。
  Future<String> mute(int conversationId, {required bool muted}) async =>
      (await muteReceipt(conversationId, muted: muted)).legacyMessage;

  Future<ImReceipt> muteReceipt(int conversationId, {required bool muted}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/im/mute',
      options: RequestSessionScope.options(),
      data: FormData.fromMap(<String, dynamic>{
        'conversation_id': conversationId.toString(),
        // ApiImController 用 Convert.toInt(muted, 0) == 1，只认 1/0。
        'muted': muted ? '1' : '0',
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw ImApiException((body['msg'] as String?) ?? '操作失败',
        localReason: body['msg'] == null ? ImLocalFailure.operation : null);
    }
    return ImReceipt(muted ? ImReceiptKind.muted : ImReceiptKind.unmuted, serverMessage: body['msg'] as String?);
  }

  /// 删除会话:`POST /api/im/delete`(conversation_id)。
  ///
  /// ⚠️ 删的是**我这一侧的会话**,不是把消息从对方那儿撤回 ——
  ///   文案别写成「撤回」或「已销毁」,那是对用户撒谎。
  Future<String> deleteConversation(int conversationId) async =>
      (await deleteConversationReceipt(conversationId)).legacyMessage;

  Future<ImReceipt> deleteConversationReceipt(int conversationId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/im/delete',
      options: RequestSessionScope.options(),
      data: FormData.fromMap(
        <String, dynamic>{'conversation_id': conversationId.toString()},
      ),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw ImApiException((body['msg'] as String?) ?? '删除失败',
        localReason: body['msg'] == null ? ImLocalFailure.delete : null);
    }
    return ImReceipt(ImReceiptKind.deleted, serverMessage: body['msg'] as String?);
  }

  /// 发起单聊:`POST /api/im/start`(表单 target_member_id)→ {conversationId}。
  ///
  /// ★ 后端保证幂等 —— 已存在会话时返回同一个 id,不会建出两条。
  ///   所以失败重试是安全的。
  Future<int> startChat(int targetMemberId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/im/start',
      options: RequestSessionScope.options(),
      data: FormData.fromMap(
        <String, dynamic>{'target_member_id': targetMemberId.toString()},
      ),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw ImApiException((body['msg'] as String?) ?? '没能开始聊天',
        localReason: body['msg'] == null ? ImLocalFailure.start : null);
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final id = (data['conversationId'] as num?)?.toInt() ?? 0;
    // ★ 拿不到会话 id 就不要跳转 —— 跳到 /im/chat/0 会进一个空聊天。
    if (id <= 0) throw const ImApiException('没能开始聊天,请稍后再试', localReason: ImLocalFailure.missingConversation);
    return id;
  }
}

enum ImLocalFailure { request, operation, report, delete, start, missingConversation, uploadMissingUrl }
enum ImReceiptKind { blocked, unblocked, reported, muted, unmuted, deleted }

/// A successful action with separately identified original server text.
class ImReceipt {
  const ImReceipt(this.kind, {this.serverMessage});
  final ImReceiptKind kind;
  final String? serverMessage;
  String get legacyMessage => serverMessage ?? switch (kind) {
    ImReceiptKind.blocked => '已拉黑',
    ImReceiptKind.unblocked => '已取消',
    ImReceiptKind.reported => '举报已提交,将进入审核',
    ImReceiptKind.muted => '已开启免打扰',
    ImReceiptKind.unmuted => '已关闭免打扰',
    ImReceiptKind.deleted => '已删除会话',
  };
}
