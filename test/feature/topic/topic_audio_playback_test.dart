import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:just_audio_background/just_audio_background.dart'
    show MediaItem;

import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/feature/topic/topic_detail_controller.dart';
import 'package:chengyin_app/feature/topic/topic_detail_page.dart';

TopicDetail _topicWithAudio() => TopicDetail.fromJson(<String, dynamic>{
  'id': 12,
  'name': '静安微旅行',
  'description': '测试用',
  'audioUrl': 'https://example.com/guide.mp3',
  'audioDuration': 88,
  'chaptersList': <dynamic>[],
});

class _FakeTopicAudioPlayer implements TopicAudioPlayer {
  final StreamController<TopicAudioPlaybackState> _states =
      StreamController<TopicAudioPlaybackState>.broadcast();
  final StreamController<Object> _errors = StreamController<Object>.broadcast();

  int loadCalls = 0;
  int playCalls = 0;
  int pauseCalls = 0;
  int seekToStartCalls = 0;
  int disposeCalls = 0;
  Uri? loadedUri;
  MediaItem? loadedMediaItem;
  Completer<void>? loadCompleter;
  Object? pauseError;

  @override
  Stream<TopicAudioPlaybackState> get stateStream => _states.stream;

  @override
  Stream<Object> get errorStream => _errors.stream;

  @override
  Future<void> load(Uri uri, {MediaItem? mediaItem}) async {
    loadCalls += 1;
    loadedUri = uri;
    loadedMediaItem = mediaItem;
    await loadCompleter?.future;
  }

  @override
  Future<void> play() async {
    playCalls += 1;
    _states.add(TopicAudioPlaybackState.playing);
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    if (pauseError case final Object error) throw error;
    _states.add(TopicAudioPlaybackState.paused);
  }

  @override
  Future<void> seekToStart() async {
    seekToStartCalls += 1;
  }

  void completePlayback() {
    _states.add(TopicAudioPlaybackState.completed);
  }

  void failDuringPlayback([Object error = const FormatException('stream')]) {
    _errors.add(error);
  }

  /// 流本身出错(不是流上送来一个错误对象)。没有 `onError:` 的 listen 遇到它
  /// 就是未捕获的 zone error。
  void breakStateStream() {
    _states.addError(const FormatException('state stream broke'));
  }

  void breakErrorStream() {
    _errors.addError(const FormatException('error stream broke'));
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await _states.close();
    await _errors.close();
  }
}

