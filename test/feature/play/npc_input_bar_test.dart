import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/feature/play/free_explore/widgets/npc_input_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

String? _sent;
final List<bool> _voice = <bool>[];

Future<void> _pump(
  WidgetTester t, {
  bool recording = false,
  bool thinking = false,
  bool withVoice = true,
  String npcName = '阿旧',
}) {
  return t.pumpWidget(
    CupertinoApp(
      home: CupertinoPageScaffold(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 375,
            child: NpcInputBar(
              npcName: npcName,
              recording: recording,
              thinking: thinking,
              onSend: (String s) => _sent = s,
              onVoice: withVoice ? (bool holding) => _voice.add(holding) : null,
            ),
          ),
        ),
      ),
    ),
  );
}

/// 找这个 key 底下那个**带底色**的容器。
///
/// ⚠️ 只认 `color != null` 的 [BoxDecoration]:`CupertinoButton` 自己也会建一个
/// `DecoratedBox`(color 为 null)—— 不排掉的话「录音态高亮」那条会取到它,
/// 变成一条恒真的绿。
BoxDecoration? _fillOf(WidgetTester t, Key k) {
  for (final Element e
      in find
          .descendant(of: find.byKey(k), matching: find.byType(DecoratedBox))
          .evaluate()) {
    final Decoration d = (e.widget as DecoratedBox).decoration;
    if (d is BoxDecoration && d.color != null) return d;
  }
  return null;
}

CupertinoTextField _field(WidgetTester t) =>
    t.widget<CupertinoTextField>(find.byType(CupertinoTextField));

