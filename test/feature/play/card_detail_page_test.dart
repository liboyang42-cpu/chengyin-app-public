import 'package:chengyin_app/core/map/map_launcher.dart';
import 'package:chengyin_app/core/theme/app_colors.dart';
import 'package:chengyin_app/core/widgets/cy_native_notice.dart';
import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/free_explore/card_detail_page.dart';
import 'package:chengyin_app/feature/play/free_explore/chapter_story_page.dart';
import 'package:chengyin_app/feature/play/free_explore/widgets/card_box_3d.dart';
import 'package:chengyin_app/feature/play/play_session_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../theme/contrast_test.dart' show composite, contrast;

const PlaySessionKey _key = (activityId: 77, topicId: null);

Map<String, dynamic> _node({
  bool arrived = false,
  bool selfReported = false,
  bool done = false,
  double? lat,
  double? lng,
}) => <String, dynamic>{
  'nodeId': 1,
  'name': '长乐路旧物店',
  'address': '长乐路 139 号',
  'sortId': 1,
  'chapterId': 100,
  'hookText': '你得先说出一个年份。',
  'arrived': arrived,
  'selfReported': selfReported,
  'done': done,
  'latitude': lat,
  'longitude': lng,
};

/// ★ 章节喂后端 `/api/play/nodes` 的真实键(name / imgArr / description / audioUrl,
/// **没有** meta/title/cover),整条走 PlayNodesResult.fromJson —— 用构造函数直接造
/// PlayChapter 会绕过解析层,键名错配就完全隐形(2026-09-09 三字段恒 null 即此)。
/// 眉标「第 N 章」按数组下标生成,所以摆两章让本节点(chapterId=100)落在第 2 章。
const List<Map<String, dynamic>> _chaps = <Map<String, dynamic>>[
  <String, dynamic>{'chapterId': 99, 'name': '晨间烘焙'},
  <String, dynamic>{'chapterId': 100, 'name': '旧书与唱片'},
];

/// 同一套章节,但第 2 章**写了剧情** —— 点卡片进故事流那几条要的正是这个。
const List<Map<String, dynamic>> _chapsStory = <Map<String, dynamic>>[
  <String, dynamic>{'chapterId': 99, 'name': '晨间烘焙'},
  <String, dynamic>{
    'chapterId': 100,
    'name': '旧书与唱片',
    'description': '第一段\n\n第二段',
  },
];

/// 详情页现在按 nodeId 从 provider 现读,所以固件走 PlayApi。
class _Api implements PlayApi {
  _Api(this.node, {this.chapters = _chaps});

