final class PlayOsTag {
  const PlayOsTag({
    required this.id,
    required this.value,
    required this.status,
  });

  final int id;
  final String value;
  final String status;
  bool get revoked => status == 'REVOKED';
  bool get canRevoke => id > 0 && !revoked;

  factory PlayOsTag.fromJson(Map<String, dynamic> json) => PlayOsTag(
    id: _int(json['id']),
    value: '${json['tagValue'] ?? json['value'] ?? ''}'.trim(),
    status: '${json['status'] ?? ''}'.trim().toUpperCase(),
  );
}

final class PlayOsResultCard {
  const PlayOsResultCard({required this.title, required this.body});
  final String title;
  final String body;

  factory PlayOsResultCard.fromJson(Map<String, dynamic> json) =>
      PlayOsResultCard(
        title: '${json['title'] ?? json['name'] ?? ''}'.trim(),
        body: '${json['body'] ?? json['description'] ?? json['text'] ?? ''}'
            .trim(),
      );
}

final class PlayOsMapAnchor {
  const PlayOsMapAnchor({
    required this.nodeId,
    required this.name,
    required this.latitude,
    required this.longitude,
  });
  final int nodeId;
  final String name;
  final double latitude;
  final double longitude;

  factory PlayOsMapAnchor.fromJson(Map<String, dynamic> json) =>
      PlayOsMapAnchor(
        nodeId: _int(json['nodeId']),
        name: '${json['name'] ?? ''}'.trim(),
        latitude: _double(json['latitude']),
        longitude: _double(json['longitude']),
      );
}

final class PlayOperatingSystem {
  const PlayOperatingSystem({
    required this.topicId,
    required this.edition,
    required this.tags,
    required this.resultCards,
    required this.mapAnchors,
    required this.actions7Days,
    required this.actions30Days,
  });

  final int topicId;
  final String edition;
  final List<PlayOsTag> tags;
  final List<PlayOsResultCard> resultCards;
  final List<PlayOsMapAnchor> mapAnchors;
  final List<String> actions7Days;
  final List<String> actions30Days;

  bool get isEmpty =>
      tags.isEmpty &&
      resultCards.isEmpty &&
      mapAnchors.isEmpty &&
      actions7Days.isEmpty &&
      actions30Days.isEmpty;

  factory PlayOperatingSystem.fromJson(Map<String, dynamic> json) =>
      PlayOperatingSystem(
        topicId: _int(json['topicId']),
        edition: '${json['edition'] ?? ''}'.trim(),
        tags: _maps(json['tags'])
            .map(PlayOsTag.fromJson)
            .where((PlayOsTag tag) => tag.id > 0 && tag.value.isNotEmpty)
            .toList(growable: false),
        resultCards: _maps(json['resultCards'])
            .map(PlayOsResultCard.fromJson)
            .where(
              (PlayOsResultCard card) =>
                  card.title.isNotEmpty || card.body.isNotEmpty,
            )
            .toList(growable: false),
        mapAnchors: _maps(json['mapAnchors'])
            .map(PlayOsMapAnchor.fromJson)
            .where(
              (PlayOsMapAnchor anchor) =>
                  anchor.nodeId > 0 &&
                  anchor.latitude.abs() <= 90 &&
                  anchor.longitude.abs() <= 180,
            )
            .toList(growable: false),
        actions7Days: _strings(json['actions7Days']),
        actions30Days: _strings(json['actions30Days']),
      );
}

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((Map<dynamic, dynamic> row) => Map<String, dynamic>.from(row))
          .toList(growable: false)
    : const <Map<String, dynamic>>[];

List<String> _strings(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .map((Object? item) {
        if (item is Map) {
          return '${item['title'] ?? item['text'] ?? item['action'] ?? ''}'
              .trim();
        }
        return '${item ?? ''}'.trim();
      })
      .where((String item) => item.isNotEmpty)
      .toList(growable: false);
}

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;
double _double(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('${value ?? ''}') ?? 0;
