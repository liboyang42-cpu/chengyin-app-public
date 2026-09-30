import 'dart:math' as math;

import '../../core/network/dio_client.dart';
import '../../core/network/request_session_scope.dart';
import '../models/merchant_npc.dart';

/// 门店 NPC:商家自助配置 + 玩家侧对话。
///
/// 对齐后端 `ApiMerchantNpcController`(/api/merchant/npc)与
/// `ApiAiNpcController#merchantChat`(/api/ai/npc/merchant-chat)。
class MerchantNpcApi {
  MerchantNpcApi(this._client);

  final DioClient _client;

  /// 读我的门店形象(含待审 / 被驳回)。
  ///
  /// ★ 后端回的是 `NpcProfile` 实体本身(`ApiMerchantController#npcProfile`),
  ///   **没配过时 `data` 为 null**(不是 404、也不是 `{configured:false}` 空壳)——
  ///   [_post] 把 null 折成空 map,所以「没配过」照旧不必当异常处理。
  ///
  /// ⚠️ 实体里**没有** `configured` / `statusText` / `hasVoice` / `modelUrl`:
  ///   模型里那四个字段在这条接口上恒为默认值,审核横幅与 3D 区因此不显示。
  ///   (2026-09-17 核后端 github/master@1b3ca1c4:`/npc/info` 全树不存在。)
  Future<MerchantNpcProfile> myProfile() async {
    final Map<String, dynamic> data = await _post(
      '/api/merchant/npc/profile',
      const <String, dynamic>{},
    );
    return MerchantNpcProfile.fromJson(data);
  }

