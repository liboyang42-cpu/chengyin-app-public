import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS 真机优先调用 UIKit `UIDatePicker`;其他平台、测试环境或通道
/// 不可用时，退回 Flutter 官方 CupertinoDatePicker。
///
/// 这个边界刻意不用 Material date/time dialog：iOS 用户始终获得
/// 系统日历、本地化次序、Dynamic Type 和 VoiceOver 语义。
const MethodChannel _nativeDatePickerChannel = MethodChannel(
  'com.chengyin.app/native_date_picker',
);

Future<DateTime?> showCySystemDatePicker({
  required BuildContext context,
  required CupertinoDatePickerMode mode,
  required DateTime initialDateTime,
  required DateTime minimumDate,
  required DateTime maximumDate,
  String title = '选择日期',
}) async {
  final DateTime initial = _clamp(initialDateTime, minimumDate, maximumDate);

  if (defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb) {
    try {
      final int? milliseconds = await _nativeDatePickerChannel
          .invokeMethod<int>('show', <String, Object>{
            'mode': mode == CupertinoDatePickerMode.date
                ? 'date'
                : mode == CupertinoDatePickerMode.time
                ? 'time'
                : 'dateTime',
            'initialMilliseconds': initial.millisecondsSinceEpoch,
            'minimumMilliseconds': minimumDate.millisecondsSinceEpoch,
            'maximumMilliseconds': maximumDate.millisecondsSinceEpoch,
            'title': title,
          });
      return milliseconds == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(milliseconds);
    } on MissingPluginException {
      // Widget tests and older embeddings have no native channel.
    } on PlatformException {
      // Native presentation failure must not make the form unusable.
    }
  }

  if (!context.mounted) return null;
  return _showCupertinoFallback(
    context: context,
    mode: mode,
    initialDateTime: initial,
    minimumDate: minimumDate,
    maximumDate: maximumDate,
    title: title,
  );
}

DateTime _clamp(DateTime value, DateTime minimum, DateTime maximum) {
  if (value.isBefore(minimum)) return minimum;
  if (value.isAfter(maximum)) return maximum;
  return value;
}

Future<DateTime?> _showCupertinoFallback({
  required BuildContext context,
  required CupertinoDatePickerMode mode,
  required DateTime initialDateTime,
  required DateTime minimumDate,
  required DateTime maximumDate,
  required String title,
}) {
  DateTime pending = initialDateTime;
  return showCupertinoModalPopup<DateTime>(
    context: context,
    semanticsDismissible: true,
    builder: (BuildContext context) => CupertinoPopupSurface(
      isSurfacePainted: true,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 316,
          child: Column(
            children: <Widget>[
              SizedBox(
                height: 52,
                child: Row(
                  children: <Widget>[
                    CupertinoButton(
                      key: const Key('cy-native-picker-cancel'),
                      minimumSize: const Size(44, 44),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: CupertinoTheme.of(
                          context,
                        ).textTheme.navTitleTextStyle,
                      ),
                    ),
                    CupertinoButton(
                      key: const Key('cy-native-picker-done'),
                      minimumSize: const Size(44, 44),
                      onPressed: () => Navigator.of(context).pop(pending),
                      child: const Text('完成'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: mode,
                  initialDateTime: initialDateTime,
                  minimumDate: minimumDate,
                  maximumDate: maximumDate,
                  use24hFormat: true,
                  showDayOfWeek: mode == CupertinoDatePickerMode.date,
                  onDateTimeChanged: (DateTime value) => pending = value,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
