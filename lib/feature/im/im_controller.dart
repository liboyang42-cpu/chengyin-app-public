import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/models/im.dart';
import '../auth/auth_controller.dart';

/// 我的会话列表。进列表页 / 从聊天页返回时 invalidate 刷新未读与最后消息。
final imConversationsProvider = FutureProvider.autoDispose<List<Conversation>>((
  ref,
) {
  return ref.watch(imApiProvider).conversations();
});

/// 当前登录用户 id —— 聊天页判断「自己 / 对方」的依据(senderId == 当前 id)。
final currentMemberIdProvider = Provider<int>((ref) {
  return ref.watch(authControllerProvider).user?.id ?? 0;
});

/// 某会话最新一页消息(正序,旧→新)。发送后 invalidate 刷新。
final imMessagesProvider = FutureProvider.autoDispose.family<ChatPage, int>((
  ref,
  conversationId,
) {
  return ref.watch(imApiProvider).messages(conversationId);
});
