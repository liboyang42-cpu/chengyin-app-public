// 章节剧情全屏故事流(屏③)。逐条照搬小程序 `.fx-story`
// (pages/play/index.wxml:481-517 / index.wxss:1615-1687 / index.js:1013-1126)。
//
// 手感三条,缺一条就不是那个东西:①滚动中不显形,停下来那一刻才逐行浮起
// ②由虚到实、由小到大、上浮一行,带一点回弹 ③出屏复位,滚回来能重演。

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:just_audio_background/just_audio_background.dart'
    show MediaItem;

import '../../../core/media_art_uri.dart';
import '../../../core/providers.dart';
import '../../../core/theme/cy_tokens.dart';
import '../../../core/widgets/cy_native_button.dart';
import '../../../core/widgets/cy_native_notice.dart';
import '../../../data/models/advanced_play.dart';
import '../../../data/models/checkin_models.dart';
import '../advanced/advanced_play_controller.dart';
import '../advanced/playkit_fullscreen.dart';
import '../advanced/playkit_host.dart';
import '../advanced/playkit_projection.dart';
import '../play_session_controller.dart';
import 'story_lines.dart';
import 'story_reveal.dart';
import 'widgets/game_section.dart';
import 'widgets/story_dust.dart';
import 'widgets/story_line_view.dart';

/// 整屏入场:`.fx-story{ opacity:0; transition:opacity .26s ease }`。
/// 260ms 靠近 standard(220)，归档看语义不看远近。
const Duration kStoryFade = CyMotion.standard;

/// 开页 30ms 后才 `is-open` + 主动 settle 一次 —— 首屏那几行不用等用户滚动
/// (样机 index.js:1035-1039)。
const Duration kStoryOpenDelay = Duration(milliseconds: 30);

/// 滚动区上下各留 22vh(`.fx-story__pad`)。
const double kStoryPadFraction = 0.22;

/// 音频键:外壳 88rpx = 44pt 命中区(背景透明),可见圆 72rpx = 36pt。
const double kStoryAudioHit = 44;
const double kStoryAudioDisc = 36;

/// `right:12rpx; bottom:272rpx`。
const double kStoryAudioRight = 6;
const double kStoryAudioBottom = 136;

/// 收起时音频键 `translateY(40rpx)` —— AnimatedSlide 的偏移是自身尺寸的倍数。
const double kStoryAudioAwayShift = 20 / kStoryAudioHit;

/// 章节旁白在 [_ChapterStoryPageState._audioSource] 里的键。
/// 真源 `audioNodeId` 对旁白存字符串 `'chapter'`、对节点存数字 nodeId,
/// `===` 比较天然不撞(pages/play/index.js:2700)。
const String kChapterNarrationSource = 'chapter';

/// 内嵌玩法段的块高(`.chfull__kit{ --pk-stage-height:70vh }`)—— 视口高的 70%。
const double kStoryKitHeightFraction = 0.7;

/// 底栏 `transform .26s` / `opacity .2s`。
const Duration kStoryBarSlide = CyMotion.standard;
const Duration kStoryBarFade = CyMotion.fadeSwap;

/// 一行的显形状态。
@immutable
class StoryLineReveal {
  const StoryLineReveal({
    this.shown = false,
    this.fromTop = false,
    this.delay = Duration.zero,
  });

  final bool shown;

  /// 样机的 `from-top`:这一行是从上方落下来还是从下方浮起来。
  final bool fromTop;

  /// 同一批补显形的行逐条错开 50ms。
  final Duration delay;
}

/// 停下来这一刻,按各行相对滚动框的矩形重算显形状态(样机 `_settleStory`,
/// index.js:1104-1126)。[rects] 与 [current] 同序,`null` = 这一行还没布局。
///
/// ⚠️ **没有任何一行的 shown 变了就返回 null**,调用方据此跳过 setState。
///   样机在这里留了专门的注释(index.js:1123):停一次就整表重刷,会把已显形那些行
///   的过渡重放一遍。
List<StoryLineReveal>? settleStoryReveal({
  required List<StoryLineReveal> current,
  required List<({double top, double height})?> rects,
  required double boxTop,
  required double boxHeight,
  required bool fromTop,
}) {
  final List<StoryLineReveal> next = List<StoryLineReveal>.of(current);
  bool changed = false;
  int order = 0;
  for (int i = 0; i < current.length && i < rects.length; i++) {
    final ({double top, double height})? r = rects[i];
    if (r == null) continue;
    final bool inView = lineInView(
      lineTop: r.top,
      lineHeight: r.height,
      boxTop: boxTop,
      boxHeight: boxHeight,
    );
    if (current[i].shown && !inView) {
      // 出屏复位。★ 复位方向按它从哪一头出去:从上方出去的,滚回来要从上方落下。
      final double cy = r.top + r.height / 2 - boxTop;
      next[i] = StoryLineReveal(fromTop: cy < 0);
      changed = true;
    } else if (!current[i].shown && inView) {
      next[i] = StoryLineReveal(
        shown: true,
        fromTop: fromTop,
        delay: staggerFor(order++),
      );
      changed = true;
    }
  }
  return changed ? next : null;
}

