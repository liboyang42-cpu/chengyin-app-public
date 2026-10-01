import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../data/models/club_ops.dart';
import '../../l10n/strings.dart';

String clubOccurrenceMeta(BuildContext context, SeriesOccurrence row) {
  final source = row.displaySource;
  if (source == null) return row.meta;
  final strings = stringsOf(context);
  if (source.cancelled) {
    return source.refundedCount == null
        ? strings.clubOccurrenceCancelled
        : strings.clubOccurrenceRefunded(source.refundedCount!);
  }
  final count = source.signupCount;
  if (count == null) return strings.clubOccurrenceCountPending;
  if (count == 0) return strings.clubOccurrenceNotOnSale;
  return source.editable
      ? strings.clubOccurrenceRegistered(count)
      : strings.clubOccurrenceRegisteredLocked(count);
}

String clubOccurrenceBadge(BuildContext context, SeriesOccurrence row) {
  final source = row.displaySource;
  if (source == null) return row.badge;
  final strings = stringsOf(context);
  if (source.cancelled) return strings.clubOccurrenceCancelled;
  if (source.editable) return strings.clubOccurrenceEdit;
  return source.lockReason.isEmpty
      ? strings.clubOccurrenceLocked
      : source.lockReason;
}

String clubOccurrenceDate(BuildContext context, SeriesOccurrence row) {
  final source = row.displaySource;
  if (source == null) return row.dateText;
  final raw = source.occurrenceAt;
  if (raw == null || raw.toString().isEmpty) {
    return stringsOf(context).clubOccurrenceDatePending;
  }
  final parsed = raw is num
      ? DateTime.fromMillisecondsSinceEpoch(raw.toInt() * 1000)
      : DateTime.tryParse(raw.toString().replaceFirst(' ', 'T'));
  if (parsed == null) return row.dateText;
  final locale = Localizations.localeOf(context);
  if (locale.languageCode == 'zh') return row.dateText;
  return DateFormat.MMMEd(locale.toString()).add_Hm().format(parsed);
}
