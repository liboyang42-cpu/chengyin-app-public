// 屏③ 章节故事流的页面组装。
//
// ⚠️ **本文件一律用定量 `pump(Duration)`,不用 `pumpAndSettle`**:
//   `StoryDust` 照样机是无限 rAF(Task 4),页面挂着它就永远有帧被排上,
//   `pumpAndSettle` 必然 timeout。
//   计划 brief 给的出路是「把被测子树包一层 `TickerMode(enabled:false)`」——
//   **实测行不通**:TickerMode 会连行的显形动画一起冻住(`StoryLineView` 用的是
//   `TweenAnimationBuilder`),而首屏显形那条断言正是要读它跑完之后的 opacity。
//   定量 pump 既不冻结生产行为,也不需要改生产代码,与 `story_dust_test.dart` 同款。
import 'dart:async';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/free_explore/chapter_story_page.dart';
import 'package:chengyin_app/feature/play/free_explore/story_reveal.dart';
import 'package:chengyin_app/feature/play/free_explore/widgets/story_dust.dart';
import 'package:chengyin_app/feature/play/free_explore/widgets/story_line_view.dart';
import 'package:chengyin_app/feature/play/play_session_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:just_audio_background/just_audio_background.dart'
    show MediaItem;

const PlaySessionKey _key = (activityId: 77, topicId: null);

/// 五段正文 —— 800×600 的测试视口里首屏只装得下前两三行,后面那几行必须靠滚动补显形。
const String _desc = '第一段\n\n第二段\n\n第三段\n\n第四段\n\n第五段';

/// ★ 章节喂后端 `/api/play/nodes` 的真实键(name / imgArr / description / audioUrl,
/// **没有** meta/title/cover),整条走 `PlayNodesResult.fromJson` —— 用构造函数直接造
/// `PlayChapter` 会绕过解析层,键名错配就完全隐形(本分支已栽三次)。
class _Api implements PlayApi {
  _Api({
    required this.audioUrl,
    required this.description,
    this.chapterAudioUrl,
    this.reloadGate,
  });

  /// 第二次(及以后)取数要等它 —— 用来把页面按在 loading 兜底态上,
  /// 模拟「用户正滑着,一次刷新落下来」。
  final Future<void>? reloadGate;
  int _calls = 0;

  /// **节点**的语音导览(后端 `:594` `m.put("audioUrl", tpl.getAudioUrl())`)——
  /// 屏③ 右下那颗音频键放的就是它。
  final String? audioUrl;

