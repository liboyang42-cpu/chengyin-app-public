// 聊天里的卡片消息(msgType=3)。三类:
//
//   · location —— **用户可发**,字段全在 extra_json 里
//     (小程序 `onSendLocation` → `sendCard({cardType:'location', name, address, lat, lng})`)。
//   · route / signup —— 只有 topicId,展示字段接收方现拉(小程序 spec 决策 8);
//     signup 多一个「报名成功」标记条(wxml `.rcard-flag`)。
//   · generic —— **仅系统可发**:标题 / 副标题 / meta / 按钮 / 处理结果。
//
// ★ App 此前**能发不能收**:卡片会掉进「不认识的类型」兜底,渲成一行斜体
//   「[这条消息当前版本显示不了]」——自己发的自己都看不懂。第一轮补了
//   location/route,这一轮补 generic(占位气泡里最扎眼的一处)。
//
// ⚠️ 卡片里**只有 topicId**,展示字段现拉。查不到时**不能什么都不显示**:
//   一条对方明明发了的消息在我这儿消失,比显示「路线已下架」严重得多。
//
// 真源:`xcx-ref/subpackageB/pages/im/chat/index.wxml`(通用卡分支 92-113 行)
//      + `index.js` 的 `decorate`(老卡片无 cardType → 补 'generic',
//        且 generic 无 title 时用消息 content 兜底)。

import 'dart:convert';

import '../../core/map/map_launcher.dart';

/// 系统卡上的一个动作按钮 —— 对齐小程序 `card.buttons[]`
/// (`{text, action, key, type:'reject'}`)。
class ChatCardButton {
  const ChatCardButton({
    required this.text,
    this.action,
    this.key,
    this.isReject = false,
  });

  final String text;

  /// 以 `/` 开头 = 站内路径,点了跳转;否则提示「已处理」
  /// (小程序 `onCardBtn` 的同一条分支)。
  final String? action;

  /// 业务动作标识(暂时只做展示语义,后端按它分支)。
  final String? key;

  /// `type: 'reject'` —— 拒绝类动作,危险色(小程序 `.card-btn.reject`)。
  final bool isReject;
}

/// 系统卡的「处理结果」(审核回执)。字段与小程序 im/chat 的处理结果面板逐字一致。
class ChatCardResult {
  const ChatCardResult({
    this.taskId = '',
    this.bizId = '',
    this.outcome = '',
    this.reason = '',
    this.followUp = '',
  });

  final String taskId;
  final String bizId;
  final String outcome;
  final String reason;
  final String followUp;

  /// 五个字段全空 ⇒ 没有可展示的处理结果(空壳 result 不该长出一个按钮)。
  bool get isEmpty =>
      taskId.isEmpty &&
      bizId.isEmpty &&
      outcome.isEmpty &&
      reason.isEmpty &&
      followUp.isEmpty;
}

/// 解析出来的卡片载荷。除路线/系统卡(topicId、bcId、action)外,
/// 还带位置卡字段(name/address/lat/lng)与系统卡字段
/// (title/sub/meta/buttons/result)—— 无关字段为空值,调用方按 [type] 分流。
typedef ChatCardData = ({
  String type,
  int topicId,
  int? bcId,
  String? action,
  String name,
  String address,
  double? lat,
  double? lng,
  String title,
  String sub,
  String meta,
  List<ChatCardButton> buttons,
  ChatCardResult? result,
});

