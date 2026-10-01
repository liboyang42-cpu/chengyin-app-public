// IM 聊天页测试的共用替身。
//
// ★ 第二批一次加了 7 件事(系统卡 / 报名角标 / 四态 / 分页 / 轮询 / 清空 / 发送人名),
//   每个文件各抄一份 `_FakeImApi` 的话,接口签名一动就要改七处 ——
//   而漏改的那几处会**编译不过**,不是悄悄变绿,所以抄七份的代价是纯摩擦。

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/im_api.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/data/models/im.dart';
import 'package:chengyin_app/feature/im/im_chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// 一次 `messages` 调用的入参。
typedef MessagesCall = ({int cursorId, int size});

/// 可编程的 IM 假件:
/// - [onMessages] 为空时,任何一页都返回空列表(空会话);
/// - [calls] 记下每一次拉取的游标/页大小(分页与轮询的判据就是它);
/// - 其余方法只实现这轮用得到的(清空)。
class FakeImChatApi implements ImApi {
  FakeImChatApi({this.onMessages});

  Future<ChatPage> Function(int cursorId, int size)? onMessages;

  final List<MessagesCall> calls = <MessagesCall>[];
  final List<int> deleted = <int>[];
  final List<int> readCalls = <int>[];
  Future<void> Function(int conversationId)? onRead;

  /// 覆盖删除行为(默认成功);用来钉失败分支。
  Future<String> Function(int conversationId)? onDelete;

  @override
  Future<ChatPage> messages(
    int conversationId, {
    int cursorId = 0,
    int size = 30,
  }) {
    calls.add((cursorId: cursorId, size: size));
    final Future<ChatPage> Function(int, int)? handler = onMessages;
    if (handler == null) {
      return Future<ChatPage>.value(ChatPage(list: <ChatMessage>[]));
    }
    return handler(cursorId, size);
  }

  @override
  Future<void> read(int conversationId) async {
    readCalls.add(conversationId);
    await onRead?.call(conversationId);
  }

  @override
  Future<String> deleteConversation(int conversationId) async {
    deleted.add(conversationId);
    final Future<String> Function(int)? handler = onDelete;
    if (handler != null) return handler(conversationId);
    return '已删除会话';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 造一条消息。[extraJson] 给卡片用。
ChatMessage msg(
  int id, {
  int senderId = 2,
  int msgType = kMsgText,
  String? content,
  String? extraJson,
  String time = '2026-01-15 20:10:00',
  String? senderName,
  String? senderAvatar,
}) => ChatMessage(
  id: id,
  conversationId: 9,
  senderId: senderId,
  msgType: msgType,
  content: content,
  extraJson: extraJson,
  createTime: time,
  senderName: senderName,
  senderAvatar: senderAvatar,
);

/// 进聊天页(不挂路由):用于只关心页内渲染的用例。
Future<void> pumpChat(
  WidgetTester tester, {
  required ImApi api,
  int conversationId = 9,
  String peerName = '小李',
  String peerAvatar = '',
  int peerMemberId = 2,
  bool? liquidGlassSupported,
  List<dynamic> extra = const <dynamic>[],
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      // `<dynamic>[...].cast()` 是本仓现有测试的口径:riverpod 3 没有把
      // `Override` 导出到 flutter_riverpod.dart,写死类型编译不过。
      overrides: <dynamic>[
        imApiProvider.overrideWithValue(api),
        ...extra,
      ].cast(),
      child: MaterialApp(
        home: ImChatPage(
          conversationId: conversationId,
          peerName: peerName,
          peerAvatar: peerAvatar,
          peerMemberId: peerMemberId,
          liquidGlassSupported: liquidGlassSupported,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 进聊天页(**挂在 GoRouter 上**):需要 `context.pop()/go()` 的用例用它 ——
/// 「返回消息列表」这类出口在裸 MaterialApp 里没有路由可去。
Future<void> pumpChatRouted(
  WidgetTester tester, {
  required ImApi api,
  int conversationId = 9,
  List<RouteBase> extraRoutes = const <RouteBase>[],
  List<dynamic> extra = const <dynamic>[],
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final GoRouter router = GoRouter(
    initialLocation: '/im/chat/$conversationId',
    routes: <RouteBase>[
      GoRoute(
        path: '/im',
        builder: (_, _) => const Scaffold(body: Text('消息列表')),
      ),
      ...extraRoutes,
      GoRoute(
        path: '/im/chat/:conversationId',
        builder: (BuildContext context, GoRouterState state) => ImChatPage(
          conversationId:
              int.tryParse(state.pathParameters['conversationId'] ?? '') ?? 0,
          peerName: '小李',
          peerMemberId: 2,
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        imApiProvider.overrideWithValue(api),
        ...extra,
      ].cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

class _FixedAuth extends AuthController {
  _FixedAuth(this._state);

  final AuthState _state;

  @override
  AuthState build() => _state;
}

/// 把「我」钉成 [id]。
///
/// ★ 不钉的话 `currentMemberIdProvider` 是 0 —— 对方的消息(senderId 2)会和
///   「自己」判得一样近,左右/名字这类判据全失真。基准图那边踩过同一个坑。
dynamic meIsMember(int id) => authControllerProvider.overrideWith(
  () => _FixedAuth(
    AuthState(
      user: User(id: id, nickname: '我', avatar: '', role: 'player'),
      initialized: true,
    ),
  ),
);
