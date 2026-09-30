// 对方消息上的发送人名。
//
// 真源:`xcx-ref/subpackageB/pages/im/chat/index.wxml` 74 行 ——
//   `.sender-name` = `{{item.displayName}}{{ ' · ' }}{{item.timeDivider}}`,
//   自己一侧是 `.msg-time`(只有时间)。
//   `index.js` 的 decorate:`displayName = that.data.name`(会话对方名;
//   小程序不露出群聊,所以不是逐条 senderName)。
//
// ★ 此前 App 两侧都只有一条居中时间分隔:一屏里谁说的话要靠左右分列的
//   位置自己判断 —— 对方两条消息连着来时,连"这是同一个人说的"都看不出来。

import 'package:chengyin_app/core/theme/cy_palette.dart';
import 'package:chengyin_app/data/models/im.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'im_chat_test_support.dart';
import 'package:chengyin_app/feature/im/im_time.dart';

String _at(DateTime base, int minutes) {
  final DateTime d = base.add(Duration(minutes: minutes));
  String p(int n) => n < 10 ? '0$n' : '$n';
  return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}:00';
}

void main() {
  final DateTime base = DateTime.now().subtract(const Duration(hours: 2));
  final String t1 = _at(base, 0); // 对方
  final String t2 = _at(base, 10); // 我(与上一条差 10 分钟 → 自己那行只显示时间)
  final String t3 = _at(base, 12); // 对方(与上一条差 2 分钟 → 只显示名字)

  // F1 根因的一半在后端契约层:两字段随 JSON 下发(`ImMessage` 非 @JsonIgnore),
  // 但 `ChatMessage.fromJson` 此前只取 7 个字段,把它们丢了。
  test('fromJson 保留后端回填的 senderName/senderAvatar', () {
    final ChatMessage m = ChatMessage.fromJson(<String, dynamic>{
      'id': 1,
      'conversationId': 9,
      'senderId': 21,
      'msgType': kMsgText,
      'content': '我到集合点了',
      'senderName': '阿伟',
      'senderAvatar': 'https://example.invalid/awei.png',
    });
    expect(m.senderName, '阿伟');
    expect(m.senderAvatar, 'https://example.invalid/awei.png');
    // 系统消息(senderId=0)后端不回填 → 缺失即 null,不许凭空造出名字。
    final ChatMessage sys = ChatMessage.fromJson(<String, dynamic>{
      'id': 2,
      'conversationId': 9,
      'senderId': 0,
      'msgType': kMsgText,
      'content': '公告',
    });
    expect(sys.senderName, isNull);
    expect(sys.senderAvatar, isNull);
  });

  Future<void> pump(WidgetTester tester) async {
    final FakeImChatApi api = FakeImChatApi();
    api.onMessages = (_, _) async => ChatPage(
      list: <ChatMessage>[
        msg(1, senderId: 2, content: '周六见', time: t1),
        msg(2, senderId: 1, content: '好,我带水', time: t2),
        msg(3, senderId: 2, content: '集合点发你了', time: t3),
      ],
    );
    await pumpChat(tester, api: api, extra: <dynamic>[meIsMember(1)]);
  }

  // 导航栏标题也是对方名字,断言必须圈进消息列表,否则 `find.text('小李')`
  // 会连标题一起数进去(踩过)。
  Finder inList(String text) =>
      find.descendant(of: find.byType(ListView), matching: find.text(text));

  testWidgets('对方每条消息上方是「名字 · 时间」,间隔够才带时间', (tester) async {
    await pump(tester);

    expect(
      inList('小李 · ${fmtMessageTime(t1)}'),
      findsOneWidget,
      reason: '第一条对方消息:名字 + 时间',
    );
    expect(inList('小李'), findsOneWidget, reason: '紧跟着的对方消息只显示名字(时间不重复出现)');
    expect(
      find.text('小李 · ${fmtMessageTime(t3)}'),
      findsNothing,
      reason: '时间只在间隔 ≥5 分钟时追加,不是每条都挂',
    );
  });

  testWidgets('负控:自己发的消息不带对方名字,只有时间', (tester) async {
    await pump(tester);

    expect(find.text('好,我带水'), findsOneWidget);
    expect(
      inList(fmtMessageTime(t2)),
      findsOneWidget,
      reason: '自己一侧是 .msg-time:只有时间',
    );
    expect(
      find.text('小李 · ${fmtMessageTime(t2)}'),
      findsNothing,
      reason: '自己的气泡上挂对方名字 = 张冠李戴',
    );
  });

  testWidgets('连续多图分组也带名字', (tester) async {
    final FakeImChatApi api = FakeImChatApi();
    api.onMessages = (_, _) async => ChatPage(
      list: <ChatMessage>[
        msg(
          1,
          senderId: 2,
          msgType: kMsgImage,
          content: 'https://example.invalid/a.png',
          time: t1,
        ),
        msg(
          2,
          senderId: 2,
          msgType: kMsgImage,
          content: 'https://example.invalid/b.png',
          time: _at(base, 1),
        ),
      ],
    );
    await pumpChat(tester, api: api, extra: <dynamic>[meIsMember(1)]);

    expect(find.text('小李 · ${fmtMessageTime(t1)}'), findsOneWidget);
  });

  // F1·P1(b1-sim-im-2):后端 `ImServiceImpl#listMessages` 群聊按 senderId
  // 回填 senderName/senderAvatar,此前 `ChatMessage.fromJson` 把两字段丢了,
  // 气泡头写死入口传的群名 —— 群里三个人发言渲染成同一个人。
  testWidgets('群聊气泡头显发送者昵称,不是群名;缺回填才回退群名', (tester) async {
    final String g1 = _at(base, 0); // 阿伟(带时间)
    final String g2 = _at(base, 2); // 小花(距 2 分钟,只挂名字)
    final String g3 = _at(base, 12); // 我(只挂时间)
    final String g4 = _at(base, 30); // 系统(无回填 → 回退群名)
    final FakeImChatApi api = FakeImChatApi();
    api.onMessages = (_, _) async => ChatPage(
      list: <ChatMessage>[
        msg(1, senderId: 21, content: '我到集合点了', time: g1, senderName: '阿伟'),
        msg(2, senderId: 22, content: '我在路上了', time: g2, senderName: '小花'),
        msg(3, senderId: 1, content: '我也到了', time: g3),
        // 系统消息(senderId=0)后端不回填 → 回退会话级名字(群名)。
        msg(4, senderId: 0, content: '公告:今晚八点', time: g4),
      ],
    );
    await pumpChat(
      tester,
      api: api,
      peerName: '周五夜局',
      extra: <dynamic>[meIsMember(1)],
    );

    expect(
      inList('阿伟 · ${fmtMessageTime(g1)}'),
      findsOneWidget,
      reason: '第一条群消息挂发送者昵称',
    );
    expect(inList('小花'), findsOneWidget, reason: '第二个发送者显自己的昵称,不再和第一条同名');
    expect(
      inList('周五夜局 · ${fmtMessageTime(g1)}'),
      findsNothing,
      reason: '群名出现在气泡头上 = 分不清谁说的(F1 本尊)',
    );
    expect(
      inList('周五夜局 · ${fmtMessageTime(g4)}'),
      findsOneWidget,
      reason: 'senderId=0 无回填,回退会话级名字',
    );
    expect(
      inList(fmtMessageTime(g3)),
      findsOneWidget,
      reason: '自己一侧仍只有时间,不挂名字',
    );
  });

  // ── A5 iOS 27 外观复核(a5-ios27-im-bubble-97)对 #459 新落点的度量钉──

  final String d0 = '2026-01-15 20:10:00'; // msg() 的默认 createTime

  TextStyle headerStyle(WidgetTester tester, String text) {
    final RenderParagraph p = tester.renderObject<RenderParagraph>(
      inList(text),
    );
    return p.text.style!;
  }

  testWidgets('气泡头落 iOS 排版梯级 Caption2:11pt、常规重、中文字距 0(T5)', (tester) async {
    final FakeImChatApi api = FakeImChatApi();
    api.onMessages = (_, _) async => ChatPage(
      list: <ChatMessage>[
        msg(1, senderId: 2, content: '周六见', senderName: '阿伟'),
      ],
    );
    await pumpChat(tester, api: api, extra: <dynamic>[meIsMember(1)]);

    final TextStyle s = headerStyle(tester, '阿伟 · ${fmtMessageTime(d0)}');
    // 真源 .sender-name = --cy-font-caption(22rpx→11pt)且不置字重(400)。
    // textTheme.labelSmall 同为 11pt,但带 Material 的 w500 + 0.5 字距,
    // 不在 CyType 梯级观感上 —— 本用例钉的是修复后的梯级值。
    expect(s.fontSize, 11);
    expect(s.fontWeight, FontWeight.w400);
    expect(s.letterSpacing, 0, reason: 'T5:中文字距一律 0,不随 Material 梯带正值');
    expect(
      s.color,
      CyPalette.dark.textSecondary,
      reason: 'C4:取 palette 语义色(玩家恒暗端与旧 CyTokens 常量同值)',
    );
    // 间距:真源 margin `0 0 --cy-legacy-6(3pt) 8rpx(4pt)`(critic 第 1 轮逮出
    // 旧实现用了 space1_5=6pt,是真源两倍)。
    final Padding pad = tester.widget<Padding>(
      find
          .ancestor(
            of: inList('阿伟 · ${fmtMessageTime(d0)}'),
            matching: find.byType(Padding),
          )
          .first,
    );
    expect(
      pad.padding,
      const EdgeInsets.only(left: 4, bottom: 3),
      reason: '气泡头行左 4pt、离气泡 3pt',
    );
  });

  testWidgets('群聊长昵称不撑爆行:气泡头与多图组都换行不 overflow', (tester) async {
    const String longName = '这是一个非常非常长的群成员昵称用来把气泡头那一行撑到整屏宽之外测试排版不破';
    final FakeImChatApi api = FakeImChatApi();
    api.onMessages = (_, _) async => ChatPage(
      list: <ChatMessage>[
        msg(1, senderId: 2, content: '文字气泡', senderName: longName),
        msg(
          2,
          senderId: 2,
          msgType: kMsgImage,
          content: 'https://example.invalid/a.png',
          senderName: longName,
          time: _at(base, 10),
        ),
        msg(
          3,
          senderId: 2,
          msgType: kMsgImage,
          content: 'https://example.invalid/b.png',
          senderName: longName,
          time: _at(base, 11),
        ),
      ],
    );
    await pumpChat(tester, api: api, extra: <dynamic>[meIsMember(1)]);

    expect(tester.takeException(), isNull, reason: 'Row 溢出 = 黄黑条,三态排版破');
    // 长名折行后仍在树上(不是被截没了)。
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.textContaining('非常非常长', findRichText: true),
      ),
      findsWidgets,
    );
    final RenderParagraph head = tester.renderObject<RenderParagraph>(
      find
          .descendant(
            of: find.byType(ListView),
            matching: find.textContaining(longName, findRichText: true),
          )
          .first,
    );
    expect(head.size.height, greaterThan(20), reason: '昵称行确实占了多于一行');
  });

  testWidgets('昵称脏值原样显示、空串回退会话名 —— 与列表显示口径一致', (tester) async {
    final FakeImChatApi api = FakeImChatApi();
    api.onMessages = (_, _) async => ChatPage(
      list: <ChatMessage>[
        // 后端 nickname 本身可能就是脏键值(真源 im/list 无前缀清洗),App 不许吞。
        msg(1, senderId: 21, content: 'a', senderName: 'topic_666'),
        // 空串 = 无回填(后端可能给 ''而非 null)→ 回退会话级名字。
        msg(2, senderId: 22, content: 'b', senderName: '', time: _at(base, 10)),
      ],
    );
    await pumpChat(
      tester,
      api: api,
      peerName: '周五夜局',
      extra: <dynamic>[meIsMember(1)],
    );

    expect(
      inList('topic_666 · ${fmtMessageTime(d0)}'),
      findsOneWidget,
      reason: '脏值可恨但吞掉=改了显示口径',
    );
    expect(
      inList('周五夜局 · ${fmtMessageTime(_at(base, 10))}'),
      findsOneWidget,
      reason: '空串与缺失同按回退处理',
    );
  });

  testWidgets('头像取回填 senderAvatar,无回填消息回退会话级头像', (tester) async {
    final FakeImChatApi api = FakeImChatApi();
    api.onMessages = (_, _) async => ChatPage(
      list: <ChatMessage>[
        msg(
          1,
          senderId: 21,
          content: 'a',
          senderName: '阿伟',
          senderAvatar: 'https://example.invalid/awei.png',
        ),
        // 无回填消息:头像回退 peerAvatar。
        msg(2, senderId: 22, content: 'b', time: _at(base, 10)),
      ],
    );
    await pumpChat(
      tester,
      api: api,
      peerName: '周五夜局',
      peerAvatar: 'https://example.invalid/group.png',
      extra: <dynamic>[meIsMember(1)],
    );

    final List<String> loaded = tester
        .widgetList<Image>(find.byType(Image))
        .map((Image i) => i.image)
        .whereType<NetworkImage>()
        .map((NetworkImage i) => i.url)
        .toList();
    expect(loaded, contains('https://example.invalid/awei.png'));
    expect(loaded, contains('https://example.invalid/group.png'));
  });

  testWidgets('senderAvatar 与 peerAvatar 皆缺:渲首字占位,不渲空 URL 网络图', (tester) async {
    final FakeImChatApi api = FakeImChatApi();
    api.onMessages = (_, _) async => ChatPage(
      list: <ChatMessage>[msg(1, senderId: 21, content: 'a', senderName: '阿伟')],
    );
    await pumpChat(
      tester,
      api: api,
      peerName: '周五夜局',
      extra: <dynamic>[meIsMember(1)],
    );

    expect(
      tester
          .widgetList<Image>(find.byType(Image))
          .map((Image i) => i.image)
          .whereType<NetworkImage>(),
      isEmpty,
      reason: '缺值不许渲空 URL 网络图(破图)',
    );
    expect(inList('阿'), findsOneWidget, reason: '占位取发送者名首字,不是群名首字');
  });
}
