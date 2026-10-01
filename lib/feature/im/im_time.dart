import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';

// IM 时间格式化(容错)。后端时间是 `yyyy-MM-dd HH:mm:ss` 字符串,
// 解析失败一律返回空串,绝不抛异常。

DateTime? _parse(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  // 兼容 '2026-06-22 10:30:00' 与 ISO 形式。
  return DateTime.tryParse(raw.replaceFirst(' ', 'T'));
}

String _pad(int n) => n < 10 ? '0$n' : '$n';

/// 会话列表时间:今天显示 HH:mm,昨天显示「昨天」,更早显示 M月d日。
///
/// ⚠️ [now] 可注入 —— 不注入就没法测「这个时间会不会随日子变」。
///   2026-08-20 实证:聊天基准图用了「昨天」那一档的日期,过一天就自动变成
///   「8月18日」,**基准图每天红一次**,而红的原因和代码无关。
///   会自己腐烂的证据比没有更坏 —— 它会训练人忽略红色。
String fmtConversationTime(String? raw, {DateTime? now, BuildContext? context}) {
  final localized = context == null ? null : Localizations.of<AppLocalizations>(context, AppLocalizations);
  final d = _parse(raw);
  if (d == null) return '';
  now ??= DateTime.now();
  // Calendar-day distance must not become zero across a 23-hour DST day.
  final today = DateTime.utc(now.year, now.month, now.day);
  final that = DateTime.utc(d.year, d.month, d.day);
  final diffDays = today.difference(that).inDays;
  if (diffDays == 0) return '${_pad(d.hour)}:${_pad(d.minute)}';
  if (diffDays == 1) return localized?.imYesterday ?? '昨天';
  if (d.year == now.year) {
    return localized == null ? '${d.month}月${d.day}日'
        : DateFormat.MMMd(localized.localeName).format(d);
  }
  return localized == null ? '${d.year}/${d.month}/${d.day}'
      : DateFormat.yMd(localized.localeName).format(d);
}

/// 聊天气泡上方时间分隔:今天 HH:mm,昨天 昨天 HH:mm,更早 M月d日 HH:mm。
///
/// ⚠️ [now] 可注入,理由同 [fmtConversationTime]。
String fmtMessageTime(String? raw, {DateTime? now, BuildContext? context}) {
  final localized = context == null ? null : Localizations.of<AppLocalizations>(context, AppLocalizations);
  final d = _parse(raw);
  if (d == null) return '';
  now ??= DateTime.now();
  final hm = '${_pad(d.hour)}:${_pad(d.minute)}';
  // Calendar-day distance must not become zero across a 23-hour DST day.
  final today = DateTime.utc(now.year, now.month, now.day);
  final that = DateTime.utc(d.year, d.month, d.day);
  final diffDays = today.difference(that).inDays;
  if (diffDays == 0) return hm;
  if (diffDays == 1) return '${localized?.imYesterday ?? '昨天'} $hm';
  final date = localized == null ? '${d.month}月${d.day}日'
      : DateFormat.MMMd(localized.localeName).format(d);
  return '$date $hm';
}
