/// Protocol values are deliberately separate from translated category labels.
const objectCardCategories = <String>[
  '', '电子产品', '服饰', '鞋包', '食物饮料', '书籍文具', '玩具摆件', '日用杂物', '其他',
];

class ObjectCard {
  const ObjectCard({
    required this.id,
    required this.title,
    required this.frames,
    this.sourceUrl = '',
    this.cutoutUrl = '',
    this.cutoutBox,
    this.caption = '',
    this.category = '',
    this.place = '',
    this.cardStyle = 'foil',
    this.genStatus = 'NONE',
  });

  factory ObjectCard.fromJson(Map<String, dynamic> json) {
    if (json['id'] == null || json['title'] is! String) {
      throw const FormatException('Invalid object-card row');
    }
    String string(String key) => json[key] is String ? json[key] as String : '';
    final rawFrames = json['frames'];
    final frames = rawFrames is List
        ? rawFrames.whereType<String>().where((url) => url.isNotEmpty).toList()
        : <String>[];
    return ObjectCard(
      id: json['id'].toString(),
      title: string('title'),
      frames: List.unmodifiable(frames.isEmpty ? [string('sourceUrl')] : frames),
      sourceUrl: string('sourceUrl'),
      cutoutUrl: string('cutoutUrl'),
      cutoutBox: _validBox(json['cutoutBox']),
      caption: string('caption'),
      category: string('category'),
      place: string('place'),
      cardStyle: string('cardStyle') == 'plain' ? 'plain' : 'foil',
      genStatus: string('genStatus'),
    );
  }

  final String id, title, sourceUrl, cutoutUrl, caption, category, place;
  final String cardStyle, genStatus;
  final List<String> frames;
  final List<double>? cutoutBox;
  bool get generating => genStatus == 'QUEUED' || genStatus == 'GENERATING';
  String get thumbnail => cutoutUrl.isNotEmpty
      ? cutoutUrl
      : sourceUrl.isNotEmpty ? sourceUrl : frames.firstOrNull ?? '';
}

class ObjectCardCollection {
  const ObjectCardCollection({required this.cards, required this.total});

  factory ObjectCardCollection.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Missing object-card data');
    }
    final rows = value['list'];
    final total = value['total'];
    if (rows is! List || total is! num || !total.isFinite ||
        total < 0 || total != total.truncateToDouble()) {
      throw const FormatException('Invalid object-card list');
    }
    return ObjectCardCollection(
      cards: List.unmodifiable(rows.map((row) {
        if (row is! Map<String, dynamic>) {
          throw const FormatException('Invalid object-card row');
        }
        return ObjectCard.fromJson(row);
      })),
      total: total.toInt(),
    );
  }

  final List<ObjectCard> cards;
  final int total;
}

List<double>? _validBox(Object? raw) {
  if (raw is! List || raw.length != 4 || raw.any((value) => value is! num)) {
    return null;
  }
  final box = raw.cast<num>().map((value) => value.toDouble()).toList();
  if (box.any((value) => !value.isFinite) || box[0] < 0 || box[1] < 0 ||
      box[2] <= 0 || box[3] <= 0 || box[0] + box[2] > 1.0001 ||
      box[1] + box[3] > 1.0001) {
    return null;
  }
  return List.unmodifiable(box);
}
