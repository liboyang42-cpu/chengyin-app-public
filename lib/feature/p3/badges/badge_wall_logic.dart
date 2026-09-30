/// 勋章墙装配逻辑(对齐小程序 subpackageP3/pages/badge-wall/index.js 的
/// CATEGORY_TO_TRACK / displayDate / itemToBadge / medalToBadge)。
///
/// Flutter 侧不移植 WebGL 引擎(glyphs.js/engine.js),徽记几何用首字符
/// 圆盘代替;目录、类别配色轨道、锁定语义与小程序一致。
library;

import '../../../data/models/badge_wall.dart';

/// 类别配色轨道。身份卡不标稀有度只标类别,类别复用墙面五档配色轨道。
const List<String> _tracks = <String>['探索', '创造', '组织', '连接', '共创'];

/// 库 category → 配色轨道下标。库写 CO_CREATE(下划线),轨道 key 是
/// CO-CREATE(连字符),两种写法都显式归一到 4 —— 不靠巧合对上。
/// 未知类别落 0(探索),不崩。
const Map<String, int> categoryToTrack = <String, int>{
  'EXPLORE': 0,
  'CREATE': 1,
  'ORGANIZE': 2,
  'CONNECT': 3,
  'CO_CREATE': 4,
  'CO-CREATE': 4,
  'COCREATE': 4,
};

/// 类别轨道下标(未知/缺失落 0)。
int trackOf(String? category) {
  final t = categoryToTrack[category ?? ''];
  if (t == null || t < 0 || t >= _tracks.length) return 0;
  return t;
}

String trackZh(int track) => _tracks[track];

/// 墙上一枚徽章的统一视图(身份卡 / 城市纪念章 / 成就徽章共用)。
class WallBadgeView {
  const WallBadgeView({
    required this.name,
    required this.track,
    required this.tierKey,
    required this.tierZh,
    required this.locked,
    required this.timeText,
    required this.source,
    required this.desc,
    required this.cond,
    required this.style,
    required this.iconUrl,
  });

  final String name;
  final int track;
  final String tierKey;
  final String tierZh;
  final bool locked;

  /// 已点亮:获得日期或 '—';未点亮:'未点亮'。
  final String timeText;
  final String source;
  final String desc;
  final String cond;

  /// glow(发光,墙上本体即终态)/ enamel(珐琅,可进 3D 详情)。
  final String style;
  final String iconUrl;

  /// 三族归类(真源每枚徽章带 family;identity/medal/achievement 与
  /// tierKey ID/CITY/ACHIEVEMENT 一一对应,列表视图按族分组)。
  String get family => switch (tierKey) {
    'ID' => 'identity',
    'CITY' => 'medal',
    _ => 'achievement',
  };
}

/// 三族分组标题(真源 BADGE_FAMILIES,badge-wall/index.js:16-20)。
const List<(String, String)> badgeFamilies = <(String, String)>[
  ('identity', '城市身份卡'),
  ('medal', '城市纪念章'),
  ('achievement', '成长成就'),
];

/// 列表视图的分组:族顺序固定,空族不占标题(与真源 filter 一致)。
class WallFamilyGroup {
  const WallFamilyGroup({
    required this.key,
    required this.title,
    required this.items,
  });

  final String key;
  final String title;
  final List<WallBadgeView> items;
}

List<WallFamilyGroup> buildFamilyGroups(List<WallBadgeView> badges) {
  return <WallFamilyGroup>[
    for (final (String key, String title) in badgeFamilies)
      if (badges.any((b) => b.family == key))
        WallFamilyGroup(
          key: key,
          title: title,
          items: badges.where((b) => b.family == key).toList(),
        ),
  ];
}

/// wall-v2 的 identity[] 一枚 → 墙视图。
/// 详情只展示日期,不展示时分。
WallBadgeView identityBadgeView(BadgeWallItem item) {
  final track = trackOf(item.category);
  final time = wallDateText(item.unlockTime);
  return WallBadgeView(
    name: item.badgeName.isNotEmpty ? item.badgeName : '城市身份卡',
    track: track,
    tierKey: 'ID',
    tierZh: trackZh(track),
    locked: !item.unlocked,
    timeText: item.unlocked ? (time ?? '—') : '未点亮',
    source: '城市身份卡 · ${trackZh(track)}',
    desc: item.statement,
    cond: item.unlockHint,
    style: 'glow',
    iconUrl: item.iconUrl,
  );
}

