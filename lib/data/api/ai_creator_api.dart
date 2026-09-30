import '../../core/network/dio_client.dart';
import '../models/ai_quota.dart';

/// AI 创作。对齐后端 `ApiAiController`(/api/ai)。
///
/// ⚠️ 所有端点前都有一道 `gate` —— 玩家身份被拒
/// (「当前身份暂不支持AI创作」),那是**产品规则不是故障**。
class AiCreatorApi {
  AiCreatorApi(this._client);
  final DioClient _client;

  /// 配额:`POST /api/ai/theme/draft/quota`。
  ///
  /// ★ 拿不到配额时返回 `const AiQuota()`(loaded=false)而**不是抛错** ——
  ///   配额只是个提示,取不到不该让整个功能不可用。
  Future<AiQuota> quota() async {
    try {
      final resp = await _client.dio
          .post<Map<String, dynamic>>('/api/ai/theme/draft/quota');
      final body = resp.data ?? <String, dynamic>{};
      if ((body['code'] as num?)?.toInt() != 200) return const AiQuota();
      return AiQuota.fromJson(
        (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      );
    } catch (_) {
      // 网络抖动不该废掉功能 —— 让后端在真正生成时把关。
      return const AiQuota();
    }
  }

  /// 生成主题草稿:`POST /api/ai/theme/draft`。
  ///
  /// 失败时抛出后端原话,调用方用 [AiGateResult] 分流
  /// (身份问题不给重试,故障给重试)。
  Future<Map<String, dynamic>> themeDraft(String idea) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/ai/theme/draft',
      data: <String, dynamic>{'idea': idea.trim()},
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? 'AI 生成失败');
    }
    return (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }

  /// 节点玩法**整表填充**:`POST /api/ai/template/fill`。
  ///
  /// ★★ 这条取代了旧的 `/api/ai/node/generate` —— 小程序真源里
  ///   `grep -rn 'ai/node/generate' pages/ utils/` **零调用方**,
  ///   而 `/api/ai/template/fill` 恰有一个调用方
  ///   (`pages/publish/temp/index.js:834`)。旧端点那三个字段
  ///   (description/questionName/questionAnswer)是它的子集。
  ///
  /// ★ 入参照抄真源同名同形(`pages/publish/temp/index.js:838-845`),
  ///   `category` 真源就传空串,所以这里也传 —— 别"顺手"传个看起来更有用的值,
  ///   那会改变服务端的取数分支。
  ///
  /// 返回的是 **AjaxResult.data**,里面装整张表:
  /// `data.template` 或 `data.node`(真源两种都认,`:852`)。取用见
  /// [AiNodeAssistResult.fromResponse]。
  Future<Map<String, dynamic>> templateFill({
    required String shopName,
    required String extraNote,
    String category = '',
    String reward = '',
    String playStyle = '',
    int? validationMethod,
  }) =>
      _generate('/api/ai/template/fill', <String, dynamic>{
        'shopName': shopName,
        'category': category,
        'reward': reward,
        'playStyle': playStyle,
        'validationMethod': ?validationMethod,
        'extraNote': extraNote,
      });

  /// 俱乐部活动设计:`POST /api/ai/club/design`。
  Future<Map<String, dynamic>> clubDesign({
    required String idea,
    String? clubStyle,
    int? targetDurationMin,
  }) =>
      _generate('/api/ai/club/design', <String, dynamic>{
        'idea': idea.trim(),
        'clubStyle': ?clubStyle,
        'targetDurationMin': ?targetDurationMin,
      });

  Future<Map<String, dynamic>> _generate(
      String path, Map<String, dynamic> body) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(path, data: body);
    final Map<String, dynamic> res = resp.data ?? <String, dynamic>{};
    if ((res['code'] as num?)?.toInt() != 200) {
      throw Exception((res['msg'] as String?) ?? 'AI 生成失败');
    }
    return (res['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }
}
