// 聊天里发路线卡片。
//
// ★★ `kMsgCard`(3) 与 `ChatMessage.extraJson` **一直都在** ——
//   常量有、模型有,就是 `ImApi.send` 没有 extra_json 参数,发不出去。
//   于是 App 只能发文本和图。今天第四次撞上「模型支持、链路断一节」。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/im/route_picker_sheet.dart';
import '../../support/source_text.dart';

void main() {
  test('★★ 卡片 JSON 与小程序 sendCard 同形 —— 两端要能互相解析', () {
    final Map<String, dynamic> j =
        jsonDecode(routeCardJson(12)) as Map<String, dynamic>;
    expect(j['cardType'], 'route');
    expect(j['topicId'], 12);
  });

  test('★★ 只传 topicId,不塞标题/封面', () {
    // 展示字段服务端不收、由接收方现拉(小程序 spec 决策 8)。
    // 塞进去的话,路线改名后聊天记录里还是旧名字。
    final Map<String, dynamic> j =
        jsonDecode(routeCardJson(12)) as Map<String, dynamic>;
    expect(j.keys.toSet(), <String>{'cardType', 'topicId'});
  });

  test('★ send 支持 extra_json,且空串不发', () {
    final String api = codeOf('lib/data/api/im_api.dart');
    expect(api.contains('String? extraJson'), isTrue);
    expect(api.contains("if ((extraJson ?? '').isNotEmpty) 'extra_json'"), isTrue,
        reason: '空串会被后端存成一个解析不出东西的卡片');
  });

  test('★ content 是降级文案 —— 不认识卡片的客户端要有东西可显示', () {
    final String page = codeOf('lib/feature/im/im_chat_page.dart');
    // 2026-09-17:文本 / 图片 / 卡片改成**共用一个发送出口**(_dispatch),
    // 类型由 _Outgoing 的四个具名构造器决定 —— 失败重发才有唯一的地方能按
    // 原样重发。断言跟着换成新形状(锚在具名构造器上),守的还是同两条:
    // 降级文案 + 卡片类型。
    // 归一化空白,免得 format 重排一行就红。
    final String flat = page.replaceAll(RegExp(r'\s+'), ' ');
    expect(
        flat.contains(
            "_Outgoing.route(int topicId) : content = '[路线]', "
            'msgType = kMsgCard'),
        isTrue,
        reason: '路线卡必须以 kMsgCard + 降级文案「[路线]」发出,'
            '退化成文本接收方就认不出来了');
  });

  test('★ 复用 /api/topic/list,零新端点', () {
    final String sheet = codeOf('lib/feature/im/route_picker_sheet.dart');
    expect(sheet.contains('topicApiProvider'), isTrue);
    expect(sheet.contains('/api/im/'), isFalse, reason: '不该为选路线新开端点');
  });
}
