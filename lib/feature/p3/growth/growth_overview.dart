/// 成长中心概览构建(对齐小程序 `utils/growth-overview.js`)。
///
/// ★ 核心语义:三个数据源里任一个「没拿到」(参数为 null)与「拿到了但值是
/// 0/空」是两回事 —— 前者 stat.value = null → 界面显示 '—',后者显示真实
/// 数字。失败绝不把数据伪装成零(零是用户在陈述自己的资产,伪造的零是撒谎)。
library;

import 'package:chengyin_app/data/models/growth.dart';

/// 概览统计单格。[value] 为 null 时界面显示 '—'(没拿到),非 null 显示数字。
class OverviewStat {
  const OverviewStat({
    required this.key,
    required this.label,
    required this.value,
    required this.unit,
  });

  final String key;
  final String label;
  final String? value;
  final String unit;
}

/// 成长中心概览(等级文案 + 四项统计)。
class GrowthOverview {
  const GrowthOverview({required this.levelText, required this.stats});

  final String levelText;
  final List<OverviewStat> stats;
}

/// 千分位格式化:12345 → '12,345'。null/NaN/无穷 → null(不显示假数字)。
String? formatInteger(Object? value) {
  if (value == null) return null;
  final n = value is num ? value.toDouble() : double.tryParse('$value');
  if (n == null || !n.isFinite) return null;
  final v = n.round();
  final digits = '$v';
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final fromEnd = digits.length - i;
    buf.write(digits[i]);
    if (fromEnd > 1 && (fromEnd - 1) % 3 == 0) buf.write(',');
  }
  return buf.toString();
}

/// 里程格式化:最多 1 位小数,整数不带小数点(3 → '3',3.45 → '3.5')。
String? formatMileage(num? value) {
  if (value == null) return null;
  final rounded = (value * 10).round() / 10;
  return rounded == rounded.roundToDouble()
      ? '${rounded.round()}'
      : rounded.toStringAsFixed(1);
}

/// 非负数值检查:null/空串/非数字/负数 → null;0 是真实 0。
/// (js 版 nonNegativeNumber,App 侧输入已过模型层,这里做最后一道防线。)
int? nonNegative(int? value) =>
    (value == null || value < 0) ? null : value;

/// 完成主题数:按 topicId 去重后的个数。
/// items 为 null(接口没接通)→ null,界面显示 '—';空列表 → 真实的 0。
int? completedTopicCount(List<CompletedActivity>? items) {
  if (items == null) return null;
  final topicIds = <int>{};
  for (final item in items) {
    if (item.topicId != 0) topicIds.add(item.topicId);
  }
  return topicIds.length;
}

/// 由三个数据源构建概览。[center]/[play]/[completed] 任一为 null 表示
/// 该接口没接通,对应统计显示 '—',不显示 0。
GrowthOverview buildGrowthOverview({
  GrowthCenter? center,
  PlayGrowth? play,
  List<CompletedActivity>? completed,
}) {
  final exp = center == null ? null : nonNegative(center.expValue);
  final level = center == null ? null : nonNegative(center.levelNo);
  final badgeCount = center?.badges.length;
  final mileage = play?.totalMileage;
  final topicCount = completedTopicCount(completed);

  return GrowthOverview(
    levelText: level == null ? '成长概览' : 'Lv.${level < 1 ? 1 : level}',
    stats: <OverviewStat>[
      OverviewStat(
        key: 'exp',
        label: '探索值',
        value: formatInteger(exp),
        unit: 'EXP',
      ),
      OverviewStat(
        key: 'badge',
        label: '徽章',
        value: badgeCount?.toString(),
        unit: '枚',
      ),
      OverviewStat(
        key: 'topic',
        label: '完成主题',
        value: topicCount?.toString(),
        unit: '个',
      ),
      OverviewStat(
        key: 'distance',
        label: '累计距离',
        value: formatMileage(mileage),
        unit: 'km',
      ),
    ],
  );
}

/// 徽章「获得时刻」文案。
///
/// 后端 selectMemberBadges 下发 unlock_time 是不带时区的中国时间串
/// (yyyy-MM-dd HH:mm:ss)。这里做纯字符串解析再拼装,不经过 DateTime
/// 本地时区换算 —— 直接 DateTime.parse 在非 +8 设备上会把时间整体偏移。
/// 解析失败返回 null(拿不到就整块不展示,不填占位符)。
String? unlockMomentText(String? value) {
  if (value == null) return null;
  final m = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})',
  ).firstMatch(value);
  if (m == null) return null;
  final month = int.parse(m.group(2)!);
  final day = int.parse(m.group(3)!);
  final hour = int.parse(m.group(4)!);
  final minute = int.parse(m.group(5)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  if (hour > 23 || minute > 59) return null;
  return '${m.group(1)}年$month月$day日 '
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// 徽章展示名:badgeName → badgeCode → '徽章' 三级兜底。
String badgeDisplayName(MedalBadge badge) {
  if (badge.badgeName.isNotEmpty) return badge.badgeName;
  final code = badge.badgeCode;
  if (code != null && code.isNotEmpty) return code;
  return '徽章';
}

/// 名称首字符(徽章圆形头像里用)。空名 → '?'。
String nameInitial(String? name) {
  if (name == null) return '?';
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed[0];
}