void main() {
  setUp(() {
    _sent = null;
    _voice.clear();
  });

  testWidgets('★打字框吃满 200 字就不再往里进(样机 maxlength=200)', (WidgetTester t) async {
    await _pump(t);
    await t.enterText(find.byType(CupertinoTextField), 'x' * 250);
    await t.pump();
    // 断行为不断参数:断 `maxLength == 200` 只证明我写了这个数字,
    // 证明不了它真的拦住了第 201 个字。
    expect(_field(t).controller!.text.length, 200);
  });

  testWidgets('★回车即发,发完框自己清空', (WidgetTester t) async {
    await _pump(t);
    await t.enterText(find.byType(CupertinoTextField), '几点关门');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pump();
    expect(_sent, '几点关门');
    expect(_field(t).controller!.text, isEmpty);
  });

  testWidgets('★发送键在输入为空时置灰,而且点了不发', (WidgetTester t) async {
    await _pump(t);
    // 先确认它**在**——只断「点了没反应」的话,按钮被整个删掉也会绿。
    expect(find.byKey(const Key('npc-input-send')), findsOneWidget);
    expect(
      t.widget<Opacity>(find.byKey(const Key('npc-input-send-dim'))).opacity,
      0.35,
    );
    await t.tap(find.byKey(const Key('npc-input-send')));
    await t.pump();
    expect(_sent, isNull, reason: '空文本发出去,后端拿到一句空话');

    await t.enterText(find.byType(CupertinoTextField), '有停车位吗');
    await t.pump();
    expect(
      t.widget<Opacity>(find.byKey(const Key('npc-input-send-dim'))).opacity,
      1.0,
    );
    await t.tap(find.byKey(const Key('npc-input-send')));
    await t.pump();
    expect(_sent, '有停车位吗');
  });

  testWidgets('★只有空白也算空(样机 sendShopNpc 先 trim 再判)', (WidgetTester t) async {
    await _pump(t);
    await t.enterText(find.byType(CupertinoTextField), '   ');
    await t.pump();
    expect(
      t.widget<Opacity>(find.byKey(const Key('npc-input-send-dim'))).opacity,
      0.35,
    );
    await t.tap(find.byKey(const Key('npc-input-send')));
    await t.pump();
    expect(_sent, isNull);
  });

  testWidgets('★等分身回答时发送置灰,且**不清空**已经打好的字', (WidgetTester t) async {
    await _pump(t, thinking: true);
    await t.enterText(find.byType(CupertinoTextField), '再问一句');
    await t.pump();
    await t.tap(find.byKey(const Key('npc-input-send')));
    await t.pump();
    expect(_sent, isNull);
    expect(
      _field(t).controller!.text,
      '再问一句',
      reason: '发被挡下了却把框清了,等于玩家白打一遍——样机 sendShopNpc 早退时 input 原样留着',
    );
  });

  testWidgets('★不传 onVoice 就不渲染麦克风,不留一个点了没反应的按钮', (WidgetTester t) async {
    await _pump(t, withVoice: false);
    expect(find.byKey(const Key('npc-input-mic')), findsNothing);
    // 打字那一半必须还在——语音没接不该把输入条也一起端走。
    expect(find.byType(CupertinoTextField), findsOneWidget);
    expect(find.byKey(const Key('npc-input-send')), findsOneWidget);
  });

  testWidgets('★按下抬起各回一次:按住说话与打字并列在同一条输入框里', (WidgetTester t) async {
    await _pump(t);
    // 样机注释:「所以『点了语音回不了打字』在结构上不成立:输入框一直在,
    // 语音只是它旁边的另一个入口」。
    expect(find.byType(CupertinoTextField), findsOneWidget);
    expect(find.byKey(const Key('npc-input-mic')), findsOneWidget);

    final TestGesture g = await t.startGesture(
      t.getCenter(find.byKey(const Key('npc-input-mic'))),
    );
    await t.pump();
    expect(_voice, <bool>[true]);
    await g.up();
    await t.pump();
    expect(_voice, <bool>[true, false]);
  });

  testWidgets('★手势被打断也要收尾,否则录音一直挂着', (WidgetTester t) async {
    await _pump(t);
    final TestGesture g = await t.startGesture(
      t.getCenter(find.byKey(const Key('npc-input-mic'))),
    );
    await t.pump();
    await g.cancel();
    await t.pump();
    expect(_voice, <bool>[true, false]);
  });

  testWidgets('★等分身回答时按下不开录(样机 onVoiceStart 见 thinking 就早退)', (
    WidgetTester t,
  ) async {
    await _pump(t, thinking: true);
    final TestGesture g = await t.startGesture(
      t.getCenter(find.byKey(const Key('npc-input-mic'))),
    );
    await t.pump();
    await g.up();
    await t.pump();
    // ⚠️ 断「没有开录」而不是「一次回调都没有」:收尾那条边**故意**放行
    //   (样机 `onVoiceEnd` 也不判 thinking),重复收尾由 `ShopNpcVoice.stop()`
    //   自己的 `if (!_recording) return` 挡 —— 下一条测的就是那条边为什么不能挡。
    expect(
      _voice.where((bool holding) => holding),
      isEmpty,
      reason: '正在等回答还开录,上一段还在飞的临时文件会被下一段删掉',
    );
  });

  testWidgets('★★按住途中 thinking 变真:抬手仍要收尾,否则录音挂到 60 秒上限', (
    WidgetTester t,
  ) async {
    // 按住麦克风的同时另一根手指点发送(或软键盘 send)—— 页面把 thinking 置真。
    await _pump(t);
    final TestGesture g = await t.startGesture(
      t.getCenter(find.byKey(const Key('npc-input-mic'))),
    );
    await t.pump();
    expect(_voice, <bool>[true], reason: '前提:这一次按下确实开了录,不然收不收尾无所谓');

    await _pump(t, thinking: true);
    await g.up();
    await t.pump();
    expect(
      _voice,
      <bool>[true, false],
      reason: '收尾被 thinking 挡下 ⇒ stop() 永远不被调用,录音挂到 60 秒上限再把那 60 秒传上去',
    );
  });

  testWidgets('★录音态:占位文案换成「正在听…松开发送」并高亮', (WidgetTester t) async {
    await _pump(t);
    expect(find.text('问问阿旧…'), findsOneWidget);
    final Color idlePill = _fillOf(t, const Key('npc-input-pill'))!.color!;
    expect(
      _fillOf(t, const Key('npc-input-mic')),
      isNull,
      reason: '静默态麦克风没有底色',
    );

    await _pump(t, recording: true);
    expect(find.text('正在听…松开发送'), findsOneWidget);
    expect(find.text('问问阿旧…'), findsNothing);
    expect(
      _fillOf(t, const Key('npc-input-pill'))!.color,
      isNot(idlePill),
      reason: '录音时输入框底色要变——不然「正在听」只有文案在说,视觉上没发生任何事',
    );
    // 用 `?.` 不用 `!`:高亮整个丢了的时候要看见一条「期望 X 拿到 null」的断言,
    // 而不是一句 null check 崩溃。
    expect(_fillOf(t, const Key('npc-input-mic'))?.color, CyTokens.textPrimary);
  });

  testWidgets('★录音时打字框仍然可用', (WidgetTester t) async {
    await _pump(t, recording: true);
    expect(_field(t).enabled, isTrue);
    await t.enterText(find.byType(CupertinoTextField), '打字');
    await t.pump();
    expect(_field(t).controller!.text, '打字');
  });

  testWidgets('★麦克风与发送键的命中区都不小于 44pt', (WidgetTester t) async {
    await _pump(t);
    final Size mic = t.getSize(find.byKey(const Key('npc-input-mic')));
    expect(mic.width, greaterThanOrEqualTo(44.0));
    expect(mic.height, greaterThanOrEqualTo(44.0));
    final Size send = t.getSize(find.byKey(const Key('npc-input-send')));
    expect(send.width, greaterThanOrEqualTo(44.0));
    expect(send.height, greaterThanOrEqualTo(44.0));

    // 命中区靠外扩的透明盒去够,可见圆仍是样机的 56rpx=28pt ——
    // 把圆本身撑成 44 会让输入条看起来完全不是样机那条。
    expect(
      t.getSize(find.byKey(const Key('npc-input-mic-dot'))),
      const Size(28, 28),
    );
  });

  testWidgets('★降低动态时按钮不消失也不禁用', (WidgetTester t) async {
    await t.pumpWidget(
      CupertinoApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CupertinoPageScaffold(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 375,
                child: NpcInputBar(
                  npcName: '阿旧',
                  onSend: (String s) => _sent = s,
                  onVoice: (bool h) => _voice.add(h),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.enterText(find.byType(CupertinoTextField), '在吗');
    await t.pump();
    await t.tap(find.byKey(const Key('npc-input-send')));
    await t.pump();
    expect(_sent, '在吗');
    final TestGesture g = await t.startGesture(
      t.getCenter(find.byKey(const Key('npc-input-mic'))),
    );
    await t.pump();
    await g.up();
    await t.pump();
    expect(_voice, <bool>[true, false]);
  });
}