/// 这一章的音频。只要三件事:放、停、知道它自己停了或者放不出来。
///
/// ⚠️ 没复用 `TopicAudioPlayer` —— 它长在 `feature/topic/topic_detail_page.dart` 里,
///   为了一个接口把整张路线详情页拖进 play 域不划算。要收口应该另起一棒把它挪进 core,
///   那时这两处一起改。
abstract interface class ChapterAudioPlayer {
  /// **不响了**:正常播完 / 被停 / 平台侧打断(来电、音频会话被抢走)。
  ///
  /// ★ 样机注册的是 `onEnded` **和** `onStop` 两个终态(index.js:1060-1061),
  ///   UI 对两者的处置完全一样 —— 把按钮态收回去,所以这里合成一条。
  ///   只收 `completed` 的话,被打断时暂停图标一直亮着,用户再点一下会被当成
  ///   「暂停」(`_toggleAudio` 的第一支),**必须点两下才能重来**。
  Stream<void> get onStopped;

  /// 放不出来。样机 `onError`:收回按钮态 + 提示。
  ///
  /// ⚠️ 覆盖面必须含**运行中**的播放错误(CDN 中途断流 / 解码失败),不只是
  ///   起播时 `setUrl` / `play()` 抛的那一类 —— 那两类走 Future,运行时那一类
  ///   走 just_audio 自己的 `errorStream`(just_audio.dart:352 造 PlayerException
  ///   → :640 errorStream)。漏掉后者 = 音频断了但按钮永远亮着且没有提示。
  Stream<Object> get onError;

  /// **真出声了**(样机 `onPlay`,index.js:5496-5499)。
  ///
  /// ★ 为什么必须有:换源顶掉(旁白在响时点节点导览)时,just_audio 的
  ///   `setUrl` 会先把旧源停掉 —— [onStopped] 因此收到一次「不响了」把播放态
  ///   收掉;新源随后真开播,必须由这条流把播放态**点回来**。样机正是
  ///   onStop 收、onPlay 复的两拍;少了 onPlay 这一拍,导览在响但键不亮。
  Stream<void> get onStarted;

  Future<void> play(Uri uri, {MediaItem? mediaItem});

  Future<void> stop();

  Future<void> dispose();
}

/// 从播放器状态流里挑出「不响了」的时刻:正常播完(`completed`)、被停、
/// 平台侧打断(来电、音频会话被抢 ⇒ `playing` 掉回 false)。
///
/// ★ 抽成顶层函数是为了能直接喂状态序列断言 —— `just_audio.AudioPlayer`
///   在单测里起不来,挂在实例上就没有任何东西能钉住这条链。
/// ⚠️ `skipWhile`:订阅那一刻播放器还是 idle(不 playing),这一串**前导的**
///   「不响」不是终态。少了它,按钮刚点亮就会被状态流的首发打回去。
///   用一个 `_started` 标志位判则会和首发抢时序。
Stream<void> chapterStoppedFrom(Stream<just_audio.PlayerState> states) => states
    .map(
      (just_audio.PlayerState s) =>
          s.processingState == just_audio.ProcessingState.completed ||
          !s.playing,
    )
    .distinct()
    .skipWhile((bool idle) => idle)
    .where((bool idle) => idle)
    .map<void>((_) {});

/// [chapterStoppedFrom] 的镜像:挑出「真出声」的时刻(样机 `onPlay`,index.js:5496)。
///
/// ★ 存在的理由是**换源顶掉**那一段:点导览把旁白换下去时,`setUrl` 先把旧源
///   停掉 ⇒ [chapterStoppedFrom] 收到一次「不响了」把播放态收掉;新源随后开播,
///   要由这条流把播放态点回来。少了它 = 导览在响但键不亮、再点一下变成从头重放。
/// ⚠️ `distinct` 之后只留 false→true 的**沿**:订阅瞬间已在 playing 的情况也报一次
///   (页面此刻本来就该是播放态,重复置真无害)。
Stream<void> chapterStartedFrom(Stream<just_audio.PlayerState> states) => states
    .map((just_audio.PlayerState s) => s.playing)
    .distinct()
    .where((bool playing) => playing)
    .map<void>((_) {});

/// 把两路播放错误合成一条:
/// - [launch] = **起播时**抛的(`setUrl` / `play()` 的 Future)
/// - [runtime] = **播放中**出的(CDN 中途断流 / 解码失败)。just_audio 只从
///   `errorStream` 报这一类(just_audio.dart:352 造 PlayerException → :640),
///   不订阅它 = 音频断了但按钮永远亮着、一句提示都没有,再点一下还被当成暂停。
///   样机 `ctx.onError`(index.js:1063)覆盖的正是这一路。
///
/// ★ 抽成顶层函数是为了单独钉合流规则。**接哪条流**这层胶水另有守卫:
///   `just_audio.AudioPlayer` 起不来真播放器,但它是普通 class,
///   `implements + noSuchMethod` 就能注进构造函数的 `{player}`
///   (chapter_story_page_test.dart 的 `_FakeJustAudio`)。
Stream<Object> chapterErrorsFrom(
  Stream<Object> launch,
  Stream<Object> runtime,
) {
  late final StreamController<Object> out;
  List<StreamSubscription<Object>> subs = <StreamSubscription<Object>>[];
  out = StreamController<Object>.broadcast(
    onListen: () => subs = <Stream<Object>>[launch, runtime]
        .map((Stream<Object> s) => s.listen(out.add, onError: out.addError))
        .toList(),
    onCancel: () async {
      for (final StreamSubscription<Object> s in subs) {
        await s.cancel();
      }
      subs = <StreamSubscription<Object>>[];
    },
  );
  return out.stream;
}

