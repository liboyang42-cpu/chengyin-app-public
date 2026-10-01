import 'package:flutter/widgets.dart';
import '../../l10n/strings.dart';

/// Local picker options only. Saved server/UGC tags bypass this mapping.
String merchantStoreTagOption(BuildContext context, String wireTag) => switch (wireTag) {
  '空间' => stringsOf(context).merchantStoreTagSpace,
  '体验' => stringsOf(context).merchantStoreTagExperience,
  '人群' => stringsOf(context).merchantStoreTagAudience,
  '老街' => stringsOf(context).merchantStoreTagOldStreet,
  '天台' => stringsOf(context).merchantStoreTagRooftop,
  '独立空间' => stringsOf(context).merchantStoreTagIndependentSpace,
  '宠物友好' => stringsOf(context).merchantStoreTagPetFriendly,
  '夜间开放' => stringsOf(context).merchantStoreTagNight,
  '适合拍照' => stringsOf(context).merchantStoreTagPhotography,
  '适合单人' => stringsOf(context).merchantStoreTagSolo,
  '适合情侣' => stringsOf(context).merchantStoreTagCouples,
  '适合亲子' => stringsOf(context).merchantStoreTagFamily,
  '适合组队' => stringsOf(context).merchantStoreTagGroups,
  '雨天可去' => stringsOf(context).merchantStoreTagRain,
  '安静' => stringsOf(context).merchantStoreTagQuiet,
  '学生党' => stringsOf(context).merchantStoreTagStudents,
  '上班族' => stringsOf(context).merchantStoreTagWorkers,
  '摄影爱好者' => stringsOf(context).merchantStoreTagPhotographers,
  '美食探店' => stringsOf(context).merchantStoreTagFood,
  '亲子家庭' => stringsOf(context).merchantStoreTagFamilies,
  '潮流青年' => stringsOf(context).merchantStoreTagYouth,
  _ => wireTag,
};