/// 解析卡片载荷。★ 解析不了返回 null,由调用方退回占位气泡 ——
/// 不抛:一条坏消息不该让整个会话崩掉。
///
/// [fallbackTitle] 是这条消息的 content —— 系统卡没有 title 时拿它兜底
/// (小程序 `decorate`:`if (card.cardType === 'generic' && !card.title)
/// card.title = m.content || '通知'`)。标题拿不到就只剩一个空壳卡片。
ChatCardData? parseChatCard(String? extraJson, {String? fallbackTitle}) {
  final String s = (extraJson ?? '').trim();
  if (s.isEmpty) return null;
  try {
    final Object? j = jsonDecode(s);
    if (j is! Map<String, dynamic>) return null;
    String type = (j['cardType'] ?? '').toString();
    // 老卡片**没有 cardType** —— 小程序 decorate 里补成 'generic' 走通用卡渲染
    // (`if (!card.cardType) card.cardType = 'generic'`)。缺字段不等于坏数据。
    if (type.isEmpty) type = 'generic';

    // ★ 官方通知卡片带 bcId(点击回流用)与 action(跳哪儿)。
    //   这两个是**可选**的:路线/位置卡片没有它们,不能因此判成解析失败。
    final Object? b = j['bcId'];
    final int? bcId = b is num
        ? b.toInt()
        : (b == null ? null : int.tryParse('$b'));
    final String? action = (j['action'] ?? '').toString().trim().isEmpty
        ? null
        : (j['action'] as Object).toString().trim();

    // 位置卡:名字与坐标全无 ⇒ 这张卡既显示不出什么、也导不了航,
    // 当解析失败,让调用方走占位(而不是渲一张空白卡)。
    if (type == 'location') {
      final String name = (j['name'] ?? '').toString().trim();
      final String address = (j['address'] ?? '').toString().trim();
      final double? lat = _toDouble(j['lat']);
      final double? lng = _toDouble(j['lng']);
      if (name.isEmpty && !hasCoordinates(lat, lng)) return null;
      return (
        type: type,
        topicId: 0,
        bcId: null,
        action: null,
        name: name,
        address: address,
        lat: lat,
        lng: lng,
        title: '',
        sub: '',
        meta: '',
        buttons: const <ChatCardButton>[],
        result: null,
      );
    }

    // 路线卡 / 报名卡同构:都只有 topicId,都现拉。
    if (type == 'route' || type == 'signup') {
      final Object? raw = j['topicId'];
      final int id = raw is num
          ? raw.toInt()
          : int.tryParse('${raw ?? ''}') ?? 0;
      // ★ topicId 无效时整条当解析失败 —— 渲一张点进去 404 的卡片
      //   比渲占位更糟:用户会以为是自己网络问题。
      if (id <= 0 && action == null) return null;
      return (
        type: type,
        topicId: id,
        bcId: bcId,
        action: action,
        name: '',
        address: '',
        lat: null,
        lng: null,
        title: '',
        sub: '',
        meta: '',
        buttons: const <ChatCardButton>[],
        result: null,
      );
    }

    // 其余一律按系统卡渲 —— 小程序 wxml 里非 location/route/signup 的
    // msgType==3 走的正是通用卡布局;decorate 还给没有 cardType 的老卡片
    // 补了 'generic'。
    final String sub = (j['sub'] ?? '').toString().trim();
    final String meta = (j['meta'] ?? '').toString().trim();
    final List<ChatCardButton> buttons = _parseButtons(j['buttons']);
    final ChatCardResult? result = _parseResult(j['result']);
    final String rawTitle = (j['title'] ?? '').toString().trim();
    final String fallback = (fallbackTitle ?? '').trim();
    // 一个字段都渲染不出来的卡片(既没有文案也没有动作)⇒ 当解析失败,
    // 退回占位气泡 —— 渲一张只有底色的空壳,看着像渲染坏了。
    if (rawTitle.isEmpty &&
        sub.isEmpty &&
        meta.isEmpty &&
        action == null &&
        buttons.isEmpty &&
        (result == null || result.isEmpty) &&
        fallback.isEmpty) {
      return null;
    }
    // 标题兜底:卡片自己的 title → 这条消息的 content → 「通知」
    // (小程序 decorate:`card.title = m.content || '通知'`)。
    final String title = rawTitle.isNotEmpty
        ? rawTitle
        : (fallback.isNotEmpty ? fallback : '通知');

    return (
      type: 'generic',
      topicId: 0,
      bcId: bcId,
      action: action,
      name: '',
      address: '',
      lat: null,
      lng: null,
      title: title,
      sub: sub,
      meta: meta,
      buttons: buttons,
      result: result,
    );
  } catch (_) {
    return null;
  }
}

List<ChatCardButton> _parseButtons(Object? raw) {
  if (raw is! List) return const <ChatCardButton>[];
  final List<ChatCardButton> out = <ChatCardButton>[];
  for (final Object? e in raw) {
    if (e is! Map) continue;
    final String text = (e['text'] ?? '').toString().trim();
    // 没有文字的按钮渲不出来,跳过而不是渲一个空块。
    if (text.isEmpty) continue;
    final String action = (e['action'] ?? '').toString().trim();
    final String key = (e['key'] ?? '').toString().trim();
    out.add(
      ChatCardButton(
        text: text,
        action: action.isEmpty ? null : action,
        key: key.isEmpty ? null : key,
        isReject: (e['type'] ?? '').toString() == 'reject',
      ),
    );
  }
  return out;
}

ChatCardResult? _parseResult(Object? raw) {
  if (raw is! Map) return null;
  String text(Object? v) => (v ?? '').toString().trim();
  final ChatCardResult result = ChatCardResult(
    taskId: text(raw['taskId']),
    bizId: text(raw['bizId']),
    outcome: text(raw['outcome']),
    reason: text(raw['reason']),
    followUp: text(raw['followUp']),
  );
  return result.isEmpty ? null : result;
}

/// 位置卡的 extra_json。★ 与小程序
/// `sendCard({cardType:'location', name, address, lat, lng})` 逐字同形 ——
/// 两端要能互相解析,字段名不能各写各的
/// (小程序真源:`subpackageB/pages/im/chat/index.js` 的 onSendLocation)。
String locationCardJson({
  required String name,
  required String address,
  required double lat,
  required double lng,
}) => jsonEncode(<String, dynamic>{
  'cardType': 'location',
  'name': name,
  'address': address,
  'lat': lat,
  'lng': lng,
});

double? _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

/// 卡片标题拿不到时显示什么。
///
/// ★ 不显示「加载中…」也不显示空白 —— 用**卡片类型 + 编号**兜,
///   至少让人知道「这是一条路线」并且点得进去。
///   活动(signup)与路线(route)是两种东西,降级文案也跟着分:小程序那边
///   分别是「该活动已下架」「该路线已下架」。
String chatCardFallbackTitle({required String type, required int topicId}) =>
    switch (type) {
      'route' => '路线 #$topicId',
      'signup' => '活动 #$topicId',
      _ => '内容 #$topicId',
    };
