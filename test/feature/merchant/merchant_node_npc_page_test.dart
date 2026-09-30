// 点位角色的落点页(`chapter-node/npc/*` 七条中除打卡码外的六条)。
//
// ★★ 这一页是两个域的分界:点位角色(挂在章节点位上)与门店形象(挂在商家上)
//   是两套端点,后端明确不许复用(node-npc-form.test.js:132)。
//   页面能打开、能读到空态、能显示出四态声音,才算"接口接上了"。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/feature/merchant/merchant_node_npc_page.dart';

class _FakeMerchantApi implements MerchantApi {
  _FakeMerchantApi({this.detail, this.fail = false});

  final Map<String, dynamic>? detail;
  final bool fail;
  int detailCalls = 0;

  @override
  Future<Map<String, dynamic>?> chapterNodeNpcDetail(int nodeId) async {
    detailCalls++;
    if (fail) throw MerchantApiException('承接已失效或未生效,不能编辑节点内容');
    return detail;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(_FakeMerchantApi api) => ProviderScope(
  overrides: [merchantApiProvider.overrideWithValue(api)],
  child: const MaterialApp(
    home: MerchantNodeNpcPage(nodeId: 5, nodeName: '南京西路店'),
  ),
);

void main() {
  testWidgets('★★ 没配过(data:null)是正常空态,不是报错页', (WidgetTester tester) async {
    final _FakeMerchantApi api = _FakeMerchantApi();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(api.detailCalls, 1);
    expect(find.byKey(const Key('node-npc-name')), findsOneWidget);
    expect(find.byKey(const Key('node-npc-save')), findsOneWidget);
    expect(
      find.textContaining('承接已失效'),
      findsNothing,
      reason: '把"没配过"当异常,第一次进来的商家看到的是报错页',
    );
  });

  testWidgets('★ 已配过:把名字/招呼语填回去,并显示声音四态', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(
        _FakeMerchantApi(
          detail: <String, dynamic>{
            'name': '阿福',
            'avatar': 'https://x/a.png',
            'greeting': '来杯咖啡吧',
            'voiceStatus': 2,
            'voiceSample': 'https://x/v.mp3',
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('阿福'), findsOneWidget);
    expect(find.text('来杯咖啡吧'), findsOneWidget);
    expect(
      find.text('声音已就绪'),
      findsOneWidget,
      reason: '提交录音只是"录好了",克隆在供应商那边异步跑 —— 必须看得到进度',
    );
  });

  testWidgets('★★ 生成中的点位角色:交出「试听/清除」之外的刷新口,不让人干等',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(
        _FakeMerchantApi(
          detail: <String, dynamic>{
            'name': '阿福',
            'avatar': 'https://x/a.png',
            'voiceStatus': 1,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('声音生成中…(稍后自动刷新)'), findsOneWidget);
    expect(find.byKey(const Key('node-npc-voice-refresh')), findsOneWidget);
    expect(
      find.byKey(const Key('node-npc-voice-reset')),
      findsNothing,
      reason: '生成中清掉 = 把供应商那边正在跑的任务扔掉',
    );
  });

  testWidgets('★ 承接失效:原文显示,并说清这是权限态(不给重试)', (WidgetTester tester) async {
    await tester.pumpWidget(_app(_FakeMerchantApi(fail: true)));
    await tester.pumpAndSettle();

    expect(find.textContaining('承接已失效或未生效'), findsOneWidget);
  });
}
