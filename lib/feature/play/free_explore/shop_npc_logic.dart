// 店铺分身对话(屏④)的纯逻辑。**不碰 widget** —— 这三件事全都「看着对、其实错」,
// 而且错法都不报错:取问取错 → 分身答非所问;兜底编话 → 玩家一直重试;
// 问候顶掉作者的话 → 商家白配。必须能脱离 widget 树断言。
// 语义逐条照搬小程序 pages/play/index.js:1192-1206 / 1352-1440。

import '../../../data/models/shop_npc_models.dart';

/// 等待名条第二拍的间隔:「{名} 正在输入…」→「正在回答」(样机 `_startThinkBeat`)。
///
/// 一句话不动地挂着,超过一秒就像卡住了;换一拍是在说「还在,只是慢」。
const Duration kThinkPhaseDelay = Duration(milliseconds: 1200);

/// 兜底文案的**最后一档**:服务端也没话可说时才用。
const String kShopNpcFallback = '这个我说不好，你到店里当面问我一次。';

/// 重答:从 [index] 往前找最近的我方提问。找不到返回 null(调用方据此**不发请求**)。
///
/// 两条**明确不做**(样机 `retryNpcMsg` 注释):
/// - 不写回输入框 —— 会覆盖玩家正在打的字;
/// - 不追加一条新回答 —— 同一个问题挂两个答案,读起来像分身自言自语说了两遍。
String? retryQuestionFor(List<ShopNpcMessage> msgs, int index) {
  for (int i = (index < msgs.length ? index : msgs.length) - 1; i >= 0; i--) {
    if (msgs[i].mine) return msgs[i].text;
  }
  return null;
}

/// 兜底文案的**唯一口径**(样机 index.js:1376):回答 → 服务端原话 → 兜底句。
///
/// ⚠️ 接口被闸掉(店铺分身对话默认关)或没配人设时,**不要编一句「我有点忙」**——
/// 那是假话,玩家会一直重试。把服务端说的原话端出来。
///
/// [reply] 是 `ShopNpcReply.text`,[serverMsg] 是 `ShopNpcException.message`。
/// 空串与 null 同义(样机是 JS 的 `||`)——端一句空话跟没端一样。
String replyTextOr(String reply, String? serverMsg) {
  if (reply.isNotEmpty) return reply;
  if (serverMsg != null && serverMsg.isNotEmpty) return serverMsg;
  return kShopNpcFallback;
}

/// 重答失败时的**轻提示**(样机 index.js:1373 原句)。
///
/// ★ 口径②:重答失败**不能覆盖原文** —— 失败走这一句 toast,不进消息流。
/// 后端说了话就端后端的,这句只是它没话时的兜底。
const String kShopNpcRetryFailed = '没问成，原来那条还在';

/// 请求根本没送出去(dio 抛异常)时,分身那条位置上写什么。
///
/// ⚠️ **不能拿 [kShopNpcFallback] 顶这一档**:那句是「替分身回答」,而这里是
/// 「问题从来没送到」—— 分工与下面语音那条 [kVoiceNotHeard] 同源。混用会让玩家
/// 以为分身答不上来,于是换个问题问,而其实一句都没发出去。
///
/// ⚠️ 样机这条链路的 `.then()` **没有 `.catch()`**,网络失败静默无反应。
/// 那是样机的缺陷不是设计意图,不照抄(控制者裁决 2026-09-10)。
const String kShopNpcNetFailed = '没问成，网络不太好，再问一次试试';

/// 开场问候:作者配了用作者的,否则按时段合成(样机 `openShopNpc`,index.js:1194-1201)。
///
/// ⚠️ 用**设备本地时间**([now] 由调用方传 `DateTime.now()`),与「有效期按中国日历」
/// 不同源 —— 玩家人就在店里,本地时间是对的。
///
/// ⚠️ 作者写过的话不许被模板顶掉;只有 trim 后为空才算没配。
String greetingFor({
  String? authored,
  required String npcName,
  String? shopName,
  required DateTime now,
}) {
  final String own = (authored ?? '').trim();
  if (own.isNotEmpty) return own;

  final int h = now.hour;
  final String hi = h < 6
      ? '凌晨好'
      : h < 11
      ? '早上好'
      : h < 13
      ? '中午好'
      : h < 18
      ? '下午好'
      : '晚上好';
  final String shop = (shopName ?? '').trim();
  return '$hi，我是$npcName，欢迎来到${shop.isNotEmpty ? shop : '我们店铺'}';
}

// ─── 语音链路的口径(样机 index.js:1295-1347)────────────────────────────────
//
// 这几句和上面打字那条**不是一份**:语音多两种败法(没权限、没听清),
// 而且失败时端的话不一样 —— 打字失败端「这个我说不好」是在替分身回答,
// 语音失败端「没听清,再说一次」是在说这一次没收到,让玩家重说。混用会让玩家
// 以为分身答不上来,于是换个问题问,而其实问题从来没送到。

/// 不到这个时长不算一句话 —— 手指蹭到麦克风就发一次,这条链路是**要花钱的写操作**。
const Duration kVoiceMinClip = Duration(milliseconds: 500);

/// 一段录音的上限(样机 `duration:60000`)。到点自己停,不等玩家松手。
///
/// ⚠️ 这不只是体验:后端 `VOICE_MAX_BYTES` 是 2MB,而计费按转写时长走 ——
/// 没有这道闸,一根卡住的手指就是一段没人要的长录音,钱照花。
const Duration kVoiceMaxClip = Duration(seconds: 60);

/// 没有录音权限时端的话(样机原句)。**不许静默** ——
/// 按了没反应,玩家只会一直按。
const String kVoiceNoPermission = '没有录音权限，先在设置里打开';

/// 录音器自己出错(样机 `rec.onError`)。
///
/// ⚠️ 与「太短」分开:太短是误触,**静默丢掉**;出错要说,否则玩家不知道白说了一段。
const String kVoiceRecordFailed = '录音出错了';

/// 语音这一路的最后一档兜底(样机 `r.msg || '没听清，再说一次'`)。
const String kVoiceNotHeard = '没听清，再说一次';

/// ASR 没回话时,我方那条消息写什么(样机 `d.asr || '（语音）'`)。
const String kVoiceMineFallback = '（语音）';

/// 太短 ⇒ 不算一句话,连请求都不发。
bool voiceClipTooShort(Duration held) => held < kVoiceMinClip;

/// 我方消息的正文:识别出的原话,识别不出写「（语音）」。
///
/// ⚠️ 「玩家要能看见自己被听成了什么」—— 分身答非所问时,玩家得能分清
/// 是它没听懂还是它在胡说。所以这条**先于回答**补进消息流。
///
/// ⚠️ 样机是 JS 的 `||`:空串也要回落。用 `??` 的话会挂一条空的我方消息。
String asrMineText(String? asr) =>
    (asr == null || asr.isEmpty) ? kVoiceMineFallback : asr;

/// 语音失败时端什么话:服务端原话优先(闸关时它说的是「店铺分身对话还没开放」,
/// ASR 没接时说的是「语音识别还没接入,先打字问我」——两句都比我编的准)。
///
/// ⚠️ 端出来的是**分身的一条回答**,不是 toast(样机 `_pushShopNpcReply(r.msg || …)`)。
String voiceErrorText(String? serverMsg) =>
    (serverMsg == null || serverMsg.isEmpty) ? kVoiceNotHeard : serverMsg;
