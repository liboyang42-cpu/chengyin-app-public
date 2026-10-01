import 'package:flutter/widgets.dart';

import '../../data/models/coupon.dart';
import '../../l10n/strings.dart';

String couponName(BuildContext context, CouponRecord record) =>
    record.couponName?.isNotEmpty == true
        ? record.couponName!
        : stringsOf(context).couponWalletDefaultName;

String couponStatus(BuildContext context, int status) => switch (status) {
  0 => stringsOf(context).couponWalletUnused,
  1 => stringsOf(context).couponWalletUsed,
  2 => stringsOf(context).couponWalletExpired,
  3 => stringsOf(context).couponWalletInvalid,
  _ => stringsOf(context).couponWalletUnknown,
};

/// Same display-only date truncation as CouponRecord.dateText. Eligibility
/// remains owned by the model/server; localization never recomputes status.
String couponDateLine(BuildContext context, CouponRecord record) {
  final strings = stringsOf(context);
  if (record.useStatus == 3) return strings.couponWalletRevoked;
  String dayDots(String? raw) {
    final text = (raw ?? '').trim();
    if (text.length < 10) return '';
    final date = text.replaceFirst('T', ' ').substring(0, 10);
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)
        ? date.replaceAll('-', '.') : '';
  }
  final end = dayDots(record.endTime);
  final endLabel = end.isEmpty
      ? strings.couponWalletDateUnknown : strings.couponWalletValidUntil(end);
  if (record.started) return endLabel;
  final start = dayDots(record.startTime);
  return start.isEmpty ? endLabel
      : '${strings.couponWalletAvailableFrom(start)} · $endLabel';
}
