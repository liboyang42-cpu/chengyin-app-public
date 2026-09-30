import 'package:chengyin_app/data/models/shop_npc_models.dart';
import 'package:chengyin_app/feature/play/free_explore/shop_npc_logic.dart';
import 'package:chengyin_app/feature/play/free_explore/widgets/npc_message_list.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// ⚠️ `ShopNpcMessage` **故意没有 fromJson**(它是本端自攒的消息,后端没有端点
/// 返回这个形状)。所以这里用构造函数造 —— 编一个 fromJson 再拿它喂测试才是假 fixture。
int _seq = 0;
ShopNpcMessage _me(String t) => ShopNpcMessage(id: ++_seq, mine: true, text: t);
ShopNpcMessage _ai(String t) =>
    ShopNpcMessage(id: ++_seq, mine: false, text: t);

String? _copied;
int? _retried;

Future<void> _pump(
  WidgetTester t,
  List<ShopNpcMessage> msgs, {
  bool thinking = false,
  String npcName = '阿旧',
  bool reduceMotion = false,
}) {
  return t.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Center(
          child: SizedBox(
            width: 375,
            height: 400,
            child: NpcMessageList(
              messages: msgs,
              npcName: npcName,
              thinking: thinking,
              onCopy: (String s) => _copied = s,
              onRetry: (int i) => _retried = i,
            ),
          ),
        ),
      ),
    ),
  );
}

/// 沿着这条文字往上找**带底色**的容器。
///
/// ⚠️ 只认 `color != null` 的 [BoxDecoration]:`CupertinoButton` 自己也会建一个
/// `DecoratedBox`,但它的 `color` 是 null —— 不排掉的话「对方没有气泡」这条会恒真地绿。
BoxDecoration? _capsuleOf(WidgetTester t, String text) {
  for (final Element e
      in find
          .ancestor(of: find.text(text), matching: find.byType(DecoratedBox))
          .evaluate()) {
    final Decoration d = (e.widget as DecoratedBox).decoration;
    if (d is BoxDecoration && d.color != null) return d;
  }
  return null;
}

/// 完整落在滚动视口里(不是「有交集」—— 露半行不算滚到底)。
bool _isVisible(WidgetTester t, Finder f) {
  final Rect r = t.getRect(f);
  final Rect view = t.getRect(find.byKey(const Key('npc-msg-list')));
  return r.top >= view.top - 0.5 && r.bottom <= view.bottom + 0.5;
}

