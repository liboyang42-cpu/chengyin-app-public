// 屏④ 店铺分身对话:页面组装 + 入口接线(批 4-7)。
//
// ★ 本文件钉的是**只有到了页面这一层才谈得上**的三件事:
//   ① 闸关时端服务端原话(口径①)② 重答失败不覆盖原文(口径②)
//   ③ 重答改写时消息 id 不变(口径③)。前六棒都够不着 —— 没有 controller
//   就没有「这次别 push」这条分支。
//
// ⚠️ 视口一律 390×844:消息流的盒子是 `top:380 / bottom:150`,默认的 800×600 里
//   只剩 70pt 高,`重答` 会被挤到视口外 —— 那样点不着的红是假红(假绿 ③ 的反面)。

import 'dart:async';
import 'dart:io';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/widgets/cy_native_notice.dart';
import 'package:chengyin_app/data/api/ai_npc_api.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/data/models/shop_npc_models.dart';
import 'package:chengyin_app/feature/play/free_explore/card_detail_page.dart';
import 'package:chengyin_app/feature/play/free_explore/shop_npc_logic.dart';
import 'package:chengyin_app/feature/play/free_explore/shop_npc_page.dart';
import 'package:chengyin_app/feature/play/free_explore/shop_npc_voice.dart';
import 'package:chengyin_app/feature/play/free_explore/widgets/npc_input_bar.dart';
import 'package:chengyin_app/feature/play/play_session_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const PlaySessionKey _key = (activityId: 77, topicId: null);

/// ★ fixture 喂 `/api/play/nodes` 的**原始 JSON**,整条走 `PlayNodesResult.fromJson`
/// —— 分身那块尤其要走解析层:`PlayNpcBrief.fromJson` 会把「有 npc 对象但没名字」
/// 判成 null(checkin_models.dart:446),而入口那条判据正是它。
/// 用构造函数直接造 `PlayNpcBrief` 会把这条判据一起绕过去。
///
/// (`ShopNpcMessage` 是例外:它是本端自攒的消息,后端没有端点返回这个形状,
///  Task 1 确认它**故意没有 fromJson**。)
Map<String, dynamic> _payload({Object? npc = _npc}) => <String, dynamic>{
  'topicId': 23,
  'mode': 2,
  'playable': true,
  'total': 1,
  'doneCount': 0,
  'chapters': <dynamic>[
    <String, dynamic>{'chapterId': 100, 'name': '旧书与唱片'},
  ],
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
      'npc': ?npc,
    },
  ],
};

const Map<String, dynamic> _npc = <String, dynamic>{
  'name': '阿旧',
  'greeting': '随便挑挑，看上哪张问我',
};

class _PlayApi implements PlayApi {
  _PlayApi(this.payload);

  final Map<String, dynamic> payload;

  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async =>
      PlayNodesResult.fromJson(payload);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 三种败法各来一次:后端说了话(闸关)、根本没送到(dio)、送到了但没话。
class _NpcApi implements AiNpcApi {
  _NpcApi({
    this.reply,
    this.serverMsg,
    this.offline = false,
    this.asr,
    this.thirdKind = false,
  });

  String? reply;
  String? serverMsg;
  bool offline;
  String? asr;

  /// 第三种异常:**既不是** [ShopNpcException] **也不是** [DioException]。
  ///
  /// 抛的就是复审实证的那一个:`voiceChat` 里 `await MultipartFile.fromFile(...)`
  /// 在临时文件不在时抛 `PathNotFoundException`,而且它在 `dio.post` **之前**求值,
  /// dio 的包装够不着(探针实测 `isDio=false`)。
  bool thirdKind;

  final List<String> asked = <String>[];
  final List<String> uploaded = <String>[];

  /// 挂住这次请求,好在「还在飞」那一刻断言。null = 立刻回。
  Completer<void>? gate;

  @override
  Future<ShopNpcReply> shopChat({
    required String requestId,
    required int nodeId,
    required String message,
  }) async {
    asked.add(message);
    return _answer();
  }