/// 假的 `just_audio.AudioPlayer`。
///
/// ⚠️ 「`just_audio.AudioPlayer` 单测里起不来所以胶水层覆盖不到」**不成立**:
///   起不来的是真播放器(要平台通道),但 `AudioPlayer` 是普通 class
///   (just_audio.dart:58),`implements … + noSuchMethod` 就能造一个注进
///   `JustAudioTopicAudioPlayer` 的 `{player}`。钉的正是那两行**胶水**:接哪条流。
///   接错了照样编译得过、整套测试照样全绿,只有真机 CDN 断流才炸出来。
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
    if (setUrlThrows case final Object error) throw error;
    setUrlArg = url;
    return null;
  }

  @override
  Future<void> play() async => didPlay = true;

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration? position, {int? index}) async {}

  @override
  Future<void> dispose() async {
    await _states.close();
    await _errors.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, _FakeTopicAudioPlayer player) async {
  await tester.binding.setSurfaceSize(const Size(390, 1200));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        topicDetailProvider(12).overrideWith((ref) async => _topicWithAudio()),
      ].cast(),
      child: MaterialApp(
        home: TopicDetailPage(topicId: 12, audioPlayerFactory: () => player),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('主题音频首次点击播放，再次点击暂停，并更新 VoiceOver 动作', (tester) async {
    final player = _FakeTopicAudioPlayer();
    await _pump(tester, player);

    expect(find.bySemanticsLabel('播放主题音频'), findsOneWidget);

    await tester.tap(find.byKey(const Key('topic-audio')));
    await tester.pump();

    expect(player.loadedUri, Uri.parse('https://example.com/guide.mp3'));
    expect(player.loadCalls, 1);
    expect(player.playCalls, 1);
    // 锁屏/控制中心元数据:必须带真实业务字段(名称/时长),不许缺挂。
    expect(player.loadedMediaItem?.title, '静安微旅行');
    expect(player.loadedMediaItem?.duration, const Duration(seconds: 88));
    expect(find.bySemanticsLabel('暂停主题音频'), findsOneWidget);
    expect(find.textContaining('正在播放'), findsOneWidget);

    await tester.tap(find.byKey(const Key('topic-audio')));
    await tester.pump();

    expect(player.pauseCalls, 1);
    expect(find.bySemanticsLabel('播放主题音频'), findsOneWidget);
    expect(player.loadCalls, 1, reason: '暂停后再播不应重复加载同一 URL');
  });

  testWidgets('播放完成后回到可重播状态并将播放头归零', (tester) async {
    final player = _FakeTopicAudioPlayer();
    await _pump(tester, player);

    await tester.tap(find.byKey(const Key('topic-audio')));
    await tester.pump();
    player.completePlayback();
    await tester.pump();
    // CyCell 现在走系统 CupertinoListTile(无按压动画):错误经 microtask 送达,
    // 这一帧只让它落地并排出下一帧 —— 所以要多画一帧才看得到文案。
    await tester.pump();

    expect(find.bySemanticsLabel('播放主题音频'), findsOneWidget);
    expect(player.pauseCalls, 1);
    expect(player.seekToStartCalls, 1);

    await tester.tap(find.byKey(const Key('topic-audio')));
    await tester.pump();
    expect(player.playCalls, 2);
    expect(player.loadCalls, 1);
  });

  testWidgets('播放已开始后的底层错误不会变成未处理异常', (tester) async {
    final player = _FakeTopicAudioPlayer();
    await _pump(tester, player);

    await tester.tap(find.byKey(const Key('topic-audio')));
    await tester.pump();
    expect(find.bySemanticsLabel('暂停主题音频'), findsOneWidget);

    player.failDuringPlayback();
    await tester.pump();
    await tester.pump(); // 同上:流事件晚一帧落地

    expect(find.bySemanticsLabel('播放主题音频'), findsOneWidget);
    expect(find.textContaining('加载失败'), findsOneWidget);
    expect(find.text('主题音频暂时无法播放'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('暂停失败会回到可重试状态，不泄漏异步异常', (tester) async {
    final player = _FakeTopicAudioPlayer();
    await _pump(tester, player);

    await tester.tap(find.byKey(const Key('topic-audio')));
    await tester.pump();
    player.pauseError = Exception('暂停失败');

    await tester.tap(find.byKey(const Key('topic-audio')));
    await tester.pump();

    expect(find.bySemanticsLabel('播放主题音频'), findsOneWidget);
    expect(find.textContaining('加载失败'), findsOneWidget);
    expect(find.text('主题音频暂时无法播放'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('音频加载与失败有可达反馈，退页释放播放器', (tester) async {
    final player = _FakeTopicAudioPlayer()..loadCompleter = Completer<void>();
    await _pump(tester, player);

    await tester.tap(find.byKey(const Key('topic-audio')));
    await tester.pump();
    expect(find.bySemanticsLabel('主题音频加载中'), findsOneWidget);
    expect(find.textContaining('正在加载'), findsOneWidget);

    player.loadCompleter!.completeError(Exception('网络错误'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('加载失败'), findsOneWidget);
    expect(find.bySemanticsLabel('播放主题音频'), findsOneWidget);
    expect(find.text('主题音频暂时无法播放'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(player.disposeCalls, 1);
  });

  group('★状态流折叠:接得住的两个终态,和接不住的那一个', () {
    just_audio.PlayerState st(bool playing, just_audio.ProcessingState p) =>
        just_audio.PlayerState(playing, p);

    Future<List<TopicAudioPlaybackState>> foldOf(
      List<just_audio.PlayerState> seq,
    ) => topicAudioStatesFrom(
      Stream<just_audio.PlayerState>.fromIterable(seq),
    ).toList();

    test('★播完(completed)报终态 —— 此时 playing 仍是 true,只盯 playing 收不到', () async {
      expect(
        await foldOf(<just_audio.PlayerState>[
          st(false, just_audio.ProcessingState.idle),
          st(true, just_audio.ProcessingState.ready),
          st(true, just_audio.ProcessingState.completed),
        ]),
        <TopicAudioPlaybackState>[
          TopicAudioPlaybackState.paused,
          TopicAudioPlaybackState.playing,
          TopicAudioPlaybackState.completed,
        ],
      );
    });

    test('★平台侧打断(来电/音频会话被抢)收回按钮态 —— 样机 onStop 的对应物', () async {
      expect(
        await foldOf(<just_audio.PlayerState>[
          st(false, just_audio.ProcessingState.idle),
          st(true, just_audio.ProcessingState.buffering),
          st(true, just_audio.ProcessingState.ready),
          st(false, just_audio.ProcessingState.ready),
        ]),
        <TopicAudioPlaybackState>[
          TopicAudioPlaybackState.paused,
          TopicAudioPlaybackState.loading,
          TopicAudioPlaybackState.playing,
          TopicAudioPlaybackState.paused,
        ],
        reason: '只收 completed 的话被打断时暂停图标一直亮着,用户得点两下才能重来',
      );
    });

    test('★出错这一路在状态流上看不见 —— 这就是必须订 errorStream 的理由', () async {
      expect(
        await foldOf(<just_audio.PlayerState>[
          st(false, just_audio.ProcessingState.idle),
          st(true, just_audio.ProcessingState.ready),
          // just_audio 出错时 playing 仍是 true,只有 processingState 掉回 idle。
          st(true, just_audio.ProcessingState.idle),
        ]),
        <TopicAudioPlaybackState>[
          TopicAudioPlaybackState.paused,
          TopicAudioPlaybackState.playing,
        ],
        reason: 'distinct 把它吃掉了 —— 断流后状态流一声不吭,按钮停在「播放中」',
      );
    });
  });

  test('★运行中的播放错误也要出来 —— 起播那两条 Future 盖不住 CDN 断流', () async {
    final launch = StreamController<Object>();
    final runtime = StreamController<Object>();
    final seen = <Object>[];
    final sub = topicAudioErrorsFrom(
      launch.stream,
      runtime.stream,
    ).listen(seen.add);
    launch.add('load 404');
    runtime.add('播到一半断流');
    await pumpEventQueue();
    expect(seen, <Object>[
      'load 404',
      '播到一半断流',
    ], reason: 'just_audio 只从 errorStream 报运行时错误,漏订阅 = 断流后按钮永远亮着');
    await sub.cancel();
    await launch.close();
    await runtime.close();
  });

  group('★JustAudioTopicAudioPlayer 的胶水:接哪条流', () {
    test('★运行中断流必须从 player.errorStream 出来', () async {
      final raw = _FakeJustAudio();
      final TopicAudioPlayer p = JustAudioTopicAudioPlayer(player: raw);
      final seen = <Object>[];
      final sub = p.errorStream.listen(seen.add);
      raw.emitRuntimeError();
      await pumpEventQueue();
      expect(
        seen,
        hasLength(1),
        reason:
            '只订 load/play 那两条 Future 的话,CDN 播到一半断流一句提示都没有 —— '
            '按钮一直亮着,点两下才能重来',
      );
      await sub.cancel();
      await p.dispose();
    });

    test('★起播失败(play() 抛)也从同一条流出来', () async {
      final raw = _FakeJustAudio();
      final TopicAudioPlayer p = JustAudioTopicAudioPlayer(player: raw);
      final seen = <Object>[];
      final sub = p.errorStream.listen(seen.add);
      await p.load(Uri.parse('https://cdn.example.com/guide.mp3'));
      expect(raw.setUrlArg, 'https://cdn.example.com/guide.mp3');
      await p.play();
      await pumpEventQueue();
      expect(raw.didPlay, isTrue);
      expect(seen, isEmpty, reason: '没出错就不该报错');
      await sub.cancel();
      await p.dispose();
    });

    test('★load 失败照旧从 Future 抛给调用方 —— UI 那一支靠它', () async {
      final raw = _FakeJustAudio()..setUrlThrows = Exception('404');
      final TopicAudioPlayer p = JustAudioTopicAudioPlayer(player: raw);
      await expectLater(
        p.load(Uri.parse('https://cdn.example.com/guide.mp3')),
        throwsA(isA<Exception>()),
      );
      await p.dispose();
    });

    test('★状态必须从 player.playerStateStream 出来', () async {
      final raw = _FakeJustAudio();
      final TopicAudioPlayer p = JustAudioTopicAudioPlayer(player: raw);
      final seen = <TopicAudioPlaybackState>[];
      final sub = p.stateStream.listen(seen.add);
      raw.emitState(true, just_audio.ProcessingState.ready);
      raw.emitState(true, just_audio.ProcessingState.completed);
      await pumpEventQueue();
      expect(seen, <TopicAudioPlaybackState>[
        TopicAudioPlaybackState.playing,
        TopicAudioPlaybackState.completed,
      ], reason: '接错流 = 播完了按钮还亮着,用户得点两下才能重来');
      await sub.cancel();
      await p.dispose();
    });
  });

  testWidgets('★状态流自己出错也走失败提示,不变成未捕获的 zone error', (tester) async {
    final player = _FakeTopicAudioPlayer();
    await _pump(tester, player);

    await tester.tap(find.byKey(const Key('topic-audio')));
    await tester.pump();
    expect(find.bySemanticsLabel('暂停主题音频'), findsOneWidget);

    player.breakStateStream();
    await tester.pump();
    await tester.pump(); // 同上:流事件晚一帧落地

    expect(find.bySemanticsLabel('播放主题音频'), findsOneWidget);
    expect(find.text('主题音频暂时无法播放'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('★错误流自己出错也走失败提示,不变成未捕获的 zone error', (tester) async {
    final player = _FakeTopicAudioPlayer();
    await _pump(tester, player);

    await tester.tap(find.byKey(const Key('topic-audio')));
    await tester.pump();
    expect(find.bySemanticsLabel('暂停主题音频'), findsOneWidget);

    player.breakErrorStream();
    await tester.pump();
    await tester.pump(); // 同上:流事件晚一帧落地

    expect(find.bySemanticsLabel('播放主题音频'), findsOneWidget);
    expect(find.text('主题音频暂时无法播放'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
