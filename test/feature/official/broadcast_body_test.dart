// 官方通知的请求体拼装。
//
// ★ 抽成纯函数就是为了能对着它写断言 —— 这条通知一旦发出去就收不回来,
//   参数拼错的代价比一般表单高。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/feature/official/official_broadcast_sheet.dart';

void main() {
  test('★★ audience 的顺序固定,不跟 Set 的遍历序', () {
    // Set 的遍历序不稳定,同样的选择会拼出不同的字符串,
    // 后端按字符串比对/去重时就会出现「一样的通知不一样」。
    final Map<String, dynamic> a = buildBroadcastBody(
      title: 't', sub: 's', audience: <String>{'merchant', 'player'});
    final Map<String, dynamic> b = buildBroadcastBody(
      title: 't', sub: 's', audience: <String>{'player', 'merchant'});
    expect(a['audience'], b['audience']);
    expect(a['audience'], 'player,merchant', reason: '按 kBroadcastAudiences 的顺序');
  });

  test('受众取值与后端逐字对齐,不自己造词', () {
    expect(kBroadcastAudiences.map((e) => e.wire).toList(),
        <String>['player', 'club', 'merchant']);
  });

  test('★ contentJson 里的引号/换行要转义 —— 否则拼出坏 JSON', () {
    final Map<String, dynamic> b = buildBroadcastBody(
      title: '他说"走"', sub: '第一行\n第二行', audience: <String>{'player'});
    final String json = b['contentJson'] as String;
    expect(json.contains(r'\"'), isTrue);
    expect(json.contains(r'\n'), isTrue);
    expect(json.contains('\n'), isFalse, reason: '真换行会让 JSON 断成两截');
  });

  test('title/sub 去空白;copyMode=1(统一文案);channels 默认 inapp', () {
    final Map<String, dynamic> b = buildBroadcastBody(
      title: '  标题  ', sub: ' 副 ', audience: <String>{'club'});
    expect(b['title'], '标题');
    expect(b['copyMode'], 1);
    expect(b['channels'], 'inapp');
  });
}
