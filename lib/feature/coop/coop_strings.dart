import 'package:flutter/widgets.dart';

import '../../data/models/coop_invite.dart';
import '../../data/models/coop_pool.dart';
import '../../data/models/merchant_coop.dart';
import '../../l10n/strings.dart';

/// Display labels only. Protocol wire values remain in the models.
String coopActionLabel(BuildContext context, CoopHandleAction action) => switch (action) {
  CoopHandleAction.accept => stringsOf(context).coopActionAccept,
  CoopHandleAction.reject => stringsOf(context).coopReject,
  CoopHandleAction.cancel => stringsOf(context).coopActionCancel,
};

String coopInviteTypeLabel(BuildContext context, CoopInviteType type) => switch (type) {
  CoopInviteType.merchant => stringsOf(context).coopBusinessType,
  CoopInviteType.club => stringsOf(context).coopClubType,
};

String coopApplicationStatus(BuildContext context, int? status) => switch (status) {
  0 => stringsOf(context).coopPendingConfirmation,
  1 => stringsOf(context).coopRejected,
  2 => stringsOf(context).coopWithdrawn,
  3 => stringsOf(context).coopReturnedInvite,
  _ => stringsOf(context).coopUnknownStatus,
};
String coopCandidateStatus(BuildContext context, int? status) => switch (status) {
  1 => stringsOf(context).coopDeclined,
  2 => stringsOf(context).coopWithdrawn,
  3 => stringsOf(context).coopConverted,
  _ => stringsOf(context).coopPending,
};
String coopAuditStatus(BuildContext context, int? status) => switch (status) {
  0 => stringsOf(context).coopPendingAllocation,
  1 => stringsOf(context).coopAwarded,
  2 => stringsOf(context).coopNotAwarded,
  _ => stringsOf(context).coopPendingStatus,
};
String coopInvitationStatus(BuildContext context, int? status) => switch (status) {
  0 => stringsOf(context).coopPendingConfirmation,
  1 => stringsOf(context).coopAccepted,
  2 => stringsOf(context).coopRejected,
  3 => stringsOf(context).coopCancelled,
  4 => stringsOf(context).coopReplaced,
  5 => stringsOf(context).coopExpired,
  _ => '',
};
String coopPoolStatus(BuildContext context, String status) => switch (status) {
  'applied' => stringsOf(context).coopPoolApplied,
  'invited' => stringsOf(context).coopPoolInvited,
  'taken' => stringsOf(context).coopPoolTaken,
  'cooped' => stringsOf(context).coopPoolCooped,
  'converted' => stringsOf(context).coopPoolConverted,
  'declined' => stringsOf(context).coopPoolDeclined,
  'withdrawn' => stringsOf(context).coopPoolWithdrawn,
  _ => stringsOf(context).coopPoolOpen,
};
String coopComplaintCategory(BuildContext context, int index) => switch (index) {
  0 => stringsOf(context).coopComplaintService,
  1 => stringsOf(context).coopComplaintFees,
  2 => stringsOf(context).coopComplaintSafety,
  3 => stringsOf(context).coopComplaintAdvertising,
  _ => stringsOf(context).coopComplaintOther,
};

String coopPoolName(BuildContext context, CoopPoolItem row) => row.hasCustomName
    ? row.name : stringsOf(context).coopUnnamedTheme;
String coopApplyTitle(BuildContext context, CoopPoolApply row) =>
    (row.topicName ?? '').trim().isNotEmpty ? row.topicName!.trim()
        : stringsOf(context).coopThemeNumber(row.topicId.toString());
String coopApplyPeer(BuildContext context, CoopPoolApply row, {required bool received}) {
  final peer = (received ? row.clubName : row.merchantNick)?.trim() ?? '';
  if (peer.isEmpty) return '';
  return received ? stringsOf(context).coopApplyFrom(peer) : stringsOf(context).coopApplyTo(peer);
}
String coopApplySub(BuildContext context, CoopPoolApply row, {required bool received}) {
  if (received) return stringsOf(context).coopApplyClubLeads;
  final name = row.clubName?.trim() ?? '';
  return name.isEmpty ? stringsOf(context).coopApplyLead : stringsOf(context).coopApplyLeadClub(name);
}
String coopApplyTerms(BuildContext context, CoopPoolApply row) {
  final message = row.message?.trim() ?? '';
  return message.isEmpty ? stringsOf(context).coopApplyIntentOnly : stringsOf(context).coopApplyMessage(message);
}
String? coopInviteBlocker(BuildContext context, CoopInviteForm form) {
  if (form.topicId == null) return stringsOf(context).coopSelectThemeFirst;
  if (form.targets.isEmpty) return stringsOf(context).coopSelectTargetFirst(coopInviteTypeLabel(context, form.type));
  if (form.shareMode == CoopShareMode.fixed && (form.fixedFee == null || form.fixedFee! <= 0)) {
    return stringsOf(context).coopPositiveFixedFee;
  }
  return null;
}

String coopPerkType(BuildContext context, int type) => switch (type) {
  0 => stringsOf(context).coopPerkTypeGift,
  1 => stringsOf(context).coopPerkTypeCoupon,
  2 => stringsOf(context).coopPerkTypeDiscount,
  _ => stringsOf(context).coopPerkTypeBenefit,
};

String coopTargetName(BuildContext context, CoopInviteTarget target, CoopInviteType type) =>
    !target.isLocalDefaultName ? target.name : type == CoopInviteType.club
        ? stringsOf(context).coopTargetClub : stringsOf(context).coopTargetMerchant;