  @override
  Future<ShopNpcReply> voiceChat({
    required String requestId,
    required int nodeId,
    required String filePath,
  }) async {
    uploaded.add(filePath);
    return _answer();
  }

  Future<ShopNpcReply> _answer() async {
    if (gate != null) await gate!.future;
    if (thirdKind) {
      throw PathNotFoundException(
        '/tmp/clip.m4a',
        const OSError('No such file or directory', 2),
      );
    }
    if (offline) {
      throw DioException(requestOptions: RequestOptions(path: '/x'));
    }
    if (serverMsg != null) throw ShopNpcException(serverMsg);
    // 后端真实形状:`data` 里是 NpcChatResp,`asr` 在 AjaxResult 顶层。
    return ShopNpcReply.fromJson(<String, dynamic>{
      if (reply != null) 'text': reply,
    }, asr: asr);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 录音器替身。`ShopNpcVoice` 的公开面只有这四个成员。
class _SpyVoice implements ShopNpcVoice {
  int disposed = 0;
  bool _rec = false;
  void Function(String path)? _onClip;
  void Function(String message)? _onNotice;

  /// true = `stop()` 走真实现里 `path == null` 那一支:**端话,不吐文件**。
  ///
  /// 真触发点在 `ShopNpcVoice.stop():157` —— 按住够久、退页时 `_recorder.stop()`
  /// 拿不到文件(权限被撤、被系统打断)。`_boot():92/112` 的权限被拒 / 开录失败
  /// 也是同一个出口,而**首次按下弹权限框那一次尤其常见**。
  bool noticeOnStop = false;

  final List<String> noticed = <String>[];

  @override
  bool get recording => _rec;

  @override
  Future<void> start({
    required void Function(String path) onClip,
    required void Function(String message) onNotice,
  }) async {
    _rec = true;
    _onClip = onClip;
    _onNotice = onNotice;
  }

  @override
  Future<void> stop() async {
    if (!_rec) return;
    _rec = false;
    if (noticeOnStop) {
      noticed.add(kVoiceRecordFailed);
      _onNotice?.call(kVoiceRecordFailed);
      return;
    }
    _onClip?.call('/tmp/clip.m4a');
  }

  /// ⚠️ 真的 [ShopNpcVoice.dispose] 是 `stop()` 打头,所以「握着麦克风退页」
  /// 会一路走到 `onClip` → `_uploadVoice`。替身这里少走一步的话,
  /// 那条路在测试里根本不存在。
  @override
  Future<void> dispose() async {
    disposed++;
    await stop();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester t,
  _NpcApi api, {
  _SpyVoice? voice,
  double keyboard = 0,
}) async {
  addTearDown(() {
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
    t.view.resetViewInsets();
  });
  t.view.devicePixelRatio = 3;
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        playApiProvider.overrideWithValue(_PlayApi(_payload())),
        aiNpcApiProvider.overrideWithValue(api),
      ].cast(),
      child: MaterialApp(
        home: ShopNpcPage(sessionKey: _key, nodeId: 1, voice: voice),
      ),
    ),
  );
  await t.pump(); // 取数落地
  await t.pump(const Duration(milliseconds: 400)); // 开页 30ms + 整屏渐显
}

/// 打一句并等回来。
Future<void> _say(WidgetTester t, String text) async {
  await t.enterText(find.byType(CupertinoTextField), text);
  await t.pump();
  await t.tap(find.byKey(const Key('npc-input-send')));
  await t.pump(); // setState:我方消息 + thinking
  await t.pump(); // 请求回来
  await t.pump();
}

Future<void> _tapRetry(WidgetTester t) async {
  await t.tap(find.text('重答'));
  await t.pump();
  await t.pump();
  await t.pump();
}

void main() {
  tearDown(CyNativeNotice.hide);

  // ── 口径① 闸关时端服务端原话 ───────────────────────────────────────

  testWidgets('★闸关时端后端原话,不编话也不落到兜底句', (WidgetTester t) async {
    final _NpcApi api = _NpcApi(serverMsg: '店铺分身对话还没开放');
    await _pump(t, api);
    await _say(t, '几点关门');

    expect(find.text('店铺分身对话还没开放'), findsOneWidget);
    expect(
      find.text(kShopNpcFallback),
      findsNothing,
      reason: '后端明明说了话,却端自己那句兜底 —— 玩家会以为分身答不上来,继续重试',
    );
  });

  testWidgets('★后端也没话才落到兜底句', (WidgetTester t) async {
    await _pump(t, _NpcApi(serverMsg: null, reply: ''));
    await _say(t, '几点关门');
    expect(find.text(kShopNpcFallback), findsOneWidget);
  });

  testWidgets('★请求根本没送到:不静默,且不拿「替分身回答」那句顶', (
    WidgetTester t,
  ) async {
    await _pump(t, _NpcApi(offline: true));
    await _say(t, '几点关门');

    expect(
      find.text(kShopNpcNetFailed),
      findsOneWidget,
      reason: '样机这条 .then() 没有 .catch(),点了没反应 —— 那是缺陷,不照抄',
    );
    expect(
      find.text(kShopNpcFallback),
      findsNothing,
      reason: '「这个我说不好」是替分身回答;问题从来没送到,说成分身答不上来会让玩家换个问题重问',
    );
  });

  // ── 口径② 重答失败不能覆盖原文 ★本棒的落点 ────────────────────────

  testWidgets('★★★重答失败:原文原样还在,错误只走轻提示', (WidgetTester t) async {
    final _NpcApi api = _NpcApi(reply: '九点关门');
    await _pump(t, api);
    await _say(t, '几点关门');
    expect(find.text('九点关门'), findsOneWidget);

    api
      ..reply = null
      ..serverMsg = '模型忙不过来';
    await _tapRetry(t);

    expect(
      find.text('九点关门'),
      findsOneWidget,
      reason: '玩家点重答是想要个更好的答案,失败却把已经拿到的好答案弄丢了(2026-09-08 实拍)',
    );
    expect(
      find.text('模型忙不过来'),
      findsOneWidget,
      reason: '失败要说一声,但走 toast 不进消息流',
    );
    expect(
      find.byKey(const Key('npc-msg-ai-2')),
      findsOneWidget,
      reason: '失败不许追加一条新回答',
    );
  });

  testWidgets('★重答掉线也保住原文,后端没话时端本端那句轻提示', (WidgetTester t) async {
    final _NpcApi api = _NpcApi(reply: '九点关门');
    await _pump(t, api);
    await _say(t, '几点关门');

    api.offline = true;
    await _tapRetry(t);

    expect(find.text('九点关门'), findsOneWidget);
    expect(find.text(kShopNpcRetryFailed), findsOneWidget);
  });

  // ── 口径③ 重答改写时消息 id 不变 ─────────────────────────────────

  testWidgets('★重答成功:原地改写,id 不变、条数不变', (WidgetTester t) async {
    final _NpcApi api = _NpcApi(reply: '九点关门');
    await _pump(t, api);
    await _say(t, '几点关门');

    api.reply = '周末十点，平日九点';
    await _tapRetry(t);

    expect(find.text('周末十点，平日九点'), findsOneWidget);
    expect(find.text('九点关门'), findsNothing, reason: '重答是改写,不是追加');
    expect(
      find.byKey(const Key('npc-msg-ai-2')),
      findsOneWidget,
      reason: '换 id 会让列表判成新节点,整条重新入场闪一下(样机 index.js:1394)',
    );
    expect(
      find.byKey(const Key('npc-msg-ai-3')),
      findsNothing,
      reason: 'id 变了 = 新节点 = 闪一下',
    );
    expect(api.asked, <String>['几点关门', '几点关门'], reason: '重答问的是同一句,不是别的');
  });

  testWidgets('★前面没有我方提问就不发请求', (WidgetTester t) async {
    // 语音失败会先挂一条分身消息而**没有**我方消息 —— 这就是那个前置。
    final _NpcApi api = _NpcApi(serverMsg: '语音识别还没接入，先打字问我');
    final _SpyVoice voice = _SpyVoice();
    await _pump(t, api, voice: voice);
    await _hold(t);

    expect(find.text('语音识别还没接入，先打字问我'), findsOneWidget);
    await _tapRetry(t);
    expect(
      api.asked,
      isEmpty,
      reason: '找不到我方提问还发请求的话,分身只能瞎答 —— 而且要花钱',
    );
  });

  // ── 语音接线(Task 6 交过来的三件事)─────────────────────────────

  testWidgets('★语音回来:先补 ASR 原话,再挂回答', (WidgetTester t) async {
    final _NpcApi api = _NpcApi(reply: '九点关门', asr: '几点关门');
    final _SpyVoice voice = _SpyVoice();
    await _pump(t, api, voice: voice);
    await _hold(t);

    expect(api.uploaded, <String>['/tmp/clip.m4a']);
    expect(
      find.byKey(const Key('npc-msg-me-1')),
      findsOneWidget,
      reason: '玩家要能看见自己被听成了什么',
    );
    expect(find.text('几点关门'), findsOneWidget);
    expect(find.byKey(const Key('npc-msg-ai-2')), findsOneWidget);
  });

  testWidgets('★上传期间挂着 thinking —— 它是「上传还在飞又按下去」那道闸', (
    WidgetTester t,
  ) async {
    final _NpcApi api = _NpcApi(reply: '九点关门', asr: '几点关门');
    final _SpyVoice voice = _SpyVoice();
    await _pump(t, api, voice: voice);

    // ★ 把这次上传挂在半空:不挂住的话 fake 的 Future 下一帧就回来了,
    //   「上传期间」这个窗口根本不存在,断言量到的是回来之后的态(必然假绿)。
    api.gate = Completer<void>();
    await _hold(t);
    expect(
      t.widget<NpcInputBar>(find.byType(NpcInputBar)).thinking,
      isTrue,
      reason: '上传期间不挂 thinking 的话,玩家能立刻再按一次 —— 上一段临时文件会被删掉',
    );

    api.gate!.complete();
    await t.pump();
    await t.pump();
    expect(
      t.widget<NpcInputBar>(find.byType(NpcInputBar)).thinking,
      isFalse,
      reason: '回来了就得放开,否则这道闸就成了死锁',
    );
  });

  // ── 漏网异常不许让整屏静默卡死 ────────────────────────────────────

  testWidgets('★★★打字撞上第三种异常:thinking 要放开,不许整屏卡死', (
    WidgetTester t,
  ) async {
    // `_ask` 是 `unawaited(...)` 发起的:没有兜底 catch,任何非 Dio 非 ShopNpc 的异常
    // 都变成未捕获的异步错误,`_thinking` 永远停在 true —— 发送键恒置灰、
    // 麦克风恒不响应、底下挂一条「正在回答」不会消失,玩家唯一的出路是退出这一页。
    final _NpcApi api = _NpcApi(thirdKind: true);
    final List<String> logs = await _printsDuring(() async {
      await _pump(t, api);
      await _say(t, '几点关门');
    });

    expect(
      t.takeException(),
      isNull,
      reason: '异常漏出去 = 未捕获的异步错误,而界面上什么都没变',
    );
    expect(
      logs.where((String l) => l.contains('_ask 兜底异常')),
      isNotEmpty,
      reason: '兜底 catch 一个字都不记的话,第三种异常与「网络不好」在现场完全无法区分',
    );
    expect(
      t.widget<NpcInputBar>(find.byType(NpcInputBar)).thinking,
      isFalse,
      reason: 'thinking 卡在 true 就是整屏功能全灭,而且一声不吭',
    );
    expect(
      find.byKey(const Key('npc-msg-thinking')),
      findsNothing,
      reason: '「正在回答」挂在底下不会消失',
    );
    expect(find.text(kShopNpcNetFailed), findsOneWidget, reason: '至少要说一声');
  });

  testWidgets('★★★语音撞上 PathNotFoundException:同样不许卡死', (
    WidgetTester t,
  ) async {
    // 实证触发点:`voiceChat` 里 `await MultipartFile.fromFile(...)` 在临时文件
    // 不在时抛的是 `PathNotFoundException`,而且它在 `dio.post` 之前求值。
    final _NpcApi api = _NpcApi(thirdKind: true);
    final _SpyVoice voice = _SpyVoice();
    final List<String> logs = await _printsDuring(() async {
      await _pump(t, api, voice: voice);
      await _hold(t);
    });

    expect(t.takeException(), isNull);
    expect(
      logs.where((String l) => l.contains('_uploadVoice 兜底异常')),
      isNotEmpty,
      reason: '同上:不记的话「临时文件没了」和「网络不好」长得一模一样',
    );
    expect(
      t.widget<NpcInputBar>(find.byType(NpcInputBar)).thinking,
      isFalse,
      reason: '语音这条路卡死更难受:麦克风也归 thinking 管,按了永远没反应',
    );
    expect(find.text(kShopNpcNetFailed), findsOneWidget);
  });

  testWidgets('★★握着麦克风退页:不许 setState after dispose,也不许再发一次请求', (
    WidgetTester t,
  ) async {
    // `dispose()` → `_voice.dispose()` → `stop()` → `onClip(path)` → `_uploadVoice`。
    final _NpcApi api = _NpcApi(reply: '九点关门', asr: '几点关门');
    final _SpyVoice voice = _SpyVoice();
    await _pump(t, api, voice: voice);

    // 按住不放 —— 退页那一刻手还在麦克风上。
    final TestGesture g = await t.startGesture(
      t.getCenter(find.byKey(const Key('npc-input-mic'))),
    );
    await t.pump();
    await t.pump();
    expect(voice.recording, isTrue, reason: '前提:退页那一刻确实在录');

    // ⚠️ 这一段**必须**接管 `FlutterError.onError`(见 [_errorsDuring]):
    //   「Looking up a deactivated widget's ancestor is unsafe」是
    //   `BuildOwner.finalizeTree` 里同步抛出来的,不接管的话 `pumpWidget` 那一句
    //   就把测试打断了 —— 下面的 `expect` 一句都跑不到,负控红在「框架捕获到异常」
    //   而不是断言上。
    final List<FlutterErrorDetails> errors = await _errorsDuring(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
      await g.up();
      await t.pump();
    });

    expect(
      errors,
      isEmpty,
      reason: '页面已失活还去 ref.read ⇒ 「Looking up a deactivated widget\'s ancestor is unsafe」',
    );
    expect(
      t.takeException(),
      isNull,
      reason: 'setState() called after dispose() —— 玩家看到的是一屏红',
    );
    // ⚠️ **这一条在 debug 下没有区分度,留着是为了写清 `_gone` 在 release 下的价值**:
    //   失活断言是 `assert`,release 会被剥掉 —— 真机上 `ref.read` 不抛,
    //   这一次要花钱的写请求会真的发出去。而 debug 里两种实现都走不到
    //   `api.voiceChat`(有 `_gone` 是被挡下,没有是当场抛),`uploaded` 恒空。
    //   debug 侧真正区分两种实现的是上面那条 `errors`。
    expect(
      api.uploaded,
      isEmpty,
      reason: '页面都没了还发一次要花钱的写请求,答案没人看得到',
    );
  });

