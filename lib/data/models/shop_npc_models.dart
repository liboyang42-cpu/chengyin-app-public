/// 店铺分身对话(自由探索屏④)的两个模型。
///
/// ⚠️ 与 `npc.dart` 是**两条轨**,别合并:那边是无形陪伴 V1 的途中 NPC
/// (`/api/ai/npc/chat`,底部 sheet),这边是**这一家店的分身**
/// (`/api/ai/npc/shop-chat`,全屏舞台)。接口、语义、版式都不同。
library;

/// 消息流里的一条。
///
/// ⚠️ 这是**本端自己攒**的对象(样机 `msgs.concat([{id, role, text}])`,
/// index.js:1355),后端没有任何端点返回这个形状 —— 所以它**没有 fromJson**,
/// 编一个出来只会是假 fixture。走 fromJson 的是下面的 [ShopNpcReply]。
class ShopNpcMessage {
  const ShopNpcMessage({
    required this.id,
    required this.mine,
    required this.text,
  });

  final int id;

  /// true = 我方(右侧胶囊) / false = 对方(裸正文 + 操作行)。
  final bool mine;

  final String text;

  /// 重答改写:**id 原样带过去**。
  ///
  /// ⚠️ 换 id 会让列表判成新节点,整条重新入场闪一下 —— 玩家点重答是想换个答案,
  /// 不是想看这条消息重演一遍(样机 index.js:1394 注释)。
  ShopNpcMessage copyWithText(String t) =>
      ShopNpcMessage(id: id, mine: mine, text: t);
}

/// 分身的一次回答。
class ShopNpcReply {
  const ShopNpcReply({required this.text, this.asr});

  /// 展示文本。后端 `safeText`(拒绝/失败时的安全兜底)与 `text`(正常回答)
  /// 走**同一字段位**,取法与样机 index.js:1367 同源。
  ///
  /// 拿不到任何一条时是**空串**,由调用方 `replyTextOr` 决定兜底文案 ——
  /// 口径只能有一份,不在这里编话。
  final String text;

  /// 仅语音链路:识别出的原话,要作为我方消息补进去
  /// (「玩家要能看见自己被听成了什么」)。
  final String? asr;

  /// [data] 是 AjaxResult 的 **data 节点**(`NpcChatResp`)。
  ///
  /// ⚠️ [asr] 单独传,因为后端把它 `put` 在 **AjaxResult 顶层**而不是 data 里
  /// (`ApiAiNpcController:296`)。顺手写 `data['asr']` 会永远拿到 null 且不报错。
  factory ShopNpcReply.fromJson(Map<String, dynamic> data, {String? asr}) {
    // ⚠️ 样机是 JS 的 `d.safeText || d.text` —— 空串要落到 text,
    //   用 `??` 的话空 safeText 会赢,页面上挂一条空回答。
    final String safe = (data['safeText'] as String?) ?? '';
    final String plain = (data['text'] as String?) ?? '';
    return ShopNpcReply(text: safe.isNotEmpty ? safe : plain, asr: asr);
  }
}
