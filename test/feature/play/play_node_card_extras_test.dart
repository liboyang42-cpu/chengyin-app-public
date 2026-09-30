import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/free_explore/card_detail_page.dart';
import 'package:chengyin_app/feature/play/play_session_controller.dart';
import 'package:chengyin_app/feature/play/widgets/play_node_card_extras.dart';
import 'package:chengyin_app/feature/play/widgets/playkit_woodfish.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 节点卡尾段两件:赛博木鱼(`cy-playkit-woodfish`)+ AI 参考分(`cy-ai-score-card`)。
/// 收敛自两套未合并的实现(#173 落点/接线 + #229 组件逐值),判据逐条对着真源:
/// * `pages/play/index.wxml:962` —— `wx:if="{{sheet.node.ambient === 'woodfish'}}"`,
///   就地内联在节点卡里;「不判定通关,所以计数是纯陪伴」(`playkit-woodfish/index.js:1-6`);
/// * `pages/play/index.js:4745-4748` `onWoodfishKnock` —— 只 `setData` 自增,
///   不落库、不上报、活过整趟游玩(page data,不是组件私产);
/// * `pages/play/index.js:4725` `_applyAiScore` —— 分数只从照片回执来,
///   `Number(ai.score) > 0` 才挂上,「没给分就没有这张卡,不造一个占位分」。
const PlaySessionKey _key = (activityId: 77, topicId: null);
const ValueKey<String> _stage = ValueKey<String>('woodfish-stage');

/// 真源 `pages/play/index.wxml:962` 的字面值 —— 转抄,不读小程序仓。
const String _miniProgramAmbient = 'woodfish';

/// 节点固件(真源截图夹具 F51 `scripts/shot-matrix.js:538` 的同款数据)。
Map<String, dynamic> _node({String? ambient}) => <String, dynamic>{
  'nodeId': 51,
  'name': '河岸静心站',
  'address': '苏州河 · 约 5 分钟',
  'sortId': 2,
  'done': false,
  'ambient': ?ambient,
};

/// ★ 详情页按 nodeId 从 provider 现读,所以固件走 PlayApi。
///   顺带记账:敲木鱼**不许**让它再发一次请求。
class _Api implements PlayApi {
  _Api(this.node);

