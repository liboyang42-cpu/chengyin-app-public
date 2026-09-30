// 店铺分身「按住说话」的录音端(屏④)。语义照搬小程序 pages/play/index.js:1295-1347。
//
// 只管**从按下到拿到一段音频**这一截:权限、开录、太短就丢、到点自己停、收尾删文件。
// 上传与消息流由页面接(`AiNpcApi.voiceChat` + `shop_npc_logic.dart` 的那几句口径),
// 这里不碰 widget,也不发请求 —— 所以三件会静默出错的事(权限被拒、误触、到点没停)
// 能脱离录音硬件断言。
//
// ⚠️ **格式与样机不同,是被 Dart 侧逼的,不是随手改的**:样机录 mp3,而 `record`
//   插件在 iOS / Android 上都**没有 mp3 编码器**(AudioEncoder 里只有 aac/amr/opus/
//   flac/wav/pcm)。这里录 AAC-LC(m4a 容器),采样率与声道数仍按样机的 16k / 单声道。
//   ⚠️ 后端 `ApiAiNpcController:282` 把格式**硬编码**成 `transcribe(bytes, "mp3")`,
//   不看上传的文件名 —— 今天没事(`SpeechToTextService` 只有 Noop 实现,
//   `available()` 为 false,请求在进模型前就被挡下),但**谁接 ASR 谁必须先把这行
//   改成按真实容器判**,否则 App 的 m4a 会被当成 mp3 喂进去,解出一段噪音或直接失败。

import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'shop_npc_logic.dart';

/// 按住说话的录音器。一个页面一个,页面 dispose 时调 [dispose]。
class ShopNpcVoice {
  ShopNpcVoice({
    AudioRecorder? recorder,
    Future<String> Function()? clipPath,
    DateTime Function()? now,
  }) : _recorder = recorder ?? AudioRecorder(),
       _clipPath = clipPath ?? _defaultClipPath,
       _now = now ?? DateTime.now;

  final AudioRecorder _recorder;
  final Future<String> Function() _clipPath;
  final DateTime Function() _now;

  bool _recording = false;
  DateTime _startedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _limit;

  /// 开录那几步(权限 / 删旧文件 / 取路径 / 平台通道)还在飞时挂在这里。
  ///
  /// ⚠️ [stop] 必须先等它落地再去停:平台通道那一步真机要 50–300ms,不等的话
  /// 停的是一个还没开起来的录音器 —— 这一端认为自己停了,而麦克风随后才被打开。
  Future<void>? _booting;

  /// 第几轮按下。[stop] 与 [_boot] 在每个 `await` 之后拿它比一次 ——
  /// **不是自己这一轮的就别去动录音器**。
  ///
  /// ⚠️ 玩家快速双击麦克风(第一次抬手时开录还在飞,50–300ms 窗口):
  /// 第一轮的 `stop` 在 `await _booting` 之后醒来,停掉的是**第二轮**刚开起来的
  /// 麦克风 —— `_recording` 停在 true、`_limit` 已武装、麦克风实际是关的,
  /// 界面写着「正在听…松开发送」而麦克风最长哑 60 秒,到点再端一句「录音出错了」。
  int _session = 0;
  void Function(String path)? _onClip;
  void Function(String message)? _onNotice;

  /// 上一段还留在盘上的临时文件。开下一段与 [dispose] 时删掉 ——
  /// 「语音不落盘」说的是服务端,本机这份临时文件也没有留着的理由。
  String? _stale;

  /// 正在录。页面据此把输入框换成「正在听…松开发送」。
  bool get recording => _recording;

  /// 按下。
  ///
  /// [onClip] 拿到一段**够长的**录音时调一次(松手停的、到 60 秒自己停的,同一条路)。
  /// [onNotice] 端话给玩家:没权限、录音器出错。
  ///
  /// ⚠️ 权限被拒**必须端话**(样机 `cyToast('没有录音权限，先在设置里打开')`)——
  /// 按了没反应,玩家只会一直按。
  Future<void> start({
    required void Function(String path) onClip,
    required void Function(String message) onNotice,
  }) async {
    if (_recording) return;
    // ★★★ 进门就置位,**不能**排在下面那几个 await 之后(2026-09-10 复审实证)。
    //   玩家轻点一下:`onTapUp` 在平台通道返回之前就到了(真机开录 50–300ms,
    //   一次 tap 约 80–150ms)⇒ [stop] 的第一句 `if (!_recording) return` 命中,
    //   **直接空转**;随后 start 返回把标志置真且不 setState ⇒ 界面还是「问问阿旧…」,
    //   而麦克风一直开着,60 秒后 `_limit` 把这段没人要的录音交出去 ——
    //   一次转写 + 一次模型,两次计费,全程没有任何提示。
    _recording = true;
    _startedAt = _now();
    final int session = ++_session;
    _onClip = onClip;
    _onNotice = onNotice;
    final Future<void> booting = _boot(onNotice, session);
    _booting = booting;
    await booting;
  }