  /// 保存(落待审)。成功返回后端的提示文案。
  ///
  /// ★ 不传 merchantId:端点根本不收这个字段,商家主体由后端从登录态解析。
  Future<String> save(MerchantNpcProfile profile) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/npc/save',
      data: <String, dynamic>{
        'name': profile.name,
        'avatar': profile.avatar,
        'greeting': profile.greeting,
        'persona': profile.persona,
        'knowledge': profile.knowledge,
      },
    );
    final Map<String, dynamic> body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantNpcException((body['msg'] as String?) ?? '保存失败');
    }
    return (body['msg'] as String?) ?? '已提交,等待审核';
  }

  /// 跟某家店的形象说一句话。
  ///
  /// ★★ **不是 SSE。** 后端 PR #75 起是普通 POST,一次性返回**已过审**的完整文本
  ///   (依据《漫游AI 补充方案》§1.1-5:客户端收到 SUCCEEDED 后自行逐字呈现)。
  ///   仓库里旧的 `AiNpcApi.chatStream` 还在用 `_client.sse`,那条已经与后端对不上了 ——
  ///   它零调用方,所以一直没暴露。
  ///
  /// ★ [requestId] 由调用方持有并在重试时**原样重发**:后端按 (userId, requestId) 幂等,
  ///   换一个新的 id 重试 = 一次全新的计费调用。
  ///
  /// ⚠️ 开关未开时后端返回 code=403,这里抛 [MerchantNpcException],
  ///   调用方应据此**不显示对话入口**,而不是让人点了才失败。
  Future<NpcChatResult> chat({
    required int merchantId,
    required String message,
    required String requestId,
  }) async {
    final Map<String, dynamic> data = await _post(
      '/api/ai/npc/merchant-chat',
      <String, dynamic>{
        'requestId': requestId,
        // bizId 就是 merchantId —— 门店轨复用同一个信封字段。
        'bizId': merchantId,
        'message': message,
      },
    );
    return NpcChatResult.fromJson(data);
  }

  /// 声音克隆:能不能录 + 要念的五句话。
  ///
  /// ★ `available=false` 时**不要显示录音入口** —— 供应商没接就让人录完五句再失败,
  ///   是最差的做法。这个判断故意放在服务端:客户端不该猜供应商接没接。
  Future<VoiceEnrollScript> voiceScript() async {
    final Map<String, dynamic> data = await _post(
      '/api/merchant/npc/voice/script',
      const <String, dynamic>{},
    );
    return VoiceEnrollScript.fromJson(data);
  }

  /// 提交五段录音。[sampleUrls] 必须**按脚本顺序**,第一段是授权声明。
  Future<String> voiceEnroll(List<String> sampleUrls) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/npc/voice/enroll',
      data: <String, dynamic>{
        'sampleUrls': sampleUrls,
        'requestId': newChatRequestId(),
      },
    );
    final Map<String, dynamic> body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantNpcException((body['msg'] as String?) ?? '提交失败');
    }
    return (body['msg'] as String?) ?? '已提交';
  }

  /// 声音克隆跑到哪一步了:`POST /api/merchant/npc/voice/status`。
  ///
  /// ★ 提交录音([voiceEnroll])只代表**提交成功** —— 克隆在供应商那边异步跑。
  ///   这条是唯一能问进度的口,状态 1(生成中)时按 5 秒轮询,
  ///   收口到 2(就绪)/3(失败)就停(小程序 ai-npc 页同节奏)。
  ///
  /// ⚠️ 查询失败**不改判上一次状态**:状态是背景事实,
  ///   查不到只说明这一拍没读到,下一次轮询就是重试。
  Future<NpcVoiceStatus> voiceStatus() async {
    final Map<String, dynamic> data = await _post(
      '/api/merchant/npc/voice/status',
      const <String, dynamic>{},
    );
    return NpcVoiceStatus.fromJson(data);
  }

  /// 撤回声音授权(删音色)。
  ///
  /// ★ 后端在「远端没删成」时返回非 200 —— 这里抛出去让 UI 如实说没删掉,
  ///   而不是吞掉报成已撤回。报成已撤回而远端还在,等于骗用户。
  Future<String> voiceRevoke() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/npc/voice/revoke',
      data: <String, dynamic>{'requestId': newChatRequestId()},
    );
    final Map<String, dynamic> body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantNpcException((body['msg'] as String?) ?? '撤回失败');
    }
    return (body['msg'] as String?) ?? '已撤回';
  }

  /// 3D 形象:能不能生成 + 可选风格 + 最近一次任务。
  ///
  /// ★ 这一个端点同时承担「查可用性」与「轮询任务」——
  ///   后端在返回前顺带把出结果的任务收尾了,客户端不必区分两个动作。
  Future<NpcAvatarStatus> avatarStatus() async {
    final Map<String, dynamic> data = await _post(
      '/api/merchant/npc/avatar/status',
      const <String, dynamic>{},
    );
    return NpcAvatarStatus.fromJson(data);
  }

  /// 提交一张照片开始生成。
  Future<NpcAvatarJob> avatarGenerate({
    required String imageUrl,
    required String style,
  }) async {
    final Map<String, dynamic> data = await _post(
      '/api/merchant/npc/avatar/generate',
      <String, dynamic>{'imageUrl': imageUrl, 'style': style},
    );
    return NpcAvatarJob.fromJson(data);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      path,
      data: body,
      options: RequestSessionScope.options(),
    );
    final Map<String, dynamic> payload = resp.data ?? <String, dynamic>{};
    if ((payload['code'] as num?)?.toInt() != 200) {
      throw MerchantNpcException((payload['msg'] as String?) ?? '请求失败', isLocalFallback: payload['msg'] == null);
    }
    return (payload['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }
}

class MerchantNpcException implements Exception {
  const MerchantNpcException(this.message, {this.isLocalFallback = false});

  final bool isLocalFallback;

  final String message;

  @override
  String toString() => message;
}

/// 生成一个 UUID v4。
///
/// ★ 后端用正则卡死格式(版本位必须 1-5、variant 位必须 8/9/a/b),随便拼一串十六进制
///   会被判 INVALID_REQUEST。这里显式把两个位设对。
///
/// 为什么不引 `uuid` 包:整个 App 只有这一处需要 UUID,十行代码换一个依赖不划算。
String newChatRequestId() {
  final math.Random rnd = math.Random.secure();
  final List<int> bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
  String hex(int start, int end) => bytes
      .sublist(start, end)
      .map((int b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
