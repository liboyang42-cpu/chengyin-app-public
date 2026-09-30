// AI 起草主题的解析与校验 —— 逐条移植小程序 pages/publish/simple/index.js:155-180。
//
// ★★ 这一段的核心不是「调个接口拿回文本」,是三条纪律:
//
//   ① **AI 只出草稿,地点必须用户逐个确认**。节点回来时坐标是空的、
//     confirmed=false;不确认完不许进编辑器。小程序页面上那句
//     「AI 只协助起草,地点与发布内容始终由你确认」不是免责套话,
//     是这段逻辑的说明。
//
//   ② **最多 3 个点位**。超了整份草稿作废并让用户换个说法,
//     而不是截断前 3 个 —— 截断会把 AI 的路线逻辑拦腰砍断,
//     用户拿到的是一条走不通的路。
//
//   ③ **不完整就整份丢掉**。title 空、一个节点都没有、或任一节点
//     三个名字字段全空 —— 任一条就作废。半份草稿比没有更坏:
//     用户会以为 AI 只想到这么多,而不是「这次没生成好」。
//
// ⚠️ 配额用完**不挡手动发布** —— 文案要说「可以先手动填」。
//   把整页禁掉等于用一个附加功能废掉主功能。

/// 小程序 `MAX_AI_PLAN_NODES`。
const int kMaxAiPlanNodes = 3;

class AiDraftNode {
  const AiDraftNode({required this.name, required this.description});
  final String name;
  final String description;
}

class AiDraft {
  const AiDraft({
    required this.title,
    required this.subtitle,
    required this.storyline,
    required this.nodes,
    this.traceId,
    this.remainingQuota,
  });
  final String title;
  final String subtitle;
  final String storyline;
  final List<AiDraftNode> nodes;
  final String? traceId;

  /// 后端**顺带**下发的剩余次数。null = 这次没给,沿用原值别清零。
  final int? remainingQuota;
}

/// 解析失败的原因。★ 每种给一句**用户能照着做**的话。
class AiDraftError implements Exception {
  const AiDraftError(this.message);
  final String message;
  @override
  String toString() => message;
}

String _s(Object? v) => (v ?? '').toString().trim();

/// 把 `data` 解析成草稿;不合格抛 [AiDraftError]。
///
/// 判据顺序与小程序一致:先判整体完整,再判点位数量。
AiDraft parseAiDraft(Map<String, dynamic> data, {String? serverMsg}) {
  final Map<String, dynamic> draft =
      (data['draft'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  final List<dynamic> raw =
      (draft['nodes'] as List<dynamic>?) ?? const <dynamic>[];

  // 每个节点必须至少有一个能当名字用的字段。
  bool usable(dynamic n) =>
      n is Map<String, dynamic> &&
      (_s(n['merchantName']).isNotEmpty ||
          _s(n['roleText']).isNotEmpty ||
          _s(n['task']).isNotEmpty);

  if (_s(draft['title']).isEmpty || raw.isEmpty || !raw.every(usable)) {
    // ★ 后端有话就用后端的 —— 它知道是内容安全还是模型没返好。
    throw AiDraftError(
      (serverMsg ?? '').trim().isNotEmpty
          ? serverMsg!.trim()
          : 'AI 返回的主题不完整,请换一种说法重试。',
    );
  }
  if (raw.length > kMaxAiPlanNodes) {
    throw const AiDraftError('AI 草稿最多只能包含不超过 $kMaxAiPlanNodes 个点位,请换一种说法重试。');
  }

  return AiDraft(
    title: _s(draft['title']),
    subtitle: _s(draft['subtitle']),
    storyline: _s(draft['storyline']),
    nodes: <AiDraftNode>[
      for (int i = 0; i < raw.length; i++)
        AiDraftNode(
          // 三选一的兜底顺序与小程序一致;都没有时用「点位 N」。
          // (上面 usable 已经保证至少有一个,这里的兜底只为绝对安全。)
          name: <String>[
            _s((raw[i] as Map<String, dynamic>)['merchantName']),
            _s((raw[i] as Map<String, dynamic>)['roleText']),
            _s((raw[i] as Map<String, dynamic>)['task']),
          ].firstWhere((String s) => s.isNotEmpty, orElse: () => '点位 ${i + 1}'),
          description: <String>[
            _s((raw[i] as Map<String, dynamic>)['task']),
            _s((raw[i] as Map<String, dynamic>)['roleText']),
          ].firstWhere((String s) => s.isNotEmpty, orElse: () => ''),
        ),
    ],
    traceId: _s(data['traceId']).isEmpty ? null : _s(data['traceId']),
    remainingQuota: data['remainingQuota'] is num
        ? (data['remainingQuota'] as num).toInt()
        : null,
  );
}

/// 用户在页面上确认过坐标的点位。
class ConfirmedNode {
  const ConfirmedNode({
    required this.name,
    required this.description,
    this.address,
    this.longitude,
    this.latitude,
  });
  final String name;
  final String description;
  final String? address;
  final String? longitude;
  final String? latitude;

  /// ★ 确认 = **有坐标**。只让用户点一下「确认」而不取坐标是假确认 ——
  ///   发布出去的点位在地图上落不了地。
  bool get confirmed =>
      (longitude ?? '').trim().isNotEmpty && (latitude ?? '').trim().isNotEmpty;
}

/// 能不能进编辑器。★ 三条都要:有标题、有点位、**每个点位都确认过坐标**。
bool canEnterAiEditor({
  required String title,
  required List<ConfirmedNode> nodes,
}) =>
    title.trim().isNotEmpty &&
    nodes.isNotEmpty &&
    nodes.every((ConfirmedNode n) => n.confirmed);