class JustAudioChapterPlayer implements ChapterAudioPlayer {
  JustAudioChapterPlayer({just_audio.AudioPlayer? player})
    : _player = player ?? just_audio.AudioPlayer();

  final just_audio.AudioPlayer _player;
  final StreamController<Object> _errors = StreamController<Object>.broadcast();

  @override
  Stream<void> get onStopped => chapterStoppedFrom(_player.playerStateStream);

  @override
  Stream<void> get onStarted => chapterStartedFrom(_player.playerStateStream);

  @override
  Stream<Object> get onError =>
      chapterErrorsFrom(_errors.stream, _player.errorStream);

  @override
  Future<void> play(Uri uri, {MediaItem? mediaItem}) async {
    try {
      // tag = MediaItem 是给 just_audio_background 的锁屏/控制中心元数据。
      await _player.setUrl(uri.toString(), tag: mediaItem);
    } catch (error) {
      if (!_errors.isClosed) _errors.add(error);
      return;
    }
    // play() 要等到暂停或播完才返回,UI 指令不该长时占用回调。
    unawaited(
      _player.play().catchError((Object error) {
        if (!_errors.isClosed) _errors.add(error);
      }),
    );
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() async {
    await _errors.close();
    await _player.dispose();
  }
}

typedef ChapterAudioPlayerFactory = ChapterAudioPlayer Function();

/// 章节剧情全屏故事流。
///
/// ★ 与 `CardDetailPage` 同款:**按 sessionKey + nodeId 从 provider 现读**,
///   不持有 `PlayNode` / `PlayChapter` 快照。批 2a 的复审在详情页上抓到过一次快照 bug
///   (扫码成功后 pushed route 不重建,后两步永远走不到)。
class ChapterStoryPage extends ConsumerStatefulWidget {
  const ChapterStoryPage({
    super.key,
    required this.sessionKey,
    required this.nodeId,
    required this.onPrimary,
    this.audioPlayerFactory,
  });

  final PlaySessionKey sessionKey;
  final int nodeId;

  /// 主 CTA(样机 `heroEnter`):把**当前**节点交给调用方去开玩法。
  ///
  /// ⚠️ 计划的 Produces 只写了 sessionKey + nodeId,但那样这颗 CTA 点下去没有去处 =
  ///   假按钮。调用方(Task 6)本来就握着详情页的 `onPrimary`,直接透传即可。
  final ValueChanged<PlayNode> onPrimary;

  /// 仅供测试注入。
  final ChapterAudioPlayerFactory? audioPlayerFactory;

  @override
  ConsumerState<ChapterStoryPage> createState() => _ChapterStoryPageState();
}

class _ChapterStoryPageState extends ConsumerState<ChapterStoryPage> {
  final GlobalKey _boxKey = GlobalKey();

  /// 滚动位移只喂粒子做视差 —— 每帧整页 setState 是白花的开销。
  final ValueNotifier<double> _dustTop = ValueNotifier<double>(0);

  List<GlobalKey> _lineKeys = <GlobalKey>[];
  List<StoryLineReveal> _reveal = <StoryLineReveal>[];

  Timer? _openTimer;
  Timer? _settleTimer;
  bool _primed = false;
  bool _open = false;
  bool _barAway = false;

  /// 上一次滚动的方向与位置。样机 `_storyDir` / `_storyTop`(index.js:1085-1087):
  /// 往下滚(top 变大)字从**下方**浮起,往上滚才从上方落下。
  bool _fromTop = false;
  double _prevTop = 0;
  Duration _prevAt = Duration.zero;

  ChapterAudioPlayer? _player;
  StreamSubscription<void>? _endedSub;
  StreamSubscription<void>? _startedSub;
  StreamSubscription<Object>? _errorSub;
  bool _playing = false;

  /// 播放器此刻挂的是**哪条音源** —— 真源 `audioNodeId`(index.js:393)的替身:
  /// 章节旁白存字符串 [kChapterNarrationSource],节点语音导览存数字 nodeId。
  /// 字符串和数字天然撞不上(真源 index.js:2700 同一手法)。
  /// 共用一个播放器 = 「后播的把前面那段顶掉」(真源 playChapterAudio 注释),
  /// 顶没顶过、该不该收,全看这个键,不能只看 [_playing]。
  Object? _audioSource;

  /// 旁白只在**进本章那一刻**试播一次。build 会随取数/刷新反复重进,
  /// 重播会把旁白剁成开头一秒(真源 index.js:2704 同一条教训)。
  bool _narrationStarted = false;

  /// 这一站高级玩法的会话控制器 —— 只为「把内嵌 kit 铺进故事流」而存在。
  ///
  /// 样机的内嵌段绑的是页级会话组件(cy-advanced-game)抛上来的权威视图;
  /// App 的会话控制器长在 `play_session_page` 的 CTA 路径上、随 sheet 生灭,
  /// 故事流拿不到它。在 a4-playkit-present 把会话持有层交出来之前,这里
  /// **自己 resume 一份**:`/api/play/advanced/start` 本就是「取该节点权威
  /// 视图」的可重入调用(每次点玩法 CTA 都会再 start 一次)。只读不改别的面。
  AdvancedPlayController? _kitController;

