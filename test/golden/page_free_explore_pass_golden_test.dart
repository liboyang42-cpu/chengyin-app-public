// fixture 造的是**语义边界**不是漂亮数据:4 章 + 第 1 章已核销,
// 一屏之内同时能看到「卡片等大」「已核销只阴掉不挂标签」「简介是主题的」三件事。
//
// 更新基准图:flutter test --update-goldens test/golden/page_free_explore_pass_golden_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/free_explore/free_explore_pass_view.dart';
import 'golden_theme.dart';

void main() {
  testWidgets('★ 自由探索通行证首屏:4 章 / 首张已核销(阴掉,无标签)',
      (WidgetTester tester) async {
    final PlayNodesResult data = PlayNodesResult.fromJson(<String, dynamic>{
      'topicId': 7,
      'mode': 2,
      'topicDesc': '一个慢下来的下午,从巨鹿路的第一炉可颂走到五原路的陶艺工作室。'
          '四家店各出一份权益,30 天内去哪家、先去哪家都由你,只去一家也算。',
      'selfPlay': true,
      'total': 4,
      'doneCount': 1,
      'chapters': <dynamic>[
        <String, dynamic>{'chapterId': 100, 'name': '晨间烘焙'},
        <String, dynamic>{'chapterId': 101, 'name': '旧书与唱片'},
        <String, dynamic>{'chapterId': 102, 'name': '午后小酌'},
        <String, dynamic>{'chapterId': 103, 'name': '手作时间'},
      ],
      'nodes': <dynamic>[
        <String, dynamic>{'nodeId': 1, 'name': 'Bakehouse 巨鹿路店', 'address': '', 'sortId': 1, 'chapterId': 100, 'done': true},
        <String, dynamic>{'nodeId': 2, 'name': '长乐路旧物店', 'address': '', 'sortId': 2, 'chapterId': 101},
        <String, dynamic>{'nodeId': 3, 'name': '安福路小酒馆', 'address': '', 'sortId': 3, 'chapterId': 102},
        <String, dynamic>{'nodeId': 4, 'name': '陶所 · 五原路', 'address': '', 'sortId': 4, 'chapterId': 103},
      ],
    });

    setGoldenViewport(tester, const Size(390, 1000));
    await tester.pumpWidget(MaterialApp(
      theme: goldenTheme(),
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: FreeExplorePassView(data: data, onTapNode: (_) {}),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_free_explore_pass.png'),
    );
  });
}
