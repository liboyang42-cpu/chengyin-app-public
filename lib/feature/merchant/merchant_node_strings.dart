import 'package:flutter/widgets.dart';
import '../../l10n/strings.dart';
import '../../data/models/merchant_city_node.dart';

/// Only explicit local model labels and validation messages belong here.
String merchantNodeLocalText(BuildContext context, String text) => switch (text) {
  '写实' => stringsOf(context).merchantNodeRealistic,
  '卡通' => stringsOf(context).merchantNodeCartoon,
  '像素' => stringsOf(context).merchantNodePixel,
  '请给形象起个名字' => stringsOf(context).merchantNodeNameMissing,
  '名字不超过 20 字' => stringsOf(context).merchantNodeNameTooLong,
  '请上传形象头像' => stringsOf(context).merchantNodeAvatarMissing,
  '招呼语不超过 60 字' => stringsOf(context).merchantNodeGreetingTooLong,
  '请填写形象的说话风格(人设)' => stringsOf(context).merchantNodePersonalityMissing,
  '人设不超过 1000 字' => stringsOf(context).merchantNodePersonalityTooLong,
  '店铺知识不超过 2000 字' => stringsOf(context).merchantNodeKnowledgeTooLong,
  '未配置(可选)' => stringsOf(context).merchantNodeVoiceOptional,
  '声音生成中…(稍后自动刷新)' => stringsOf(context).merchantNodeVoiceGenerating,
  '声音已就绪' => stringsOf(context).merchantNodeVoiceReady,
  '上次生成失败,可以重新生成' => stringsOf(context).merchantNodeVoiceFailed,
  '声音状态未知' => stringsOf(context).merchantNodeVoiceUnknown,
  '请填写角色名字' => stringsOf(context).merchantNodeRoleNameMissing,
  '请先选一张形象照片' => stringsOf(context).merchantNodeRolePhotoMissing,
  '请填写标题' => stringsOf(context).merchantNodeTitleRequired,
  '请选择玩家怎么算完成' => stringsOf(context).merchantNodeMethodRequired,
  '文字作答要填答案' => stringsOf(context).merchantNodePassphraseRequired,
  '选项问答要填题目' => stringsOf(context).merchantNodeQuestionRequired,
  '选项问答至少要两个选项' => stringsOf(context).merchantNodeTwoOptions,
  '请把正确答案指到一个填了内容的选项上' => stringsOf(context).merchantNodeFilledAnswer,
  '文字作答' => stringsOf(context).merchantNodeTextMethod,
  '拍照打卡' => stringsOf(context).merchantNodePhotoMethod,
  '选项问答' => stringsOf(context).merchantNodeQuizMethod,
  '到店扫码' => stringsOf(context).merchantNodeScanMethod,
  'GPS 到达' => stringsOf(context).merchantNodeGpsMethod,
  '玩家到店后输入你给的暗号' => stringsOf(context).merchantNodeTextMethodHint,
  '玩家拍一张现场照片' => stringsOf(context).merchantNodePhotoMethodHint,
  '玩家从选项里选一个' => stringsOf(context).merchantNodeQuizMethodHint,
  '玩家扫你店里贴的那张码' => stringsOf(context).merchantNodeScanMethodHint,
  '玩家走进范围内自动完成' => stringsOf(context).merchantNodeGpsMethodHint,
  _ => text,
};

String merchantNodeApplicationStatus(BuildContext context, CityNodeApplication application) {
  if (application.status == 1) return stringsOf(context).merchantNodeApproved;
  if (application.status == 2) {
    final reason = application.rejectReason;
    return reason != null && reason.isNotEmpty
        ? stringsOf(context).merchantNodeRejectedReason(reason)
        : stringsOf(context).merchantNodeRejected;
  }
  return stringsOf(context).merchantNodeReviewing;
}

String merchantNodeName(BuildContext context, CityNode node) => node.hasNameFallback
    ? stringsOf(context).merchantNodeUnnamed : node.name;
String merchantNodeApplicationName(BuildContext context, CityNodeApplication application) =>
    application.hasNameFallback ? stringsOf(context).merchantNodeUnnamedPlace : application.poiName;