  @override
  void dispose() {
    _openTimer?.cancel();
    _settleTimer?.cancel();
    _endedSub?.cancel();
    _startedSub?.cancel();
    _errorSub?.cancel();
    _kitController?.removeListener(_onKitChanged);
    _kitController?.dispose();
    // ★ 离开本页必须停。放在 dispose 里而不是返回钮的回调里,是因为退出的路不止一条:
    //   返回钮、iOS 侧滑、系统返回都会走到这里 —— 只挂在按钮上的话,侧滑退出还在响。
    unawaited(_player?.dispose());
    _dustTop.dispose();
    super.dispose();
  }

  // ── 滚动 → 收底栏 + 排一次 settle ──────────────────────────────────

  bool _onScroll(ScrollNotification n) {
    if (n is! ScrollUpdateNotification || n.depth != 0) return false;
    final double top = n.metrics.pixels;
    // ★ 用帧时间戳当时钟,不用 DateTime.now():样机的判据本就是「每帧位移」,
    //   而帧时间戳在测试里跟着假时钟走,同一段手势不会因为机器快慢漂。
    final Duration now = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    final double velocity = frameVelocity(
      top: top,
      prevTop: _prevTop,
      dt: now - _prevAt,
    );
    _fromTop = top < _prevTop;
    _prevTop = top;
    _prevAt = now;
    _dustTop.value = top;
    if (!_barAway) setState(() => _barAway = true);
    _settleTimer?.cancel();
    _settleTimer = Timer(settleDelayFor(velocity), _settle);
    return false;
  }

  void _settle() {
    _settleTimer = null;
    if (!mounted) return;
    final RenderObject? boxRo = _boxKey.currentContext?.findRenderObject();
    if (boxRo is! RenderBox || !boxRo.hasSize) {
      // ★ 量不到 = 整屏在加载/兜底态,滚动框根本没渲。这里**不能直接算完**:
      //   `_barAway` 可能已经是 true,没人补排的话底栏和音频键会一直收着,
      //   要等用户再滚一次才回来 —— 一条没有任何提示的静默失败。
      // ★ 但也**不在这里定时重排**:那是一个没有出口的自旋 —— 刷新失败
      //   停在 `AsyncError`(离线)时滚动框再也回不来,每 30ms 空转一次直到用户离页。
      //   改成「滚动框回来那一帧再补排」(见 build 里的补排):兜底屏下零开销,
      //   而那条静默失败照样有人救。
      return;
    }
    final double boxTop = boxRo.localToGlobal(Offset.zero).dy;
    final List<({double top, double height})?> rects = _lineKeys
        .map<({double top, double height})?>((GlobalKey k) {
          final RenderObject? ro = k.currentContext?.findRenderObject();
          if (ro is! RenderBox || !ro.hasSize) return null;
          // ★ 量**变形之后**的矩形,与样机 `boundingClientRect()` 同源
          //   (锚点已挂在 Transform 内侧,见 StoryLineView.measureKey)。
          //   直接用 localToGlobal + size 拿到的是布局位置与未缩放高度,
          //   会比样机早约一整行就把字点亮。
          final Rect r = MatrixUtils.transformRect(
            ro.getTransformTo(null),
            Offset.zero & ro.size,
          );
          return (top: r.top, height: r.height);
        })
        .toList();
    final List<StoryLineReveal>? next = settleStoryReveal(
      current: _reveal,
      rects: rects,
      boxTop: boxTop,
      boxHeight: boxRo.size.height,
      fromTop: _fromTop,
    );
    if (next == null && !_barAway) return;
    setState(() {
      _barAway = false; // 停下来,底栏弹回来
      if (next != null) _reveal = next;
    });
  }

  // ── 音频 ───────────────────────────────────────────────────────────

