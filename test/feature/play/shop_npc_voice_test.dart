// 店铺分身「按住说话」的录音端。
//
// ⚠️ **覆盖边界写在这里,不假装测到了**:
//   录音插件(`record`)的真实实现要平台通道,单测里起不来。所以这里钉的是
//   `ShopNpcVoice` **自己**的判断 —— 权限被拒怎么办、多短算误触、到点停没停、
//   退页面松没松麦克风 —— 用一个 `implements AudioRecorder` 的替身收下调用。
//   **没有覆盖**的是:真机录出来的文件能不能被后端 ASR 解开、iOS 音频会话与
//   just_audio 抢占时的行为。那两条只有真机能答,别拿这份文件当它们的证据。
//
// 替身是真的 `implements AudioRecorder` —— 那个类没有 final/base 标记,
// 可以直接实现;不需要 mock 框架,也不需要在生产代码里多包一层接口。

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

import 'package:chengyin_app/feature/play/free_explore/shop_npc_logic.dart';
import 'package:chengyin_app/feature/play/free_explore/shop_npc_voice.dart';

void main() {
  // ─── 口径(纯函数,不碰录音器)──────────────────────────────────────────
  test('★ ASR 没回话时我方那条写「（语音）」—— 样机是 JS 的 `||`,空串也要回落', () {
    // 玩家要能看见自己被听成了什么;挂一条空的我方消息等于把这件事悄悄取消了。
    expect(asrMineText('几点关门'), '几点关门');
    expect(asrMineText(''), '（语音）');
    expect(asrMineText(null), '（语音）');
  });

  test('★ 语音失败端服务端原话,不编话', () {
    // 闸关时后端说「店铺分身对话还没开放」,ASR 没接时说「语音识别还没接入，先打字问我」。
    // 两句都比我编的准,而且都告诉玩家下一步该干什么。
    expect(voiceErrorText('语音识别还没接入，先打字问我'), '语音识别还没接入，先打字问我');
    expect(voiceErrorText(null), kVoiceNotHeard);
    expect(voiceErrorText(''), kVoiceNotHeard);
  });

  test('★ 语音失败的兜底句与打字那条不是一句', () {
    // 打字失败端「这个我说不好」是替分身回答;语音失败端「没听清」是说这一次没收到。
    // 混用会让玩家以为分身答不上来,于是换个问题问 —— 而问题从来没送到。
    expect(kVoiceNotHeard, isNot(kShopNpcFallback));
  });

  test('★ 500ms 是含边界的下限 —— 不到半秒不算一句话', () {
    expect(voiceClipTooShort(const Duration(milliseconds: 499)), isTrue);
    expect(voiceClipTooShort(const Duration(milliseconds: 500)), isFalse);
    expect(voiceClipTooShort(const Duration(seconds: 3)), isFalse);
  });

  // ─── 录音器(替身)────────────────────────────────────────────────────
  test('★ 没权限:端样机那句话,而且一次都不许开录', () async {
    final _FakeRecorder rec = _FakeRecorder(permission: false);
    final List<String> notices = <String>[];
    final List<String> clips = <String>[];
    final ShopNpcVoice voice = _voice(rec);

    await voice.start(onClip: clips.add, onNotice: notices.add);

    expect(notices, <String>['没有录音权限，先在设置里打开']);
    expect(rec.startCalls, 0, reason: '权限没拿到还去 start,录出来的是一段空文件');
    expect(voice.recording, isFalse, reason: '没录成却把输入框换成「正在听…」是骗人');
    expect(clips, isEmpty);
  });

  test('★ 录音参数按样机:16k / 单声道', () async {
    final _FakeRecorder rec = _FakeRecorder();
    final ShopNpcVoice voice = _voice(rec);
    await voice.start(onClip: (_) {}, onNotice: (_) {});

    expect(rec.config!.sampleRate, 16000);
    expect(rec.config!.numChannels, 1);
    expect(
      rec.config!.bitRate,
      lessThanOrEqualTo(32000),
      reason: '默认 128kbps 时一分钟约 960KB,逼近后端 2MB 上限;人声 16k 单声道不需要那么高',
    );
    expect(voice.recording, isTrue);
  });

  test('★ 误触:不到 500ms 静默丢掉,不发请求也不弹话', () async {
    final File clip = _tempClip();
    final _FakeRecorder rec = _FakeRecorder(path: clip.path);
    final List<String> notices = <String>[];
    final List<String> clips = <String>[];
    DateTime now = DateTime(2026, 9, 10, 12);
    final ShopNpcVoice voice = _voice(rec, now: () => now);

    await voice.start(onClip: clips.add, onNotice: notices.add);
    now = now.add(const Duration(milliseconds: 499));
    await voice.stop();

    expect(clips, isEmpty, reason: '这条链路是要花钱的写操作,手指蹭一下不该计一次费');
    expect(notices, isEmpty, reason: '每次手滑都挨一句提示,比不提示更烦');
    expect(
      clip.existsSync(),
      isFalse,
      reason: '丢掉的那段也要从盘上删掉 —— 玩家的声音没有留在本机的理由',
    );
  });

  test('★ 够长:把文件交出去', () async {
    final File clip = _tempClip();
    final _FakeRecorder rec = _FakeRecorder(path: clip.path);
    final List<String> clips = <String>[];
    DateTime now = DateTime(2026, 9, 10, 12);
    final ShopNpcVoice voice = _voice(rec, now: () => now);

    await voice.start(onClip: clips.add, onNotice: (_) {});
    now = now.add(const Duration(milliseconds: 500));
    await voice.stop();

    expect(clips, <String>[clip.path]);
    expect(voice.recording, isFalse);
    expect(clip.existsSync(), isTrue, reason: '还没上传就把文件删了,发出去的是个空壳');
    clip.deleteSync();
  });

  test('★ 够长却没拿到文件 = 真出错了,这个要说', () async {
    // 权限中途被撤、被系统来电打断都长这样。不说的话玩家对着屏幕说了一段,
    // 什么都没发生,也不知道为什么。
    final _FakeRecorder rec = _FakeRecorder(failStop: true);
    final List<String> notices = <String>[];
    final List<String> clips = <String>[];
    DateTime now = DateTime(2026, 9, 10, 12);
    final ShopNpcVoice voice = _voice(rec, now: () => now);

    await voice.start(onClip: clips.add, onNotice: notices.add);
    now = now.add(const Duration(seconds: 2));
    await voice.stop();

    expect(notices, <String>['录音出错了']);
    expect(clips, isEmpty);
  });

  test('★ 到 60 秒自己停 —— 一根卡住的手指不是不给钱的理由', () {
    final File clip = _tempClip();
    fakeAsync((FakeAsync async) {
      final _FakeRecorder rec = _FakeRecorder(path: clip.path);
      final List<String> clips = <String>[];
      DateTime now = DateTime(2026, 9, 10, 12);
      final ShopNpcVoice voice = _voice(rec, now: () => now);

      voice.start(onClip: clips.add, onNotice: (_) {});
      async.flushMicrotasks();
      expect(rec.startCalls, 1);

      // 玩家一直按着不放:59 秒时还在录。
      now = now.add(const Duration(seconds: 59));
      async.elapse(const Duration(seconds: 59));
      async.flushMicrotasks();
      expect(rec.stopCalls, 0);
      expect(voice.recording, isTrue);

      // 第 60 秒,没有任何人松手。
      now = now.add(const Duration(seconds: 1));
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(rec.stopCalls, 1, reason: '没这道闸,一段没人要的长录音照样转写照样计费');
      expect(clips, <String>[clip.path]);
      expect(voice.recording, isFalse);
    });
    if (clip.existsSync()) clip.deleteSync();
  });

  test('★★★ 轻点一下:抬手早于平台通道返回,也必须真的停下来', () {
    // 2026-09-10 复审实证的资损 + 隐私路径:`onTapUp` 在开录那几个 await 之前就到了
    // (真机开录 50–300ms,一次 tap 约 80–150ms)。置位晚一步 ⇒ stop 空转 ⇒
    // 麦克风静默开到 60 秒上限,再把一段没人要的录音交出去(转写 + 模型两次计费),
    // 而界面全程还是「问问阿旧…」。实证数据:`recorder.stop()` 调用数 0。
    //
    // ⚠️ 替身的 `start` **必须真的异步挂住**:同步替身天然没有这段竞态窗口,
    //    照着页面测试那个替身写法补,补了也测不到(假绿第八种)。
    final File clip = _tempClip();
    fakeAsync((FakeAsync async) {
      final Completer<void> channel = Completer<void>();
      final _FakeRecorder rec = _FakeRecorder(
        path: clip.path,
        startGate: channel.future,
      );
      final List<String> clips = <String>[];
      DateTime now = DateTime(2026, 9, 10, 12);
      final ShopNpcVoice voice = _voice(rec, now: () => now);

      unawaited(voice.start(onClip: clips.add, onNotice: (_) {}));
      async.flushMicrotasks();
      expect(rec.startCalls, 1, reason: '前提:确实走到了开录这一步');
      expect(
        channel.isCompleted,
        isFalse,
        reason: '前提:平台通道还没返回 —— 这就是那个窗口,替身同步化的话它根本不存在',
      );

      // 玩家抬手了(一次 tap 约 80–150ms),而开录还在飞。
      now = now.add(const Duration(milliseconds: 120));
      unawaited(voice.stop());
      async.flushMicrotasks();
      channel.complete(); // 平台通道这才返回
      async.flushMicrotasks();

      expect(rec.stopCalls, 1, reason: '抬手时空转 ⇒ 麦克风一直开着(复审实证 stop 调用数 0)');
      expect(voice.recording, isFalse, reason: '手早松了,状态还停在「正在录」');
      expect(
        rec.stopDuringStart,
        isFalse,
        reason: '在 start 还没返回时就 stop 等于没停:平台侧随后才把麦克风开起来,之后没人再去关它',
      );

      // 60 秒那道闸只对真的在录时有意义。这里没在录了,不许有人替玩家发一段。
      now = now.add(kVoiceMaxClip);
      async.elapse(kVoiceMaxClip);
      async.flushMicrotasks();
      expect(
        clips,
        isEmpty,
        reason: '轻点一下换来一次转写 + 一次模型调用,消息流里凭空多出一问一答',
      );
      expect(rec.stopCalls, 1, reason: '到点的定时器还挂着 = 这一路没被真正收尾');
    });
    // ⚠️ 误触那一支的 `_dropStale()` 是真的文件 I/O,fakeAsync 驱不动它、
    //    但它会在真事件循环上自己跑完 —— 谁先到不确定,所以这里只兜底清,不断言。
    try {
      clip.deleteSync();
    } catch (_) {
      // 已经被 `_dropStale()` 删掉了,正是想要的结果。
    }
  });

  test('★ 开录失败不许把麦克风锁死 —— 标志要放回去', () async {
    // 设备被别的 App 占着、临时目录写不了都长这样。标志不放回去的话,
    // `start` 的第一句 `if (_recording) return` 会让之后每一次按下都空转。
    final _FakeRecorder rec = _FakeRecorder(failStart: true);
    final List<String> notices = <String>[];
    final ShopNpcVoice voice = _voice(rec);

    await voice.start(onClip: (_) {}, onNotice: notices.add);

    expect(notices, <String>['录音出错了'], reason: '按了没反应,玩家只会一直按');
    expect(voice.recording, isFalse, reason: '没录成却说自己在录');

    // 再按一次:必须还能开得起来。
    rec.failStart = false;
    await voice.start(onClip: (_) {}, onNotice: notices.add);
    expect(rec.startCalls, 2, reason: '标志锁死的话这一次会被第一句挡下,整页麦克风从此报废');
    expect(voice.recording, isTrue);
  });

  test('★ 松手之后再松一次不会重复发', () async {
    // 手势被打断时组件层会补一次 onTapCancel(false),和真松手撞在一起。
    final File clip = _tempClip();
    final _FakeRecorder rec = _FakeRecorder(path: clip.path);
    final List<String> clips = <String>[];
    DateTime now = DateTime(2026, 9, 10, 12);
    final ShopNpcVoice voice = _voice(rec, now: () => now);

    await voice.start(onClip: clips.add, onNotice: (_) {});
    now = now.add(const Duration(seconds: 2));
    await voice.stop();
    await voice.stop();

    expect(clips.length, 1, reason: '发两次 = 收两次钱,答两遍');
    expect(rec.stopCalls, 1);
    clip.deleteSync();
  });

  test('★★★ 快速双击:上一次的 stop 不许把下一次的录音停掉', () {
    // 2026-09-10 复审实证。玩家快速双击麦克风(第一次抬手时开录还在飞,
    // 50–300ms 窗口):第一轮的 `stop` 在 `await _booting` 之后醒来,
    // 停掉的是**第二轮**刚开起来的麦克风。结果 `_recording` 停在 true、
    // `_limit` 已武装、麦克风实际是关的 —— 界面写着「正在听…松开发送」,
    // 而 `start()` 之后每次按下都被第一句 `if (_recording) return` 挡掉,
    // **麦克风最长哑 60 秒**,到点再端一句「录音出错了」。
    //
    // ⚠️ 靶子必须是 `micOpen`:`stopCalls` / `recording` / `_limit` 在两种实现下
    //    都一样(假绿⑥,采样点落在公共解上)。
    fakeAsync((FakeAsync async) {
      final Completer<void> gate1 = Completer<void>();
      final Completer<void> gate2 = Completer<void>();
      final _FakeRecorder rec = _FakeRecorder(
        path: '/tmp/never-written.m4a',
        startGates: <Future<void>>[gate1.future, gate2.future],
      );
      DateTime now = DateTime(2026, 9, 10, 12);
      final ShopNpcVoice voice = _voice(rec, now: () => now);

      // 第一次按下 —— 开录还在飞。
      unawaited(voice.start(onClip: (_) {}, onNotice: (_) {}));
      async.flushMicrotasks();
      expect(rec.startCalls, 1, reason: '前提:第一轮真的走到了开录这一步');

      // 抬手(一次 tap 约 80–150ms)。`stop` 挂在 `await _booting` 上。
      now = now.add(const Duration(milliseconds: 120));
      unawaited(voice.stop());
      async.flushMicrotasks();
      expect(gate1.isCompleted, isFalse, reason: '前提:第一轮的通道还没返回 —— 这就是那个窗口');

      // 紧接着第二次按下。
      now = now.add(const Duration(milliseconds: 60));
      unawaited(voice.start(onClip: (_) {}, onNotice: (_) {}));
      async.flushMicrotasks();
      expect(rec.startCalls, 2, reason: '前提:第二轮真的开起来了');

      // 第二轮的通道**先**返回:麦克风现在是第二轮的。
      gate2.complete();
      async.flushMicrotasks();
      expect(rec.micOpen, isTrue, reason: '前提:第二轮的麦克风确实开了');

      // 第一轮的通道这才返回,第一轮那个 `stop` 随之落地。
      gate1.complete();
      async.flushMicrotasks();

      expect(
        rec.micOpen,
        isTrue,
        reason: '上一轮的 stop 把这一轮的麦克风关了 —— 界面写着「正在听…松开发送」,'
            '而麦克风哑到 60 秒上限,再端一句「录音出错了」',
      );
      expect(voice.recording, isTrue, reason: '前提:这一刻确实还在第二轮');
    });
  });

  test('★ 退出页面:停录音、放开麦克风、删掉临时文件', () async {
    // 不停的话麦克风会一直被占着,表现是「退出这页之后微信语音也用不了了」。
    final File clip = _tempClip();
    final _FakeRecorder rec = _FakeRecorder(path: clip.path);
    DateTime now = DateTime(2026, 9, 10, 12);
    final ShopNpcVoice voice = _voice(rec, now: () => now);

    await voice.start(onClip: (_) {}, onNotice: (_) {});
    now = now.add(const Duration(seconds: 2));
    await voice.dispose();

    expect(rec.stopCalls, 1, reason: '页面没了录音还在录');
    expect(rec.disposeCalls, 1, reason: 'stop 之后不 dispose,麦克风仍被这个实例占着');
    expect(voice.recording, isFalse);
    expect(clip.existsSync(), isFalse, reason: '走的时候要把玩家的声音带走');
  });
}