  final Map<String, dynamic> node;
  int calls = 0;

  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async {
    calls++;
    return PlayNodesResult.fromJson(<String, dynamic>{
      'topicId': 23,
      'mode': 2,
      'playable': true,
      'total': 1,
      'doneCount': 0,
      'nodes': <dynamic>[node],
      'chapters': const <dynamic>[],
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _noop(PlayNode _) {}

/// 详情页正文很长,默认视口里尾段天然在屏幕外 —— `findsNothing` 会假绿。
/// 撑到整页都在视口里,判据才是「有没有渲染」。
Future<_Api> _pumpCard(WidgetTester t, Map<String, dynamic> node) async {
  final _Api api = _Api(node);
  t.view.physicalSize = const Size(390, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[playApiProvider.overrideWithValue(api)].cast(),
      child: MaterialApp(
        home: CardDetailPage(sessionKey: _key, nodeId: 51, onPrimary: _noop),
      ),
    ),
  );
  await t.pumpAndSettle();
  return api;
}

Widget _host(Widget child, {bool disableAnimations = false}) => MaterialApp(
  // 用 copyWith 而不是另起一个 MediaQueryData:后者会把 size 清成 0,
  // 组件会在 0×0 里排版,量出来的「有没有渲染」全不作数。
  home: Builder(
    builder: (BuildContext context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

/// 复刻游玩页的持有姿势:`ref.watch(playNodeCardExtrasProvider(key))` 让附加物
/// 活过每一次开卡/关卡;开关卡片只是换子树,不碰这份会话状态。
class _SessionShell extends ConsumerWidget {
  const _SessionShell({required this.showCard});

  final bool showCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(playNodeCardExtrasProvider(_key));
    return showCard
        ? CardDetailPage(sessionKey: _key, nodeId: 51, onPrimary: _noop)
        : const SizedBox.shrink();
  }
}

void main() {
  group('① PlayNode.ambient 解析(真源字段名,fail-closed)', () {
    test('按下发值解析;缺失/null 即 null,不落回默认值', () {
      expect(PlayNode.fromJson(_node(ambient: 'woodfish')).ambient, 'woodfish');
      expect(PlayNode.fromJson(_node()).ambient, isNull);
      expect(
        PlayNode.fromJson(<String, dynamic>{
          ..._node(),
          'ambient': null,
        }).ambient,
        isNull,
      );
    });

    test('挂载判据与真源 wx:if 同一条;不认识的名字当不存在', () {
      expect(
        PlayKitWoodfish.visibleFor(
          PlayNode.fromJson(_node(ambient: _miniProgramAmbient)),
        ),
        isTrue,
      );
      expect(
        PlayKitWoodfish.visibleFor(PlayNode.fromJson(_node(ambient: 'fish'))),
        isFalse,
      );
      expect(
        PlayKitWoodfish.visibleFor(
          PlayNode.fromJson(_node(ambient: 'Woodfish')),
        ),
        isFalse,
        reason: '大小写敏感 —— 与真源 === 严格相等同一条',
      );
      expect(PlayKitWoodfish.visibleFor(PlayNode.fromJson(_node())), isFalse);
    });

    test('withRoute 复建节点时透传 ambient(路线刷新不许把氛围件洗掉)', () {
      final PlayNode node = PlayNode.fromJson(_node(ambient: 'woodfish'));
      expect(node.withRoute(state: 'PLAYABLE').ambient, 'woodfish');
    });
  });

  group('② 赛博木鱼组件', () {
    testWidgets('渲染真源三行文案;敲一下只回调,自己不改计数', (WidgetTester t) async {
      int knocks = 0;
      await t.pumpWidget(
        _host(PlayKitWoodfish(count: 18, onKnock: () => knocks++)),
      );
      expect(find.text('×18'), findsOneWidget);
      expect(find.text('今晚的烦恼,敲一下少一个'), findsOneWidget);
      expect(find.text('剧情氛围件 · 不判定通关'), findsOneWidget);
      expect(find.text('功德 +1'), findsNothing, reason: '没敲之前不许挂着飘字');

      await t.tap(find.byKey(_stage));
      expect(knocks, 1, reason: '计数由宿主持有(真源 properties.count),组件只抛 knock');
      expect(find.text('×18'), findsOneWidget, reason: '宿主没回传新计数前,组件不许自己加');
      await t.pump();
      expect(find.text('功德 +1'), findsOneWidget);
    });

    testWidgets('敲门那一下出「功德 +1」,600ms 后自己收(连点不排队)', (WidgetTester t) async {
      await t.pumpWidget(_host(PlayKitWoodfish(count: 0, onKnock: () {})));
      await t.tap(find.byKey(_stage));
      await t.pump();
      expect(find.text('功德 +1'), findsOneWidget);
      // 中途再敲:定时器重置,从这一敲起再计 600ms(真源 clearTimeout)。
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byKey(_stage));
      await t.pump(const Duration(milliseconds: 599));
      expect(find.text('功德 +1'), findsOneWidget, reason: '第二次敲击把飘字续到 600ms');
      await t.pump(const Duration(milliseconds: 2));
      expect(find.text('功德 +1'), findsNothing);
      // 真源 aria-label 原话(全角逗号),挂在台面那层 Semantics 上。
      final Semantics sem = t.widget<Semantics>(
        find.descendant(
          of: find.byType(PlayKitWoodfish),
          matching: find.byWidgetPredicate(
            (Widget w) =>
                w is Semantics &&
                (w.properties.label ?? '').startsWith('敲一下木鱼'),
          ),
        ),
      );
      expect(sem.properties.label, '敲一下木鱼，当前功德 0');
      expect(sem.properties.button, isTrue);
    });

    testWidgets('减动效走静态:飘字照出现但不动、木槌无过渡', (WidgetTester t) async {
      int knocks = 0;
      await t.pumpWidget(
        _host(
          PlayKitWoodfish(count: 0, onKnock: () => knocks++),
          disableAnimations: true,
        ),
      );
      await t.tap(find.byKey(_stage));
      await t.pump();
      // 真源 `.wf__stage--static .wf__merit { animation: none }`:飘字照出现,只是不动。
      expect(find.text('功德 +1'), findsOneWidget);
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
      expect(
        t.widget<AnimatedRotation>(find.byType(AnimatedRotation)).duration,
        Duration.zero,
      );
      await t.pump(const Duration(seconds: 1));
    });
  });

  group('③ 节点卡挂载(CardDetailPage)', () {
    testWidgets('ambient=woodfish 就挂;敲一下只在会话里 +1,全程零请求', (
      WidgetTester t,
    ) async {
      final _Api api = await _pumpCard(t, _node(ambient: 'woodfish'));
      expect(api.calls, 1);
      expect(find.byType(PlayKitWoodfish), findsOneWidget);
      expect(t.widget<PlayKitWoodfish>(find.byType(PlayKitWoodfish)).count, 0);

      await t.tap(find.byKey(_stage));
      await t.pump();
      expect(find.text('×1'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      expect(find.text('×1'), findsOneWidget);
      expect(api.calls, 1, reason: '计数纯本地:敲木鱼不许再发一次 /api/play/nodes,更不许发通关请求');
    });

    testWidgets('节点没有 ambient 就不挂(与真源同一条 wx:if),也不冒参考分卡', (
      WidgetTester t,
    ) async {
      await _pumpCard(t, _node());
      expect(find.byType(PlayKitWoodfish), findsNothing);
      expect(find.text('剧情氛围件 · 不判定通关'), findsNothing);
      expect(find.text('AI 参考分'), findsNothing);
    });
  });

  group('④ 会话内附加物(真源 page data 的生命周期)', () {
    test('计数按节点各记一份;敲一下只动本地字典,不碰服务端模型', () {
      final PlayNodeCardExtras extras = PlayNodeCardExtras();
      expect(extras.woodfishCount(51), 0);
      extras.knockWoodfish(51);
      extras.knockWoodfish(51);
      extras.knockWoodfish(52);
      expect(extras.woodfishCount(51), 2);
      expect(extras.woodfishCount(52), 1);
      expect(extras.aiScore(51), isNull);
    });

    test('applyPhotoReceipt 只收给了分的回执;null 不留痕', () {
      final PlayNodeCardExtras extras = PlayNodeCardExtras();
      extras.applyPhotoReceipt(51, null);
      expect(extras.aiScore(51), isNull);
      final PlayAiScore score = PlayAiScore(score: 88, comment: '构图可以更好');
      extras.applyPhotoReceipt(51, score);
      expect(extras.aiScore(51), same(score));
    });

    testWidgets('计数活过整趟游玩:卡片关掉再进不清零(真源是 page data)', (WidgetTester t) async {
      final _Api api = _Api(_node(ambient: 'woodfish'));
      t.view.physicalSize = const Size(390, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      // 根 ProviderScope 不重装配:换的只是 home 子树 —— 会话容器活着。
      ProviderScope scope({bool card = false}) => ProviderScope(
        overrides: <dynamic>[playApiProvider.overrideWithValue(api)].cast(),
        child: MaterialApp(home: _SessionShell(showCard: card)),
      );

      await t.pumpWidget(scope());
      await t.pumpAndSettle();
      expect(find.byType(CardDetailPage), findsNothing);
      await t.pumpWidget(scope(card: true));
      await t.pumpAndSettle();
      expect(find.byType(CardDetailPage), findsOneWidget);

      await t.tap(find.byKey(_stage));
      await t.pumpAndSettle();
      expect(find.text('×1'), findsOneWidget);
      expect(api.calls, 1, reason: '计数纯本地:敲木鱼不许再发一次 /api/play/nodes');

      // 关掉卡片(下一张还没开的那一帧)再进:真源里这份计数不清零。
      await t.pumpWidget(scope());
      await t.pumpAndSettle();
      expect(find.byType(CardDetailPage), findsNothing);
      await t.pumpWidget(scope(card: true));
      await t.pumpAndSettle();
      expect(find.text('×1'), findsOneWidget, reason: '附加物活在会话层,不活在组件里');
    });
  });

  group('⑤ AI 参考分(PlayAiScore / cy-ai-score-card)', () {
    test('score<=0 一律当「没给分」;数字下发成字符串也认;note 缺失落回真源默认句', () {
      expect(PlayAiScore.fromJson(null), isNull);
      expect(PlayAiScore.fromJson(<String, dynamic>{'score': 0}), isNull);
      expect(PlayAiScore.fromJson(<String, dynamic>{'score': -3}), isNull);
      // 后端数字常以 String 下发(契约测试同口径),92 就是 92。
      expect(PlayAiScore.fromJson(<String, dynamic>{'score': '92'})?.score, 92);
      final PlayAiScore? s = PlayAiScore.fromJson(<String, dynamic>{
        'score': 92,
        'comment': ' 拍得清楚 ',
      });
      expect(s, isNotNull);
      expect(s!.score, 92);
      expect(s.comment, '拍得清楚');
      expect(s.note, '最终以商家审核为准');
    });

    test('CheckinReward 解析照片回执里的 aiScore;没给就是 null', () {
      final CheckinReward withScore = CheckinReward.fromJson(<String, dynamic>{
        'nodeId': 51,
        'done': 1,
        'total': 3,
        'aiScore': <String, dynamic>{'score': 90, 'comment': '好'},
      });
      expect(withScore.aiScore, isNotNull);
      expect(withScore.aiScore!.score, 90);
      final CheckinReward bare = CheckinReward.fromJson(<String, dynamic>{
        'nodeId': 51,
        'done': 1,
        'total': 3,
      });
      expect(bare.aiScore, isNull);
    });

    testWidgets('分数卡纯展示:渲染分数/评语/尾注,不可点', (WidgetTester t) async {
      await t.pumpWidget(
        _host(
          const PlayAiScoreCard(
            score: PlayAiScore(score: 88, comment: '光影不错', note: '最终以商家审核为准'),
          ),
        ),
      );
      expect(find.text('88'), findsOneWidget);
      expect(find.text('AI 参考分'), findsOneWidget);
      expect(find.text('光影不错'), findsOneWidget);
      expect(find.text('最终以商家审核为准'), findsOneWidget);
      expect(
        find.byType(GestureDetector),
        findsNothing,
        reason: '真源刻意不带交互 —— 可点会误导成「点了能申诉」',
      );
      expect(find.byType(CupertinoButton), findsNothing);
    });
  });
}
