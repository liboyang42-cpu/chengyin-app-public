library;

/// 漫游会话记录(本地存储)。对齐小程序 `roam_sessions` 存储契约:
/// 会话对象在结算时落盘,字段见 [RoamSession.fromJson]。
///
/// ★ 校验逻辑与小程序 `subpackageRoam/session` 页同源,必须一起搬:
/// 它区分两种**不同**的错误态:
///   · 存储读不出来 / 记录结构坏了 → 「漫游记录读不出来」(记录还在,可重试)
///   · ts 找不到对应记录          → 「找不到这次漫游」(本地只留最近 50 条)
/// 少了它,坏数据(比如 pois 里混进非法坐标)会被当成 ready 渲染出一张错的卡。
const List<String> _week = <String>['日', '一', '二', '三', '四', '五', '六'];

/// 坐标合法性:数字或非空数字串,有限,|值| ≤ max。
bool isValidRoamCoordinate(Object? value, num max) {
  final bool primitive = value is num ||
      (value is String && value.trim().isNotEmpty);
  if (!primitive) return false;
  final double? number = value is num
      ? value.toDouble()
      : double.tryParse((value as String).trim());
  return number != null && number.isFinite && number.abs() <= max;
}

bool isValidRoamPoint(Object? point) {
  if (point is! Map) return false;
  final Object? lat = point['lat'];
  final Object? lng = point['lng'];
  return isValidRoamCoordinate(lat, 90) && isValidRoamCoordinate(lng, 180);
}

/// 会话整体合法性:ts 必须是数字或非空数字串且有限;pois/track 为 null 允许,
/// 是数组则每一项都必须是合法点。
bool isValidRoamSession(Object? raw) {
  if (raw is! Map) return false;
  final Object? timestamp = raw['ts'];
  final bool tsPrimitive = timestamp is num ||
      (timestamp is String && timestamp.trim().isNotEmpty);
  if (!tsPrimitive) return false;
  final double? tsNumber = timestamp is num
      ? timestamp.toDouble()
      : double.tryParse((timestamp as String).trim());
  if (tsNumber == null || !tsNumber.isFinite) return false;
  for (final String key in <String>['pois', 'track']) {
    final Object? points = raw[key];
    if (points == null) continue;
    if (points is! List) return false;
    for (final Object? point in points) {
      if (!isValidRoamPoint(point)) return false;
    }
  }
  return true;
}

