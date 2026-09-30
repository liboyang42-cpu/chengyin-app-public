// 屏③ 章节故事流的基准图。
//
// ⚠️ **本文件一律用定量 `pump(Duration)`,不用 `pumpAndSettle`**:`StoryDust`
//   照样机是无限 rAF(Task 4),挂着它就永远有帧被排上,`pumpAndSettle` 必然 timeout。
//   计划 brief 原本裁决「包一层 `TickerMode(enabled:false)`」——**实测行不通**,
//   它会连行的显形动画(`TweenAnimationBuilder`)一起冻住,拍出来是一片黑。
//   与 `test/feature/play/chapter_story_page_test.dart` 同款处置,不改生产代码。
//
// ⚠️ 视口取真机档 390×844 而不是别的 golden 那种 390×1900:段距 400rpx(=200pt)
//   是**刻意**让「屏幕上同时只有一段」的(story_line_view.dart:45),拉高视口就把
//   这条设计意图拍没了,基线也就不再是用户会看到的画面。
//
// 更新基准图:flutter test --update-goldens test/golden/page_free_explore_story_golden_test.dart
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/free_explore/chapter_story_page.dart';
import 'package:chengyin_app/feature/play/play_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_background/just_audio_background.dart'
    show MediaItem;

import 'golden_theme.dart';

const PlaySessionKey _key = (activityId: 56, topicId: null);

/// 静默播放器:golden 不跑平台通道(真 just_audio 在测试 binding 里
/// dispose 会炸 MissingPluginException),旁白自动播也不该改变画面。
class _NoAudio implements ChapterAudioPlayer {
  @override
  Stream<void> get onStopped => const Stream<void>.empty();

  @override
  Stream<void> get onStarted => const Stream<void>.empty();

  @override
  Stream<Object> get onError => const Stream<Object>.empty();

  @override
  Future<void> play(Uri uri, {MediaItem? mediaItem}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _Api implements PlayApi {
  _Api(this.payload);

  final Map<String, dynamic> payload;

  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async =>
      PlayNodesResult.fromJson(payload);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// ★ fixture 喂 `/api/play/nodes` 的**原始 JSON**,整条走 `PlayNodesResult.fromJson`。
/// 用构造函数直接造模型对象会绕过解析层,后端键名与模型对不上就完全隐形 ——
/// 这条分支上已经栽过三次(最严重一次:章节三字段恒 null,而基线图里因为 fixture
/// 自造一直好好显示着)。
///
/// ⚠️ 章节键照后端:`name` / `imgArr` / `description` / `audioUrl`,
///   **后端没有 `cover` 这个键** —— `PlayChapter.cover` 由 `imgArr` 逗号首段派生
///   (checkin_models.dart:489)。所以这里喂 `imgArr`。
/// 眉标「第 N 章」按数组下标生成,所以摆两章,让本节点落在第 2 章。
Map<String, dynamic> _payload({String? audioUrl}) => <String, dynamic>{
  'topicId': 9,
  'mode': 2,
  'playable': true,
  'total': 4,
  'doneCount': 0,
  'chapters': <dynamic>[
    <String, dynamic>{'chapterId': 100, 'name': '晨间烘焙'},
    <String, dynamic>{
      'chapterId': 200,
      'name': '旧书与唱片',
      'imgArr': 'https://picsum.photos/seed/fx-story/600/400',
      // 章节背景旁白(后端 `:736`)—— 进本章**自动播**,不长按钮、不改画面,
      // 所以基线对它无感(播放器在测试里被换成静默假件,见 _NoAudio)。
      // 音频键照旧只认节点的导览:键要是照它渲,下面那张「没有音频」的基线
      // 会长出一颗键来。
      'audioUrl': 'https://cdn.example.com/chapter-narration.mp3',
      'description':
          '推门进去,先闻到的是纸和灰的味道。\n\n'
          '靠墙那排唱片按年代排,最上面一格落着一层薄灰。\n\n'
          '老板说,愿意讲价的人他都记得住。',
    },
  ],
  'nodes': <dynamic>[
    <String, dynamic>{
      'nodeId': 12,
      'name': '长乐路旧物店',
      'address': '长乐路 88 号',
      'sortId': 2,
      'done': false,
      'arrived': false,
      'selfReported': false,
      'chapterId': 200,
      'imgUrl': 'https://picsum.photos/seed/fx-node/600/800',
      'hasGame': true,
      'gameTitle': '猜年代小游戏',
      // ★ 屏③ 右下那颗音频键的音源是**节点**的语音导览(后端 `:594`),
      //   不是上面那条章节旁白。
      'audioUrl': audioUrl,
    },
  ],
};

Future<void> _pump(WidgetTester tester, {String? audioUrl}) async {
  // ★ 走 `tester.view` 而不是别的 golden 那种 `setSurfaceSize` ——
  //   `setSurfaceSize` 只改渲染面尺寸,**不改 MediaQuery**:实测拍出来的画布是
  //   390×844,而页面读到的 `mq.size` 还是默认的 800×600。本页上下留白是
  //   22vh(`kStoryPadFraction`)、底栏内边距吃 `mq.padding.bottom`,
  //   照 600 算出来的留白是 132pt 而不是 185.7pt —— 基线会把这个错误固化成期望。
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        playApiProvider.overrideWithValue(_Api(_payload(audioUrl: audioUrl))),
      ].cast(),
      child: MaterialApp(
        theme: goldenTheme(),
        debugShowCheckedModeBanner: false,
        home: ChapterStoryPage(
          sessionKey: _key,
          nodeId: 12,
          onPrimary: _noop,
          audioPlayerFactory: () => _NoAudio(),
        ),
      ),
    ),
  );
  await tester.pump(); // 取数落地
  await tester.pump(const Duration(milliseconds: 400)); // 整屏渐显 + 开页 30ms
  await tester.pump(const Duration(milliseconds: 900)); // 首屏那几行逐条显形跑完
  // ★ 插图那一块还得再走几帧:flutter_test 的 HttpClient 兜底对所有请求回 400,
  //   `Image.network` 的失败是**异步**到达的,不多跑几帧就停在「加载中」——
  //   而加载中画的是空,于是插图块在基线里是一片纯黑,与「没有这一块」无从分辨。
  //   多跑几帧后 `CyNetImage` 的兜底底色(#141416)才落到画布上,基线才真的钉住它。
  //   (这里不能用 `pumpAndSettle` 让它自己跑完 —— StoryDust 是无限 ticker。)
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void _noop(PlayNode node) {}

void main() {
  testWidgets('★ 章节故事流常态:抬头 + 正文 + 插图,首屏已显形', (WidgetTester tester) async {
    await _pump(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_free_explore_story.png'),
    );
  });

  testWidgets('★ 章节故事流有音频:右下音频键 + 底栏展开态', (WidgetTester tester) async {
    await _pump(tester, audioUrl: 'https://cdn.example.com/ch-200.mp3');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_free_explore_story_audio.png'),
    );
  });
}
