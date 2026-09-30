// Hero 的判据不是「动画好不好看」,而是**两端的 tag 必须一致** —— 不一致就退化成
// 生硬跳转,而且不会有任何报错。这条测试就钉这个。
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/free_explore/card_detail_page.dart';
import 'package:chengyin_app/feature/play/free_explore/free_explore_pass_view.dart';
import 'package:chengyin_app/feature/play/play_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const PlaySessionKey _key = (activityId: 77, topicId: null);

/// 详情页按 nodeId 从 provider 现读,固件走 PlayApi(照抄 2a 的写法)。
class _Api implements PlayApi {
  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async =>
      PlayNodesResult.fromJson(<String, dynamic>{
        'topicId': 7,
        'mode': 2,
        'playable': true,
        'total': 1,
        'doneCount': 0,
        // 章节键照后端:name / imgArr,**没有** meta/title/cover(见 PlayChapter.fromJson)。
        'chapters': <dynamic>[
          <String, dynamic>{'chapterId': 100, 'name': '晨间烘焙'},
        ],
        'nodes': <dynamic>[
          <String, dynamic>{
            'nodeId': 42, 'name': 'Bakehouse', 'address': '', 'sortId': 1,
            'chapterId': 100, 'done': false,
          },
        ],
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('★屏① 与详情页的 Hero tag 一致(按 nodeId)', (WidgetTester t) async {
    final PlayNodesResult data = PlayNodesResult.fromJson(<String, dynamic>{
      'topicId': 7, 'mode': 2, 'total': 1, 'doneCount': 0,
      'chapters': <dynamic>[<String, dynamic>{'chapterId': 100, 'name': '晨间烘焙'}],
      'nodes': <dynamic>[<String, dynamic>{
        'nodeId': 42, 'name': 'Bakehouse', 'address': '', 'sortId': 1, 'chapterId': 100,
      }],
    });
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: FreeExplorePassView(data: data, onTapNode: (_) {})),
    ));
    final Hero grid = t.widget<Hero>(find.byType(Hero).first);
    expect(grid.tag, 'fx-card-42');

    await t.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[playApiProvider.overrideWithValue(_Api())].cast(),
        child: MaterialApp(
          home: const CardDetailPage(sessionKey: _key, nodeId: 42, onPrimary: _noop),
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final Hero detail = t.widget<Hero>(find.byType(Hero).first);
    expect(detail.tag, 'fx-card-42', reason: 'tag 对不上,Hero 静默退化成生硬跳转');
  });
}

void _noop(PlayNode _) {}
