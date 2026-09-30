import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/free_explore/free_explore_pass_view.dart';

PlayNodesResult _fixture({
  required int chapters,
  int done = 0,
  String? topicDesc = '一个慢下来的下午',
}) {
  return PlayNodesResult.fromJson(<String, dynamic>{
    'topicId': 7, 'mode': 2, 'topicDesc': topicDesc,
    'total': chapters, 'doneCount': done,
    'chapters': List<dynamic>.generate(chapters, (i) => <String, dynamic>{
      'chapterId': 100 + i, 'name': '章节 ${i + 1}',
    }),
    'nodes': List<dynamic>.generate(chapters, (i) => <String, dynamic>{
      'nodeId': i + 1, 'name': '店 ${i + 1}', 'address': '', 'sortId': i + 1,
      'chapterId': 100 + i, 'done': i < done,
    }),
  });
}

Future<void> _pump(WidgetTester t, PlayNodesResult data) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: FreeExplorePassView(data: data, onTapNode: (_) {}),
    ),
  ));
}

void main() {
  testWidgets('首屏简介取 topicDesc,不是第一章的描述', (t) async {
    await _pump(t, _fixture(chapters: 4));
    expect(find.text('一个慢下来的下午'), findsOneWidget);
  });

  testWidgets('★3/4/5/6 章卡片尺寸完全一致', (t) async {
    final sizes = <int, Size>{};
    for (final int n in <int>[3, 4, 5, 6]) {
      await _pump(t, _fixture(chapters: n));
      sizes[n] = t.getSize(find.byKey(const ValueKey<String>('fx-tile-0')));
    }
    expect(sizes[3], sizes[4], reason: '3 章应右边空一格,不是把卡片放大');
    expect(sizes[5], sizes[4], reason: '5 章应往下滚,不是把卡片缩小');
    expect(sizes[6], sizes[4]);
  });

  testWidgets('★已核销只把卡阴掉,不挂「已核销」标签', (t) async {
    await _pump(t, _fixture(chapters: 4, done: 1));
    expect(find.text('已核销'), findsNothing);
    expect(find.byKey(const ValueKey<String>('fx-tile-dim-0')), findsOneWidget);
  });

  testWidgets('★ 渲染出来的宽高比就是 1.38', (t) async {
    await _pump(t, _fixture(chapters: 4));
    final Size s = t.getSize(find.byKey(const ValueKey<String>('fx-tile-0')));
    // 字面量而非 kFreeExploreTileRatio:断言要独立于被测对象,
    // 否则常量一改两边一起动,抓不住实现漂离规格这件事。
    expect(s.height / s.width, closeTo(1.38, 0.02));
  });

  testWidgets('★topicDesc 为空时简介整段不渲染', (t) async {
    await _pump(t, _fixture(chapters: 4, topicDesc: null));
    expect(find.text('一个慢下来的下午'), findsNothing);
    // 防止把 guard 写成"desc ?? ''"这种仍会渲染空文本段落的变体。
    expect(find.text(''), findsNothing);
  });

  testWidgets('★章节眉标匹配不到时不渲染,不拿店名冒充', (t) async {
    final PlayNodesResult data = PlayNodesResult.fromJson(<String, dynamic>{
      'topicId': 7, 'mode': 2, 'topicDesc': '一个慢下来的下午',
      'total': 1, 'doneCount': 0,
      'chapters': <dynamic>[
        <String, dynamic>{'chapterId': 100, 'name': '章节 1'},
      ],
      'nodes': <dynamic>[
        <String, dynamic>{
          'nodeId': 1, 'name': '店 1', 'address': '', 'sortId': 1,
          'chapterId': 999, 'done': false, // chapters 里没有 999,匹配不到
        },
      ],
    });
    await _pump(t, data);
    expect(find.text('第 1 章 · 章节 1'), findsNothing);
    // 店名只应出现在卡片底部这一处;若被拿去冒充眉标,这里会变成两处。
    expect(find.text('店 1'), findsOneWidget);
  });
}
