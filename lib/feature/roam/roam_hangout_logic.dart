/// 附近的局:页面之外的纯函数(marker / 空态文案 / 表单校验 / 时间口语化)。
///
/// ★ 与小程序 `utils/roam-hangout.js`、`utils/roam-hangout-marker.js`、
///   `utils/roam-runners.js` 逐条对齐(2026-09-15,github/master@7860bfa0f)。
///   放纯函数是为了单测钉住 —— 这些文案与阈值两端必须一模一样。
library;

/// 300 m 内算「就在眼前」,卡片与列表文案都用它。
const int kRoamHangoutNearM = 300;

/// 建局表单闸(与后端 `RoamHangoutServiceImpl.create` 同一套):
/// 标题 2–30 字、说明最多 120 字、地点必选。
const int kHangoutTitleMin = 2;
const int kHangoutTitleMax = 30;
const int kHangoutDescMax = 120;

/// 附近正在走的人最多显示 / 一次返回几个人由后端限制,前端不额外截断。

/// 距离口语化:1000 以下取整到米;1000 以上 1 位小数,10000 以上取整。
/// 后端可能下发 null(局没有坐标),这时返回空串而不是「0m」。
String roamFmtKm(Object? raw) {
  final double? n = _numOrNull(raw);
  if (n == null) return '';
  if (n >= 10000) return '${(n / 1000).round()}km';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}km';
  return '${n.round()}m';
}

/// 卡片三格的距离拆成 {num, unit}(大数字 + 单位)。
({String num, String unit}) roamSplitDist(Object? raw) {
  final double? n = _numOrNull(raw);
  if (n == null) return (num: '', unit: 'm');
  if (n >= 1000) {
    return (
      num: (n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1),
      unit: 'km',
    );
  }
  return (num: '${n.round()}', unit: 'm');
}

/// 时间口语化(卡片 / 列表共用):
/// `今晚 8:00` / `明天 7:30` / `周六 20:00` / `9/12`。
/// ⚠️ 只有「今晚」用 12 小时制(自带下午语境),其余保留 24 小时制 ——
///   否则「明天 7:30」分不清早晚(小程序原注释)。
({String label, String hm, String short}) roamWhenParts(
  Object? value, {
  DateTime? now,
}) {
  final DateTime? parsed = _parseWhen(value);
  if (parsed == null) return (label: '', hm: '', short: '');
  final DateTime n = now ?? DateTime.now();
  int dayOf(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
  final int diff = dayOf(parsed) - dayOf(n);
  final String label;
  if (diff == 0) {
    label = parsed.hour >= 17 ? '今晚' : '今天';
  } else if (diff == 1) {
    label = '明天';
  } else if (diff > 1 && diff < 7) {
    label = _week[parsed.weekday % 7];
  } else {
    label = '${parsed.month}/${parsed.day}';
  }
  final String hm = parsed.hour == 0 && parsed.minute == 0 && _dateOnly(value)
      ? ''
      : '${_pad2(parsed.hour)}:${_pad2(parsed.minute)}';
  final String spoken = label == '今晚'
      ? '${parsed.hour > 12 ? parsed.hour - 12 : parsed.hour}:${_pad2(parsed.minute)}'
      : hm;
  return (label: label, hm: hm, short: hm.isEmpty ? label : '$label $spoken');
}

const List<String> _week = <String>['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

/// 空态:后端给了 suggestedRadius/suggestedCount 就引导拉远,否则引导开局。
({String title, String sub, String primary, bool expand}) roamEmptyStateCopy({
  required int radiusM,
  int? suggestedRadius,
  int? suggestedCount,
}) {
  if ((suggestedRadius ?? 0) > 0 && (suggestedCount ?? 0) > 0) {
    return (
      title: '还没有局',
      sub: '雾再远一点,${roamFmtKm(suggestedRadius)} 内有 $suggestedCount 个局在约。',
      primary: '看远一点',
      expand: true,
    );
  }
  return (
    title: '还没有局',
    sub: '开一个,让附近的人找到你。',
    primary: '在这里开一局',
    expand: false,
  );
}

/// 建局表单校验;返回 null 表示通过,否则是第一条错误文案(指明哪道闸)。
String? validateRoamHangoutForm({
  required String title,
  required String description,
  required double? lat,
  required double? lng,
}) {
  final String t = title.trim();
  if (t.length < kHangoutTitleMin || t.length > kHangoutTitleMax) {
    return '标题 $kHangoutTitleMin–$kHangoutTitleMax 字';
  }
  if (description.trim().length > kHangoutDescMax) {
    return '说明最多 $kHangoutDescMax 字';
  }
  if (lat == null || lng == null) return '请选择地点';
  return null;
}

/// 在走时长:原型写的是 38:20 / 12:04(分:秒);过一小时才补出小时位。
String roamElapsedLabel(int seconds) {
  int s = seconds < 0 ? 0 : seconds;
  final int h = s ~/ 3600;
  final int m = (s % 3600) ~/ 60;
  final int ss = s % 60;
  return h > 0 ? '$h:${_pad2(m)}:${_pad2(ss)}' : '${_pad2(m)}:${_pad2(ss)}';
}

/// 「刚出发 / 走了半小时上下 / 走了一个多小时」——按在走时长真算,不写死。
String roamSinceLabel(int seconds) {
  final int s = seconds < 0 ? 0 : seconds;
  if (s < 600) return '刚出发';
  if (s < 3600) return '走了半小时上下';
  return '走了一个多小时';
}

/// 每个人一个环色:同一个人每次进来都该是同一个颜色 ——
/// 地图刷新一次就换一身衣服会让人认错人。取模定色,与小程序同表。
const List<int> kRoamRunnerColors = <int>[
  0xFFA78BFA,
  0xFF22D3EE,
  0xFFF0ABFC,
  0xFFFDBA74,
  0xFF67E8F9,
  0xFFFCA5A5,
];

int roamRunnerColor(int memberId) {
  final int n = memberId.abs();
  return kRoamRunnerColors[n % kRoamRunnerColors.length];
}

double? _numOrNull(Object? value) {
  if (value == null || value == '') return null;
  final double? n = value is num
      ? value.toDouble()
      : double.tryParse(value.toString());
  return (n != null && n.isFinite) ? n : null;
}

bool _dateOnly(Object? value) {
  final String s = value?.toString() ?? '';
  return !RegExp(r'[T ]\d{2}:\d{2}').hasMatch(s);
}

DateTime? _parseWhen(Object? value) {
  if (value == null) return null;
  final RegExpMatch? m = RegExp(
    r'(\d{4})-(\d{2})-(\d{2})(?:[T ]+(\d{2}):(\d{2}))?',
  ).firstMatch(value.toString());
  if (m == null) return null;
  return DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    int.tryParse(m.group(4) ?? '') ?? 0,
    int.tryParse(m.group(5) ?? '') ?? 0,
  );
}

String _pad2(int n) => n < 10 ? '0$n' : '$n';