void main() {
  setUp(() {
    _seq = 0;
    _copied = null;
    _retried = null;
  });

  testWidgets('★对方消息不套气泡,我方才是胶囊', (WidgetTester t) async {
    await _pump(t, <ShopNpcMessage>[_ai('九点关门'), _me('知道了')]);
    expect(_capsuleOf(t, '知道了'), isNotNull);
    expect(
      _capsuleOf(t, '九点关门'),
      isNull,
      reason: '对方套上气泡就成了双方对称的聊天软件,不是样机那种「分身在说话」',
    );
  });

  testWidgets('★只有对方消息挂「复制」「重答」', (WidgetTester t) async {
    await _pump(t, <ShopNpcMessage>[_ai('长乐路 88 号'), _me('谢谢')]);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('重答'), findsOneWidget);
    // 挂在对方那条下面,不是我方
    expect(
      find.ancestor(
        of: find.text('复制'),
        matching: find.byKey(const Key('npc-msg-ai-1')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('npc-msg-me-2')),
        matching: find.text('重答'),
      ),
      findsNothing,
    );
  });

  testWidgets('★两个操作都是文字不是图标', (WidgetTester t) async {
    await _pump(t, <ShopNpcMessage>[_ai('九点')]);
    // 图标集是生成物(scripts/ds-build-icons.py,源 coolicons)不许手改,
    // 里面没有「复制」字形;硬拿别的图标顶会比文字更难认(样机 index.wxml:541 注释)。
    final Finder ops = find.byKey(const Key('npc-msg-ops'));
    expect(find.descendant(of: ops, matching: find.byType(Icon)), findsNothing);
    expect(
      find.descendant(of: ops, matching: find.byType(Text)),
      findsNWidgets(2),
    );
  });

  testWidgets('★两个操作的命中区都不小于 44pt', (WidgetTester t) async {
    await _pump(t, <ShopNpcMessage>[_ai('九点')]);
    for (final String label in <String>['复制', '重答']) {
      final Size s = t.getSize(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(CupertinoButton),
        ),
      );
      expect(s.height, greaterThanOrEqualTo(44), reason: '$label 的命中区高不够');
      expect(s.width, greaterThanOrEqualTo(44), reason: '$label 的命中区宽不够');
    }
  });

  testWidgets('★两个操作真的回调出去(不是画着好看的死字)', (WidgetTester t) async {
    await _pump(t, <ShopNpcMessage>[_me('几点关门'), _ai('九点关门')]);
    await t.tap(find.text('复制'));
    expect(_copied, '九点关门');
    await t.tap(find.text('重答'));
    expect(_retried, 1, reason: '回调带的是这条回答在 msgs 里的下标,页面要拿它往前找提问');
  });

  testWidgets('★等待名条 1200ms 后换第二拍', (WidgetTester t) async {
    await _pump(t, const <ShopNpcMessage>[], thinking: true, npcName: '阿旧');
    expect(find.text('阿旧 正在输入…'), findsOneWidget);
    await t.pump(kThinkPhaseDelay);
    expect(
      find.text('阿旧 正在回答'),
      findsOneWidget,
      reason: '一句话不动地挂着,超过一秒就像卡住了;换一拍是在说「还在,只是慢」',
    );
    expect(find.text('阿旧 正在输入…'), findsNothing);
  });

  testWidgets('★负控:不到 1200ms 不许提前换拍', (WidgetTester t) async {
    await _pump(t, const <ShopNpcMessage>[], thinking: true);
    await t.pump(kThinkPhaseDelay - const Duration(milliseconds: 1));
    expect(find.text('阿旧 正在输入…'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 1));
    expect(find.text('阿旧 正在回答'), findsOneWidget);
  });

  testWidgets('★不在等的时候没有名条', (WidgetTester t) async {
    await _pump(t, <ShopNpcMessage>[_ai('九点')]);
    expect(find.byKey(const Key('npc-msg-thinking')), findsNothing);
  });

  testWidgets('★新消息进来滚到底', (WidgetTester t) async {
    await _pump(
      t,
      List<ShopNpcMessage>.generate(
        20,
        (int i) => i.isEven ? _me('问 $i') : _ai('答 $i'),
      ),
    );
    await t.pumpAndSettle();
    // ⚠️ 先断言它被建出来了:`ListView.builder` 不给视口外的行建 widget,
    //   直接 getRect 会抛异常 —— 那是「测试出错」不是「断言变红」,
    //   拿不到能看的红,以后回归就分不清是哪一种。
    expect(find.text('答 19'), findsOneWidget, reason: '没滚到底的话最后一条压根没被构建');
    expect(_isVisible(t, find.text('答 19')), isTrue);
  });

  testWidgets('★负控:第一条早滚出视口了(上面那条不是「反正全都看得见」)', (
    WidgetTester t,
  ) async {
    await _pump(
      t,
      List<ShopNpcMessage>.generate(
        20,
        (int i) => i.isEven ? _me('问 $i') : _ai('答 $i'),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('问 0'), findsNothing);
  });

  testWidgets('★降低动态:操作行、名条、消息一个都不许藏', (WidgetTester t) async {
    await _pump(
      t,
      <ShopNpcMessage>[_ai('长乐路 88 号'), _me('谢谢')],
      thinking: true,
      reduceMotion: true,
    );
    expect(find.text('长乐路 88 号'), findsOneWidget);
    expect(find.text('谢谢'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('重答'), findsOneWidget);
    expect(find.text('阿旧 正在输入…'), findsOneWidget);
    await t.tap(find.text('复制'));
    expect(_copied, '长乐路 88 号', reason: '★降级不许把操作变成 IgnorePointer 下的死字');
    await t.pump(kThinkPhaseDelay);
  });

  testWidgets('★重答原地改写:id 不变的那次不当成新消息', (WidgetTester t) async {
    final List<ShopNpcMessage> msgs = <ShopNpcMessage>[
      _me('几点关门'),
      _ai('九点'),
    ];
    await _pump(t, msgs);
    await t.pumpAndSettle();
    final List<ShopNpcMessage> rewritten = <ShopNpcMessage>[
      msgs[0],
      msgs[1].copyWithText('九点半，最后一单八点五十'),
    ];
    await _pump(t, rewritten);
    await t.pump();
    expect(find.text('九点半，最后一单八点五十'), findsOneWidget);
    expect(find.byKey(const Key('npc-msg-ai-2')), findsOneWidget, reason: 'id 原样带过去');
    expect(find.text('九点'), findsNothing);
  });

  testWidgets('★★重答原地改写**不许把列表拽到底** —— 玩家可能正往回翻旧回答', (
    WidgetTester t,
  ) async {
    // 上面那条只钉了「文案换了、id 没换」;反向的那一半 —— **滚动位置没动** ——
    // 一直没有断言。把 `didUpdateWidget` 里的条件改成无条件 `_scheduleScrollToEnd()`,
    // 全仓仍然全绿,而那正是这条产品口径本身。
    //
    // ⚠️⚠️ **必须走完页面 `_retry` 的三步**:`thinking: false → true`(点下那一刻,
    //   消息一条没变)→ `false` + 原地改写。只钉最后一步的话,滚动条件里
    //   `|| widget.thinking != oldWidget.thinking` 那半边在**第一步**就把列表拽到底,
    //   而测试全程按住 `thinking` 不动 ⇒ 照样绿(2026-09-10 复审实测:600 → 1027)。
    //   这就是本项目第 9 种假绿:**只走了 `||` 的一半**。
    final List<ShopNpcMessage> msgs = List<ShopNpcMessage>.generate(
      20,
      (int i) => i.isEven ? _me('问 $i') : _ai('答 $i'),
    );
    await _pump(t, msgs);
    await t.pumpAndSettle();

    // ★ 先离开底部。不离开的话「没滚」和「本来就在底」是同一个数,
    //   无条件滚也照样绿(假绿⑥:采样点落在两种实现的公共解上)。
    await t.drag(find.byKey(const Key('npc-msg-list')), const Offset(0, 400));
    await t.pumpAndSettle();
    final double before = _offset(t);
    expect(before, lessThan(_maxExtent(t) - 1), reason: '前提:这一刻确实不在底部');

    // ① 点「重答」那一刻:`thinking` 变真,消息**一条没变**。
    await _pump(t, msgs, thinking: true);
    await t.pumpAndSettle();
    expect(
      _offset(t),
      before,
      reason: '手指还没抬,列表就被「正在输入…」那一行拽到底 —— 正在看的那条旧回答当场消失',
    );

    // ② 回答落地:原地改写 + `thinking` 归 false。
    await _pump(t, <ShopNpcMessage>[
      ...msgs.sublist(0, 19),
      msgs[19].copyWithText('答 19（重答）'),
    ]);
    await t.pumpAndSettle();

    expect(
      _offset(t),
      before,
      reason: '重答是原地改写,硬滚到底会把玩家正在看的那条旧回答一把拽走',
    );
  });

  testWidgets('★负控前提:**新**消息进来照样滚到底(证明上一条测的不是「从来不滚」)', (
    WidgetTester t,
  ) async {
    final List<ShopNpcMessage> msgs = List<ShopNpcMessage>.generate(
      20,
      (int i) => i.isEven ? _me('问 $i') : _ai('答 $i'),
    );
    await _pump(t, msgs);
    await t.pumpAndSettle();
    await t.drag(find.byKey(const Key('npc-msg-list')), const Offset(0, 400));
    await t.pumpAndSettle();
    expect(_offset(t), lessThan(_maxExtent(t) - 1), reason: '前提:先离开底部');

    // 追加一条(**新 id**)。
    await _pump(t, <ShopNpcMessage>[...msgs, _ai('新答')]);
    await t.pumpAndSettle();

    // ⚠️ 不拿 `_maxExtent` 当靶子:`ListView.builder` 的 maxScrollExtent 是**估算值**,
    //   会随着后面的行被真正建出来而变(实测 1073.2 → 1084.0),
    //   那种红是「估算值抖了」不是「没滚到底」。断「新那条看得见」才是这条要的。
    expect(
      find.text('新答'),
      findsOneWidget,
      reason: '把「不滚」写死成「从来不滚」的话,新消息连建都不会建',
    );
    expect(
      _isVisible(t, find.text('新答')),
      isTrue,
      reason: '新消息永远看不见 —— 那是另一个 bug',
    );
  });
}

/// 列表当前的滚动位置。`ListView.controller` 就是组件自己那一个,不另找。
double _offset(WidgetTester t) => t
    .widget<ListView>(find.byKey(const Key('npc-msg-list')))
    .controller!
    .offset;

double _maxExtent(WidgetTester t) => t
    .widget<ListView>(find.byKey(const Key('npc-msg-list')))
    .controller!
    .position
    .maxScrollExtent;
