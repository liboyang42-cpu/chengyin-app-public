// 店铺分身对话的纯逻辑。抽出来单测,是因为这三件事(重答取问、兜底口径、时段问候)
// 全都「看着对、其实错」,而错法都不报错:
//   取问取错 → 分身答非所问;兜底编话 → 玩家一直重试;问候顶掉作者的话 → 商家白配。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/shop_npc_models.dart';
import 'package:chengyin_app/feature/play/free_explore/shop_npc_logic.dart';

ShopNpcMessage _me(String t) => ShopNpcMessage(id: 0, mine: true, text: t);
ShopNpcMessage _ai(String t) => ShopNpcMessage(id: 0, mine: false, text: t);

void main() {
  test('重答取的是这条回答之前最近的我方提问', () {
    final List<ShopNpcMessage> msgs = <ShopNpcMessage>[
      _me('几点关门'),
      _ai('九点'),
      _me('有停车位吗'),
      _ai('有'),
    ];
    expect(retryQuestionFor(msgs, 3), '有停车位吗');
    expect(retryQuestionFor(msgs, 1), '几点关门');
  });

  test('前面没有我方提问 ⇒ null,调用方据此不发请求', () {
    expect(retryQuestionFor(<ShopNpcMessage>[_ai('欢迎')], 0), isNull);
  });

  test('index 越界不炸 —— 越界返回最后一句我方提问', () {
    final List<ShopNpcMessage> msgs = <ShopNpcMessage>[_me('几点关门'), _ai('九点')];
    expect(retryQuestionFor(msgs, 99), '几点关门');
  });

  test('闸关时端服务端原话,不编话', () {
    expect(replyTextOr('', '店铺分身对话还没开放'), '店铺分身对话还没开放');
  });

  test('服务端也没话才用兜底句', () {
    expect(replyTextOr('', null), kShopNpcFallback);
  });

  test('服务端 msg 是空串也算没话 —— 空串端上去等于一条空回答', () {
    expect(replyTextOr('', ''), kShopNpcFallback);
  });

  test('有正经回答时不看服务端 msg(成功那条 msg 是「操作成功」)', () {
    expect(replyTextOr('九点关门', '操作成功'), '九点关门');
  });

  test('时段问候按本地时间分五档', () {
    String at(int h) => greetingFor(
      npcName: '阿旧',
      shopName: '旧物店',
      now: DateTime(2026, 9, 9, h),
    );
    expect(at(5), startsWith('凌晨好'));
    expect(at(9), startsWith('早上好'));
    expect(at(12), startsWith('中午好'));
    expect(at(15), startsWith('下午好'));
    expect(at(20), startsWith('晚上好'));
  });

  test('档位边界照抄样机:6/11/13/18 是下一档的第一个小时', () {
    String at(int h) =>
        greetingFor(npcName: '阿旧', shopName: '旧物店', now: DateTime(2026, 9, 9, h));
    expect(at(5), startsWith('凌晨好'), reason: 'h<6 才是凌晨(index.js:1195)');
    expect(at(6), startsWith('早上好'));
    expect(at(10), startsWith('早上好'));
    expect(at(11), startsWith('中午好'));
    expect(at(12), startsWith('中午好'));
    expect(at(13), startsWith('下午好'));
    expect(at(17), startsWith('下午好'));
    expect(at(18), startsWith('晚上好'));
    expect(at(0), startsWith('凌晨好'));
    expect(at(23), startsWith('晚上好'));
  });

  test('合成的问候带上分身名与店名', () {
    expect(
      greetingFor(npcName: '阿旧', shopName: '旧物店', now: DateTime(2026, 9, 9, 9)),
      '早上好，我是阿旧，欢迎来到旧物店',
    );
  });

  test('没有店名时回落到「我们店铺」,不留一句半截话', () {
    expect(
      greetingFor(npcName: '阿旧', now: DateTime(2026, 9, 9, 9)),
      endsWith('欢迎来到我们店铺'),
    );
  });

  test('作者配了问候语就用作者的,不合成', () {
    expect(
      greetingFor(authored: '随便挑挑', npcName: '阿旧', now: DateTime(2026, 9, 9, 9)),
      '随便挑挑',
    );
  });

  test('作者那句只有空白 ⇒ 当没配,回落到合成(样机 trim 后判空)', () {
    expect(
      greetingFor(
        authored: '   ',
        npcName: '阿旧',
        shopName: '旧物店',
        now: DateTime(2026, 9, 9, 9),
      ),
      startsWith('早上好'),
    );
  });

  test('等待名条第二拍的间隔与样机同一个数(index.js:1408)', () {
    expect(kThinkPhaseDelay.inMilliseconds, 1200);
  });
}
