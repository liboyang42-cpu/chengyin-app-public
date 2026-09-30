import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/network/session_data.dart';
import '../../core/network/request_session_scope.dart';
import '../../data/api/merchant_npc_api.dart';
import '../../data/models/merchant_npc.dart';

/// 门店 NPC 对话状态(按 merchantId 分 family,离页自动释放)。
///
/// ★★ **为什么不复用 `npcSessionProvider`:** 那个是漫游/局内轨,状态围绕
///   「活动会话 + SSE 流式 delta」构建,而门店轨是**一次 POST 一个完整回复**
///   (后端 PR #75 起 chat 不再是 SSE)。硬塞进去要给它加一堆恒空的流式字段,
///   两轨都会更难读。
class MerchantNpcChatState {
  const MerchantNpcChatState({
    this.messages = const <ChatMessage>[],
    this.sending = false,
  });

  final List<ChatMessage> messages;
  final bool sending;

  MerchantNpcChatState copyWith({
    List<ChatMessage>? messages,
    bool? sending,
  }) {
    return MerchantNpcChatState(
      messages: messages ?? this.messages,
      sending: sending ?? this.sending,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.text,
    required this.fromNpc,
    this.failed = false,
    this.isLocalFallback = false,
    this.isLocalRequestFailure = false,
    this.audioUrl,
  });

  final String text;
  final bool isLocalFallback;
  final bool isLocalRequestFailure;
  final bool fromNpc;

  /// 这条回复的合成语音。★ **null 是常态** ——
  /// 店主没克隆过声音、供应商未开通、合成失败都会是 null,那时只显示文字。
  final String? audioUrl;

  /// 这条是不是"没答上来"。★ 用来给气泡换个样子 ——
  /// 把失败提示画成正常回复,用户会以为那就是店主说的话。
  final bool failed;
}

final merchantNpcChatProvider = NotifierProvider.autoDispose
    .family<MerchantNpcChatController, MerchantNpcChatState, int>(
      MerchantNpcChatController.new,
    );

class MerchantNpcChatController extends Notifier<MerchantNpcChatState> {
  MerchantNpcChatController(this._merchantId);

  final int _merchantId;

  /// 当前这一问的 requestId。
  ///
  /// ★★ 重试必须**原样重发同一个 id** —— 后端按 (userId, requestId) 幂等。
  ///   换新 id 重试 = 一次全新的计费调用,而且上一条可能还在跑。
  String? _pendingRequestId;

  /// ★ 开场白**不进这里**:它是店铺主页已经拿到的展示文案,不是对话产物。
  /// 由面板作为固定首条气泡渲染 —— 放进 state 会让「重试」「历史」这些
  /// 操作要处处小心别把它当成一条真回复。
  @override
  MerchantNpcChatState build() {
    _pendingRequestId = null;
    _scope = null;
    final generation = ++_generation;
    ref.onDispose(() { _generation++; });
    try {
      final session = watchSessionDataScope(ref);
      _scope = RequestSessionScope(() => generation == _generation && session.isCurrent());
    } on SessionDataUnavailable { /* Guests cannot start private conversations. */ }
    return const MerchantNpcChatState();
  }

  int _generation = 0;
  RequestSessionScope? _scope;

  Future<void> send(String raw) async {
    final String message = raw.trim();
    if (message.isEmpty || state.sending || _scope?.isCurrent() != true) return;

    _pendingRequestId = newChatRequestId();
    state = state.copyWith(
      messages: <ChatMessage>[
        ...state.messages,
        ChatMessage(text: message, fromNpc: false),
      ],
      sending: true,
    );
    await _run(message);
  }

  /// 重试最后一次失败的提问。用同一个 requestId,不重复计费。
  Future<void> retry() async {
    if (state.sending || _pendingRequestId == null || _scope?.isCurrent() != true) return;
    final ChatMessage? lastAsk = _lastUserMessage;
    if (lastAsk == null) return;
    // 把上一条失败回复摘掉再重试,否则会堆两条"没答上来"。
    final List<ChatMessage> trimmed = state.messages.last.failed
        ? state.messages.sublist(0, state.messages.length - 1)
        : state.messages;
    state = state.copyWith(messages: trimmed, sending: true);
    await _run(lastAsk.text);
  }

  ChatMessage? get _lastUserMessage {
    for (final ChatMessage m in state.messages.reversed) {
      if (!m.fromNpc) return m;
    }
    return null;
  }

  Future<void> _run(String message) async {
    final scope = _scope!;
    final requestId = _pendingRequestId!;
    final api = ref.read(merchantNpcApiProvider);
    try {
      final NpcChatResult result = await RequestSessionScope.run(scope, () => api.chat(
            merchantId: _merchantId,
            message: message,
            requestId: requestId,
          ));
      if (!scope.isCurrent()) return;
      _append(
        // ★ 直接显示后端给的 safeText。它已过出参内容安全,
        //   客户端不再加工 —— 加工等于把审核结果改了。
        ChatMessage(
          text: result.displayText,
          isLocalFallback: (result.safeText ?? '').trim().isEmpty,
          fromNpc: true,
          failed: !result.succeeded,
          // ★ 只有成功的回复才带语音。被内容安全拦下时 safeText 是兜底话术,
          //   后端也不会给 audioUrl —— 那句不该用店主的声音念出来。
          audioUrl: result.succeeded ? result.audioUrl : null,
        ),
      );
      if (result.succeeded) _pendingRequestId = null;
    } catch (e) {
      if (!scope.isCurrent()) return;
      _append(
        ChatMessage(
          text: e.toString().replaceFirst('Exception: ', ''),
          isLocalRequestFailure: e is MerchantNpcException && e.isLocalFallback,
          fromNpc: true,
          failed: true,
        ),
      );
    }
  }

  void _append(ChatMessage m) {
    state = state.copyWith(
      messages: <ChatMessage>[...state.messages, m],
      sending: false,
    );
  }
}