  Future<void> _toggleAudio(
    String url,
    Object source,
    MediaItem mediaItem,
  ) async {
    // 同一条音源在响 → 收(样机 `toggleChapAudio`:暂停即 destroy,再点从头重放)。
    // 不同音源 → 直接换源:共用播放器天然「后播的把前面那段顶掉」,
    // 旁白被节点导览顶掉后**不会**回来(样机同口径 —— 顶掉就是顶掉)。
    if (_playing && _audioSource == source) {
      await _player?.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    final ChapterAudioPlayer player = _player ??= _createPlayer();
    setState(() {
      _playing = true;
      _audioSource = source;
    });
    await player.play(Uri.parse(url), mediaItem: mediaItem);
  }

  /// 章节背景旁白:进本章自动播,玩家不用点(真源 `openChapterFull`  setData
  /// 回调里的 `playChapterAudio`,pages/play/index.js:2685,2701-2712)。
  /// 它**不新增任何按钮** —— 样机这一屏对旁白零控件,收/顶全跟着播放器走。
  void _maybeStartNarration(PlayChapter chapter) {
    if (_narrationStarted) return;
    final String url = (chapter.audioUrl ?? '').trim();
    if (url.isEmpty) return;
    _narrationStarted = true;
    // build 里不直接 setState 起播:排到本帧之后(样机也是渲染完的回调里才起)。
    unawaited(
      Future<void>.microtask(() async {
        if (!mounted) return;
        await _toggleAudio(
          url,
          kChapterNarrationSource,
          MediaItem(
            // 样机用裸 InnerAudioContext、没有锁屏元数据可抄;这里给
            // just_audio_background 的最小集:标题=章节名,封面=章节封面。
            id: 'chapter-narration-${chapter.chapterId}-$url',
            title: chapter.title ?? '这一章',
            artUri: mediaArtUri(chapter.cover),
            duration: const Duration(milliseconds: 1),
          ),
        );
      }),
    );
  }

  ChapterAudioPlayer _createPlayer() {
    final ChapterAudioPlayer player =
        widget.audioPlayerFactory?.call() ?? JustAudioChapterPlayer();
    // ★ 三条 listen 都要带 onError:流本身出错时没有 onError 就是**未捕获的
    //   zone error**,而按钮态照样卡在「播放中」。
    _endedSub = player.onStopped.listen((_) {
      if (mounted) setState(() => _playing = false);
    }, onError: (Object _) => _audioFailed());
    // 样机 `onPlay`:换源顶掉时 stopped 那拍先把播放态收了,真出声这一拍点回来。
    // 这条出错不再补提示(onError 那条流负责提示),只把状态收回。
    _startedSub = player.onStarted.listen(
      (_) {
        if (mounted) setState(() => _playing = true);
      },
      onError: (Object _) {
        if (mounted) setState(() => _playing = false);
      },
    );
    _errorSub = player.onError.listen(
      (_) => _audioFailed(),
      onError: (Object _) => _audioFailed(),
    );
    return player;
  }

  void _audioFailed() {
    if (!mounted) return;
    setState(() => _playing = false);
    // ★ `isError: true` 是**经裁决的有意选择**,别拿「样机是中性 cyToast」改回去:
    //   样机 `pages/play/index.js` 全页 `cyToast.error` **零命中** —— 那边压根没用过
    //   错误态,所以「样机是中性」只说明它没这个用法,不构成「设计上要中性」的证据。
    //   两件事性质也不同:「这一章还没写剧情」是**内容缺失的告知**(作者没写,已改中性),
    //   这一条是**操作真的失败了**(CDN 断流 / 解码失败),错误态是准确的。
    //   门禁 `remaining_native_notice_source_test.dart` 两种写法都放行,不构成约束。
    CyNativeNotice.show(context, '这段音频放不出来', isError: true);
  }

  // ── 内嵌 kit(契约 §1.5)───────────────────────────────────────────

  void _ensureKitController(int topicId, bool hasAdvanced) {
    if (!hasAdvanced || _kitController != null) return;
    final AdvancedPlayController controller = AdvancedPlayController(
      gateway: ref.read(advancedPlayGatewayProvider),
      uploadPhoto: ref.read(playApiProvider).uploadImage,
      activityId: widget.sessionKey.activityId ?? 0,
      topicId: topicId,
      nodeId: widget.nodeId,
    );
    controller.addListener(_onKitChanged);
    _kitController = controller;
    // start() 第一步就同步 notify(loading)—— 直接在 build 里调会把
    // setState 打进构建阶段;排一帧之后再来。
    scheduleMicrotask(() => unawaited(controller.start()));
  }

  void _onKitChanged() {
    if (mounted) setState(() {});
  }

  /// 内嵌段的内容决策。返回 null = **这一行不铺**：
  /// - 会话视图还没回来时按读条/失败呈现（真源页面级组件先于故事流存在，
  ///   没有这两态；App 的会话在故事流这一屏现取，三态必须自己齐）；
  /// - `present != inline` → 不铺（内嵌与弹层互斥，真源 `show = !inline`）；
  /// - 没有玩法段 / kind 无组件 → 不铺、不报错（真源「名字不在表里就当它
  ///   不存在」同口径）。
  Widget? _storyKitBody(AdvancedPlayController controller, PlayNode node) {
    final String playLabel = GameSection.gameTitleOf(node) ?? node.name;
    final AdvancedPlayPhase phase = controller.phase;
    if (phase == AdvancedPlayPhase.unsupported) {
      return _StoryKitMessage(text: controller.message);
    }
    final AdvancedPlayState? state = controller.state;
    if (state == null) {
      final bool failed =
          phase == AdvancedPlayPhase.error ||
          phase == AdvancedPlayPhase.unknown ||
          phase == AdvancedPlayPhase.retryable;
      if (!failed) {
        return const _StoryKitMessage(text: '正在装载这一站的玩法…', busy: true);
      }
      return _StoryKitMessage(
        text:
            '「$playLabel」的玩法没能加载'
            '${controller.message.isEmpty ? '' : '：${controller.message}'}',
        actionLabel: '重试',
        onAction: () => unawaited(controller.start()),
      );
    }
    if (!state.isInlinePresent) return null;
    final List<PlayKitCard> cards = projectPlayKit(state.playKit);
    if (cards.isEmpty || !hasPlayKitComponent(cards.first.kind)) return null;
    return ClipRect(
      key: const Key('story-kit-stage'),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * kStoryKitHeightFraction,
        child: buildPlayKitFullscreen(
          context,
          playKitFullscreenContextFor(context, controller, cards.first),
        ),
      ),
    );
  }

