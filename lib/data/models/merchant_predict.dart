/// 竞猜待答(商家侧)的行模型。对齐小程序
/// `pages/merchant/predict/index.js` 的 `shapeRound` —— 纯函数,供单测。
///
/// ★ 两条文案判据不能错,它们是这一屏存在的理由:
///   · 「还剩 N 天」;`daysLeft == 0` **不是**「还剩 0 天」,而是
///     「今天不给就作废」—— 超过 48 小时这一轮由平台作废,谁都拿不到奖。
///   · `betCount == 0` 时不许写「0 个人押了这一轮」(会被读成没人参与、
///     不必着急),要写「这一轮还没有人押」。
class PredictRound {
  const PredictRound({
    required this.rid,
    required this.nodeId,
    required this.playDay,
    required this.nodeName,
    required this.question,
    required this.options,
    required this.betCount,
    required this.daysLeft,
  });

  /// 服务端没给主键,用 `nodeId:playDay` 当行身份(小程序同款)。
  final String rid;
  final int nodeId;
  final String playDay;
  final String nodeName;
  final String question;
  final List<PredictOption> options;
  final int betCount;
  final int daysLeft;

  String get betText => betCount > 0 ? '$betCount 个人押了这一轮' : '这一轮还没有人押';

  String get optionText => '${options.length} 个选项';

  /// 今天不给就没了 —— 这一档要红。
  bool get expired => daysLeft <= 0;

  String get deadlineText => expired ? '今天不给就作废' : '还剩 $daysLeft 天';

  /// 「09-11 那一轮」。
  String get roundText => playDay.isEmpty ? '这一轮' : '$playDay 那一轮';

  PredictOption? optionOf(String key) {
    for (final PredictOption option in options) {
      if (option.key == key) return option;
    }
    return null;
  }
}

class PredictOption {
  const PredictOption({required this.key, required this.label});

  final String key;
  final String label;
}

PredictRound shapePredictRound(Map<String, dynamic> row) {
  final Object? rawOptions = row['options'];
  final List<PredictOption> options = rawOptions is List
      ? rawOptions
            .whereType<Map>()
            .map((Map item) => _shapeOption(Map<String, dynamic>.from(item)))
            .where((PredictOption option) => option.key.isNotEmpty)
            .toList(growable: false)
      : const <PredictOption>[];
  final int nodeId = _int(row['nodeId']);
  final String playDay = _text(row['playDay']);
  return PredictRound(
    rid: '$nodeId:$playDay',
    nodeId: nodeId,
    playDay: playDay,
    nodeName: _text(row['nodeName']).isEmpty ? '未命名点位' : _text(row['nodeName']),
    question: _text(row['question']),
    options: options,
    betCount: _int(row['betCount']),
    daysLeft: _int(row['daysLeft']),
  );
}

PredictOption _shapeOption(Map<String, dynamic> raw) => PredictOption(
  key: _text(raw['key']),
  label: _text(raw['label']),
);

String _text(Object? value) => value == null ? '' : '$value'.trim();

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}'.trim()) ?? 0;
}