  final Map<String, dynamic> node;
  final List<Map<String, dynamic>> chapters;

  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async =>
      PlayNodesResult.fromJson(<String, dynamic>{
        'topicId': 23,
        'mode': 2,
        'playable': true,
        'total': 1,
        'doneCount': node['done'] == true ? 1 : 0,
        'nodes': <dynamic>[node],
        'chapters': chapters,
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester t,
  Map<String, dynamic> n, {
  List<Map<String, dynamic>> chapters = _chaps,
  ValueChanged<PlayNode>? onPrimary,
  int nodeId = 1,
}) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        playApiProvider.overrideWithValue(_Api(n, chapters: chapters)),
      ].cast(),
      child: MaterialApp(
        home: CardDetailPage(
          sessionKey: _key,
          nodeId: nodeId,
          onPrimary: onPrimary ?? (PlayNode _) {},
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

/// 点卡盒。★ 不用 `tap(find.byType(CardBox3d))`:卡盒高 = 宽×1.38,它的中心在
/// 800×600 的测试视口**之外**(而且被底部 CTA 盖着),按中心点会打在 CTA 上。
/// ⚠️ 进了故事流之后**不许 pumpAndSettle** —— `StoryDust` 是无限 ticker,必然 timeout。
Future<void> _tapCard(WidgetTester t) async {
  await t.tapAt(const Offset(400, 200));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400)); // 转场 + 开页 30ms
}

/// 导航行排在正文靠后的位置,800×600 的测试视口里天然在屏幕外 —— 不先滚过去
/// `tap` 会打在空处(实测 Offset(740.8, 1295.3),hit test 落到 RenderView)。
Future<void> _tapNav(WidgetTester t) async {
  await t.ensureVisible(find.text('导航'));
  await t.pumpAndSettle();
  await t.tap(find.text('导航'));
  await t.pumpAndSettle();
}

void main() {
  tearDown(CyNativeNotice.hide);

  testWidgets('章节头取 chapter,不是 node.name', (WidgetTester t) async {
    await _pump(t, _node());
    expect(find.text('旧书与唱片'), findsOneWidget);
    expect(find.text('长乐路旧物店'), findsOneWidget); // 店名只作为店铺行出现一次
  });

  testWidgets('★chapter 为 null 时不渲染章节头,且不拿店名冒充', (WidgetTester t) async {
    await _pump(t, _node(), chapters: const <Map<String, dynamic>>[]);
    expect(find.text('第 2 章'), findsNothing);
    expect(find.text('长乐路旧物店'), findsOneWidget, reason: '店名不许被当成章节名多渲染一次');
  });

  testWidgets('★小瘾说是独立标签,不是拼进正文的字符串', (WidgetTester t) async {
    await _pump(t, _node());
    expect(find.text('小瘾说'), findsOneWidget, reason: '标签必须能单独找到,不能和正文拼在一起');
    expect(find.text('小瘾说:你得先说出一个年份。'), findsNothing, reason: '不许拼冒号');
  });

  testWidgets('到店三步三行都在,亮灯跟着状态走', (WidgetTester t) async {
    await _pump(t, _node(arrived: true));
    expect(find.text('扫描门店码 · 记录到店时间'), findsOneWidget);
    expect(find.text('拍摄现场凭证 · 到店后显示拍摄要求'), findsOneWidget);
    expect(find.text('商家核销 · 核销那一刻才算服务开始'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('onsite-step-done-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('onsite-step-done-1')),
      findsNothing,
    );
  });

  testWidgets('★主 CTA 点得动,回调真被调用', (WidgetTester t) async {
    int hit = 0;
    await _pump(t, _node(), onPrimary: (PlayNode _) => hit++);
    await t.tap(find.text('开始互动 获得奖励！'));
    await t.pump();
    expect(hit, 1, reason: 'CTA 不接回调就是个假按钮');
  });

  testWidgets('★已核销:CTA 是禁用态且点不动', (WidgetTester t) async {
    int hit = 0;
    await _pump(
      t,
      _node(arrived: true, selfReported: true, done: true),
      onPrimary: (PlayNode _) => hit++,
    );
    // ★ 段②店铺卡的状态行同样会显示「已核销」(与 CTA 各自表达一个意思，
    //   与小程序 .fx-shop__off 同款)，所以这里定位到 CTA 本身，不用裸 find.text。
    final Finder cta = find.descendant(
      of: find.byType(CupertinoButton),
      matching: find.text('已核销'),
    );
    expect(cta, findsOneWidget, reason: 'done 的文案由页面按现读状态自己算');
    await t.tap(cta, warnIfMissed: false);
    await t.pump();
    expect(hit, 0, reason: '已核销还能点 = 会去重复发起核销');
  });

  testWidgets('★nodeId 在会话里找不到时给兜底,不崩也不给假 CTA', (WidgetTester t) async {
    await _pump(t, _node(), nodeId: 999);
    expect(find.textContaining('这张卡片暂时读不到'), findsOneWidget);
    expect(find.text('开始互动 获得奖励！'), findsNothing, reason: '读不到节点还给 CTA = 假按钮');
  });

  testWidgets('★卡背长介绍不炸 RenderFlex(紧约束里得靠 Flexible+maxLines）', (
    WidgetTester t,
  ) async {
    final Map<String, dynamic> longChapter = <String, dynamic>{
      'chapterId': 100,
      'name': '旧书与唱片',
      'description': List<String>.filled(800, '描').join(),
    };
    await _pump(
      t,
      _node(),
      chapters: <Map<String, dynamic>>[_chaps.first, longChapter],
    );
    // 拖过半圈翻到背面（ry += dx*0.8，越过 90° 需 dx > 112.5），长介绍在这一面。
    // ★ 起点写死在卡面上,不用 drag(find.byType(CardBox3d)) —— 卡盒高 = 宽×1.38,
    //   它的中心在 800×600 的测试视口外(而且被底部 CTA 条盖着),按中心点拖会
    //   打在 CTA 上,这一条就退化成「什么都没做,当然不抛异常」的空跑。
    await t.dragFrom(const Offset(400, 200), const Offset(160, 0));
    await t.pumpAndSettle();
    expect(find.byType(CardBox3d), findsOneWidget);
    expect(
      find.textContaining('描描描'),
      findsOneWidget,
      reason: '没真翻到背面,这条测的就不是长介绍',
    );
    // ★ 这一章是有剧情的(800 个「描」),所以横拖要是误触发了点击,现在会进故事流。
    //   顺手当「拖转不误触发进页」的负控用。
    expect(
      find.byType(ChapterStoryPage),
      findsNothing,
      reason: '横拖是翻卡面,一拖就进故事流的话卡背根本看不成',
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('★内容不满屏时,CTA 仍贴在屏幕底部(不悬空)', (WidgetTester t) async {
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.binding.setSurfaceSize(const Size(390, 1900));
    // 无游戏段/无权益/短章节的最小 fixture,内容天然矮于视口。
    await _pump(t, _node());
    final double screenBottom = t.getRect(find.byType(MaterialApp)).bottom;
    final double ctaBottom = t.getRect(find.byType(CupertinoButton)).bottom;
    expect(
      screenBottom - ctaBottom,
      lessThanOrEqualTo(80),
      reason: 'Stack 不撑满视口时,Positioned(bottom: 0) 贴的是内容的底而非屏幕的底',
    );
  });

  testWidgets('★禁用态 CTA 用占位色字,不是压在中性底上看不见的墨字', (WidgetTester t) async {
    await _pump(t, _node(arrived: true, selfReported: true, done: true));
    final CupertinoButton cta = t.widget<CupertinoButton>(
      find.byType(CupertinoButton),
    );
    // 暗色 bgSubtle = 白 4% 叠 #0A0A0A ≈ #151517;actionPrimaryFg = #0A0A0A,
    // 两者对比度 1.08:1 —— 沿用它「已核销」三个字就是隐形的。
    // 原型 .btn--disabled 规定的是占位色字 + 中性底,这里照抄。
    expect(cta.disabledColor, CyTokens.bgSubtle);
    expect(
      cta.foregroundColor,
      CyTokens.textPlaceholder,
      reason: '禁用不等于隐形:字要读得出来才叫禁用态',
    );
  });

  testWidgets('★可点态 CTA 的字读得出来(按对比度判,不是拿常量对常量)', (WidgetTester t) async {
    await _pump(t, _node());
    final CupertinoButton cta = t.widget<CupertinoButton>(
      find.byType(CupertinoButton),
    );
    // ★ 两类断言管不同的事,都要有(2026-09-09 裁决更正):
    //   · 常量断言挡「有人手改成别的颜色」—— 主 CTA 必须是这对 token,不是随便哪对;
    //   · 对比度断言挡「颜色本身不可读」—— 换了绿底黑字常量断言会红,但只有它能说明为什么。
    //   上一版只留了对比度那条,于是没有任何断言钉主 CTA 用哪对 token(禁用态两条都留着,
    //   两态处置不对称)。
    expect(cta.color, CyTokens.actionPrimaryBg);
    expect(cta.foregroundColor, CyTokens.actionPrimaryFg);
    expect(
      contrast(cta.foregroundColor!, cta.color!),
      greaterThanOrEqualTo(4.5),
      reason: '主 CTA 字底对比度不足 —— 「开始互动」在按钮上读不出来',
    );
  });

  testWidgets('★禁用态的字同样要读得出来', (WidgetTester t) async {
    await _pump(t, _node(arrived: true, selfReported: true, done: true));
    final CupertinoButton cta = t.widget<CupertinoButton>(
      find.byType(CupertinoButton),
    );
    // 禁用可以弱,但不能隐形。
    // ★ disabledColor = bgSubtle = Color(0x0AFFFFFF),**半透明**:不先合成到页面底
    //   (bgDeep)上就比对比度,等于拿「纯白按钮底」在比 —— 那是屏幕上不存在的颜色,
    //   任何深色字都轻松过关,这条断言就恒绿。上一版正是漏了 composite:把
    //   foregroundColor 手改回 actionPrimaryFg(#0A0A0A,压在合成后的底上只有 1.00:1)
    //   它照样绿。合成后底 ≈ #0A0A0A,这条才真的能红。
    expect(
      contrast(
        cta.foregroundColor!,
        composite(cta.disabledColor, AppColors.bgDeep),
      ),
      greaterThanOrEqualTo(3.0),
      reason: '禁用不等于隐形:字要读得出来才叫禁用态',
    );
  });

  group('★卡盒上的竖向手势要整套转交给正文,不只是 drag', () {
    /// 正文那个 SingleChildScrollView 的滚动位置。卡盒自己不滚,读的必须是它。
    ScrollPosition body(WidgetTester t) => t
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          ),
        )
        .position;

    /// 甩一把,停在惯性里。★ 力度必须小到 `pixels` 还没越过 202
    /// (`cardCollapse` 在 p>0.92 即 scrollTop>202.4 时把卡盒 `IgnorePointer` 掉)——
    /// 甩过头的话后面那一按根本没打在卡盒上,整条测试退化成「正文自己刹住了」的恒绿。
    Future<double> coast(WidgetTester t) async {
      await t.flingFrom(const Offset(400, 200), const Offset(0, -80), 300);
      await t.pump(); // 起惯性
      await t.pump(const Duration(milliseconds: 60));
      final double px = body(t).pixels;
      expect(px, greaterThan(0), reason: '没甩动就没有惯性可刹,这条会退化成空跑');
      expect(
        px,
        lessThan(200),
        reason: '越过 202 卡盒就被 IgnorePointer 掉了,按下打不到它 —— 断言会假绿',
      );
      return px;
    }

    testWidgets('★甩起来之后按住卡盒必须刹得住(hold 转交)', (WidgetTester t) async {
      await _pump(t, _node());
      final double coasting = await coast(t);
      // 手指按回卡盒 —— 只按下,不拖。(400,200) 在卡盒范围内(left 20,宽 760)。
      final TestGesture g = await t.startGesture(const Offset(400, 200));
      await t.pump(const Duration(milliseconds: 300));
      expect(
        body(t).pixels,
        coasting,
        reason: '按住卡盒刹不住惯性 = onVerticalDragDown 没把 position.hold() 转交过去',
      );
      await g.up();
      await t.pumpAndSettle();
    });

    testWidgets('★竖拖卡盒照样滚正文,而且不误触发进故事流', (WidgetTester t) async {
      await _pump(t, _node(), chapters: _chapsStory);
      final double before = body(t).pixels;
      await t.dragFrom(const Offset(400, 200), const Offset(0, -120));
      await t.pumpAndSettle();
      expect(body(t).pixels, greaterThan(before), reason: '竖向转交坏了 = 上半屏滚不动');
      expect(
        find.byType(ChapterStoryPage),
        findsNothing,
        reason: '竖拖一下就进故事流的话,上半屏根本没法滚',
      );
    });

    testWidgets('★对照组:按住卡盒**外面**的正文本来就刹得住(证明测的是转交不是滚动本身)', (
      WidgetTester t,
    ) async {
      await _pump(t, _node());
      final double coasting = await coast(t);
      // x=8 在卡盒左边距外(卡盒 left=20),这条指针直接落进正文自己的 Scrollable。
      final TestGesture g = await t.startGesture(const Offset(8, 300));
      await t.pump(const Duration(milliseconds: 300));
      expect(body(t).pixels, coasting);
      await g.up();
      await t.pumpAndSettle();
    });
  });

  group('★点卡片进章节故事流(样机 openChapStory,index.js:1013)', () {
    testWidgets('点一下卡盒就进故事流', (WidgetTester t) async {
      await _pump(t, _node(), chapters: _chapsStory);
      await _tapCard(t);
      expect(find.byType(ChapterStoryPage), findsOneWidget);
    });

    testWidgets('★卡盒是一个可点的无障碍节点:标签 + tap 动作在同一个节点上', (
      WidgetTester t,
    ) async {
      final SemanticsHandle handle = t.ensureSemantics();
      await _pump(t, _node(), chapters: _chapsStory);
      // ★ 锚点取**真正处理点击的那个** GestureDetector:标签挂在它外面的
      //   Semantics 上,两者没合成同一个节点的话,读屏用户听到的是一段没有
      //   动作的文字。中间被谁插一层(自带 container 的 Semantics、
      //   BlockSemantics……)就会静默退化成两个节点。
      final Finder tapper = find
          .ancestor(
            of: find.byType(CardBox3d),
            matching: find.byType(GestureDetector),
          )
          .first;
      final SemanticsNode node = t.getSemantics(tapper);
      expect(
        node,
        isSemantics(
          // 样机 index.wxml:363 的 aria-label 原话(标点照抄)。
          label: '读这一章的剧情;左右拖可以转动卡片',
          isButton: true,
          hasTapAction: true,
        ),
      );
      // 光有 flag 还不算数:用无障碍的 tap 走一遍,证明它真能被读屏点开。
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(ChapterStoryPage), findsOneWidget);
      handle.dispose();
    });

    testWidgets('★这一章没写剧情:不进页,给一句提示', (WidgetTester t) async {
      // 默认 fixture 的第 2 章没有 description。
      await _pump(t, _node());
      await _tapCard(t);
      expect(
        find.byType(ChapterStoryPage),
        findsNothing,
        reason: '开一页空白比不开更像坏了(样机 index.js:1016)',
      );
      expect(find.text('这一章还没写剧情'), findsOneWidget);
      // ★ 中性态,不是错误态(样机 index.js:1016 用的就是中性 cyToast)。
      //   「作者没写内容」是一条告知 —— 报错样式会让人以为是自己点坏了。
      expect(
        find.byIcon(CupertinoIcons.check_mark_circled_solid),
        findsOneWidget,
      );
      expect(
        find.byIcon(CupertinoIcons.exclamationmark_circle_fill),
        findsNothing,
        reason: 'isError:true 会走红色警示图标 + heavyImpact',
      );
    });

    testWidgets('★故事流的主 CTA 接的是详情页同一个回调,不是假按钮', (WidgetTester t) async {
      int hit = 0;
      await _pump(
        t,
        _node(),
        chapters: _chapsStory,
        onPrimary: (PlayNode _) => hit++,
      );
      await _tapCard(t);
      // 详情页自己的 CTA 文案一样,所以定位到故事流那棵子树里的那颗。
      await t.tap(
        find.descendant(
          of: find.byType(ChapterStoryPage),
          matching: find.text('开始互动 获得奖励！'),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 400)); // 退场转场
      expect(hit, 1, reason: '透传断了 = 故事流底部那颗主按钮点下去没有去处');
    });
  });

  testWidgets('★到店三步有段眉标 —— 邻居三段都有,只剩它光着是视觉断层', (WidgetTester t) async {
    await _pump(t, _node());
    expect(find.text('到店三步'), findsOneWidget);
  });

  group('★导航入口照样机:有地址就渲,坐标的事用提示回答', () {
    testWidgets('有坐标:「导航」在', (WidgetTester t) async {
      await _pump(t, _node(lat: 31.21, lng: 121.45));
      expect(find.text('导航'), findsOneWidget);
    });

    testWidgets('★没有坐标也照渲「导航」—— 整行不渲染=用户不知道有这回事', (WidgetTester t) async {
      await _pump(t, _node());
      expect(
        find.text('导航'),
        findsOneWidget,
        reason: '样机 .fx-shop__nav 的 wx:if 只看 address(index.wxml:420)',
      );
      expect(find.text('长乐路 139 号'), findsOneWidget);
    });

    testWidgets('★没有坐标时点导航:给一句解释,不打开一张空白地图', (WidgetTester t) async {
      await _pump(t, _node());
      await _tapNav(t);
      // 断言走共享文案本身,不写死字面量:文案改了这里跟着走,
      // 但「同一情况全 App 只有一种措辞」这条契约仍被钉住。
      expect(
        find.text(mapLaunchMessage(MapLaunchResult.noCoordinates)),
        findsOneWidget,
        reason: '样机 openHeroNav(index.js:1517)要给提示;措辞与全 App 另外 5 处统一',
      );
    });

    testWidgets('★坐标是 0/0 也算没有 —— 导过去是几内亚湾', (WidgetTester t) async {
      await _pump(t, _node(lat: 0, lng: 0));
      await _tapNav(t);
      expect(
        find.text(mapLaunchMessage(MapLaunchResult.noCoordinates)),
        findsOneWidget,
      );
    });
  });
}