  // ── 组装 ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PlayNodesResult> session = ref.watch(
      playSessionProvider(widget.sessionKey),
    );
    final PlayNodesResult? data = session.value;
    final PlayNode? node = data?.nodeById(widget.nodeId);
    final PlayChapter? chapter = node == null ? null : data?.chapterOf(node);
    if (node == null || chapter == null || data == null) {
      return const Material(
        color: CyTokens.bgPage,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              '这一章暂时读不到，返回卡片再试',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CyTokens.textSecondary,
                fontSize: CyTokens.typeBody,
              ),
            ),
          ),
        ),
      );
    }

    final List<StoryLine> lines = buildStoryLines(
      chapter,
      nodeImgUrl: node.imgUrl,
    );
    // 进本章 = 这一屏拿到章节数据的一刻:自动播章节旁白(真源 playChapterAudio)。
    _maybeStartNarration(chapter);
    _ensureKitController(data.topicId, node.hasAdvanced);
    // 内嵌段(契约 §1.5):位置在故事流末尾 —— 真源把 kit 铺在「第一个未完成
    // 节点块」处,而章节 description 的服务端投影本就停在首个 node 块
    // (`ChapterFlowCompiler:beforeFirstNode`),行尾就是那个位置;真源的兜底
    // (没有未完成节点)同样接在末尾。
    final Widget? kitBody = _kitController == null
        ? null
        : _storyKitBody(_kitController!, node);
    final List<StoryLine> rows = <StoryLine>[
      ...lines,
      if (kitBody != null) const StoryKitLine('kit'),
    ];
    final int prevRowCount = _reveal.length;
    _syncLines(rows.length);
    // 内嵌段刚铺上(会话视图晚于首屏):补排一次 settle,新段不用等滚一下才显形。
    if (rows.length > prevRowCount && _settleTimer == null) {
      _settleTimer = Timer(kSettleSlow, _settle);
    }
    // ★ 滚动框刚回来(上一帧还在兜底态,排着的那次 settle 量了个空)—— 补排一次。
    //   没有这一下,`_barAway` 会卡在 true,底栏和音频键要等用户再滚一次才回来。
    if (_barAway && _settleTimer == null) {
      _settleTimer = Timer(kSettleSlow, _settle);
    }
    if (lines.isNotEmpty && !_primed) {
      _primed = true;
      _openTimer = Timer(kStoryOpenDelay, () {
        if (!mounted) return;
        setState(() => _open = true);
        _settle(); // 首屏那几行不用等用户滚动
      });
    }

    final MediaQueryData mq = MediaQuery.of(context);
    final double pad = mq.size.height * kStoryPadFraction;
    // 降低动态时底栏**不收**。藏起来等于把功能藏了(样机
    // `.play--reduced-motion .fx-story__cta.is-away` 把三条属性整条覆盖回去)。
    final bool away = _barAway && !mq.disableAnimations;
    // ★ 两条音轨、一个播放器(真源口径):
    //   · 右下这颗键放的是**节点**语音导览 —— 样机 index.js:1032
    //     `chapStory.audio = v.audio`(v = hero.node)← :1544 ← :2732
    //     `normNode: audio = n.audioUrl`。取错成章节旁白 = 多一颗样机没有的键、
    //     放的还是另一条音轨。
    //   · **章节背景旁白**(chapter.audioUrl,后端 `:736`)不走这颗键:
    //     进本章自动播(见 [kChapterNarrationSource]),样机 chfull 那一屏对
    //     旁白零控件。键上的播放态也只跟节点那条源走 —— 旁白在响时键不许亮,
    //     按下去是「顶掉旁白换导览」,不是「暂停旁白」。
    final String? audioUrl = node.audioUrl;
    final String? playName = GameSection.gameTitleOf(node);

    // ★ 底是 [Material] 而不是 ColoredBox:本页是全屏浮层,没有 Scaffold,
    //   而 `MaterialApp` 在**没有 Material 祖先**时给的 DefaultTextStyle 是
    //   `_errorTextStyle`(material/app.dart:45)—— fontFamily:'monospace' +
    //   黄色双下划线。本页各处的 TextStyle 只覆盖了 color/fontSize,
    //   decoration 与 fontFamily 是继承来的,于是整屏正文带着黄色双下划线、
    //   中文落到等宽族名上。与 club 那批 Cupertino 页同一处置。
    return Material(
      color: CyTokens.bgPage,
      child: AnimatedOpacity(
        opacity: _open ? 1 : 0,
        duration: kStoryFade,
        curve: Curves.ease,
        child: Stack(
          key: const Key('story-stack'),
          fit: StackFit.expand,
          children: <Widget>[
            // 后景粒子:画在正文**之下**。
            ValueListenableBuilder<double>(
              key: const Key('story-dust-back'),
              valueListenable: _dustTop,
              builder: (BuildContext context, double top, Widget? _) =>
                  StoryDust(layers: kStoryDustBack, scrollOffset: top),
            ),
            NotificationListener<ScrollNotification>(
              key: const Key('story-scroll'),
              onNotification: _onScroll,
              child: SingleChildScrollView(
                key: _boxKey,
                child: Column(
                  children: <Widget>[
                    SizedBox(height: pad),
                    for (int i = 0; i < rows.length; i++) ...<Widget>[
                      StoryLineView(
                        line: rows[i],
                        shown: _reveal[i].shown,
                        fromTop: _reveal[i].fromTop,
                        delay: _reveal[i].delay,
                        measureKey: _lineKeys[i],
                        child: rows[i] is StoryKitLine ? kitBody : null,
                      ),
                      // 段距铺在行**之间**,不进被缩放的盒子(见 storyLineGap)。
                      SizedBox(height: storyLineGap(rows[i])),
                    ],
                    // 真源块流尾块 `.chfull__end`(pages/play/index.wxml:126-129):
                    // 全部消息/kit 之后、下 pad 之前。它**不是** `.chfull__para`,
                    // 不进 measureChapter 的下标对齐,也不走逐行显形 —— 常驻。
                    _ChapterEnd(onContinue: _pop),
                    SizedBox(height: pad),
                  ],
                ),
              ),
            ),
            // ★ 近景粒子压在文字**之上**,遮挡出景深 —— 这是刻意的,不是缺陷
            //   (样机 `.fx-story__dust--front{ z-index:3; pointer-events:none }`)。
            IgnorePointer(
              key: const Key('story-dust-front'),
              child: ValueListenableBuilder<double>(
                valueListenable: _dustTop,
                builder: (BuildContext context, double top, Widget? _) =>
                    StoryDust(layers: kStoryDustFront, scrollOffset: top),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _Header(title: chapter.title ?? '', onBack: _pop),
            ),
            if (audioUrl != null && audioUrl.isNotEmpty)
              Positioned(
                right: kStoryAudioRight,
                bottom: kStoryAudioBottom,
                child: _AudioKey(
                  away: away,
                  // 播放态只认「此刻响的是节点这条导览」。章节旁白在响时键不许亮 ——
                  // 那颗键管的不是旁白,亮了就是假状态。
                  playing: _playing && _audioSource == node.nodeId,
                  // 锁屏元数据取真源字段:这是**节点**的语音导览,
                  // 标题=节点名、专辑=章节标题、封面=节点图。
                  // duration 的 1ms 是防炸兜底(见 just_audio_background
                  // `_seekRelative` 对 duration! 的强解包),不是数据。
                  onTap: () => _toggleAudio(
                    audioUrl,
                    node.nodeId,
                    MediaItem(
                      id: 'chapter-node-audio-${node.nodeId}-$audioUrl',
                      title: node.name,
                      album: chapter.title,
                      artUri: mediaArtUri(node.imgUrl),
                      duration: const Duration(milliseconds: 1),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _CtaBar(
                away: away,
                playName: playName,
                bottomInset: mq.padding.bottom,
                onBack: _pop,
                onPrimary: () {
                  // 样机 heroEnter 先把整个 hero 收掉再开玩法 —— 故事流是压在详情页上的
                  // 一层,先退掉它,玩法面板才不会开在它下面。
                  _pop();
                  widget.onPrimary(node);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pop() => Navigator.of(context).pop();

  /// 行数变了(会话刷新 / 内嵌段铺上)就调整 key 与显形状态。
  ///
  /// ★ **保住已有行的前缀**:整表重置会让刚铺上的内嵌段把滚到一半的正文
  ///   全部打回未显形(样机 `onAdvancedSession` 特意「只认还没铺过这一条
  ///   上升沿,否则每次会话视图都会把滚到一半的位置弹回开头」)。
  void _syncLines(int n) {
    if (_reveal.length == n) return;
    final List<StoryLineReveal> previous = _reveal;
    final List<GlobalKey> previousKeys = _lineKeys;
    _reveal = List<StoryLineReveal>.generate(
      n,
      (int i) => i < previous.length ? previous[i] : const StoryLineReveal(),
    );
    _lineKeys = List<GlobalKey>.generate(
      n,
      (int i) => i < previousKeys.length ? previousKeys[i] : GlobalKey(),
    );
  }
}

/// 内嵌 kit 段的读条 / 失败呈现:故事流里的一行话，错误文案点名失败对象。
class _StoryKitMessage extends StatelessWidget {
  const _StoryKitMessage({
    required this.text,
    this.busy = false,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final bool busy;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: kStoryTextInset,
      vertical: CyTokens.space2,
    ),
    child: Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (busy) ...<Widget>[
              const CupertinoActivityIndicator(),
              const SizedBox(width: CyTokens.space2),
            ],
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: CyTokens.typeBody,
                  color: CyTokens.textSecondary,
                ),
              ),
            ),
          ],
        ),
        if (actionLabel != null && onAction != null) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          SizedBox(
            width: 160,
            child: CyNativeButton(
              key: const Key('story-kit-retry'),
              label: actionLabel!,
              role: CyNativeButtonRole.secondary,
              onPressed: onAction!,
            ),
          ),
        ],
      ],
    ),
  );
}

/// 顶栏。★ 自带渐隐:正文是从它底下滚过去的,不压住会把章节名和返回钮糊掉。
class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        CyTokens.pageX,
        MediaQuery.paddingOf(context).top,
        CyTokens.pageX,
        12, // 24rpx
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const <double>[0, 0.62, 1],
          colors: <Color>[
            CyTokens.bgPage.withValues(alpha: 0.96),
            CyTokens.bgPage.withValues(alpha: 0.88),
            CyTokens.bgPage.withValues(alpha: 0),
          ],
        ),
      ),
      child: Row(
        children: <Widget>[
          CyNativeIconButton(
            key: const Key('story-back'),
            label: '收起，回到卡片',
            icon: const CyNativeButtonIcon(
              sfSymbol: 'chevron.backward',
              fallback: CupertinoIcons.back,
            ),
            onPressed: onBack,
            size: CyTokens.btnH,
          ),
          // 章节名居中:两侧各留一个和返回钮等宽的占位,标题才真在正中(样机同款)。
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: CyTokens.typeBody,
                fontWeight: FontWeight.w700,
                color: CyTokens.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: CyTokens.btnH),
        ],
      ),
    );
  }
}

