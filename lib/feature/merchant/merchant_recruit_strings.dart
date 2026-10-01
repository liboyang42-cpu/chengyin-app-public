import 'package:flutter/widgets.dart';
import '../../l10n/strings.dart';
import '../../data/models/merchant_recruit.dart';

String merchantRecruitChapterName(BuildContext context, RecruitChapter row) => row.hasNameFallback ? stringsOf(context).merchantRecruitPageUnnamedChapter : row.name;
String merchantRecruitNodeName(BuildContext context, MyChapterNode row) => row.hasNameFallback ? stringsOf(context).merchantRecruitPageUnnamedNode : row.name;
String merchantRecruitCategory(BuildContext context, RecruitChapter row) => (row.category ?? '').trim().isEmpty ? stringsOf(context).merchantRecruitPageCategoryMissing : row.category!.trim();
String merchantRecruitRequired(BuildContext context, RecruitChapter row) => row.required_ == null ? stringsOf(context).merchantRecruitPageRequiredUnknown : row.required_ == 0 ? stringsOf(context).merchantRecruitPageOptional : stringsOf(context).merchantRecruitPageRequired;
String merchantRecruitLimit(BuildContext context, RecruitChapter row) {
  final left = row.remainingMerchantCount;
  if (left == null) return stringsOf(context).merchantRecruitPageUnlimited;
  if (left <= 0) return stringsOf(context).merchantRecruitPageFull;
  final total = row.maxMerchant;
  return total == null || total <= 0 ? stringsOf(context).merchantRecruitPageRemaining(left) : stringsOf(context).merchantRecruitPageRemainingOf(left, total);
}
String merchantRecruitNodeAudit(BuildContext context, MyChapterNode row) => switch(row.nodeAuditStatus) {
  0 => stringsOf(context).merchantRecruitPageReviewing,
  1 => stringsOf(context).merchantRecruitPageApproved,
  2 => stringsOf(context).merchantRecruitPageRejected,
  _ => stringsOf(context).merchantRecruitPageAuditUnknown,
};
String merchantRecruitStart(BuildContext context, UpcomingRun row) => (row.startTime ?? '').trim().isEmpty ? stringsOf(context).merchantRecruitPageStartUnknown : row.startLabel;
String merchantRecruitSource(BuildContext context, UpcomingRun row) => (row.clubName ?? '').trim().isEmpty ? stringsOf(context).merchantRecruitPageOpenRun : row.clubName!.trim();
String merchantRecruitMeta(BuildContext context, UpcomingRun row) {
  final status = switch(row.teamStatus) {
    'FORMED' || 'formed' => stringsOf(context).merchantRecruitPageFormed,
    'PENDING' || 'pending' => stringsOf(context).merchantRecruitPageForming,
    'FAILED' || 'failed' => stringsOf(context).merchantRecruitPageFailed,
    _ => '',
  };
  return [row.paidCount == null ? stringsOf(context).merchantRecruitPageCountUnknown : stringsOf(context).merchantRecruitPageCount(row.paidCount!), if(status.isNotEmpty) status].join(' · ');
}
String merchantRecruitStep(BuildContext context, UpcomingRun row) => row.nodeOrder == null || row.nodeTotal == null || row.nodeTotal! <= 0 ? '' : stringsOf(context).merchantRecruitPageStep(row.nodeOrder!, row.nodeTotal!);
String merchantRecruitArrival(BuildContext context, UpcomingRun row) {
  final start = (row.arrivalStart ?? '').trim();
  final end = (row.arrivalEnd ?? '').trim();
  if (start.isEmpty || end.isEmpty) return '';
  String clock(String raw) {
    final i = raw.indexOf(':');
    return i < 2 ? raw : raw.substring(i - 2, i + 3);
  }
  return stringsOf(context).merchantRecruitPageArrival(clock(start), clock(end));
}
