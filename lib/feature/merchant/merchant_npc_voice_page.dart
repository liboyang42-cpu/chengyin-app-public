import '../../l10n/strings.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart'
    show MediaItem;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/merchant_npc.dart';
import 'merchant_error_view.dart';

/// 用五句话克隆店主的声音。
///
/// ★★ **声音是个人生物特征。**这一页的每条规则都是为了让「谁授权的」事后立得住:
///
///   ① **第一句是授权声明,要单独标出来。** 那段录音<b>本身</b>就是同意的证据,
///      比任何勾选框都硬。把它混在其它四句里念过去,等于没有明确告知。
///
///   ② **供应商没接就不进这一页。** 入口在店铺形象页按 `available` 隐藏;
///      这里再判一次,直调也要挡 —— 让人录完五句才失败是最差的做法。
///
///   ③ **每句录完可当场回放、可重录。** 商家听不到自己录成什么样,
///      就只能靠"提交后过审被驳回"来发现录坏了,那时已经过了几天。
///
///   ④ **五句不齐不给提交。** 后端也拦(而且那道才算数),
///      但要在这里就说清还差第几句。
class MerchantNpcVoicePage extends ConsumerStatefulWidget {
  const MerchantNpcVoicePage({super.key});

  @override
  ConsumerState<MerchantNpcVoicePage> createState() =>
      _MerchantNpcVoicePageState();
}