/// 这一章的音频键。常驻右下,随底栏一起收起/弹回。
class _AudioKey extends StatelessWidget {
  const _AudioKey({
    required this.away,
    required this.playing,
    required this.onTap,
  });

  final bool away;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: away ? const Offset(0, kStoryAudioAwayShift) : Offset.zero,
      duration: kStoryBarSlide,
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: away ? 0 : 1,
        duration: kStoryBarFade,
        child: IgnorePointer(
          ignoring: away,
          child: Semantics(
            button: true,
            label: playing ? '暂停这一章的音频' : '播放这一章的音频',
            onTap: onTap,
            child: ExcludeSemantics(
              // 外壳只负责 44pt 命中区(背景透明,看不见);可见的是里面那个 36pt 的圆。
              child: SizedBox.square(
                key: const Key('story-audio'),
                dimension: kStoryAudioHit,
                child: CupertinoButton(
                  onPressed: onTap,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size.square(kStoryAudioHit),
                  child: Container(
                    width: kStoryAudioDisc,
                    height: kStoryAudioDisc,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // 播放态反色(`.fx-story__aud.is-on`)。
                      color: playing
                          ? CyTokens.textPrimary
                          : CyTokens.bgElevated,
                    ),
                    child: Icon(
                      // 样机播放态仍是 play 图标,只反色 —— 照搬,不「修正」。
                      CupertinoIcons.play_fill,
                      size: 15, // 30rpx
                      color: playing
                          ? CyTokens.textInverse
                          : CyTokens.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部双 CTA。滑动时整条收下去,停下来再弹回 —— 正文往上走的时候不该有东西压在下面挡路。
class _CtaBar extends StatelessWidget {
  const _CtaBar({
    required this.away,
    required this.playName,
    required this.bottomInset,
    required this.onBack,
    required this.onPrimary,
  });

  final bool away;
  final String? playName;
  final double bottomInset;
  final VoidCallback onBack;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    final String primaryLabel = (playName == null || playName!.isEmpty)
        ? '开始互动 获得奖励！'
        : '开始 · $playName';
    return AnimatedSlide(
      offset: away ? const Offset(0, 1.05) : Offset.zero,
      duration: kStoryBarSlide,
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: away ? 0 : 1,
        duration: kStoryBarFade,
        child: IgnorePointer(
          key: const Key('story-cta'),
          ignoring: away,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              CyTokens.pageX,
              44, // 88rpx
              CyTokens.pageX,
              CyTokens.space5 + bottomInset,
            ),
            decoration: BoxDecoration(
              // 只用渐隐,不铺纯色 —— 纯色在按钮下方是一整块黑框,很显眼。
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const <double>[0, 0.42, 1],
                colors: <Color>[
                  CyTokens.bgPage.withValues(alpha: 0),
                  CyTokens.bgPage.withValues(alpha: 0.72),
                  CyTokens.bgPage.withValues(alpha: 0.95),
                ],
              ),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: CyNativeButton(
                    label: '回到卡片',
                    role: CyNativeButtonRole.secondary,
                    onPressed: onBack,
                  ),
                ),
                const SizedBox(width: CyTokens.space3),
                Expanded(
                  child: CyNativeButton(
                    label: primaryLabel,
                    onPressed: onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 块流尾块(真源 `.chfull__end`,pages/play/index.wxml:126-129)。
///
/// 全部消息/kit 内容之后、下 pad 之前:一行小字「已读到当前解锁位置」+ 一颗
/// 全圆角主 CTA「继续探索」。几何与色值照真源引文(21rpx copy → [CyTokens.typeCaption]
/// + `#8A93A0` → [CyTokens.textSecondary];88rpx 高/999rpx 全圆角 → [CyNativeButton]
/// primary 主 CTA,暗色主题下即白底黑字,与真源 `#FFFFFF`/`#111111` 同观)。
///
/// ★ 点按 = 真源 `closeChapterFull`:停 dream + 停这一屏的音频 + 收起全屏回宿主。
///   App 里退出路径不止一条(返回钮、侧滑、系统返回都会走到 dispose),音频的停止
///   统一挂在 [State.dispose](`_player?.dispose()`),这里只需 `_pop()` 收起整屏 ——
///   与顶栏返回钮、底栏「回到卡片」是同一个关闭语义。本页没有 dream 段,故无需停表。
class _ChapterEnd extends StatelessWidget {
  const _ChapterEnd({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => Padding(
    // 真源 `.chfull__end{ padding:42rpx 46rpx 0 }`;横向与正文同栏(kStoryTextInset)。
    padding: const EdgeInsets.fromLTRB(kStoryTextInset, 21, kStoryTextInset, 0),
    child: Column(
      children: <Widget>[
        // `.chfull__end-copy{ margin-bottom:15rpx; text-align:center }`
        const Text(
          '已读到当前解锁位置',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: CyTokens.typeCaption,
            color: CyTokens.textSecondary,
          ),
        ),
        const SizedBox(height: CyTokens.space2),
        // `.chfull__continue{ height:88rpx; border-radius:999rpx }` 铺满一栏宽。
        CyNativeButton(
          key: const Key('story-continue'),
          label: '继续探索',
          width: double.infinity,
          onPressed: onContinue,
        ),
      ],
    ),
  );
}
