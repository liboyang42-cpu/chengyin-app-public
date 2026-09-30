/// 游玩结局。对齐后端 `PlayNarrativeSupport.buildEnding`
/// (/api/play/ending → {opener, fragments})。
class PlayEnding {
  const PlayEnding({this.opener = '', this.fragments = const <EndingFragment>[]});

  /// 开场白。★ 一个节点都没走完时后端下发**空串** ——
  ///   那是「还没有故事」,不是错误,也不是"加载失败"。
  final String opener;

  /// 逐节点碎片,按完成顺序。
  final List<EndingFragment> fragments;

  /// 有没有可讲的故事。
  bool get hasStory => fragments.isNotEmpty;

  factory PlayEnding.fromJson(Map<String, dynamic> json) {
    return PlayEnding(
      opener: (json['opener'] as String?) ?? '',
      fragments: ((json['fragments'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(EndingFragment.fromJson)
          .toList(),
    );
  }
}

/// 结局里的一段。
class EndingFragment {
  const EndingFragment({
    required this.step,
    required this.name,
    this.nodeId,
    this.text,
  });

  final int step;
  final String name;
  final int? nodeId;

  /// 正文。★ 后端已做过一层兜底(fragmentText 为空时退回 description),
  ///   所以这里**再空就是真的没有** —— 不显示这一段的正文,只保留标题,
  ///   而不是显示一个空段落让人以为没加载出来。
  final String? text;

  String? get body {
    final t = text?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  factory EndingFragment.fromJson(Map<String, dynamic> json) {
    return EndingFragment(
      step: (json['step'] as num?)?.toInt() ?? 0,
      name: ((json['name'] as String?) ?? '').trim().isEmpty
          ? '未命名地点'
          : (json['name'] as String).trim(),
      nodeId: (json['nodeId'] as num?)?.toInt(),
      text: json['text'] as String?,
    );
  }
}
