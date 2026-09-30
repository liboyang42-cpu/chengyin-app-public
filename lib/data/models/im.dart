// IM 会话 + 消息模型。对齐后端 `ImServiceImpl`:
// - 会话:`listConversations` 返回 `List<Map>`,每条含
//   {conversationId,type,lastMsgType,lastMsgText,lastMsgAt,unread,counterparty:{id,nickname,avatar}}。
// - 消息:`listMessages` 返回 {list:[ImMessage],nextCursor,hasMore};ImMessage 含
//   {id,conversationId,senderId,receiverId,msgType,content,extraJson,status,createTime}
//   + 群聊渲染瞬态字段 senderName/senderAvatar(`ImServiceImpl#listMessages` 明写
//   「群聊渲染:按 senderId 回填发送者昵称+头像」,非 @JsonIgnore,随 JSON 下发)。
// 时间字段(lastMsgAt/createTime)后端是 Date 序列化字符串,容错处理。

/// 会话类型。值必须对齐后端 `ImConversation` 常量 —— 那是唯一真源,后端按这些值建会话
/// (`sendSystem` 建 type=2、商家客服会话建 type=3),写错会把系统通知当成客服会话渲染。
/// 2026-07-17 修:此前 2/3 写反了(kImTypeMerchant=2、kImTypeSystem=3),与后端相反。
/// 当时两个常量只定义未使用,故未炸,是潜伏雷。
const int kImTypeSingle = 1;
const int kImTypeSystem = 2;
const int kImTypeMerchant = 3;
const int kImTypeGroup = 4;

/// 消息类型(对齐 ImMessage 常量)。
const int kMsgText = 1;
const int kMsgImage = 2;
const int kMsgCard = 3;

/// 会话列表里的对方信息。
class ImCounterparty {
  ImCounterparty({
    required this.id,
    required this.nickname,
    required this.avatar,
    this.bizKey = '',
  });

  final int id;
  final String nickname;
  final String avatar;
  final String bizKey;

  factory ImCounterparty.fromJson(Map<String, dynamic>? json) {
    final j = json ?? <String, dynamic>{};
    return ImCounterparty(
      id: (j['id'] as num?)?.toInt() ?? 0,
      nickname: (j['nickname'] as String?) ?? '',
      avatar: (j['avatar'] as String?) ?? '',
      bizKey: (j['bizKey'] as String?) ?? '',
    );
  }
}

/// 一条会话。
class Conversation {
  Conversation({
    required this.conversationId,
    required this.type,
    required this.counterparty,
    this.lastMsgType,
    this.lastMsgText,
    this.lastMsgAt,
    this.unread = 0,
    this.muted,
  });

  final int conversationId;
  final int type;
  final ImCounterparty counterparty;
  final int? lastMsgType;
  final String? lastMsgText;
  final String? lastMsgAt;
  final int unread;

  /// 免打扰状态。只接受服务端合同 0/1；缺失或畸形时保留 null，UI 不猜成“未静音”。
  final bool? muted;

  bool get isGroup => type == kImTypeGroup;

  /// 列表展示的最后消息摘要(图片/卡片显式占位)。
  String get preview {
    if (lastMsgText != null && lastMsgText!.isNotEmpty) return lastMsgText!;
    if (lastMsgType == kMsgImage) return '[图片]';
    if (lastMsgType == kMsgCard) return '[卡片]';
    return '';
  }

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    conversationId: (json['conversationId'] as num?)?.toInt() ?? 0,
    type: (json['type'] as num?)?.toInt() ?? kImTypeSingle,
    counterparty: ImCounterparty.fromJson(
      json['counterparty'] as Map<String, dynamic>?,
    ),
    lastMsgType: (json['lastMsgType'] as num?)?.toInt(),
    lastMsgText: json['lastMsgText'] as String?,
    lastMsgAt: json['lastMsgAt']?.toString(),
    unread: (json['unread'] as num?)?.toInt() ?? 0,
    muted: _parseMuted(json['muted']),
  );
}

bool? _parseMuted(Object? value) {
  if (value == 1 || value == '1') return true;
  if (value == 0 || value == '0') return false;
  return null;
}

/// 一条聊天消息。
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.msgType,
    this.content,
    this.extraJson,
    this.createTime,
    this.senderName,
    this.senderAvatar,
  });

  final int id;
  final int conversationId;
  final int senderId;
  final int msgType;
  final String? content;
  final String? extraJson;
  final String? createTime;

  /// 后端按 senderId 回填的发送者昵称/头像(`ImServiceImpl#listMessages`)。
  /// 系统消息(senderId=0)与查不到成员时为 null,由渲染侧回退会话级名字/头像。
  final String? senderName;
  final String? senderAvatar;

  bool get isText => msgType == kMsgText;
  bool get isImage => msgType == kMsgImage;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: (json['id'] as num?)?.toInt() ?? 0,
    conversationId: (json['conversationId'] as num?)?.toInt() ?? 0,
    senderId: (json['senderId'] as num?)?.toInt() ?? 0,
    msgType: (json['msgType'] as num?)?.toInt() ?? kMsgText,
    content: json['content'] as String?,
    extraJson: json['extraJson'] as String?,
    createTime: json['createTime']?.toString(),
    senderName: json['senderName'] as String?,
    senderAvatar: json['senderAvatar'] as String?,
  );
}

/// 消息分页结果。
class ChatPage {
  ChatPage({required this.list, this.nextCursor, this.hasMore = false});

  final List<ChatMessage> list;
  final int? nextCursor;
  final bool hasMore;

  factory ChatPage.fromJson(Map<String, dynamic> json) {
    final raw = (json['list'] as List<dynamic>?) ?? <dynamic>[];
    return ChatPage(
      list: raw
          .map((dynamic e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextCursor: (json['nextCursor'] as num?)?.toInt(),
      hasMore: (json['hasMore'] as bool?) ?? false,
    );
  }
}
