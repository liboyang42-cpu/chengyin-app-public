// 聊天卡片的解析。
//
// ★★ App 此前**能发不能收**:发路线卡片是本轮刚加的,而接收端没有对应分支
//   —— 卡片会掉进「不认识的类型」兜底,渲成一行斜体
//   「[这条消息当前版本显示不了]」。**自己发的自己都看不懂。**

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/feature/im/chat_card.dart';

void main() {
  test('路线卡片:只有 cardType + topicId', () {
    final r = parseChatCard('{"cardType":"route","topicId":12}');
    expect(r?.type, 'route');
    expect(r?.topicId, 12);
    expect(r?.bcId, isNull);
  });

  test('★ 官方通知卡片带 bcId 与 action —— 两个都是**可选**', () {
    // 路线卡片没有它们,不能因此判成解析失败。
    final r = parseChatCard(
        '{"cardType":"notice","bcId":7,"action":"/official/3"}');
    expect(r?.bcId, 7);
    expect(r?.action, '/official/3');
  });

  group('★★ 解析不了返回 null,不抛 —— 一条坏消息不该让整个会话崩掉', () {
    test('空/非 JSON/非对象', () {
      expect(parseChatCard(null), isNull);
      expect(parseChatCard('  '), isNull);
      expect(parseChatCard('不是 json'), isNull);
      expect(parseChatCard('[1,2]'), isNull);
    });
    test('缺 cardType', () {
      expect(parseChatCard('{"topicId":1}'), isNull);
    });
    test('★ topicId 无效**且**没有 action ⇒ null', () {
      // 渲一张点进去 404 的卡片比渲占位更糟:用户会以为是自己网络问题。
      expect(parseChatCard('{"cardType":"route","topicId":0}'), isNull);
      expect(parseChatCard('{"cardType":"route"}'), isNull);
    });
    test('★ 但只有 action 没有 topicId 是**合法**的系统卡片', () {
      final r = parseChatCard('{"cardType":"notice","action":"/official/3"}');
      expect(r, isNotNull);
      expect(r?.topicId, 0);
    });
  });

  test('★ 标题拿不到时用「路线 #id」兜,不显示空白也不显示「加载中」', () {
    // 一条对方明明发了的消息在我这儿消失,比显示一个编号严重得多。
    expect(chatCardFallbackTitle(type: 'route', topicId: 9), '路线 #9');
    expect(chatCardFallbackTitle(type: 'notice', topicId: 9), '内容 #9');
  });

  test('topicId 是字符串也认(后端两种形态都出现过)', () {
    expect(parseChatCard('{"cardType":"route","topicId":"12"}')?.topicId, 12);
  });

  group('★ 位置卡:字段与小程序 sendCard({cardType:\'location\',…}) 同形', () {
    test('name/address/lat/lng 全解析', () {
      final r = parseChatCard(
        '{"cardType":"location","name":"静安公园","address":"愚园路 100 号",'
        '"lat":31.223,"lng":121.445}',
      );
      expect(r?.type, 'location');
      expect(r?.name, '静安公园');
      expect(r?.address, '愚园路 100 号');
      expect(r?.lat, 31.223);
      expect(r?.lng, 121.445);
    });

    test('lat/lng 是字符串也认(后端两种形态都出现过)', () {
      final r = parseChatCard(
        '{"cardType":"location","name":"集合点","lat":"31.2","lng":"121.4"}',
      );
      expect(r?.lat, 31.2);
      expect(r?.lng, 121.4);
    });

    test('★ 位置卡没有 topicId 也不该判成解析失败 —— 它是另一类卡片', () {
      // topicId 无效 ⇒ null 是给**路线卡**定的:渲一张点进去 404 的卡更糟。
      // 位置卡的可点是「导航」,判据是坐标,不是 topicId。
      expect(parseChatCard('{"cardType":"location","name":"x"}'), isNotNull);
    });

    test('★ 0/0 = 没有坐标:有名字照渲(点导航才说没有坐标),全无才当解析失败', () {
      final r = parseChatCard(
        '{"cardType":"location","name":"集合点","lat":0,"lng":0}',
      );
      expect(r?.name, '集合点');
      expect(parseChatCard('{"cardType":"location","lat":0,"lng":0}'), isNull);
      expect(parseChatCard('{"cardType":"location","name":"  "}'), isNull);
    });
  });
}
