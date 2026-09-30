// test/feature/play/free_explore_wiring_test.dart
//
// 钉住两件事:①mode==2 渲染的是屏① 不是节点列表 ②点卡片进详情页
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/free_explore/free_explore_pass_view.dart';

void main() {
  testWidgets('★点卡片进卡片详情', (WidgetTester t) async {
    final PlayNodesResult data = PlayNodesResult.fromJson(<String, dynamic>{
      'topicId': 7, 'mode': 2, 'total': 1, 'doneCount': 0,
      'chapters': <dynamic>[<String, dynamic>{'chapterId': 100, 'name': '晨间烘焙'}],
      'nodes': <dynamic>[<String, dynamic>{
        'nodeId': 1, 'name': 'Bakehouse', 'address': '', 'sortId': 1, 'chapterId': 100,
      }],
    });
    PlayNode? tapped;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: FreeExplorePassView(
        data: data,
        onTapNode: (PlayNode n) => tapped = n,
      )),
    ));
    await t.tap(find.byKey(const ValueKey<String>('fx-tile-0')));
    await t.pump();
    expect(tapped?.nodeId, 1, reason: '卡片不接回调 = 点了没反应的假入口');
  });
}
