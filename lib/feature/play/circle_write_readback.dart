bool circleWriteLanded(
  Map<String, dynamic>? card,
  Map<String, dynamic>? pending,
) {
  if (card == null || pending == null) return false;
  final String kind = '${pending['kind']}';
  if (kind == 'record') {
    final String offerId = '${pending['offerId']}';
    return _maps(
      card['records'],
    ).any((item) => '${item['offerId']}' == offerId);
  }
  if (kind == 'answer') {
    final String stage = '${pending['stage']}';
    final String value = '${pending['value']}'.trim();
    return _maps(card['answers']).any(
      (item) =>
          '${item['answerStage'] ?? item['stage']}' == stage &&
          '${item['answerValue'] ?? item['value']}'.trim() == value,
    );
  }
  return false;
}

List<Map<String, dynamic>> _maps(Object? value) =>
    (value is List ? value : const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
