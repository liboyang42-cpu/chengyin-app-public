import 'package:flutter/widgets.dart';

import '../../data/models/club_crm.dart';
import '../../data/models/club.dart';
import '../../data/models/club_manage.dart';
import '../../l10n/strings.dart';

String clubCustomerItemName(BuildContext context, ClubCustomerItem row) =>
    row.displaySource?.nameMissing == true
        ? stringsOf(context).clubCustomerNoName : row.displayName;

String clubCustomerSummaryName(BuildContext context, ClubCustomerSummary row) =>
    row.displaySource?.nameMissing == true
        ? stringsOf(context).clubCustomerNoName : row.displayName;

String clubCustomerRecordTitle(BuildContext context, ClubCustomerRecord row) =>
    row.displaySource?.titleMissing == true
        ? stringsOf(context).clubCustomerUntitled : row.title;

String clubCustomerItemMeta(BuildContext context, ClubCustomerItem row) {
  final source = row.displaySource;
  if (source == null) return row.metaText;
  final strings = stringsOf(context);
  if (source.pendingCount > 0) {
    final head = strings.clubCustomerPendingTickets(source.pendingCount);
    return source.lastTopicName.isEmpty ? head
        : strings.clubCustomerRecentTopic(head, source.lastTopicName);
  }
  final head = strings.clubCustomerVisitCount(source.verifiedCount);
  final parts = _dateParts(source.lastVisitDate);
  return parts == null ? head
      : strings.clubCustomerRecentVisit(head, '${parts.month}-${parts.day}');
}

String clubCustomerInteraction(BuildContext context, ClubCustomerSummary row) {
  final source = row.displaySource;
  if (source == null) return row.lastInteractionText;
  final strings = stringsOf(context);
  final parts = _dateParts(source.lastInteractionTime);
  if (parts == null) return strings.clubCustomerNoInteraction;
  final day = strings.clubCustomerMonthDay(_number(parts.month), _number(parts.day));
  return source.remark.isEmpty ? strings.clubCustomerRecentInteraction(day)
      : strings.clubCustomerInteractionRemark(day, source.remark);
}

String clubCustomerRecordMonth(BuildContext context, ClubCustomerRecord row) {
  final source = row.displaySource;
  if (source == null) return row.monthText;
  final parts = _dateParts(source.occurredAt);
  return parts == null ? '' : stringsOf(context).clubCustomerMonth(_number(parts.month));
}

String clubCustomerRecordStatus(BuildContext context, ClubCustomerRecord row) {
  final strings = stringsOf(context);
  return switch (row.displaySource?.statusCode) {
    'VERIFIED' => strings.clubCustomerVerified,
    'PENDING' => strings.clubCustomerPending,
    'CONTACTED' => strings.clubCustomerContacted,
    'REFUNDED' => strings.clubCustomerRefunded,
    'REGISTERED' => strings.clubCustomerRegistrationLabel,
    _ => row.statusLabel,
  };
}

String clubEditionOptionLabel(BuildContext context, EditionOption option) {
  if (!option.hasGeneratedLabel) return option.label;
  final name = option.topicName.isEmpty
      ? stringsOf(context).clubEditionNumber(option.id) : option.topicName;
  return option.dateText.isEmpty ? name
      : stringsOf(context).clubCustomerEditionDate(name, option.dateText);
}

// Same lexical date extraction as the source view model. No invented dates,
// timezone conversion, validation relaxation, or normalization of raw names.
({String month, String day})? _dateParts(Object? value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})')
      .firstMatch('${value ?? ''}'.replaceFirst('T', ' '));
  return match == null ? null : (month: match.group(2)!, day: match.group(3)!);
}
int _number(String value) => int.tryParse(value) ?? 0;

String clubMemberDisplayName(BuildContext context, ClubMember member) {
  final name = (member.nickname ?? '').trim();
  return name.isEmpty ? stringsOf(context).clubMainUserNumber(member.memberId) : name;
}