  /// 真正开录的那几步。抬手可能落在其中任意一处,所以:
  /// 失败要把标志放回去(否则 `start` 的第一句会让之后每一次按下都空转 = 麦克风锁死),
  /// 成功也要看一眼还在不在录 —— 不在了就别再武装 60 秒那道闸。
  Future<void> _boot(
    void Function(String message) onNotice,
    int session,
  ) async {
    try {
      // 权限在**按下时**才要,不在进页面时要:进页面就弹框,玩家还不知道要它干什么。
      if (!await _recorder.hasPermission()) {
        if (_abort(session)) onNotice(kVoiceNoPermission);
        return;
      }
      await _dropStale();
      final String path = await _clipPath();
      // ★ 同上:这一轮已经作废,再去开麦克风等于替新那一轮开了个没人认领的录音,
      //   而新那一轮自己还会再开一次。
      if (session != _session) return;
      await _recorder.start(
        const RecordConfig(
          // mp3 在这个插件里不存在 —— 见文件头。采样率与声道照样机。
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
          // 16k 单声道的人声,32kbps 足够;默认 128k 会让一分钟逼近后端 2MB 上限。
          bitRate: 32000,
        ),
        path: path,
      );
    } catch (_) {
      // 设备被别的 App 占着、临时目录写不了都长这样。这里不 rethrow:
      // 调用方是 `unawaited(...)` 发起的,抛出去就是一个未捕获的异步错误。
      if (_abort(session)) onNotice(kVoiceRecordFailed);
      return;
    }
    // 到点自己停:玩家的手指卡住不是不给钱的理由。
    // ★ 只武装自己这一轮的:作废那一轮再挂一个,会把新那一轮的闸顶掉。
    if (_recording && session == _session) {
      _limit = Timer(kVoiceMaxClip, () => unawaited(stop()));
    }
  }

  /// 开录没成:标志放回去,这一次的回调也撤掉。返回值 = 这一轮还算不算数。
  ///
  /// ⚠️ **必须带 [session]**:这一轮早被下一次按下顶掉的话,清掉的会是**新那一轮**的
  /// 标志和回调 —— 新那一轮的麦克风随后开起来,却没人认领、`_limit` 也没武装,
  /// 于是**开着不关**。那比本来要修的双击 bug 更重,所以端话也一并跳过
  /// (新那一轮好好的,凭空弹一句「没有录音权限」)。
  bool _abort(int session) {
    if (session != _session) return false;
    _recording = false;
    _onClip = null;
    _onNotice = null;
    return true;
  }

  /// 松手、手势被打断、页面退出 —— 都走这一条。没在录时是空操作(可重复调)。
  Future<void> stop() async {
    if (!_recording) return;
    final int session = _session;
    _recording = false;
    _limit?.cancel();
    _limit = null;
    final Duration held = _now().difference(_startedAt);
    final void Function(String path)? onClip = _onClip;
    final void Function(String message)? onNotice = _onNotice;
    _onClip = null;
    _onNotice = null;

    String? path;
    try {
      // ★ 先等开录那几步落地(见 [_booting])。停一个还没开起来的录音器 =
      //   麦克风在这之后才被打开,而且再没人去关它。
      await _booting;
      // ★ 等的这一会儿玩家又按下去了(快速双击)。再停就是停**新那一轮**的麦克风 ——
      //   见 [_session]。不是自己这一轮就整条收尾都不做:文件、提示、临时文件
      //   都归现在这一轮管。
      if (session != _session) return;
      path = await _recorder.stop();
    } catch (_) {
      path = null;
    }

    if (voiceClipTooShort(held)) {
      // 误触:**静默**丢掉。这里弹一句话的话,每次手滑都要挨一次提示。
      _stale = path;
      await _dropStale();
      return;
    }
    if (path == null) {
      // 够长却没拿到文件 = 真出错了(权限被撤、被系统打断)。这个要说,
      // 否则玩家对着屏幕说了一段,什么都没发生,也不知道为什么。
      onNotice?.call(kVoiceRecordFailed);
      return;
    }
    _stale = path;
    onClip?.call(path);
  }

  /// 页面退出时调:停录音 + 删临时文件。
  ///
  /// ⚠️ 不停的话麦克风会一直被占着,表现是「退出这页之后微信语音也用不了了」。
  Future<void> dispose() async {
    await stop();
    await _dropStale();
    await _recorder.dispose();
  }

  Future<void> _dropStale() async {
    final String? p = _stale;
    _stale = null;
    if (p == null) return;
    try {
      await File(p).delete();
    } catch (_) {
      // 删不掉就算了(临时目录,系统会回收);为了删一个临时文件把页面搞崩不值。
    }
  }
}

Future<String> _defaultClipPath() async {
  final Directory dir = await getTemporaryDirectory();
  return '${dir.path}/shop_npc_voice_'
      '${DateTime.now().millisecondsSinceEpoch}.m4a';
}
