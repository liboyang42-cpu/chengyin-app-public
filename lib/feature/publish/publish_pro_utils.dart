import 'package:flutter/cupertino.dart';

import '../../core/widgets/cy_system_date_picker.dart';
import '../../data/models/publish_draft.dart';

/// 发布编辑器共用小工具(日期格式化 / 默认票种 / 错误文案)。

/// 默认票种(对齐 fabu/index.js createDefaultTicket):
/// 售票窗口默认今天 → 明天;名称按模式区分。
PublishTicket defaultTicket(int mode) {
  final nextMode = mode == 2 ? 2 : 1;
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day)
      .add(const Duration(days: 1));
  final end = DateTime(now.year, now.month, now.day)
      .add(const Duration(days: 8));
  return PublishTicket()
    ..name = nextMode == 2 ? '自由探索票' : '城市定向票'
    ..price = 0
    ..totalStock = 100
    ..mode = nextMode
    ..teamSize = 0
    ..saleStartTime = fmtDate(now)
    ..saleEndTime = fmtDate(start)
    ..startTime = fmtDateTime(now)
    ..endTime = fmtDateTime(end)
    ..refundSupported = true
    ..syncWithTheme = false;
}

/// 取异常里的后端 msg:裸 Exception 的字符串形如 'Exception: xxx'。
String publishMessage(Object e, String fallback) {
  final s = e.toString();
  if (s.startsWith('Exception: ') && s.length > 11) {
    return s.substring(11);
  }
  if (s.startsWith('Bad state: ')) return s.substring(11);
  return fallback;
}

String _pad2(int n) => n.toString().padLeft(2, '0');

/// 'yyyy-MM-dd'
String fmtDate(DateTime d) =>
    '${d.year}-${_pad2(d.month)}-${_pad2(d.day)}';

/// 'yyyy-MM-dd HH:mm:ss'
String fmtDateTime(DateTime d) =>
    '${fmtDate(d)} ${_pad2(d.hour)}:${_pad2(d.minute)}:${_pad2(d.second)}';

/// 选日期(今天起 31 天,对齐小程序 generateDateList)。
Future<DateTime?> pickDate(BuildContext context, {DateTime? initial}) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final picked = await showCySystemDatePicker(
    context: context,
    mode: CupertinoDatePickerMode.date,
    initialDateTime: initial ?? today,
    minimumDate: today,
    maximumDate: today.add(const Duration(days: 365)),
    title: '选择日期',
  );
  return picked;
}

/// 选日期 + 时间。
Future<DateTime?> pickDateTime(
  BuildContext context, {
  DateTime? initial,
}) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return showCySystemDatePicker(
    context: context,
    mode: CupertinoDatePickerMode.dateAndTime,
    initialDateTime: initial ?? now,
    minimumDate: today,
    maximumDate: today.add(const Duration(days: 365)),
    title: '选择日期和时间',
  );
}
