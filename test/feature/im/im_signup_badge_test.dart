// 报名卡(cardType:signup)的「报名成功」角标。
//
// 真源:`xcx-ref/subpackageB/pages/im/chat/index.wxml` 62 行
//      `<view wx:if="{{item.card.cardType === 'signup'}}" class="rcard-flag">报名成功</view>`
//      + `index.wxss` 的 `.rcard-flag`(绿 = 成功语义)。
//
// ★ route 与 signup 同构(都只有 topicId、都现拉),差别之一就是这条标记:
//   给路线卡盖上「报名成功」= 伪造了一个不存在的状态,所以正反两面都要钉。

import 'package:chengyin_app/data/models/im.dart';
import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/feature/topic/topic_detail_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'im_chat_test_support.dart';

TopicDetail _topic(int id) => TopicDetail(
  id: id,
  name: '静安夜行',
  chapters: const <TopicChapter>[],
);

Future<void> _pumpCard(WidgetTester tester, String cardType) async {
  final FakeImChatApi api = FakeImChatApi();
  api.onMessages = (_, _) async => ChatPage(
    list: <ChatMessage>[
      msg(
        1,
        senderId: 2,
        msgType: kMsgCard,
        content: '[卡片]',
        extraJson: '{"cardType":"$cardType","topicId":7}',
      ),
    ],
  );
  await pumpChat(
    tester,
    api: api,
    extra: <dynamic>[
      topicDetailProvider(7).overrideWith((ref) async => _topic(7)),
    ],
  );
}

void main() {
  testWidgets('报名卡带「报名成功」标记条,并照常渲染主题', (tester) async {
    await _pumpCard(tester, 'signup');

    expect(find.text('报名成功'), findsOneWidget);
    expect(find.text('静安夜行'), findsOneWidget, reason: '角标不该顶掉卡片正文');
  });

  testWidgets('负控:路线卡没有这条标记', (tester) async {
    await _pumpCard(tester, 'route');

    expect(find.text('静安夜行'), findsOneWidget);
    expect(
      find.text('报名成功'),
      findsNothing,
      reason: '路线卡渲「报名成功」= 给一条没报名过的路线盖了成功章',
    );
  });
}
