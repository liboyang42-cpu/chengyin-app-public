import 'package:flutter/widgets.dart';
import '../../l10n/strings.dart';
import '../../data/models/merchant_relation.dart';
import '../../data/models/merchant_coop.dart';
import '../../data/models/chapter_application.dart';

/// Only local enum/option labels are mapped; stored merchant text bypasses it.
String merchantDirectoryLocalText(BuildContext context, String text) => switch (text) {
  '已接受' => stringsOf(context).merchantDirectoryAccepted,
  '已拒绝' => stringsOf(context).merchantDirectoryDeclined,
  '已过期' => stringsOf(context).merchantDirectoryExpired,
  '待你确认' => stringsOf(context).merchantDirectoryWaitingConfirmation,
  '已中标承接' => stringsOf(context).merchantDirectoryAwarded,
  '本轮未中标' => stringsOf(context).merchantDirectoryNotSelected,
  '待后台确认' => stringsOf(context).merchantDirectoryBackendPending,
  '状态待确认' => stringsOf(context).merchantDirectoryStatusPending,
  '待处理' => stringsOf(context).merchantDirectoryPending,
  '夜间友好' => stringsOf(context).merchantDirectoryNight,
  '可拍照' => stringsOf(context).merchantDirectoryPhotos,
  '适合组队' => stringsOf(context).merchantDirectoryGroups,
  '宠物友好' => stringsOf(context).merchantDirectoryPets,
  '安静' => stringsOf(context).merchantDirectoryQuiet,
  '适合亲子' => stringsOf(context).merchantDirectoryFamily,
  _ => text,
};

String merchantDirectoryRelationDescription(BuildContext context, MerchantRelation row) {
  for (final value in [row.address, row.categoryName, row.city]) {
    if (value != null && value.trim().isNotEmpty) return value.trim();
  }
  return row.type == 'club' ? stringsOf(context).merchantDirectoryViewClub
      : stringsOf(context).merchantDirectoryViewMerchant;
}
String? merchantDirectoryRouteDeadline(BuildContext context, RecruitingRoute row) {
  final date = row.signUpEndDate;
  if (date == null || date.isEmpty) return null;
  return stringsOf(context).merchantDirectorySignupDeadline(date.length > 10 ? date.substring(0, 10) : date);
}
String merchantDirectoryInviteDeadline(BuildContext context, MerchantInvite row) {
  final raw = (row.expireTime ?? '').trim();
  if (raw.isEmpty) return stringsOf(context).merchantDirectoryDeadlinePending;
  final date = DateTime.tryParse(raw) ?? DateTime.tryParse(raw.replaceAll('-', '/'));
  return date == null ? raw : stringsOf(context).merchantDirectoryDeadlineDate(date.month, date.day);
}
String merchantDirectoryChapterTitle(BuildContext context, ChapterApplication row) {
  final parts = [row.topicName, row.chapterName]
      .whereType<String>().map((value) => value.trim()).where((value) => value.isNotEmpty).toList();
  return parts.isEmpty ? stringsOf(context).merchantDirectoryApplication : parts.join(' · ');
}
String merchantDirectoryChapterStatus(BuildContext context, ChapterApplication row) {
  if (row.isRejected) {
    final reason = row.auditRemark?.trim() ?? '';
    return reason.isEmpty ? stringsOf(context).merchantDirectoryDeclined
        : stringsOf(context).merchantDirectoryRejectedReason(reason);
  }
  if (row.isApproved) return row.isInvited ? stringsOf(context).merchantDirectoryInvitedHost
      : stringsOf(context).merchantDirectoryApproved;
  return stringsOf(context).merchantDirectoryReview;
}
