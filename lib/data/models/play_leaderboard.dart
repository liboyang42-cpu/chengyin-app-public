/// 同行者榜一行。服务端口径为完成节点数，榜外的「我」允许没有名次。
class PlayLeaderboardEntry {
  const PlayLeaderboardEntry({
    required this.memberId,
    required this.nickname,
    required this.score,
    this.rank,
    this.avatarUrl,
    this.rankPercentage,
  });

  final int? rank;
  final int memberId;
  final String nickname;
  final String? avatarUrl;
  final int score;
  final String? rankPercentage;

  String get displayName => nickname.trim().isEmpty ? '同行者' : nickname.trim();

  factory PlayLeaderboardEntry.fromJson(
    Map<String, dynamic> json, {
    required bool rankRequired,
  }) {
    final int? rank = _optionalPositiveInt(json['rank']);
    final int? memberId = _positiveInt(json['memberId']);
    final int? score = _nonNegativeInt(json['score']);
    if ((json['rank'] != null && rank == null) ||
        memberId == null ||
        score == null ||
        (rankRequired && rank == null)) {
      throw const FormatException('同行者榜行回执不完整');
    }
    return PlayLeaderboardEntry(
      rank: rank,
      memberId: memberId,
      nickname: _optionalText(json['nickname']) ?? '',
      avatarUrl: _optionalText(json['avatar']),
      score: score,
      rankPercentage: _optionalText(json['rankPercentage']),
    );
  }
}

/// `/api/play/leaderboard` 的完整服务端读回。
class PlayLeaderboard {
  const PlayLeaderboard({required this.entries, required this.me});

  final List<PlayLeaderboardEntry> entries;
  final PlayLeaderboardEntry me;

  factory PlayLeaderboard.fromJson(Map<String, dynamic> json) {
    final Object? rawList = json['list'];
    final Object? rawMe = json['me'];
    if (rawList is! List || rawMe is! Map) {
      throw const FormatException('同行者榜回执不完整');
    }
    final List<PlayLeaderboardEntry> entries = <PlayLeaderboardEntry>[];
    for (final Object? raw in rawList) {
      if (raw is! Map) throw const FormatException('同行者榜回执不完整');
      entries.add(
        PlayLeaderboardEntry.fromJson(
          Map<String, dynamic>.from(raw),
          rankRequired: true,
        ),
      );
    }
    if (entries.length > 50) {
      throw const FormatException('同行者榜回执不完整');
    }
    final Set<int> members = <int>{};
    for (int index = 0; index < entries.length; index += 1) {
      final PlayLeaderboardEntry entry = entries[index];
      if (entry.rank != index + 1 || !members.add(entry.memberId)) {
        throw const FormatException('同行者榜回执不完整');
      }
    }
    final PlayLeaderboardEntry me = PlayLeaderboardEntry.fromJson(
      Map<String, dynamic>.from(rawMe),
      rankRequired: false,
    );
    final PlayLeaderboardEntry? rankedMe = _entryFor(entries, me.memberId);
    if (me.rank == null) {
      if (rankedMe != null) {
        throw const FormatException('同行者榜回执不完整');
      }
    } else if (rankedMe == null ||
        rankedMe.rank != me.rank ||
        rankedMe.score != me.score) {
      throw const FormatException('同行者榜回执不完整');
    }
    return PlayLeaderboard(
      entries: List<PlayLeaderboardEntry>.unmodifiable(entries),
      me: me,
    );
  }
}

PlayLeaderboardEntry? _entryFor(
  List<PlayLeaderboardEntry> entries,
  int memberId,
) {
  for (final PlayLeaderboardEntry entry in entries) {
    if (entry.memberId == memberId) return entry;
  }
  return null;
}

int? _positiveInt(Object? value) {
  final int? parsed = _integer(value);
  return parsed != null && parsed > 0 ? parsed : null;
}

int? _optionalPositiveInt(Object? value) =>
    value == null ? null : _positiveInt(value);

int? _nonNegativeInt(Object? value) {
  final int? parsed = _integer(value);
  return parsed != null && parsed >= 0 ? parsed : null;
}

int? _integer(Object? value) {
  if (value is! num || !value.isFinite) return null;
  final int parsed = value.toInt();
  return value == parsed ? parsed : null;
}

String? _optionalText(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('同行者榜行回执不完整');
  final String text = value.trim();
  return text.isEmpty ? null : text;
}
