// 通关卡(结算半屏)读数契约 —— gap-spec-play F1745/G1757 收口:
// 三个读数全部来自服务端投影真值,不再出现「站数 × 固定分」估算:
//   - 探索值 = Σ 已完成节点 xp(/nodes 与回执 resolveNodeXp 同源);缺字段显「—」未知态
//   - 本次解谜分 = summarizePuzzleScores 口径(带题数尾巴),后端报了记录才显「个人最佳」
//   - mode2 探店日不报经典读数:眉标换「我的探索顺序」,只报核销/集章 + 集章名单
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/feature_flags.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/classic_play_surfaces.dart';

PlayNode _node(
  int id,
  String name, {
  bool done = true,
  int? xp,
  int? puzzleScore,
}) => PlayNode(
  nodeId: id,
  name: name,
  address: '',
  sortId: id,
  done: done,
  xp: xp,
  puzzleScore: puzzleScore,
);

Future<void> _pumpFinish(WidgetTester tester, PlayNodesResult result) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 完赛页的「附近下一程」推荐槽与本组读数断言无关,关闸保持纯读数面。
          featureFlagProvider.overrideWith((_, _) => false),
        ],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: ClassicPlayFinishSurface(
              result: result,
              scrollController: ScrollController(),
              onContinue: () {},
              onJournal: () {},
              onLeaderboard: () {},
              onShare: () {},
              onSave: () {},
            ),
          ),
        ),
      ),
    );

PlayNodesResult _result({
  int mode = 1,
  int total = 2,
  int doneCount = 1,
  int? puzzlePersonalBest,
  List<PlayNode> nodes = const <PlayNode>[],
}) => PlayNodesResult(
  topicId: 1,
  mode: mode,
  playable: true,
  total: total,
  doneCount: doneCount,
  puzzlePersonalBest: puzzlePersonalBest,
  nodes: nodes,
);

void main() {
  group('ClassicPlayFinishSurface 读数', () {
    testWidgets('探索值读已完成节点 xp 真值之和,不是 站数×12', (tester) async {
      await _pumpFinish(
        tester,
        _result(
          total: 3,
          doneCount: 2,
          nodes: <PlayNode>[
            _node(1, 'A', xp: 12),
            _node(2, 'B', xp: 30),
            _node(3, 'C', done: false, xp: 99),
          ],
        ),
      );
      expect(find.text('42'), findsOneWidget); // 真值 12+30,不是 2×12=24
      expect(find.text('24'), findsNothing);
      expect(find.text('探索值'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // 点亮坐标
      expect(find.text('主题通关'), findsOneWidget);
    });

    testWidgets('缺 xp 投影 -> 未知态「—」,不估算不 Mock', (tester) async {
      await _pumpFinish(tester, _result(nodes: <PlayNode>[_node(1, 'A')]));
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('解谜分带题数与个人最佳(后端报了才显)', (tester) async {
      await _pumpFinish(
        tester,
        _result(
          total: 2,
          doneCount: 2,
          puzzlePersonalBest: 92,
          nodes: <PlayNode>[
            _node(1, 'A', xp: 5, puzzleScore: 80),
            _node(2, 'B', xp: 5, puzzleScore: 60),
          ],
        ),
      );
      expect(find.text('140'), findsOneWidget);
      expect(find.text('本次解谜分 · 2题'), findsOneWidget);
      expect(find.text('个人最佳 92'), findsOneWidget);
    });

    testWidgets('无计分站/无最佳记录:只显「本次解谜分」,不显题数与最佳', (tester) async {
      await _pumpFinish(
        tester,
        _result(nodes: <PlayNode>[_node(1, 'A', xp: 5)]),
      );
      expect(find.text('本次解谜分'), findsOneWidget);
      expect(find.text('本次解谜分 · 1题'), findsNothing);
      expect(find.textContaining('个人最佳'), findsNothing);
    });

    testWidgets('mode2 探店日:眉标「我的探索顺序」+ 核销/集章真读数', (tester) async {
      await _pumpFinish(
        tester,
        _result(
          mode: 2,
          total: 2,
          doneCount: 1,
          nodes: <PlayNode>[_node(1, '老王咖啡店'), _node(2, '河边书店', done: false)],
        ),
      );
      expect(find.text('我的探索顺序'), findsOneWidget);
      expect(find.text('主题通关'), findsNothing);
      expect(find.text('1/2'), findsOneWidget);
      expect(find.text('商户核销'), findsOneWidget);
      expect(find.text('本期集章'), findsOneWidget);
      expect(find.text('老王咖啡店'), findsOneWidget); // 集章名单
      // 经典定向读数对 mode2 显示会撒谎 —— 不许出现
      expect(find.text('探索值'), findsNothing);
      expect(find.text('点亮坐标'), findsNothing);
    });
  });
}