  testWidgets('★★握着麦克风退页、录音器还端了一句话:`_notice` 同样不许查祖先', (
    WidgetTester t,
  ) async {
    // 与上一条同源、**另一个入口**:`_notice` 只判 `mounted`,而
    // `CyNativeNotice.show` 第一句就是 `Overlay.of(context, rootOverlay: true)`
    // —— 同样是祖先查找。失活窗口里 `mounted` 仍是 true,它一个人挡不住。
    // 走的是子树 unmount 时 `RawGestureDetectorState.dispose → onTapCancel`
    // ⇒ `_hold(false)` → `_onVoice(false)` → `stop()` ⇒ 拿不到文件 ⇒ `onNotice`。
    final _SpyVoice voice = _SpyVoice()..noticeOnStop = true;
    await _pump(t, _NpcApi(reply: 'x'), voice: voice);

    final TestGesture g = await t.startGesture(
      t.getCenter(find.byKey(const Key('npc-input-mic'))),
    );
    await t.pump();
    await t.pump();
    expect(voice.recording, isTrue, reason: '前提:退页那一刻确实在录');

    final List<FlutterErrorDetails> errors = await _errorsDuring(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
      await g.up();
      await t.pump();
    });

    expect(
      voice.noticed,
      <String>[kVoiceRecordFailed],
      reason: '前提:录音器**确实端了话**。不端的话 `_notice` 根本没被调到,这条恒绿',
    );
    expect(
      errors,
      isEmpty,
      reason: '「录音出错了」这一句把玩家送上一屏红 —— 而它最常出现在首次按下弹权限框那一次',
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('★退出页面必须停录音,否则麦克风一直被占', (WidgetTester t) async {
    final _SpyVoice voice = _SpyVoice();
    await _pump(t, _NpcApi(reply: 'x'), voice: voice);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();
    expect(
      voice.disposed,
      1,
      reason: '不停的话表现是「退出这页之后微信语音也用不了了」',
    );
  });

  // ── 开场大字 / 键盘 ───────────────────────────────────────────────

  testWidgets('★开场大字用作者写的那句,不被模板顶掉', (WidgetTester t) async {
    await _pump(t, _NpcApi(reply: 'x'));
    expect(find.text('随便挑挑，看上哪张问我'), findsOneWidget);
    expect(_helloOpacity(t), 1, reason: '还没开口,大字占着中间那块地方');
  });

  testWidgets('★点了输入框,大字就让位(样机 bindfocus → started)', (
    WidgetTester t,
  ) async {
    await _pump(t, _NpcApi(reply: 'x'));
    await t.tap(find.byType(CupertinoTextField));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(_helloOpacity(t), 0);
  });

  testWidgets('★全程按住说话也让位(说完一轮之后)', (WidgetTester t) async {
    final _SpyVoice voice = _SpyVoice();
    await _pump(t, _NpcApi(reply: '九点关门', asr: '几点关门'), voice: voice);
    await _hold(t);
    await t.pump(const Duration(milliseconds: 400));
    expect(
      _helloOpacity(t),
      0,
      reason: '样机 _beginRecord(index.js:1314)按下就置 started,一句都没打也得让位',
    );
  });

  testWidgets('★★录音中(还没上传、一条消息都没有)大字就已经让位', (
    WidgetTester t,
  ) async {
    final _SpyVoice voice = _SpyVoice();
    await _pump(t, _NpcApi(reply: '九点关门', asr: '几点关门'), voice: voice);
    // ★ 按住不放:这才是「录音中」那个窗口。整段按下+抬起(`_hold`)会一路走到
    //   上传和回答,`_thinking`/`_msgs` 顺手把大字顶掉 —— 那样断言落在公共解上,
    //   去掉 `|| _voice.recording` 也照样绿(假绿模式⑥)。
    final TestGesture g = await t.startGesture(
      t.getCenter(find.byKey(const Key('npc-input-mic'))),
    );
    await t.pump();
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    // ⚠️ 先把这一刻的四个量抄下来、抬手,再断言。断言写在按住期间的话,
    //   第一条红了后面的 `g.up()` 就执行不到,指针一直按着,**下一条测试**
    //   跟着一起红(负控时实测撞到过,分不清哪条才是真的)。
    //   抬手也不能挪进 tearDown:那时控件树已经拆了,`_uploadVoice` 里的
    //   `ref.read` 会撞「Looking up a deactivated widget's ancestor」。
    final bool recordingNow = voice.recording;
    final bool thinkingNow = t
        .widget<NpcInputBar>(find.byType(NpcInputBar))
        .thinking;
    final bool hasMsgNow = find
        .byKey(const Key('npc-msg-me-1'))
        .evaluate()
        .isNotEmpty;
    final double helloNow = _helloOpacity(t);

    await g.up();
    await t.pump();
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    expect(recordingNow, isTrue, reason: '前提:那一刻确实在录');
    expect(
      thinkingNow,
      isFalse,
      reason: '负控前提:那一刻没有 thinking,大字让位只可能来自 recording',
    );
    expect(hasMsgNow, isFalse, reason: '负控前提:那一刻一条消息都没有');
    expect(
      helloNow,
      0,
      reason: '按住说话那几秒大字还压着的话,之前聊过的内容全看不见(样机 index.js:1314)',
    );
  });

  testWidgets('★键盘弹起时输入条抬到键盘上面', (WidgetTester t) async {
    await _pump(t, _NpcApi(reply: 'x'), keyboard: 300);
    expect(
      t.getRect(find.byType(NpcInputBar)).bottom,
      lessThanOrEqualTo(844 - 300),
      reason: '不吃 viewInsets 的话输入条整条压在键盘底下,打字看不见自己打了什么',
    );
  });

  testWidgets('★没键盘时输入条贴着屏幕底(证明上一条测的是避让不是常态)', (
    WidgetTester t,
  ) async {
    await _pump(t, _NpcApi(reply: 'x'));
    expect(t.getRect(find.byType(NpcInputBar)).bottom, 844);
  });

  // ── 新消息滚到底 ─────────────────────────────────────────────────

  testWidgets('★新消息进来滚到底(页面每次都换一个新 List,不原地 add)', (
    WidgetTester t,
  ) async {
    final _NpcApi api = _NpcApi(reply: '九点关门');
    await _pump(t, api);
    for (int i = 0; i < 8; i++) {
      api.reply = '答 $i';
      await _say(t, '问 $i');
    }
    await t.pump(const Duration(milliseconds: 400));
    expect(
      find.text('答 7'),
      findsOneWidget,
      reason: '最后一条连建都没建 —— 列表压根没往下滚',
    );
    final Rect box = t.getRect(find.byKey(const Key('npc-msg-list')));
    final Rect last = t.getRect(find.text('答 7'));
    expect(
      box.overlaps(last.deflate(0.5)),
      isTrue,
      reason:
          '原地 add 的话 oldWidget.messages 和 widget.messages 是同一个对象,'
          '「最后一条 id 变了吗」恒假 —— 列表永远不滚到底,而且不报错',
    );
  });

  // ── 入口接线 ─────────────────────────────────────────────────────

  testWidgets('★点店铺卡进分身对话', (WidgetTester t) async {
    await _pumpDetail(t);
    await _tapShopCard(t);
    expect(find.byType(ShopNpcPage), findsOneWidget);
  });

  testWidgets('★没分身就不进页,只给一句提示', (WidgetTester t) async {
    await _pumpDetail(t, npc: null);
    await _tapShopCard(t);
    expect(
      find.byType(ShopNpcPage),
      findsNothing,
      reason: '开一页站着个没名字的人形,比不开更像坏了',
    );
    expect(find.text('这家还没有店铺分身'), findsOneWidget);
  });

  testWidgets('★npc 有对象但没名字 = 没有分身(判据走 fromJson,不在页面再判一遍)', (
    WidgetTester t,
  ) async {
    await _pumpDetail(t, npc: const <String, dynamic>{'greeting': '你好'});
    await _tapShopCard(t);
    expect(find.byType(ShopNpcPage), findsNothing);
    expect(find.text('这家还没有店铺分身'), findsOneWidget);
  });

  testWidgets('★节点读不到时给一句话,不崩也不画一个空舞台', (WidgetTester t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          playApiProvider.overrideWithValue(_PlayApi(_payload())),
          aiNpcApiProvider.overrideWithValue(_NpcApi()),
        ].cast(),
        child: const MaterialApp(
          home: ShopNpcPage(sessionKey: _key, nodeId: 999),
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('这家的分身暂时读不到，返回卡片再试'), findsOneWidget);
  });
}

/// 点店铺卡。★ 它排在正文靠后,390×844 里天然在屏幕外 —— 不先滚过去,
/// `tap` 会打在空处,红的原因跟被测的东西无关(假绿 ③ 的反面)。
Future<void> _tapShopCard(WidgetTester t) async {
  await t.ensureVisible(find.text('长乐路旧物店'));
  await t.pumpAndSettle();
  await t.tap(find.text('长乐路旧物店'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

/// 跑一段,把这期间的框架错误**收进 list** 而不是让测试当场判失败。
///
/// ⚠️ 为什么需要它:「Looking up a deactivated widget's ancestor is unsafe」是
/// `BuildOwner.finalizeTree` 里**同步**抛出来的,`pumpWidget` 那一句就会把测试体
/// 打断 —— 后面的 `expect` 一句都执行不到,负控拿到的是「框架捕获到异常」这种红,
/// 不是断言级的红,也分不清到底红在哪一条口径上。
Future<List<FlutterErrorDetails>> _errorsDuring(
  Future<void> Function() body,
) async {
  final List<FlutterErrorDetails> errors = <FlutterErrorDetails>[];
  final FlutterExceptionHandler? prev = FlutterError.onError;
  FlutterError.onError = errors.add;
  try {
    await body();
  } finally {
    // ⚠️ 立刻放回去,别拖到 tearDown:接管期越长,越可能把**别的**真错误一起吞掉。
    FlutterError.onError = prev;
  }
  return errors;
}

/// 跑一段,接住这期间的 `debugPrint`。兜底 `catch` 记没记那一句,只有这样才量得到。
///
/// ⚠️ **必须在测试体结束前放回去**,不能挂 `addTearDown`:
/// `TestWidgetsFlutterBinding._verifyInvariants` 在测试体末尾就会查
/// `debugAssertAllFoundationVarsUnset`,那时 tearDown 还没跑 ——
/// 红的是「foundation debug 变量被改了」,跟被测的东西毫无关系(实测撞到过)。
Future<List<String>> _printsDuring(Future<void> Function() body) async {
  final List<String> logs = <String>[];
  final DebugPrintCallback prev = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) => logs.add(message ?? '');
  try {
    await body();
  } finally {
    debugPrint = prev;
  }
  return logs;
}

/// 按一下麦克风(按下 + 抬起 → `_SpyVoice.stop` 直接吐一段够长的录音)。
Future<void> _hold(WidgetTester t) async {
  await t.tapAt(t.getCenter(find.byKey(const Key('npc-input-mic'))));
  await t.pump();
  await t.pump();
  await t.pump();
}

/// 开场大字当前的不透明度。
///
/// ⚠️ 按 key 找,不按 `find.ancestor(... AnimatedOpacity)` —— 整屏渐显那层也是
/// `AnimatedOpacity`,祖先链上有两个,量到哪一个全看顺序。
double _helloOpacity(WidgetTester t) =>
    t.widget<AnimatedOpacity>(find.byKey(const Key('npc-hello-fade'))).opacity;

Future<void> _pumpDetail(WidgetTester t, {Object? npc = _npc}) async {
  addTearDown(() {
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
  t.view.devicePixelRatio = 3;
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        playApiProvider.overrideWithValue(_PlayApi(_payload(npc: npc))),
        aiNpcApiProvider.overrideWithValue(_NpcApi()),
      ].cast(),
      child: MaterialApp(
        home: CardDetailPage(
          sessionKey: _key,
          nodeId: 1,
          onPrimary: (PlayNode _) {},
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}