  /// **章节背景旁白**(后端 `:736` `cm.put("audioUrl", c.getAudioUrl())`)。
  /// 是另一个功能:进本章自动播(`_maybeStartNarration`),但**不许**接到
  /// 右下那颗键上 —— 留在 fixture 里当干扰项,两头各钉各的。
  final String? chapterAudioUrl;
  final String description;

  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async {
    if (_calls++ > 0 && reloadGate != null) await reloadGate;
    return PlayNodesResult.fromJson(<String, dynamic>{
      'topicId': 23,
      'mode': 2,
      'playable': true,
      'total': 1,
      'doneCount': 0,
      'nodes': <dynamic>[
        <String, dynamic>{
          'nodeId': 1,
          'name': '长乐路旧物店',
          'address': '长乐路 139 号',
          'sortId': 1,
          'chapterId': 100,
          'done': false,
          'arrived': false,
          'selfReported': false,
          'gameTitle': '旧物寻踪',
          'hasGame': true,
          'audioUrl': audioUrl,
        },
      ],
      'chapters': <dynamic>[
        <String, dynamic>{'chapterId': 99, 'name': '晨间烘焙'},
        <String, dynamic>{
          'chapterId': 100,
          'name': '旧书与唱片',
          'description': description,
          'audioUrl': chapterAudioUrl,
        },
      ],
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlayer implements ChapterAudioPlayer {
  final StreamController<void> _stopped = StreamController<void>.broadcast();
  final StreamController<void> _started = StreamController<void>.broadcast();
  final StreamController<Object> _errors = StreamController<Object>.broadcast();

  bool playing = false;
  bool stopped = false;
  int playCount = 0;
  Uri? playedUri;
  MediaItem? playedMediaItem;

  void endNaturally() => _stopped.add(null);

  /// 真出声这一拍(真播放器的 `playing` false→true 沿)—— 换源顶掉时
  /// 播放器先报「旧源停了」收态,再靠这条把播放态点回来。
  void emitStarted() => _started.add(null);

  void fail() => _errors.add(Exception('404'));

  /// 终态流**自己**出错(不是「播放失败」那条流)—— 页面的 listen 没写 onError
  /// 时这会变成未捕获的 zone error。
  void breakStoppedStream() => _stopped.addError(Exception('stream broke'));

  @override
  Stream<void> get onStopped => _stopped.stream;

  @override
  Stream<void> get onStarted => _started.stream;

  @override
  Stream<Object> get onError => _errors.stream;

  @override
  Future<void> play(Uri uri, {MediaItem? mediaItem}) async {
    playing = true;
    playCount++;
    playedUri = uri;
    playedMediaItem = mediaItem;
  }

  @override
  Future<void> stop() async {
    playing = false;
    stopped = true;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _stopped.close();
    await _started.close();
    await _errors.close();
  }
}

/// 假的 `just_audio.AudioPlayer`。
///
/// ⚠️ 上一轮报告写它「没有可注入的假实现」—— **不成立**:
///   `JustAudioChapterPlayer` 的构造函数本来就收 `{just_audio.AudioPlayer? player}`,
///   而 `AudioPlayer` 是普通 class(just_audio.dart:58),用本文件
///   `_Api implements PlayApi` 那套 `implements … + noSuchMethod` 就能造。
///   钉的是 [JustAudioChapterPlayer] 那两行**胶水**:接哪条流。接错了照样编译得过、
///   3000+ 条测试照样全绿,只有真机 CDN 断流才炸出来。
class _FakeJustAudio implements just_audio.AudioPlayer {
  final StreamController<just_audio.PlayerState> _states =
      StreamController<just_audio.PlayerState>.broadcast();
  final StreamController<just_audio.PlayerException> _errors =
      StreamController<just_audio.PlayerException>.broadcast();

  /// 起播时抛的 —— `setUrl` 的 Future(404 / 无网)。
  Object? setUrlThrows;
  String? setUrlArg;
  bool didPlay = false;

  void emitState(bool playing, just_audio.ProcessingState p) =>
      _states.add(just_audio.PlayerState(playing, p));

  /// 播放中出的错(CDN 中途断流 / 解码失败)—— just_audio 只从这条报。
  void emitRuntimeError() =>
      _errors.add(just_audio.PlayerException(-11800, '断流', null));

  @override
  Stream<just_audio.PlayerState> get playerStateStream => _states.stream;

  @override
  Stream<just_audio.PlayerException> get errorStream => _errors.stream;

  @override
  Future<Duration?> setUrl(
    String url, {
    Map<String, String>? headers,
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    if (setUrlThrows != null) throw setUrlThrows!;
    setUrlArg = url;
    return null;
  }

  @override
  Future<void> play() async => didPlay = true;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _states.close();
    await _errors.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 一次「停下来」:先让 settle 定时器(慢滑 30ms / 快滑 70ms)落地,
/// 再把逐条错开的 500ms 过渡跑完。
Future<void> _rest(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 120));
  await t.pump(const Duration(milliseconds: 900));
}

Future<void> _pump(
  WidgetTester t, {
  String? audioUrl = 'https://cdn.example.com/node-1.mp3',
  String? chapterAudioUrl,
  Future<void>? reloadGate,
  String description = _desc,
  bool reduceMotion = false,
  _FakePlayer? player,
  ValueChanged<PlayNode>? onPrimary,
}) async {
  final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        playApiProvider.overrideWithValue(
          _Api(
            audioUrl: audioUrl,
            chapterAudioUrl: chapterAudioUrl,
            description: description,
            reloadGate: reloadGate,
          ),
        ),
      ].cast(),
      child: MaterialApp(
        navigatorKey: nav,
        builder: (BuildContext c, Widget? child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: const ColoredBox(color: Color(0xFF000000)),
      ),
    ),
  );
  await t.pump();
  // 真实用法是从卡片详情 push 进来(Task 6),所以测试也走 pushed route ——
  // 「退出本页」那条断言要的正是路由被 pop 掉之后的 dispose。
  unawaited(
    nav.currentState!.push(
      CupertinoPageRoute<void>(
        builder: (BuildContext _) => ChapterStoryPage(
          sessionKey: _key,
          nodeId: 1,
          onPrimary: onPrimary ?? (PlayNode _) {},
          audioPlayerFactory: player == null ? null : () => player,
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 400)); // 转场 + 取数 + 开页 30ms
  await _rest(t);
}

bool _ctaHidden(WidgetTester t) =>
    t.widget<IgnorePointer>(find.byKey(const Key('story-cta'))).ignoring;

StoryLineView _lineOf(WidgetTester t, String text) => t.widget<StoryLineView>(
  find
      .ancestor(of: find.text(text), matching: find.byType(StoryLineView))
      .first,
);

/// 一行的**布局**中心(未变形)。锚点取 [StoryLineView] 自己的 RenderObject ——
/// 它是 `Opacity`,排在 `Transform` **之上**,所以拿到的是布局矩形。
double _layoutCenterY(WidgetTester t, String text) => t
    .getRect(
      find
          .ancestor(of: find.text(text), matching: find.byType(StoryLineView))
          .first,
    )
    .center
    .dy;

/// 一行的**可见**中心(应用了 `translateY(1.95em) scale(.78)` 之后)。
/// `getRect` 走 `localToGlobal`,会把祖先的 `Transform` 折算进去 ——
/// 与样机 `boundingClientRect()` 同源。
double _visualCenterY(WidgetTester t, String text) =>
    t.getRect(find.text(text)).center.dy;

double _lineOpacity(WidgetTester t, String text) => t
    .widget<Opacity>(
      find.ancestor(of: find.text(text), matching: find.byType(Opacity)).first,
    )
    .opacity;

void main() {
  testWidgets('★进来首屏几行就显形,不用等用户滚', (WidgetTester t) async {
    await _pump(t);
    // 样机开页 30ms 后主动 settle 一次;不做的话进来是一片黑,得先滑一下才有字。
    expect(_lineOpacity(t, '旧书与唱片'), 1);
    expect(_lineOpacity(t, '第一段'), 1);
  });

  testWidgets('★块流尾块:全部正文之后有「已读到当前解锁位置」+「继续探索」,点它收起整屏回宿主', (
    WidgetTester t,
  ) async {
    await _pump(t);
    // 真源 `.chfull__end`:尾块常驻(它不是 `.chfull__para`,不进逐行显形)。
    // find 不要求可见 —— 首屏滚不到也能确认渲染在树里。
    expect(find.text('已读到当前解锁位置'), findsOneWidget);
    expect(find.byKey(const Key('story-continue')), findsOneWidget);
    // 「继续探索」= 真源 closeChapterFull:停这一屏音频(挂在 dispose)+ 收起整屏。
    // 尾块落在正文与下 pad 之间,首屏装不下 —— 拖进视口再点,与玩家的手一致。
    await t.dragUntilVisible(
      find.byKey(const Key('story-continue')),
      find.byType(Scrollable).first,
      const Offset(0, -120),
    );
    await t.pump(const Duration(milliseconds: 900));
    await t.tap(find.byKey(const Key('story-continue')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 200));
    expect(
      find.byType(ChapterStoryPage),
      findsNothing,
      reason: '点「继续探索」没把 pushed route 弹掉 = 玩家困在章节全屏里出不去',
    );
  });

  testWidgets('★正文不许落在 MaterialApp 的「没有 Material 祖先」兜底样式上', (
    WidgetTester t,
  ) async {
    await _pump(t);
    // ★ 本页是全屏浮层,没有 Scaffold。没有 Material 祖先时 MaterialApp 给的
    //   DefaultTextStyle 是 `_errorTextStyle`(material/app.dart:45):
    //   fontFamily:'monospace' + 黄色双下划线。页面自己的 TextStyle 只覆盖了
    //   color/fontSize,**decoration 与 fontFamily 是继承来的** —— 于是整屏正文
    //   带着黄色双下划线、中文落到等宽族名上渲成方框。
    //   ⚠️ 不是「golden 环境问题」:生产里本页同样 push 在 CupertinoPageRoute 上,
    //     一样没有 Material 祖先。Task 7 的第一版基线就是这么拍出来的,
    //     差一点被当成「期望」入库。
    final RenderParagraph p = t.renderObject(find.text('第一段'));
    expect(
      p.text.style?.decoration ?? TextDecoration.none,
      TextDecoration.none,
      reason: '黄色双下划线 = 落在 _errorTextStyle 上了',
    );
    expect(
      p.text.style?.fontFamily,
      isNot('monospace'),
      reason: 'monospace 兜底族名 = 中文渲成方框',
    );
  });

  testWidgets('★滑动时底栏收起,停下弹回', (WidgetTester t) async {
    await _pump(t);
    await t.drag(find.byType(Scrollable), const Offset(0, -200));
    await t.pump(); // 不 rest:此刻仍在「滑动中」
    expect(_ctaHidden(t), isTrue, reason: '滑动中底栏不让位就会压住正文');
    await _rest(t); // 停下
    expect(_ctaHidden(t), isFalse);
  });

  testWidgets('★降低动态时底栏始终不收 —— 藏起来等于把功能藏了', (WidgetTester t) async {
    await _pump(t, reduceMotion: true);
    await t.drag(find.byType(Scrollable), const Offset(0, -200));
    await t.pump();
    expect(_ctaHidden(t), isFalse);
  });

  testWidgets('★降低动态时音频键也不收', (WidgetTester t) async {
    await _pump(t, reduceMotion: true);
    await t.drag(find.byType(Scrollable), const Offset(0, -200));
    await t.pump();
    expect(
      t
          .widget<IgnorePointer>(
            find
                .ancestor(
                  of: find.byKey(const Key('story-audio')),
                  matching: find.byType(IgnorePointer),
                )
                .first,
          )
          .ignoring,
      isFalse,
      reason:
          '样机只给 .fx-story__cta 写了降级覆盖,音频键漏了 —— '
          '照抄那个漏洞就是把这一章唯一的音频入口在降级下藏掉',
    );
  });

  testWidgets('★没有 audioUrl 就不渲音频键', (WidgetTester t) async {
    await _pump(t, audioUrl: null);
    expect(
      find.byKey(const Key('story-audio')),
      findsNothing,
      reason: '渲一个按不出声的键 = 假入口',
    );
  });

  testWidgets('★音频键命中区不小于 44pt(可见圆只有 36pt)', (WidgetTester t) async {
    await _pump(t);
    final Size s = t.getSize(find.byKey(const Key('story-audio')));
    expect(s.width, greaterThanOrEqualTo(44));
    expect(s.height, greaterThanOrEqualTo(44));
  });

  testWidgets('★退出本页必须停掉音频', (WidgetTester t) async {
    final _FakePlayer p = _FakePlayer();
    await _pump(t, player: p);
    await t.tap(find.byKey(const Key('story-audio')));
    await t.pump();
    expect(p.playing, isTrue);
    await t.tap(find.byKey(const Key('story-back')));
    await t.pump();
    // 退场转场跑完、路由真被摘掉,State 才 dispose —— 退场没跑完就 dispose 内容
    // 正是计划点名要避开的那条。
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byType(ChapterStoryPage), findsNothing);
    expect(p.stopped, isTrue, reason: '退出还在响 = 用户回到卡片还得再找一次开关');
    expect(p.playing, isFalse);
  });

  testWidgets('★播完 / 出错都要把按钮态收回去', (WidgetTester t) async {
    final _FakePlayer p = _FakePlayer();
    await _pump(t, player: p);
    await t.tap(find.byKey(const Key('story-audio')));
    await t.pump();
    p.endNaturally();
    await t.pump();
    // 再点一次:如果播放态没收回去,这一下会被当成「暂停」,音频永远起不来。
    await t.tap(find.byKey(const Key('story-audio')));
    await t.pump();
    expect(p.playing, isTrue);

    p.fail();
    await t.pump();
    expect(find.text('这段音频放不出来'), findsOneWidget);
  });

  testWidgets('★两层粒子都挂上了,近景那层排在文字之后', (WidgetTester t) async {
    await _pump(t);
    expect(find.byType(StoryDust), findsNWidgets(2));
    final Stack stack = t.widget<Stack>(find.byKey(const Key('story-stack')));
    int at(String key) =>
        stack.children.indexWhere((Widget w) => w.key == Key(key));
    expect(at('story-dust-back'), lessThan(at('story-scroll')));
    expect(
      at('story-dust-front'),
      greaterThan(at('story-scroll')),
      reason: '近景压在文字之上是刻意的景深,排到文字前面这层就没了',
    );
    expect(
      t
          .widget<StoryDust>(
            find.descendant(
              of: find.byKey(const Key('story-dust-front')),
              matching: find.byType(StoryDust),
            ),
          )
          .layers,
      same(kStoryDustFront),
      reason: '近景那层必须是 20+12 颗 k>1 的,喂成后景就没有视差了',
    );
  });

  testWidgets('★往下滚字从下方浮起,往回滚才从上方落下', (WidgetTester t) async {
    await _pump(t);
    // 往下滚(scrollTop 变大):方向跟着手走,字从下方浮起 —— fromTop 必须是 false。
    await t.drag(find.byType(Scrollable), const Offset(0, -600));
    await _rest(t);
    expect(
      _lineOf(t, '第四段').fromTop,
      isFalse,
      reason: '方向写反了仍然「有动效」,不对着样机根本发现不了',
    );
    // 往回滚(scrollTop 变小):字从上方落下。
    await t.drag(find.byType(Scrollable), const Offset(0, 600));
    await _rest(t);
    expect(_lineOf(t, '第一段').fromTop, isTrue);
  });

  testWidgets('★音源是节点的语音导览,不是章节背景旁白', (WidgetTester t) async {
    // 作者只配了章节背景旁白、没配节点语音导览 —— 样机右下**没有**音频键
    // (index.js:1032 `chapStory.audio = v.audio`,v = hero.node)。
    // 旁白本身照真源自动播(下面那组「旁白」测试钉它),但它**长不出按钮**。
    final _FakePlayer p = _FakePlayer();
    await _pump(
      t,
      player: p,
      audioUrl: null,
      chapterAudioUrl: 'https://cdn.example.com/chapter-narration.mp3',
    );
    expect(
      find.byKey(const Key('story-audio')),
      findsNothing,
      reason: '取成 chapter.audioUrl 的话这里会多出一颗样机没有的键,放的还是另一条音轨',
    );
  });

  testWidgets('★播的是节点那条 URL,不是章节旁白那条', (WidgetTester t) async {
    final _FakePlayer p = _FakePlayer();
    await _pump(
      t,
      player: p,
      audioUrl: 'https://cdn.example.com/node-1.mp3',
      chapterAudioUrl: 'https://cdn.example.com/chapter-narration.mp3',
    );
    await t.tap(find.byKey(const Key('story-audio')));
    await t.pump();
    expect(
      p.playedUri.toString(),
      'https://cdn.example.com/node-1.mp3',
      reason: '两条都下发,取错那条 = 按下去响的是别的音轨',
    );
    // 锁屏/控制中心元数据带真实字段:标题=节点名,专辑=所在章节名。
    expect(p.playedMediaItem?.title, '长乐路旧物店');
    expect(p.playedMediaItem?.album, '旧书与唱片');
  });

  group('★章节背景旁白:进本章自动播(真源 playChapterAudio,index.js:2701-2712)', () {
    // 音频键的播放态藏在它外层的 Semantics label 里(样机 aria-label 同一条)。
    String keyLabel(WidgetTester t) => t
        .widget<Semantics>(
          find
              .ancestor(
                of: find.byKey(const Key('story-audio')),
                matching: find.byType(Semantics),
              )
              .first,
        )
        .properties
        .label!;

    testWidgets('拿到章节数据就自动播旁白,玩家不用点;不长任何按钮', (WidgetTester t) async {
      final _FakePlayer p = _FakePlayer();
      await _pump(
        t,
        player: p,
        audioUrl: null,
        chapterAudioUrl: 'https://cdn.example.com/chapter-narration.mp3',
      );
      expect(
        p.playedUri.toString(),
        'https://cdn.example.com/chapter-narration.mp3',
        reason: '真源:打开本章即播,玩家不用点(index.js:2701 注释)',
      );
      expect(p.playing, isTrue);
      expect(p.playCount, 1, reason: '重进 build 不许把旁白剁成开头一秒重播');
      expect(p.playedMediaItem?.title, '旧书与唱片');
      expect(p.playedMediaItem?.id, startsWith('chapter-narration-100-'));
    });

    testWidgets('章节没配旁白 → 什么都不播', (WidgetTester t) async {
      final _FakePlayer p = _FakePlayer();
      await _pump(t, player: p);
      expect(p.playCount, 0);
      expect(p.playing, isFalse);
    });

    testWidgets('旁白在响时音频键不许亮播放态;点键 = 顶掉旁白换导览', (WidgetTester t) async {
      final _FakePlayer p = _FakePlayer();
      await _pump(
        t,
        player: p,
        audioUrl: 'https://cdn.example.com/node-1.mp3',
        chapterAudioUrl: 'https://cdn.example.com/chapter-narration.mp3',
      );
      expect(p.playing, isTrue, reason: '前提:旁白在响');
      expect(keyLabel(t), '播放这一章的音频', reason: '那颗键管的不是旁白,旁白在响时亮起 = 假状态');
      // 点键:共用播放器「后播的把前面那段顶掉」(真源 playChapterAudio 注释)。
      await t.tap(find.byKey(const Key('story-audio')));
      await t.pump();
      expect(p.playedUri.toString(), 'https://cdn.example.com/node-1.mp3');
      expect(keyLabel(t), '暂停这一章的音频');
      // 再点:收掉导览。旁白**不回来** —— 被顶掉就是顶掉了。
      await t.tap(find.byKey(const Key('story-audio')));
      await t.pump();
      expect(p.playing, isFalse);
      expect(p.stopped, isTrue);
      expect(p.playCount, 2, reason: '顶掉后不许有人替旁白偷偷续播');
    });

    testWidgets('退出本章把旁白一并停掉', (WidgetTester t) async {
      final _FakePlayer p = _FakePlayer();
      await _pump(
        t,
        player: p,
        audioUrl: null,
        chapterAudioUrl: 'https://cdn.example.com/chapter-narration.mp3',
      );
      expect(p.playing, isTrue);
      // 没有音频键、没有导览,响的只有旁白:退页必须停(index.js:634 卸载即销毁)。
      await t.tap(find.byKey(const Key('story-back')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.byType(ChapterStoryPage), findsNothing);
      expect(p.stopped, isTrue, reason: '退页旁白留在后台继续念 = 玩家找不到开关');
    });

    testWidgets('旁白放不出来:一句人话 + 换导览仍然按得动,不炸未捕获异常', (WidgetTester t) async {
      final _FakePlayer p = _FakePlayer();
      await _pump(
        t,
        player: p,
        audioUrl: 'https://cdn.example.com/node-1.mp3',
        chapterAudioUrl: 'https://cdn.example.com/chapter-narration.mp3',
      );
      expect(p.playedUri.toString(), endsWith('chapter-narration.mp3'));
      p.fail();
      await t.pump();
      expect(find.text('这段音频放不出来'), findsOneWidget);
      // 旁白炸了不能把这一屏的音频链一起焊死:点导览照样换源起播。
      await t.tap(find.byKey(const Key('story-audio')));
      await t.pump();
      expect(p.playedUri.toString(), endsWith('node-1.mp3'));
    });

    testWidgets('刷新重进 build 不重播旁白', (WidgetTester t) async {
      final _FakePlayer p = _FakePlayer();
      await _pump(
        t,
        player: p,
        audioUrl: null,
        chapterAudioUrl: 'https://cdn.example.com/chapter-narration.mp3',
      );
      expect(p.playCount, 1);
      // 一次取数刷新:build 重进,`_maybeStartNarration` 的闸门必须拦住重播。
      unawaited(
        ProviderScope.containerOf(
          t.element(find.byType(ChapterStoryPage)),
        ).read(playSessionProvider(_key).notifier).load(),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await _rest(t);
      expect(p.playCount, 1, reason: '重播会把旁白剁成开头一秒(真源 index.js:2704 同一条教训)');
    });

    testWidgets('★换源顶掉走真播放器的两拍:旧源停收态、新源出声点回来(样机 onStop→onPlay)', (
      WidgetTester t,
    ) async {
      final _FakePlayer p = _FakePlayer();
      await _pump(
        t,
        player: p,
        audioUrl: 'https://cdn.example.com/node-1.mp3',
        chapterAudioUrl: 'https://cdn.example.com/chapter-narration.mp3',
      );
      // 点导览换源:真播放器 setUrl 先把旁白停掉 —— 这一拍把播放态收了。
      await t.tap(find.byKey(const Key('story-audio')));
      await t.pump();
      expect(p.playedUri.toString(), endsWith('node-1.mp3'));
      p.endNaturally();
      await t.pump();
      expect(keyLabel(t), '播放这一章的音频', reason: '前提:stopped 那一拍已把播放态收掉');
      // 新源真开播(onPlay 沿):不点回来 = 导览在响但键不亮,再点变从头重放。
      p.emitStarted();
      await t.pump();
      expect(
        keyLabel(t),
        '暂停这一章的音频',
        reason: '样机 onStop 收、onPlay 复是两拍;只接前半截就是把换源钉死在熄灭态',
      );
    });
  });

  testWidgets('★终态流自己出错也要收回按钮态 + 提示(不是未捕获的 zone error)', (
    WidgetTester t,
  ) async {
    final _FakePlayer p = _FakePlayer();
    await _pump(t, player: p);
    await t.tap(find.byKey(const Key('story-audio')));
    await t.pump();
    // 流本身 addError:listen 没写 onError 的话这一下会炸成未捕获异常,
    // 而按钮态还卡在「播放中」。
    p.breakStoppedStream();
    await t.pump();
    expect(find.text('这段音频放不出来'), findsOneWidget);
    // 再点一次必须是「重放」而不是被当成暂停。
    await t.tap(find.byKey(const Key('story-audio')));
    await t.pump();
    expect(p.playing, isTrue, reason: '按钮态没收回去的话,这一下会被当成暂停');
  });

  testWidgets('★显形判据量的是变形后的矩形(位置 + 高度都得是)', (WidgetTester t) async {
    await _pump(t);
    final ScrollableState sc = t.state<ScrollableState>(
      find.byType(Scrollable),
    );
    // ★ 与页面同一个锚点:`_boxKey` 就挂在 SingleChildScrollView 上。
    final RenderBox box = t.renderObject<RenderBox>(
      find.byType(SingleChildScrollView),
    );
    // `lineInView` 的下沿:`cy < boxHeight - 40`。
    final double edge =
        box.localToGlobal(Offset.zero).dy + box.size.height - 40;
    // 未显形的行整体下移 kStoryLineShift,再绕中心缩到 .78 —— 中心只被位移搬走。
    void scrollSoThat({required double visualCenterAt}) {
      sc.position.jumpTo(
        sc.position.pixels +
            (_layoutCenterY(t, '第三段') - (visualCenterAt - kStoryLineShift)),
      );
    }

    // ① 锚点必须在 Transform 内侧:布局中心已进下沿、变形后的中心还在外面。
    //    照未变形的矩形判,这一行会早 33.15pt(一整行)就被点亮。
    scrollSoThat(visualCenterAt: edge + 6);
    await t.pump();
    expect(_layoutCenterY(t, '第三段'), lessThan(edge), reason: '前提:布局中心已进下沿');
    expect(_visualCenterY(t, '第三段'), greaterThan(edge), reason: '前提:变形后还在外面');
    await _rest(t);
    expect(
      _lineOf(t, '第三段').shown,
      isFalse,
      reason: '拿未变形的矩形判会早一整行就点亮,样机「进得晚、出得准」的迟滞就没了',
    );

    // ② 高度也得按变形后的算:样机 `boundingClientRect()` 的高是 scale(.78) 之后的。
    //    只把位置折算、高度仍取未缩放的,判据会再晚 h×(1-.78)/2 ≈ 3.65pt ——
    //    把可见中心停在下沿内 2pt,这一档就分得开。
    scrollSoThat(visualCenterAt: edge - 2);
    await t.pump();
    expect(
      _visualCenterY(t, '第三段'),
      closeTo(edge - 2, 0.05),
      reason: '前提:可见中心刚好停在下沿内 2pt',
    );
    await _rest(t);
    expect(
      _lineOf(t, '第三段').shown,
      isTrue,
      reason: '高度取未缩放的会把中心又往下推 3.65pt,这一行就还亮不起来',
    );
  });

  testWidgets('★刷新落在滑动中:量不到滚动框也要把底栏放回来', (WidgetTester t) async {
    final Completer<void> gate = Completer<void>();
    await _pump(t, reloadGate: gate.future);
    await t.drag(find.byType(Scrollable), const Offset(0, -200));
    await t.pump();
    expect(_ctaHidden(t), isTrue, reason: '前提:滑动中底栏收着');

    // 一次刷新落下来:`load()` 先把 state 打回 loading,页面整屏换成兜底文案,
    // 滚动框没了 —— 排着的那次 settle 于是量不到东西。
    unawaited(
      ProviderScope.containerOf(
        t.element(find.byType(ChapterStoryPage)),
      ).read(playSessionProvider(_key).notifier).load(),
    );
    await t.pump();
    expect(
      find.byType(SingleChildScrollView),
      findsNothing,
      reason: '前提:此刻量不到滚动框',
    );
    await t.pump(const Duration(milliseconds: 200)); // 排着的 settle 在这一段里空转
    gate.complete();
    await t.pump();
    await _rest(t);
    expect(
      _ctaHidden(t),
      isFalse,
      reason: '没人补排 settle 的话 _barAway 留在 true,底栏和音频键要等用户再滚一次才回来',
    );
  });

  testWidgets('★卡在兜底屏不许空转 —— 补排不能是没有出口的自旋', (WidgetTester t) async {
    // 刷新失败停在离线态:`.value` 恒 null ⇒ 页面一直是「这一章暂时读不到」兜底屏
    // ⇒ `_boxKey` 永远量不到。补排要是无条件定时重排,就会每 30ms 空转一次
    // 直到用户离页 —— 没有任何可见症状,纯唤醒开销。
    //
    // ★ 数法:定时器回调跑在**创建它的 zone** 里(fake_async.dart:361),
    //   所以把整段放进一个只做计数的 fork zone,链式重排会一路记在这里。
    //   ⚠️ 拖拽必须也在 zone 内 —— 只把 pump 圈进来的话,首个 timer 建在外层 zone,
    //   它排出的后继也记在外层,计数恒 0(假绿)。
    int settleTimers = 0;
    final Zone counting = Zone.current.fork(
      specification: ZoneSpecification(
        createTimer:
            (
              Zone self,
              ZoneDelegate parent,
              Zone zone,
              Duration d,
              void Function() f,
            ) {
              if (d == kSettleSlow) settleTimers++;
              return parent.createTimer(zone, d, f);
            },
      ),
    );
    await counting.run<Future<void>>(() async {
      final Completer<void> stuck = Completer<void>(); // 永不 complete = 离线
      await _pump(t, reloadGate: stuck.future);
      await t.drag(find.byType(Scrollable), const Offset(0, -200));
      await t.pump();
      expect(_ctaHidden(t), isTrue, reason: '前提:滑动中底栏收着,补排有事要救');
      unawaited(
        ProviderScope.containerOf(
          t.element(find.byType(ChapterStoryPage)),
        ).read(playSessionProvider(_key).notifier).load(),
      );
      await t.pump();
      expect(
        find.byType(SingleChildScrollView),
        findsNothing,
        reason: '前提:此刻卡在兜底屏,量不到滚动框',
      );
      settleTimers = 0; // 从卡住这一刻起数
      await t.pump(const Duration(milliseconds: 300));
    });
    expect(settleTimers, 0, reason: '兜底屏下每 30ms 排一次 = 没有出口的自旋,只有离页才停');
  });

  test('★没有一行的显形状态变了就返回 null —— 整表重刷会把已显形行的过渡重放一遍', () {
    const List<StoryLineReveal> current = <StoryLineReveal>[
      StoryLineReveal(shown: true),
      StoryLineReveal(),
    ];
    const List<({double top, double height})?> still =
        <({double top, double height})?>[
          (top: 100, height: 40), // 在屏内,本来就显形
          (top: 900, height: 40), // 在屏外,本来就没显形
        ];
    expect(
      settleStoryReveal(
        current: current,
        rects: still,
        boxTop: 0,
        boxHeight: 600,
        fromTop: false,
      ),
      isNull,
    );
    // 负控:第二行挪进视口,就必须返回新表(否则上面那条是恒真的)
    const List<({double top, double height})?> moved =
        <({double top, double height})?>[
          (top: 100, height: 40),
          (top: 300, height: 40),
        ];
    final List<StoryLineReveal>? next = settleStoryReveal(
      current: current,
      rects: moved,
      boxTop: 0,
      boxHeight: 600,
      fromTop: false,
    );
    expect(next?[1].shown, isTrue);
    expect(
      identical(next![0], current[0]),
      isTrue,
      reason: '已显形的行连对象都不该换 —— 重排一次 delay 就是把它的过渡重放一遍',
    );
  });

  group('★「不响了」这条流:三个终态都要收按钮态,首发那条 idle 不算', () {
    just_audio.PlayerState st(bool playing, just_audio.ProcessingState p) =>
        just_audio.PlayerState(playing, p);

    Future<int> countOf(List<just_audio.PlayerState> seq) async =>
        chapterStoppedFrom(
          Stream<just_audio.PlayerState>.fromIterable(seq),
        ).length;

    test('★订阅那一刻的 idle 不算终态 —— 否则按钮刚点亮就被打回去', () async {
      expect(
        await countOf(<just_audio.PlayerState>[
          st(false, just_audio.ProcessingState.idle),
          st(false, just_audio.ProcessingState.loading),
        ]),
        0,
      );
    });

    test('★正常播完(completed)报一次', () async {
      expect(
        await countOf(<just_audio.PlayerState>[
          st(false, just_audio.ProcessingState.idle),
          st(true, just_audio.ProcessingState.ready),
          // just_audio 播完时 playing 仍是 true,只有 processingState 变 ——
          // 只盯 playing 的话这一条收不到。
          st(true, just_audio.ProcessingState.completed),
        ]),
        1,
      );
    });

    test('★平台侧打断(来电/音频会话被抢)也报一次 —— 样机的 onStop 对应物', () async {
      expect(
        await countOf(<just_audio.PlayerState>[
          st(false, just_audio.ProcessingState.idle),
          st(true, just_audio.ProcessingState.ready),
          st(false, just_audio.ProcessingState.ready),
        ]),
        1,
        reason: '只收 completed 的话按钮会一直亮着,用户必须点两下才能重来',
      );
    });

    test('★响着的时候不报;一次终态只报一次(别把按钮态反复打回去)', () async {
      expect(
        await countOf(<just_audio.PlayerState>[
          st(false, just_audio.ProcessingState.idle),
          st(true, just_audio.ProcessingState.buffering),
          st(true, just_audio.ProcessingState.ready),
          st(false, just_audio.ProcessingState.ready),
          st(false, just_audio.ProcessingState.idle),
        ]),
        1,
      );
    });
  });

  group('★「真出声」这条流(onPlay 对应物):只留 false→true 的沿', () {
    just_audio.PlayerState st(bool playing, just_audio.ProcessingState p) =>
        just_audio.PlayerState(playing, p);

    Future<int> countOf(List<just_audio.PlayerState> seq) async =>
        chapterStartedFrom(
          Stream<just_audio.PlayerState>.fromIterable(seq),
        ).length;

    test('★前导的 idle 不算起播', () async {
      expect(
        await countOf(<just_audio.PlayerState>[
          st(false, just_audio.ProcessingState.idle),
          st(false, just_audio.ProcessingState.loading),
        ]),
        0,
      );
    });

    test('★换源两拍:旧源停(false 沿)不报,新源出声(true 沿)报一次', () async {
      expect(
        await countOf(<just_audio.PlayerState>[
          st(false, just_audio.ProcessingState.idle),
          st(true, just_audio.ProcessingState.ready), // 旁白开播
          st(false, just_audio.ProcessingState.loading), // setUrl 顶掉旧源
          st(true, just_audio.ProcessingState.ready), // 导览真出声
          st(true, just_audio.ProcessingState.ready), // 同值不重复报
        ]),
        2,
        reason: '两次真出声各报一次;收态那一拍不归这条管',
      );
    });
  });

  test('★运行中的播放错误也要出来 —— 起播那两条 Future 盖不住 CDN 断流', () async {
    final StreamController<Object> launch = StreamController<Object>();
    final StreamController<Object> runtime = StreamController<Object>();
    final List<Object> seen = <Object>[];
    final StreamSubscription<Object> sub = chapterErrorsFrom(
      launch.stream,
      runtime.stream,
    ).listen(seen.add);
    launch.add('setUrl 404');
    runtime.add('播到一半断流');
    await pumpEventQueue();
    expect(seen, <Object>[
      'setUrl 404',
      '播到一半断流',
    ], reason: 'just_audio 只从 errorStream 报运行时错误,漏订阅 = 断流后按钮永远亮着');
    await sub.cancel();
    await launch.close();
    await runtime.close();
  });

  group('★JustAudioChapterPlayer 的胶水:接哪条流', () {
    test('★运行中断流必须从 player.errorStream 出来', () async {
      final _FakeJustAudio raw = _FakeJustAudio();
      final ChapterAudioPlayer p = JustAudioChapterPlayer(player: raw);
      final List<Object> seen = <Object>[];
      final StreamSubscription<Object> sub = p.onError.listen(seen.add);
      raw.emitRuntimeError();
      await pumpEventQueue();
      expect(
        seen,
        hasLength(1),
        reason:
            '只订 setUrl/play 那两条 Future 的话,CDN 播到一半断流一句提示都没有 —— '
            '按钮一直亮着,点两下才能重来',
      );
      await sub.cancel();
      await p.dispose();
    });

    test('★起播失败(setUrl 抛)也从同一条流出来', () async {
      final _FakeJustAudio raw = _FakeJustAudio()
        ..setUrlThrows = Exception('404');
      final ChapterAudioPlayer p = JustAudioChapterPlayer(player: raw);
      final List<Object> seen = <Object>[];
      final StreamSubscription<Object> sub = p.onError.listen(seen.add);
      await p.play(Uri.parse('https://cdn.example.com/node-1.mp3'));
      await pumpEventQueue();
      expect(seen, hasLength(1), reason: '起播那一路掉了 = 404 也不提示');
      expect(raw.didPlay, isFalse, reason: 'setUrl 都失败了还去 play() = 播一段空');
      await sub.cancel();
      await p.dispose();
    });

    test('★终态必须从 player.playerStateStream 出来', () async {
      final _FakeJustAudio raw = _FakeJustAudio();
      final ChapterAudioPlayer p = JustAudioChapterPlayer(player: raw);
      int n = 0;
      final StreamSubscription<void> sub = p.onStopped.listen((_) => n++);
      raw.emitState(false, just_audio.ProcessingState.idle); // 首发 idle 不算
      raw.emitState(true, just_audio.ProcessingState.ready);
      raw.emitState(true, just_audio.ProcessingState.completed);
      await pumpEventQueue();
      expect(n, 1, reason: '接错流 = 播完了按钮还亮着,用户得点两下才能重来');
      await sub.cancel();
      await p.dispose();
    });

    test('★「真出声」必须从 player.playerStateStream 出来', () async {
      final _FakeJustAudio raw = _FakeJustAudio();
      final ChapterAudioPlayer p = JustAudioChapterPlayer(player: raw);
      int n = 0;
      final StreamSubscription<void> sub = p.onStarted.listen((_) => n++);
      raw.emitState(false, just_audio.ProcessingState.idle); // 首发 idle 不算起播
      raw.emitState(true, just_audio.ProcessingState.ready);
      await pumpEventQueue();
      expect(n, 1, reason: '不接这一拍,换源顶掉后新源真出声也没人把播放态点回来');
      await sub.cancel();
      await p.dispose();
    });

    test('★play() 走的是节点那条 URL', () async {
      final _FakeJustAudio raw = _FakeJustAudio();
      final ChapterAudioPlayer p = JustAudioChapterPlayer(player: raw);
      await p.play(Uri.parse('https://cdn.example.com/node-1.mp3'));
      await pumpEventQueue();
      expect(raw.setUrlArg, 'https://cdn.example.com/node-1.mp3');
      expect(raw.didPlay, isTrue);
      await p.dispose();
    });
  });

  test('★出屏复位:从上方出去的,滚回来要从上方落下', () {
    const List<StoryLineReveal> current = <StoryLineReveal>[
      StoryLineReveal(shown: true),
      StoryLineReveal(shown: true),
    ];
    const List<({double top, double height})?> rects =
        <({double top, double height})?>[
          (top: -200, height: 40), // 从上方出去
          (top: 800, height: 40), // 从下方出去
        ];
    final List<StoryLineReveal>? next = settleStoryReveal(
      current: current,
      rects: rects,
      boxTop: 0,
      boxHeight: 600,
      fromTop: false,
    );
    expect(next?[0].shown, isFalse);
    expect(next?[0].fromTop, isTrue);
    expect(next?[1].fromTop, isFalse);
  });
}