ShopNpcVoice _voice(_FakeRecorder rec, {DateTime Function()? now}) =>
    ShopNpcVoice(
      recorder: rec,
      clipPath: () async => rec.path ?? '/tmp/never-written.m4a',
      now: now,
    );

/// 真建一个临时文件:删没删得掉是这一批要断言的事之一,拿假路径断不出来。
File _tempClip() {
  final File f = File(
    '${Directory.systemTemp.path}/shop_npc_voice_test_'
    '${DateTime.now().microsecondsSinceEpoch}.m4a',
  );
  f.writeAsBytesSync(<int>[0, 1, 2, 3]);
  return f;
}

/// `AudioRecorder` 没有 final/base 标记,直接 implements 即可;
/// 用不到的成员交给 noSuchMethod —— 真被调到会当场抛,不会悄悄返回 null。
class _FakeRecorder implements AudioRecorder {
  _FakeRecorder({
    this.permission = true,
    this.path,
    this.failStop = false,
    this.failStart = false,
    this.startGate,
    this.startGates,
  });

  final bool permission;

  /// 这次录音会落到哪个文件(替身不真录,直接把它当成 stop 的返回值)。
  final String? path;

  /// true = stop 拿不到文件(权限被撤、被系统打断)。
  final bool failStop;

  /// true = 开录当场抛(设备被占、目录写不了)。
  bool failStart;

