import 'package:flutter/widgets.dart';
import '../../data/models/coop_invite_row.dart';
import '../../l10n/strings.dart';

String coopDetailInviteType(BuildContext context, CoopInviteRow row) => switch(row.inviteType) {
  0 => stringsOf(context).coopDetailTypeMerchant,
  1 => stringsOf(context).coopDetailTypeClub,
  2 => stringsOf(context).coopDetailTypeLegacy,
  _ => stringsOf(context).coopDetailTypeDefault,
};
String? coopDetailTerms(BuildContext context, CoopInviteRow row) => switch(row.shareMode) {
  1 => stringsOf(context).coopDetailRevenueRate('${row.shareRate ?? '?'}'),
  2 => stringsOf(context).coopDetailFixedFee('${row.fixedFee ?? '?'}'),
  0 => stringsOf(context).coopDetailReferral,
  _ => null,
};
String coopDetailDeposit(BuildContext context, CoopInviteRow row) {
  if (row.legacyReadonly || !row.depositOwed) return '';
  final amount = row.depositAmount;
  if (amount == null) return stringsOf(context).coopDetailDepositUnknown;
  final text = amount == amount.roundToDouble() ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2);
  return stringsOf(context).coopDetailDepositDue(text);
}
String coopDetailSlot(BuildContext context, CoopInviteRow row, Map<String, dynamic>? slots) {
  if (slots == null) return '';
  if (row.gameId != null) {
    final slot = (slots['byGame'] as Map<String, dynamic>?)?['${row.gameId}'] as Map<String, dynamic>?;
    if (slot != null) return stringsOf(context).coopDetailGameSlots('${slot['pending']}', '${slot['cap']}');
  }
  if (row.topicId != null) {
    final slot = (slots['byTopic'] as Map<String, dynamic>?)?['${row.topicId}'] as Map<String, dynamic>?;
    if (slot != null) return stringsOf(context).coopDetailTopicSlots('${slot['accepted']}', '${slot['cap']}');
  }
  return '';
}
String coopDetailTopic(BuildContext context, CoopInviteRow row) => row.topicId == null ? '' : stringsOf(context).coopDetailTopic(row.topicId!);
String coopDetailCountdown(BuildContext context, CoopInviteRow row, DateTime now) {
  final end = row.expireTime;
  if (row.status != 0 || end == null) return '';
  final left = end.difference(now);
  if (left.isNegative) return stringsOf(context).coopDetailRecruitExpired;
  return left.inDays > 0 ? stringsOf(context).coopDetailRecruitDays(left.inDays) : stringsOf(context).coopDetailRecruitHours(left.inHours);
}