/// /api/medal/wall 一枚 → 墙视图。
/// 成就行(kind=achievement)来自 player_badge,接口没有条件字段,
/// 不能套用城市节点条件或编造一条。
WallBadgeView medalBadgeView(MedalWallItem item) {
  final achievement = item.kind == 'achievement';
  final time = wallDateText(item.getTime);
  if (achievement) {
    return WallBadgeView(
      name: item.medalName.isNotEmpty ? item.medalName : '成就徽章',
      track: 1,
      tierKey: 'ACHIEVEMENT',
      tierZh: '成就徽章',
      locked: false,
      timeText: time ?? '—',
      source: '成长成就',
      desc: '',
      cond: '',
      style: 'glow',
      iconUrl: item.medalImg,
    );
  }
  return WallBadgeView(
    name: item.medalName.isNotEmpty ? item.medalName : '城市纪念章',
    track: 1,
    tierKey: 'CITY',
    tierZh: '城市纪念章',
    locked: false,
    timeText: time ?? '—',
    source: '城市纪念章 · 节点通关',
    desc: '完成带勋章的城市节点点亮,这一枚来自你走过的路。',
    cond: item.condition,
    // 模板勋章正是可选 enamel 的那类;缺省按 glow(后端未配 style)。
    style: item.style.isNotEmpty ? item.style : 'glow',
    iconUrl: item.medalImg,
  );
}

/// 图例:按轨道聚合(只列墙上真有的类别)。
class WallLegendEntry {
  const WallLegendEntry({
    required this.track,
    required this.zh,
    required this.count,
  });

  final int track;
  final String zh;
  final int count;
}

List<WallLegendEntry> buildLegend(List<WallBadgeView> badges) {
  final entries = <WallLegendEntry>[];
  for (var track = 0; track < _tracks.length; track++) {
    final n = badges.where((b) => b.track == track).length;
    if (n == 0) continue;
    entries.add(WallLegendEntry(track: track, zh: _tracks[track], count: n));
  }
  return entries;
}

/// 获得日期文案(displayDate 的 Dart 移植)。
///
/// 后端时间是不带时区的中国时间串;数值按 epoch 毫秒。
/// 解析失败 → null(详情行整块不展示,不编日期)。
String? wallDateText(Object? value) {
  if (value is num) {
    final v = value.toDouble();
    if (!v.isFinite || v <= 0) return null;
    final dt = DateTime.fromMillisecondsSinceEpoch(
      v.round() + 8 * 3600 * 1000,
      isUtc: true,
    );
    return _fmtDate(dt);
  }
  if (value is! String) return null;
  final s = value.trim();
  if (s.isEmpty) return null;

  final dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (dateOnly != null) {
    final year = int.parse(dateOnly.group(1)!);
    final month = int.parse(dateOnly.group(2)!);
    final day = int.parse(dateOnly.group(3)!);
    return _isValidDateParts(year, month, day) ? s : null;
  }

  final m = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})(\.\d{1,3})?(Z|[+-]\d{2}:?\d{2})?$',
  ).firstMatch(s);
  if (m == null) return null;
  final year = int.parse(m.group(1)!);
  final month = int.parse(m.group(2)!);
  final day = int.parse(m.group(3)!);
  final hour = int.parse(m.group(4)!);
  final minute = int.parse(m.group(5)!);
  final second = int.parse(m.group(6)!);
  if (!_isValidDateParts(year, month, day) ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return null;
  }

  final offset = m.group(8);
  if (offset != null && offset != 'Z') {
    final parts = RegExp(r'^([+-])(\d{2}):?(\d{2})$').firstMatch(offset);
    if (parts == null ||
        int.parse(parts.group(2)!) > 23 ||
        int.parse(parts.group(3)!) > 59) {
      return null;
    }
  }

  // 统一换算成「中国日历下的那一天」:naive 串按 +08:00 锚定后平移回来,
  // 带显式时区的串按绝对时刻换算(与 js chinaDateKey 同语义)。
  final iso =
      '${m.group(1)}-${m.group(2)}-${m.group(3)}T'
      '${m.group(4)}:${m.group(5)}:${m.group(6)}'
      '${m.group(7) ?? ''}'
      '${_isoOffset(offset)}';
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return null;
  final china = parsed.toUtc().add(const Duration(hours: 8));
  return _fmtDate(china);
}

String _isoOffset(String? offset) {
  if (offset == null) return '+08:00';
  if (offset == 'Z') return 'Z';
  final parts = RegExp(r'^([+-])(\d{2}):?(\d{2})$').firstMatch(offset)!;
  return '${parts.group(1)}${parts.group(2)}:${parts.group(3)}';
}

String _fmtDate(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

bool _isValidDateParts(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1) return false;
  final leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
  const daysInMonth = <int>[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  final max = daysInMonth[month - 1] + (month == 2 && leap ? 1 : 0);
  return day <= max;
}