class _MerchantNpcVoicePageState extends ConsumerState<MerchantNpcVoicePage> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  VoiceEnrollScript _script = const VoiceEnrollScript();

  /// 每句录好的本地文件路径。长度恒等于脚本条数,未录的是 null。
  List<String?> _localPaths = <String?>[];

  bool _loading = true;
  bool _loadFailed = false;
  bool _submitting = false;

  /// 提交之后停在本页看生成进度 —— `/api/merchant/npc/voice/status`
  /// 正是为了这一步存在的:提交只代表「录好了」,克隆还在供应商那边跑。
  bool _submitted = false;
  NpcVoiceStatus? _status;
  Timer? _poll;

  /// 正在录第几句。null = 没在录。
  int? _recordingIndex;

  /// 正在回放第几句。null = 没在放。
  int? _playingIndex;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // ★ 页面销毁时必须停掉录音:不停的话麦克风会一直被占着,
    //   表现是"退出这页之后微信语音也用不了了"。
    _recorder.dispose();
    _player.dispose();
    _poll?.cancel();
    super.dispose();
  }

  /// 生成中才轮询,收口(就绪/失败)就停表。
  /// 5 秒一拍,与小程序 `pages/merchant/decor/ai-npc/index.js:506` 同节奏。
  void _syncPoll() {
    _poll?.cancel();
    if (!_submitted || !(_status?.isGenerating ?? false)) return;
    _poll = Timer.periodic(const Duration(seconds: 5), (Timer t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      try {
        final NpcVoiceStatus next = await ref
            .read(merchantNpcApiProvider)
            .voiceStatus();
        if (!mounted) return;
        setState(() => _status = next);
        if (!next.isGenerating) t.cancel();
      } catch (_) {
        // ★ 查询失败不改判:状态是背景事实,下一次轮询就是重试。
        //   弹失败提示会把正在等的人吓一跳,而数据并没有变坏。
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final VoiceEnrollScript script = await ref
          .read(merchantNpcApiProvider)
          .voiceScript();
      if (!mounted) return;
      setState(() {
        _script = script;
        _localPaths = List<String?>.filled(script.lines.length, null);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  bool get _allRecorded =>
      _localPaths.isNotEmpty && _localPaths.every((String? p) => p != null);

  /// 还差第几句(1-based)。null = 齐了。
  int? get _firstMissing {
    for (int i = 0; i < _localPaths.length; i++) {
      if (_localPaths[i] == null) return i + 1;
    }
    return null;
  }

  Future<void> _toggleRecord(int index) async {
    if (_recordingIndex == index) {
      await _stopRecord(index);
      return;
    }
    if (_recordingIndex != null) return; // 同时只录一句
    await _player.stop();
    if (mounted) setState(() => _playingIndex = null);

    // ★ 权限在**按下录音时**才要,不在进页面时要 ——
    //   进页面就弹权限框,用户还不知道要它干什么。
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        CyNativeNotice.show(context, stringsOf(context).merchantNodeMicrophoneNeeded, isError: true);
      }
      return;
    }

    final Directory dir = await getTemporaryDirectory();
    final String path =
        '${dir.path}/npc_voice_$index'
        '_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    if (mounted) setState(() => _recordingIndex = index);
  }

  Future<void> _stopRecord(int index) async {
    final String? path = await _recorder.stop();
    if (!mounted) return;
    setState(() {
      _recordingIndex = null;
      // ★ path 为 null = 这次没录成(权限被撤、被系统打断)。
      //   保留上一次的录音,不要用 null 覆盖掉一条录好的。
      if (path != null) _localPaths[index] = path;
    });
    if (path == null) {
      CyNativeNotice.show(context, stringsOf(context).merchantNodeRecordingFailed, isError: true);
    }
  }

  Future<void> _play(int index) async {
    final String? path = _localPaths[index];
    if (path == null || _recordingIndex != null) return;
    if (_playingIndex == index) {
      await _player.stop();
      if (mounted) setState(() => _playingIndex = null);
      return;
    }
    setState(() => _playingIndex = index);
    try {
      // tag = MediaItem 是给 just_audio_background 的锁屏/控制中心元数据;
      // 标题用该句脚本原文(真实内容,不是编的)。
      await _player.setFilePath(
        path,
        tag: MediaItem(
          id: 'npc-voice-enroll-$index-$path',
          title: stringsOf(context).merchantVoicePlaybackTitle(index + 1, _script.lines[index]),
          // 1ms 防炸兜底:just_audio_background 锁屏拖动对 duration! 强解包。
          duration: const Duration(milliseconds: 1),
        ),
      );
      await _player.play();
      await _player.processingStateStream.firstWhere(
        (ProcessingState s) => s == ProcessingState.completed,
      );
    } catch (_) {
      // 回放失败不影响录音本身,静默收尾即可。
    } finally {
      if (mounted) setState(() => _playingIndex = null);
    }
  }

  Future<void> _submit() async {
    final int? missing = _firstMissing;
    if (missing != null) {
      CyNativeNotice.show(context, stringsOf(context).merchantVoiceMissing(missing), isError: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      // 先把五段音频上传拿到公网地址,再一次性提交 ——
      // 后端要用这些地址去调供应商,拿不到 URL 就没法克隆。
      final List<String> urls = <String>[];
      for (final String? path in _localPaths) {
        urls.add(
          await ref.read(publishApiProvider).uploadFile(path!, fileType: 'm4a'),
        );
      }
      final String msg = await ref
          .read(merchantNpcApiProvider)
          .voiceEnroll(urls);
      if (!mounted) return;
      // 不再立刻退页:提交成功只是「录好了」,声音还在生成。
      // 停在这里把进度说清楚,比回到上一页干等强。
      setState(() {
        _submitted = true;
        _status = const NpcVoiceStatus(voiceStatus: 1);
      });
      CyNativeNotice.show(context, msg);
      _syncPoll();
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantVoiceTitle)),
        child: Material(
          color: Colors.transparent,
          child: SafeArea(bottom: false, child: CySkeleton()),
        ),
      );
    }

    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;

    if (_submitted) {
      return CupertinoPageScaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantVoiceTitle)),
        child: Material(
          color: Colors.transparent,
          child: SafeArea(bottom: false, child: _submittedBody(p, t)),
        ),
      );
    }

    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantVoiceTitle)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: _loadFailed
              ? merchantErrorView(
                  context,
                  stringsOf(context).merchantVoiceScriptFailed,
                  onRetry: _load,
                  what: stringsOf(context).merchantVoiceScript,
                )
              // ★ ② 供应商没接就直说,并且不给录音入口。
              : !_script.available
              ? StatusView(
                  message: stringsOf(context).merchantVoiceUnavailable,
                  sub: stringsOf(context).merchantVoiceUnavailableHint,
                  icon: CupertinoIcons.mic_slash,
                  large: true,
                )
              : ListView(
                  padding: const EdgeInsets.all(CyTokens.space4),
                  children: <Widget>[
                    Text(
                      stringsOf(context).merchantVoiceIntro,
                      style: t.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                    const SizedBox(height: CyTokens.space4),
                    for (int i = 0; i < _script.lines.length; i++)
                      _lineCard(i, p, t),
                    const SizedBox(height: CyTokens.space2),
                    Text(
                      '你可以随时在店铺形象页撤回,撤回后声音会被删除。',
                      style: t.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                    const SizedBox(height: CyTokens.space3),
                    CyNativeButton(
                      key: const Key('merchant-npc-voice-submit'),
                      onPressed: _submitting || !_allRecorded ? null : _submit,
                      label: _submitting ? stringsOf(context).merchantNodeSubmitting : stringsOf(context).merchantVoiceSubmitFive,
                      loading: _submitting,
                    ),
                    if (!_allRecorded && _firstMissing != null) ...<Widget>[
                      const SizedBox(height: CyTokens.space2),
                      Text(
                        stringsOf(context).merchantVoiceMissing(_firstMissing!),
                        style: t.bodySmall?.copyWith(color: p.textSecondary),
                      ),
                    ],
                    const SizedBox(height: CyTokens.space6),
                  ],
                ),
        ),
      ),
    );
  }

  /// 提交后的进度页。
  ///
  /// ★ 三种收口各有各的下一步:就绪 → 完成;失败 → 直接能重录;
  ///   生成中 → 允许先走(**稍后再说**),因为克隆要好几分钟,
  ///   把人扣在这一页等是最差的做法。
  ///
  /// ★ 三句正话逐字取自小程序 `pages/merchant/decor/ai-npc/index.wxml:177-188`
  ///   的同一档状态(那边是上传录音、这边是录五句,状态机是同一套)。
  Widget _submittedBody(CyPalette p, TextTheme t) {
    final NpcVoiceStatus status =
        _status ?? const NpcVoiceStatus(voiceStatus: 1);
    final bool generating = status.isGenerating;
    return ListView(
      padding: const EdgeInsets.all(CyTokens.space4),
      children: <Widget>[
        Text(
          status.isReady
              ? stringsOf(context).merchantVoiceReady
              : status.isFailed
              ? stringsOf(context).merchantVoiceFailed
              : stringsOf(context).merchantVoiceGenerating,
          style: t.bodyMedium,
        ),
        const SizedBox(height: CyTokens.space2),
        Text(
          status.label,
          key: const Key('merchant-npc-voice-state'),
          style: t.bodySmall?.copyWith(
            color: status.isFailed ? p.statusWarning : p.textSecondary,
          ),
        ),
        const SizedBox(height: CyTokens.space4),
        if (generating)
          CyNativeButton(
            key: const Key('merchant-npc-voice-later'),
            label: stringsOf(context).merchantVoiceLater,
            role: CyNativeButtonRole.secondary,
            onPressed: () => Navigator.of(context).maybePop(true),
          ),
        if (generating) ...<Widget>[
          const SizedBox(height: CyTokens.space2),
          CupertinoButton(
            key: const Key('merchant-npc-voice-check'),
            padding: EdgeInsets.zero,
            minimumSize: const Size(88, 44),
            onPressed: _refreshStatus,
            child: Text(stringsOf(context).merchantVoiceCheckStatus),
          ),
        ],
        if (status.isReady)
          CyNativeButton(
            key: const Key('merchant-npc-voice-done'),
            label: stringsOf(context).merchantVoiceDone,
            onPressed: () => Navigator.of(context).maybePop(true),
          ),
        if (status.isFailed)
          CyNativeButton(
            key: const Key('merchant-npc-voice-retry-record'),
            label: stringsOf(context).merchantVoiceRecordAgain,
            onPressed: () => setState(() {
              _submitted = false;
              _status = null;
            }),
          ),
      ],
    );
  }

  Future<void> _refreshStatus() async {
    try {
      final NpcVoiceStatus next = await ref
          .read(merchantNpcApiProvider)
          .voiceStatus();
      if (!mounted) return;
      setState(() => _status = next);
      _syncPoll();
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Widget _lineCard(int index, CyPalette p, TextTheme t) {
    final bool isConsent = _script.isConsentLine(index);
    final bool recorded = _localPaths[index] != null;
    final bool recording = _recordingIndex == index;
    final bool playing = _playingIndex == index;

    return Container(
      margin: const EdgeInsets.only(bottom: CyTokens.space3),
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(stringsOf(context).merchantVoiceSentence(index + 1), style: t.labelLarge),
              if (isConsent) ...<Widget>[
                const SizedBox(width: CyTokens.space2),
                // ★ ① 授权声明必须单独标出来 —— 那段录音本身就是同意的证据。
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space2,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: p.bgSurfaceSubtle,
                    borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                  ),
                  child: Text(stringsOf(context).merchantVoiceAuthorizationLabel, style: t.bodySmall),
                ),
              ],
              const Spacer(),
              if (recorded && !recording)
                Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  size: 18,
                  color: p.textSecondary,
                ),
            ],
          ),
          if (isConsent) ...<Widget>[
            const SizedBox(height: CyTokens.space1),
            Text(
              '这一句是你本人的授权。念完并提交,即表示你同意城瘾用你的声音'
              '生成本店 AI 形象的语音。',
              style: t.bodySmall?.copyWith(color: p.textSecondary),
            ),
          ],
          const SizedBox(height: CyTokens.space2),
          Text(_script.lines[index], style: t.bodyMedium),
          const SizedBox(height: CyTokens.space3),
          Row(
            children: <Widget>[
              CupertinoButton(
                key: Key('merchant-npc-voice-record-$index'),
                padding: EdgeInsets.zero,
                minimumSize: const Size(88, 44),
                // 别的句子在录时不给按 —— 同时录两句会互相打断。
                onPressed: (_recordingIndex != null && !recording)
                    ? null
                    : () => _toggleRecord(index),
                child: Text(
                  recording
                      ? stringsOf(context).merchantVoiceStop
                      : recorded
                      ? stringsOf(context).merchantNodeRerecord
                      : stringsOf(context).merchantVoiceRecord,
                ),
              ),
              if (recorded && !recording)
                CupertinoButton(
                  key: Key('merchant-npc-voice-play-$index'),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(88, 44),
                  onPressed: () => _play(index),
                  child: Text(playing ? stringsOf(context).merchantNodeStopPlaying : stringsOf(context).merchantVoiceListen),
                ),
              if (recording) ...<Widget>[
                const SizedBox(width: CyTokens.space2),
                Text(
                  stringsOf(context).merchantVoiceRecording,
                  style: t.bodySmall?.copyWith(color: p.textSecondary),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