/// 秒 → `MM:SS`(前后补零,同小程序 _fmt)。
String formatRoamDuration(int? seconds) {
  final int sec = seconds ?? 0;
  final String mm = (sec ~/ 60).toString().padLeft(2, '0');
  final String ss = (sec % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}

class RoamPoint {
  const RoamPoint({required this.lat, required this.lng});

  final double lat;
  final double lng;
}

class RoamPoi {
  const RoamPoi({
    required this.name,
    this.id,
    this.cat,
    this.lat,
    this.lng,
  });

  final String name;
  final int? id;

  /// merchant / park / landmark。
  final String? cat;
  final double? lat;
  final double? lng;

  /// 图标名:商家 → poi-shop,公园 → poi-park,其余 → poi-landmark。
  String get iconName {
    switch (cat) {
      case 'merchant':
        return 'poi-shop';
      case 'park':
        return 'poi-park';
      default:
        return 'poi-landmark';
    }
  }

  factory RoamPoi.fromJson(Map<String, dynamic> json) => RoamPoi(
    id: (json['id'] as num?)?.toInt(),
    name: (json['name'] as String?) ?? '',
    cat: json['cat'] as String?,
    lat: (json['lat'] as num?)?.toDouble(),
    lng: (json['lng'] as num?)?.toDouble(),
  );
}

class RoamSession {
  const RoamSession({
    required this.ts,
    this.zone,
    this.date,
    this.dateLine,
    this.distance,
    this.explorePct,
    this.shops,
    this.time,
    this.durSec,
    this.photos = const <String>[],
    this.pois = const <RoamPoi>[],
    this.track = const <RoamPoint>[],
    this.medal,
    this.shopMedalName,
  });

  /// 落盘时间戳(毫秒)。
  final int ts;
  final String? zone;
  final String? date;
  final String? dateLine;

  /// 公里数(落盘为字符串,如 '1.2')。
  final double? distance;
  final int? explorePct;
  final int? shops;

  /// 时长文本 'MM:SS'(结算时已格式化,可能没有)。
  final String? time;
  final int? durSec;
  final List<String> photos;
  final List<RoamPoi> pois;
  final List<RoamPoint> track;
  final String? medal;
  final String? shopMedalName;

  static const String _placeholderZone = '这片街区';

  /// 解析 + 校验二合一:不合法返回 null(页面据此分流「读不出/坏数据」)。
  static RoamSession? tryParse(Object? raw) {
    if (!isValidRoamSession(raw)) return null;
    final Map<dynamic, dynamic> m = raw as Map<dynamic, dynamic>;
    final double ts = m['ts'] is num
        ? (m['ts'] as num).toDouble()
        : double.parse((m['ts'] as String).trim());
    return RoamSession(
      ts: ts.toInt(),
      zone: (m['zone'] as String?)?.trim(),
      date: m['date'] as String?,
      dateLine: m['dateLine'] as String?,
      distance: _toDoubleOrNull(m['distance']),
      explorePct: (m['explorePct'] as num?)?.toInt() ?? 0,
      shops: (m['shops'] as num?)?.toInt() ?? 0,
      time: m['time'] as String?,
      durSec: (m['durSec'] as num?)?.toInt(),
      photos: ((m['photos'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Object>()
          .map((Object p) => p is Map ? (p['path'] ?? p['url'] ?? '').toString() : p.toString())
          .where((String s) => s.isNotEmpty)
          .toList(),
      pois: ((m['pois'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((dynamic p) => RoamPoi.fromJson(Map<String, dynamic>.from(p)))
          .toList(),
      track: ((m['track'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((dynamic p) => RoamPoint(
                lat: ((p['lat'] as num?)?.toDouble()) ?? 0,
                lng: ((p['lng'] as num?)?.toDouble()) ?? 0,
              ))
          .toList(),
      medal: m['medal'] as String?,
      shopMedalName: m['shopMedalName'] as String?,
    );
  }

  DateTime? get dateTime {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return ts > 0 ? d : null;
  }

  /// `M月D日 周X`;ts 非法时「日期不可用」。
  String get dateFull {
    final d = dateTime;
    if (d == null) return '日期不可用';
    return '${d.month}月${d.day}日 周${_week[d.weekday % 7]}';
  }

  /// 有没有记到时长。time(已格式化文本)和 durSec(秒)都没有才算缺 ——
  /// timeText 自己会兜成 '00:00',调用方不判这个就会把「没记到」说成「0 秒」。
  bool get hasDuration => (time != null && time!.isNotEmpty) || durSec != null;

  String get timeText {
    final String? t = time;
    if (t != null && t.isNotEmpty) return t;
    return formatRoamDuration(durSec);
  }

  /// 卡片副行:里程 · 用时 · 点亮。
  ///
  /// ★★ **只拼有值的那几段**。原来是 `distance ?? '0.0'` / `shops ?? 0` /
  ///   durSec 兜 0 —— 一条什么都没记到的旧记录会显示成
  ///   「0.0 km · 00:00 · 点亮 0 家」,而那是**假的**:
  ///   「走了 0 公里」和「没记到里程」是两件事,
  ///   前者会让用户以为自己那次白走了。
  ///
  ///   三段都缺时返回 null —— 调用方整行不显示,比显示一行零好。
  String? get statsLine {
    final List<String> parts = <String>[];
    final double? d = distance;
    if (d != null) parts.add('${d.toStringAsFixed(1)} km');
    // time 是结算时已格式化的文本;durSec 是秒数。两者都没有才算缺。
    if ((time != null && time!.isNotEmpty) || durSec != null) {
      parts.add(timeText);
    }
    final int? sh = shops;
    if (sh != null) parts.add('点亮 $sh 家');
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// 路线名:优先用真实 zone(占位区名「这片街区」不算真实足迹名);
  /// 没有地点时才以记录日期命名,不依赖后端补字段。
  String get routeName {
    final String zoneText = zone ?? '';
    if (zoneText.isNotEmpty && zoneText != _placeholderZone) return zoneText;
    final List<String> names = pois
        .map((RoamPoi p) => p.name.trim())
        .where((String n) => n.isNotEmpty)
        .toList();
    if (names.length > 1) return '${names.first}等${names.length}处足迹回看';
    if (names.length == 1) return '${names.first}周边足迹回看';
    final d = dateTime;
    if (d != null) return '${d.month}月${d.day}日城市漫游足迹';
    return '城市漫游足迹';
  }

  String get completeFact => '已完成本次漫游';
}

/// 历史列表卡片。对齐小程序 `scene-roam-history` 的派生字段。
class RoamHistoryEntry {
  RoamHistoryEntry(this.session);

  final RoamSession session;

  int get timestamp => session.ts;

  String get dateFull => session.dateFull;

  /// `m/d/yy`;ts 非法时「日期不可用」。
  String get dateShort {
    final d = session.dateTime;
    if (d == null) return '日期不可用';
    final String yy = (d.year % 100).toString().padLeft(2, '0');
    return '${d.month}/${d.day}/$yy';
  }

  String get title {
    final String zoneText = session.zone ?? '';
    final String head = zoneText.isNotEmpty && zoneText != RoamSession._placeholderZone
        ? zoneText
        : '城市';
    return '$head漫游';
  }

  String get cover => session.photos.isNotEmpty ? session.photos.first : '';

  int get stamps => session.photos.length;

  List<String> get medals =>
      <String?>[session.medal, session.shopMedalName]
          .whereType<String>()
          .where((String m) => m.isNotEmpty)
          .toList();

  /// 出发/到达缩写:zone 去掉虚词后取前两字;全被去掉了兜底「城西」
  /// (对齐小程序:code || '城西')。
  String get fromCode => zoneCode;
  String get toCode => zoneCode;

  String get zoneCode {
    final String base = (session.zone ?? '').trim().isEmpty ? '漫游' : session.zone!.trim();
    final String stripped = base.replaceAll(RegExp('[的这那片街区]'), '');
    if (stripped.isEmpty) return '城西';
    return stripped.length <= 2 ? stripped : stripped.substring(0, 2);
  }

  int get shops => session.shops ?? 0;

  String get timeText => session.timeText;
}

/// 历史页顶部汇总:行程数 / 公里 / 点亮店铺数。
class RoamHistorySummary {
  const RoamHistorySummary({
    required this.trips,
    required this.kmText,
    required this.shops,
  });

  final int trips;

  /// 一位小数公里(同小程序 km.toFixed(1))。
  final String kmText;
  final int shops;

  static RoamHistorySummary fromSessions(List<RoamSession> sessions) {
    double km = 0;
    int shops = 0;
    for (final RoamSession s in sessions) {
      km += s.distance ?? 0;
      shops += s.shops ?? 0;
    }
    return RoamHistorySummary(
      trips: sessions.length,
      kmText: km.toStringAsFixed(1),
      shops: shops,
    );
  }
}

/// 数字或数字串 → double;其它(含 null)一律 null。
/// 落盘字段(如 distance)既可能是数字也可能是字符串,不能 `as num` 硬转。
double? _toDoubleOrNull(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String && value.trim().isNotEmpty) {
    return double.tryParse(value.trim());
  }
  return null;
}
