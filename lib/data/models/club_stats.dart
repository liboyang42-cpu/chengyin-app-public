/// 俱乐部数据看板(`POST /api/stats/club`)。
///
/// 契约真源:小程序 `pages/club/detail/index.js#shapeClubStats`。
/// 只有本俱乐部主理人能看(后端裁决);数字缺一个就整块拒收,不猜、不补 0。
class ClubStats {
  const ClubStats({
    required this.clubId,
    required this.topicCount,
    required this.participants,
    required this.completed,
    required this.overallRate,
    required this.topics,
  });

  final int clubId;
  final int topicCount;
  final int participants;
  final int completed;
  final double overallRate;
  final List<ClubTopicStats> topics;

  /// 完成率文案保留一位小数(与小程序 `toFixed(1)+'%'` 同口径)。
  String get overallRateText => '${overallRate.toStringAsFixed(1)}%';

  factory ClubStats.fromJson(
    Map<String, dynamic> json, {
    required int expectedClubId,
  }) {
    final Object? rawClubId = json['clubId'];
    final int? clubId = rawClubId is num
        ? rawClubId.toInt()
        : int.tryParse('${rawClubId ?? ''}');
    final Object? rawTopics = json['topics'];
    if (clubId == null || clubId != expectedClubId || rawTopics is! List) {
      throw const FormatException('看板回执不完整');
    }
    final int topicCount = _strictCount(json['topicCount']);
    final int participants = _strictCount(json['participants']);
    final int completed = _strictCount(json['completed']);
    final double? overallRate = _rate(json['overallRate']);
    if (overallRate == null) throw const FormatException('看板回执不完整');
    final List<ClubTopicStats> topics = <ClubTopicStats>[];
    for (final Object? row in rawTopics) {
      if (row is! Map) throw const FormatException('看板回执不完整');
      topics.add(ClubTopicStats.fromJson(Map<String, dynamic>.from(row)));
    }
    return ClubStats(
      clubId: clubId,
      topicCount: topicCount,
      participants: participants,
      completed: completed,
      overallRate: overallRate,
      topics: topics,
    );
  }
}

class ClubTopicStats {
  const ClubTopicStats({
    required this.topicId,
    required this.name,
    required this.participants,
    required this.completed,
    required this.completionRate,
  });

  final int topicId;
  final String name;
  final int participants;
  final int completed;
  final double completionRate;

  String get completionRateText => '${completionRate.toStringAsFixed(1)}%';

  factory ClubTopicStats.fromJson(Map<String, dynamic> json) {
    final Object? rawTopicId = json['topicId'];
    final int? topicId = rawTopicId is num
        ? rawTopicId.toInt()
        : int.tryParse('${rawTopicId ?? ''}');
    final double? completionRate = _rate(json['completionRate']);
    if (topicId == null || topicId <= 0 || completionRate == null) {
      throw const FormatException('看板回执不完整');
    }
    return ClubTopicStats(
      topicId: topicId,
      name: '${json['name'] ?? ''}'.trim(),
      participants: _strictCount(json['participants']),
      completed: _strictCount(json['completed']),
      completionRate: completionRate,
    );
  }
}

int _strictCount(Object? value) {
  final int? parsed = value is num
      ? (value.isFinite && value == value.truncateToDouble()
            ? value.toInt()
            : null)
      : int.tryParse('${value ?? ''}');
  if (parsed == null || parsed < 0) {
    throw const FormatException('看板回执不完整');
  }
  return parsed;
}

double? _rate(Object? value) {
  final double? parsed = value is num
      ? value.toDouble()
      : double.tryParse('${value ?? ''}');
  if (parsed == null || !parsed.isFinite || parsed < 0) return null;
  return parsed;
}
