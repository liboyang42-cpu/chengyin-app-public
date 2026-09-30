/// 徽章双样式详情页参数装配(对齐小程序 subpackageP3/pages/badge-3d)。
///
/// 小程序用 xr-frame WebGL 做 3D 珐琅转台;App 侧做静态展示卡
/// (3D 引擎不移植,详情语义与参数校验与小程序一致)。
library;

/// 五档稀有度文案(波点五色轨:0 普通 … 4 神话)。
const List<String> tierNames = <String>['普通', '稀有', '史诗', '传说', '神话'];

class BadgeDetailParams {
  const BadgeDetailParams({
    required this.name,
    required this.sub,
    required this.img,
    required this.style,
    required this.rarity,
  });

  final String name;
  final String sub;

  /// 只接受 http(s) 的真图;相对路径/坏参数一律空串(不渲染坏图)。
  final String img;

  /// glow / enamel。
  final String style;

  /// 0..4,越界夹回。
  final int rarity;

  String get tierName => tierNames[rarity];

  bool get isEnamel => style == 'enamel';
}

/// 由路由 query 装配参数。全部容错,任何坏参数都有兜底,不崩。
BadgeDetailParams badgeDetailParams(
  Map<String, String> query, {
  BadgeDetailParams fallback = const BadgeDetailParams(
    name: '徽章',
    sub: '',
    img: '',
    style: 'enamel',
    rarity: 0,
  ),
}) {
  final rarityRaw = int.tryParse(query['rarity'] ?? '') ?? 0;
  final imgRaw = query['img'] ?? '';
  return BadgeDetailParams(
    name: (query['name'] ?? '').trim().isEmpty
        ? fallback.name
        : (query['name'] ?? ''),
    sub: query['sub'] ?? '',
    img: RegExp(r'^https?://').hasMatch(imgRaw) ? imgRaw : '',
    // 真源只认 glow,其余一律 enamel(badge-3d/index.js:50)——
    // 缺省方向是珐琅转台,不是发光。
    style: query['style'] == 'glow' ? 'glow' : 'enamel',
    rarity: rarityRaw.clamp(0, tierNames.length - 1),
  );
}
