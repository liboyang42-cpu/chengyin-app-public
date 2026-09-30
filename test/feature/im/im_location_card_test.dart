// 位置消息(IM-1):收到的位置卡要能看、能导航;发出的位置卡与小程序的
// `sendCard({cardType:'location', name, address, lat, lng})` 同字段。
//
// ★ 用户明确要求「消息要比小程序更丰富」,但位置卡不是"更丰富",
//   而是小程序**有**、App 此前**收不到也发不出**的那一类:
//   收到的掉进「[这条消息当前版本显示不了]」,发送侧根本没有入口。

import 'dart:convert';

import 'package:chengyin_app/core/map/map_launcher.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/im_api.dart';
import 'package:chengyin_app/data/models/im.dart';
import 'package:chengyin_app/feature/im/chat_card.dart';
import 'package:chengyin_app/feature/im/im_chat_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeImApi implements ImApi {
  _FakeImApi({ChatPage? page}) : page = page ?? ChatPage(list: <ChatMessage>[]);

  final ChatPage page;

  /// 记下每一次 send 的原始参数 —— 断言"发出去的到底是什么"。
  final List<({String content, int msgType, String? extraJson})> sent = [];

  @override
  Future<ChatPage> messages(int conversationId,
          {int cursorId = 0, int size = 30}) async =>
      page;

  @override
  Future<void> read(int conversationId) async {}

  @override
  Future<ChatMessage> send(int conversationId,
      {required String content, int msgType = kMsgText, String? extraJson}) async {
    sent.add((content: content, msgType: msgType, extraJson: extraJson));
    return ChatMessage(
      id: 100 + sent.length,
      conversationId: conversationId,
      senderId: 1,
      msgType: msgType,
      content: content,
      extraJson: extraJson,
      createTime: '2026-01-15 20:20:00',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ChatMessage _locationMsg({
  int senderId = 2,
  String name = '静安公园',
  String address = '愚园路 100 号',
  num lat = 31.223,
  num lng = 121.445,
}) => ChatMessage(
  id: 1,
  conversationId: 9,
  senderId: senderId,
  msgType: kMsgCard,
  content: '[卡片]',
  extraJson: jsonEncode(<String, dynamic>{
    'cardType': 'location',
    'name': name,
    'address': address,
    'lat': lat,
    'lng': lng,
  }),
  createTime: '2026-01-15 20:10:00',
);

Future<void> _pumpChat(
  WidgetTester tester,
  _FakeImApi api, {
  ImMapLauncher? launcher,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        imApiProvider.overrideWithValue(api),
        if (launcher != null)
          imMapLauncherProvider.overrideWithValue(launcher),
      ].cast(),
      child: const MaterialApp(
        home: ImChatPage(conversationId: 9, peerName: '小李', peerMemberId: 2),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 带 `/publish/poi` 桩的选点路由 —— 桩页点一下就 pop 一个选点结果。
Future<void> _pumpChatWithPoiStub(WidgetTester tester, _FakeImApi api) async {
  await tester.binding.setSurfaceSize(const Size(390, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) => const ImChatPage(
          conversationId: 9,
          peerName: '小李',
          peerMemberId: 2,
        ),
      ),
      GoRoute(
        path: '/publish/poi',
        builder: (BuildContext context, _) => CupertinoPageScaffold(
          child: Center(
            child: CupertinoButton(
              onPressed: () => context.pop<
                ({String name, double latitude, double longitude})
              >((name: '静安公园', latitude: 31.223, longitude: 121.445)),
              child: const Text('stub-pick'),
            ),
          ),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[imApiProvider.overrideWithValue(api)].cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('★★ 位置卡 JSON 与小程序 sendCard 逐字同形 —— 两端要能互相解析', () {
    final Map<String, dynamic> j =
        jsonDecode(
              locationCardJson(
                name: '静安公园',
                address: '愚园路 100 号',
                lat: 31.223,
                lng: 121.445,
              ),
            )
            as Map<String, dynamic>;
    expect(j, <String, dynamic>{
      'cardType': 'location',
      'name': '静安公园',
      'address': '愚园路 100 号',
      'lat': 31.223,
      'lng': 121.445,
    });
  });

  testWidgets('★ 收到的位置卡:地点名 + 地址 + 导航过去,可点开地图', (WidgetTester tester) async {
    final _FakeImApi api = _FakeImApi(
      page: ChatPage(list: <ChatMessage>[_locationMsg()]),
    );
    ({double? lat, double? lng, String name, String? address})? called;
    await _pumpChat(
      tester,
      api,
      launcher:
          ({
            required double? lat,
            required double? lng,
            required String name,
            String? address,
            required bool isIOS,
          }) async {
            called = (lat: lat, lng: lng, name: name, address: address);
            return MapLaunchResult.opened;
          },
    );

    expect(find.text('静安公园'), findsOneWidget);
    expect(find.text('愚园路 100 号'), findsOneWidget);
    expect(find.text('导航过去'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('导航到静安公园'));
    await tester.pumpAndSettle();

    expect(called?.name, '静安公园');
    expect(called?.address, '愚园路 100 号');
    expect(called?.lat, 31.223);
    expect(called?.lng, 121.445);
  });

  testWidgets('★ 地址为空就不渲那一行(不摆空行)', (WidgetTester tester) async {
    final _FakeImApi api = _FakeImApi(
      page: ChatPage(list: <ChatMessage>[_locationMsg(address: '')]),
    );
    await _pumpChat(tester, api);
    expect(find.text('静安公园'), findsOneWidget);
    expect(find.text('导航过去'), findsOneWidget);
  });

  testWidgets('★ 没有坐标:点导航说清"导航不了",不是静默失败', (WidgetTester tester) async {
    final _FakeImApi api = _FakeImApi(
      page: ChatPage(
        list: <ChatMessage>[_locationMsg(name: '集合点', address: '', lat: 0, lng: 0)],
      ),
    );
    await _pumpChat(
      tester,
      api,
      launcher:
          ({
            required double? lat,
            required double? lng,
            required String name,
            String? address,
            required bool isIOS,
          }) async => MapLaunchResult.noCoordinates,
    );

    await tester.tap(find.bySemanticsLabel('导航到集合点'));
    await tester.pumpAndSettle();

    expect(
      find.text(mapLaunchMessage(MapLaunchResult.noCoordinates)),
      findsOneWidget,
      reason: '重试也没用的失败,要给一句解释,而不是一个没反应的按钮',
    );
  });

  testWidgets('★★ 「+」→ 位置:选点页选完 → 位置卡原样发出', (WidgetTester tester) async {
    final _FakeImApi api = _FakeImApi();
    await _pumpChatWithPoiStub(tester, api);

    await tester.tap(find.bySemanticsLabel('添加图片、位置或路线'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('位置'));
    await tester.pumpAndSettle();
    expect(find.text('stub-pick'), findsOneWidget, reason: '应打开 /publish/poi');

    await tester.tap(find.text('stub-pick'));
    await tester.pumpAndSettle();

    expect(api.sent, hasLength(1));
    final sent = api.sent.single;
    expect(sent.msgType, kMsgCard, reason: '位置是卡片消息(msg_type=3)');
    expect(sent.content, '[位置]', reason: 'content 是降级文案,不是空');
    expect(jsonDecode(sent.extraJson!) as Map<String, dynamic>, <String, dynamic>{
      'cardType': 'location',
      'name': '静安公园',
      // ⚠️ 选点页只回 name/lat/lng —— 地址只能是空串,不拿名字冒充。
      'address': '',
      'lat': 31.223,
      'lng': 121.445,
    });
  });
}