  /// 挂住开录那一步,模拟真机 50–300ms 的平台通道往返。
  ///
  /// ⚠️ 这是「轻点一下」那条测试的**前提**:替身同步返回的话,
  /// 「抬手早于开录返回」这个窗口在测试里根本不存在,补了也测不到。
  final Future<void>? startGate;

  /// 每一轮开录**各自**的通道闸(下标 = 第几次 `start`)。
  ///
  /// 快速双击那条要让**第二轮先返回**——共用一个 [startGate] 表达不了「谁先谁后」,
  /// 而那正是被测的竞态本身。
  final List<Future<void>>? startGates;

  /// 麦克风此刻到底开着没有。
  ///
  /// ⚠️ 只看 `stopCalls` 是看不出「上一轮的 stop 停掉了下一轮的录音」的:
  /// 两种实现下 `_recording` 都是 true、`_limit` 都武装着,差的只有这一位。
  bool micOpen = false;

  RecordConfig? config;
  int startCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;

  /// 有没有人在 `start` 还没返回时就来 `stop`。
  ///
  /// 真机上这么停等于没停:平台侧照旧把麦克风开起来,而这一端已经认为自己停了,
  /// 之后再没人去关它 —— 单看「stop 调过没有」这个计数是看不出来的。
  bool stopDuringStart = false;
  bool _inStart = false;

  @override
  Future<bool> hasPermission({bool request = true}) async => permission;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    startCalls++;
    this.config = config;
    if (failStart) throw StateError('recorder busy');
    final Future<void>? gate = startGates != null
        ? (startCalls <= startGates!.length ? startGates![startCalls - 1] : null)
        : startGate;
    _inStart = true;
    try {
      if (gate != null) await gate;
    } finally {
      _inStart = false;
    }
    micOpen = true;
  }

  @override
  Future<String?> stop() async {
    if (_inStart) stopDuringStart = true;
    stopCalls++;
    micOpen = false;
    return failStop ? null : path;
  }

  @override
  Future<void> dispose() async => disposeCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
