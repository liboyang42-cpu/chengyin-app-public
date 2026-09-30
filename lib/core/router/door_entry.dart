import '../../data/models/scan_entry.dart';

/// 门口码冷启动落地的纯判定逻辑。
/// 真源:`utils/game-door-entry.js`(parseDoorScene / pathForScanEntry)
/// 与 `pages/index/index.js`(readInviterId / handleInviter)。

final RegExp _doorSceneCode = RegExp(r'^[0-9a-fA-F]{32}$');

/// 小程序码 scene 必须解出 32 位 hex,且归一为小写;其余一律当没有码。
String? parseDoorScene(Object? raw) {
  if (raw == null) return null;
  String value = raw.toString();
  try {
    value = Uri.decodeComponent(value);
  } catch (_) {
    // 已经是解码后的原文,维持原样。
  }
  value = value.trim();
  if (!_doorSceneCode.hasMatch(value)) return null;
  return value.toLowerCase();
}

/// `pathForScanEntry` 的 App 路由版:`action==='play'` 进游玩(带 activityId
/// 是场次局,没有则是主题自玩),其余一律去主题购买页。缺 topicId 判不了路。
String? doorEntryRouteFor(ScanEntryResult? data) {
  final int? topicId = data?.topicId;
  if (topicId == null) return null;
  if (data!.action == 'play') {
    final int? activityId = data.activityId;
    return activityId != null
        ? '/play/$activityId?topicId=$topicId'
        : '/play/0?topicId=$topicId';
  }
  return '/topic/$topicId';
}

/// 分享 path 里的邀请人:小程序 `options.inviter || options.id`。
String readInviterId(Map<String, String> query) =>
    query['inviter'] ?? query['id'] ?? '';

/// `handleInviter` 的三闸:登录后、没绑过、不是自己才发。
/// 自己点自己的卡片要靠字符串归一比较(分享里是字符串,会话里是数字)。
bool shouldBindInviter({
  required String inviterId,
  required int? currentUserId,
  required bool hasInviter,
}) =>
    currentUserId != null &&
    inviterId.isNotEmpty &&
    !hasInviter &&
    inviterId != '$currentUserId';
