// 玩法说明详情:三种"点进来什么都没有"必须说不同的话。
//
// ★ 真源 `subpackageA/pages/infomationdetail/infomationdetail.{wxml,js}` 四态互斥:
//   缺参(不拉接口,只给返回)/ 200 但没有实体 = 这条已被后台删除 /
//   接口失败可重试 / 有实体但正文还没写。
//   App 原来把"已被删除"和"正文没写"渲成同一句,还先照着 id=0 真发了一次请求。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/infomation.dart';
import 'package:chengyin_app/feature/account/infomation_detail_page.dart';

/// 页面级替身放在 provider 边界上:override 函数被调用 = 真的发出了一次请求。
Future<void> _pump(
  WidgetTester t, {
  required int id,
  required Future<Infomation> Function() load,
  required int Function() calls,
}) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        infomationDetailProvider(id).overrideWith((Ref ref) async {
          _calls = calls() + 1;
          return load();
        }),
      ].cast(),
      child: MaterialApp(home: InfomationDetailPage(id: id)),
    ),
  );
  await t.pumpAndSettle();
}

int _calls = 0;

void main() {
  setUp(() => _calls = 0);

  testWidgets('★ 链接缺 id:不拉接口,说清是哪一段坏了,出路是返回玩法列表', (WidgetTester t) async {
    await _pump(
      t,
      id: 0,
      load: () async => throw StateError('不该被调用'),
      calls: () => _calls,
    );
    expect(find.text('这篇玩法说明打不开'), findsOneWidget);
    expect(find.text('链接里没有玩法编号，请从玩法列表重新进入'), findsOneWidget);
    expect(find.text('返回玩法列表'), findsOneWidget);
    expect(_calls, 0, reason: 'id 都是 0 了还发请求 = 明知不会有结果还打一次');
  });

  testWidgets('★ 200 但没有实体(后台删了):说「不在了」,不给假重试', (WidgetTester t) async {
    await _pump(
      t,
      id: 7,
      load: () async => Infomation.fromJson(<String, dynamic>{}),
      calls: () => _calls,
    );
    expect(find.text('这篇玩法说明不在了'), findsOneWidget);
    expect(find.text('它可能已被下架。去玩法列表看看其它的。'), findsOneWidget);
    expect(find.text('返回玩法列表'), findsOneWidget);
    // 「重试」在这里是假承诺:实体真的没了,再点一百次也还是不在了。
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('★ 有实体但正文还没写:和"被下架"不是一回事', (WidgetTester t) async {
    await _pump(
      t,
      id: 8,
      load: () async => Infomation.fromJson(<String, dynamic>{
        'id': 8,
        'title': '怎么玩城市定向',
        'contents': '   ',
      }),
      calls: () => _calls,
    );
    expect(find.text('怎么玩城市定向'), findsOneWidget);
    expect(find.text('正文还没写好,过一阵再来'), findsOneWidget);
    expect(find.text('这篇玩法说明不在了'), findsNothing);
  });
}
