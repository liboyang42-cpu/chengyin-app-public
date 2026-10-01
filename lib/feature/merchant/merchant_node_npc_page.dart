import '../../l10n/strings.dart';
import 'merchant_node_strings.dart';
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

import '../../core/media_art_uri.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../data/api/merchant_api.dart';
import '../../data/models/chapter_node_npc.dart';
import '../club/club_image_picker.dart';
import 'merchant_error_view.dart';

/// 点位上的 AI 角色。对齐小程序 `components/cy/node-npc-form`(挂在
/// `pages/topic/merchantinfo` 上,App 的对等页是 [MerchantRecruitPage])。
///
/// ★★ 与**店铺形象**(`/merchant/npc`,店铺级)完全分开:那套挂在商家身上、
///   玩家在店铺主页点开对话;这套挂在**某个章节点位**上,漫游到那个点位才有。
///   后端明说不许复用门店端点(node-npc-form.test.js:132),所以这里不去抄那一页。
///
/// ⚠️ 与小程序的一处**有意差异**:形象只走「上传照片」,不移植那 12 张预设像素头像
///   —— 它们在真源里是一张 30KB 的行程编码表 + 一个 canvas 渲染器
///   (`utils/pixel-avatar-data.js`),搬过来等于把一份图形资产塞进 App;
///   而小程序里「照片」这条路本来也是等价可用的。
class MerchantNodeNpcPage extends ConsumerStatefulWidget {
  const MerchantNodeNpcPage({super.key, required this.nodeId, this.nodeName});

  final int nodeId;
  final String? nodeName;

  @override
  ConsumerState<MerchantNodeNpcPage> createState() =>
      _MerchantNodeNpcPageState();
}

class _MerchantNodeNpcPageState extends ConsumerState<MerchantNodeNpcPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _greeting = TextEditingController();

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  ChapterNodeNpc _npc = ChapterNodeNpc.empty;
  bool _loading = true;
  String? _loadError;

  bool _saving = false;
  bool _uploading = false;

  bool _recording = false;
  bool _voiceBusy = false;
  bool _playing = false;
  Timer? _voicePoll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // ★ 离页必须停麦克风:不停的话表现是「退出这页之后微信语音也用不了了」。
    _recorder.dispose();
    _player.dispose();
    _voicePoll?.cancel();
    _name.dispose();
    _greeting.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final Map<String, dynamic>? data = await ref
          .read(merchantApiProvider)
          .chapterNodeNpcDetail(widget.nodeId);
      if (!mounted) return;
      final ChapterNodeNpc npc = data == null
          ? ChapterNodeNpc.empty
          : ChapterNodeNpc.fromJson(data);
      setState(() {
        _npc = npc;
        _name.text = npc.name;
        _greeting.text = npc.greeting;
        _loading = false;
      });
      _syncVoicePoll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// 生成中(1)才轮询;其余状态一律停表。
  void _syncVoicePoll() {
    _voicePoll?.cancel();
    if (!_npc.isVoiceGenerating) return;
    _voicePoll = Timer.periodic(const Duration(seconds: 5), (Timer t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      try {
        final Map<String, dynamic> data = await ref
            .read(merchantApiProvider)
            .chapterNodeNpcVoiceStatus(widget.nodeId);
        if (!mounted) return;
        setState(
          () => _npc = _npc.copyWith(
            voiceStatus: int.tryParse('${data['voiceStatus']}'),
            voiceSample: data['voiceSample'] as String?,
          ),
        );
        if (!_npc.isVoiceGenerating) t.cancel();
      } catch (_) {
        // ★ 查询失败不改判:状态是背景事实,下一次轮询就是重试。
        //   弹提示会把正在填表的人打断,而那正是真源有意静默的地方。
      }
    });
  }

  Future<void> _pickAvatar() async {
    setState(() => _uploading = true);
    try {
      final List<String> urls = await pickAndUploadImages(
        context,
        ref,
        maxCount: 1,
      );
      if (urls.isNotEmpty && mounted) {
        setState(() => _npc = _npc.copyWith(avatar: urls.first));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  ChapterNodeNpc get _draft =>
      _npc.copyWith(name: _name.text, greeting: _greeting.text);

  Future<void> _save() async {
    // 先本地拦一道:填的时候就知道缺什么,而不是提交后被打回。
    // 真正算数的是后端那道 —— 这里只省一次往返。
    final String? why = _draft.saveBlocker;
    if (why != null) {
      CyNativeNotice.show(context, merchantNodeLocalText(context, why), isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final Map<String, dynamic> data = await ref
          .read(merchantApiProvider)
          .chapterNodeNpcSave(
            nodeId: widget.nodeId,
            name: _draft.name.trim(),
            avatar: _draft.avatar.trim(),
            greeting: _draft.greeting.trim(),
          );
      if (!mounted) return;
      // 回读服务端那一份:它才是下一步的输入(name/avatar 都可能被规整过)。
      final ChapterNodeNpc saved = ChapterNodeNpc.fromJson(data);
      setState(() {
        _npc = saved.avatar.isEmpty && saved.name.isEmpty
            ? _npc.copyWith(
                name: _draft.name.trim(),
                greeting: _draft.greeting.trim(),
              )
            : saved;
        _name.text = _npc.name;
        _greeting.text = _npc.greeting;
      });
      CyNativeNotice.show(context, stringsOf(context).merchantNodeSaved);
    } on MerchantApiException catch (e) {
      if (!mounted) return;
      // 「承接已失效或未生效,不能编辑节点内容」等状态态原样透传 ——
      // 换成「保存失败」商家不知道自己该去补哪一步。
      CyNativeNotice.show(context, e.message, isError: true);
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      final String? path = await _recorder.stop();
      if (!mounted) return;
      setState(() => _recording = false);
      if (path == null) {
        CyNativeNotice.show(context, stringsOf(context).merchantNodeRecordingFailed, isError: true);
        return;
      }
      await _submitVoice(path);
      return;
    }
    // ★ 权限在**按下录音时**才要,不在进页面时要 —— 进页面就弹框,
    //   用户还不知道要它干什么。
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        CyNativeNotice.show(context, stringsOf(context).merchantNodeMicrophoneNeeded, isError: true);
      }
      return;
    }
    await _player.stop();
    final Directory dir = await getTemporaryDirectory();
    final String path =
        '${dir.path}/node_npc_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    if (mounted) {
      setState(() {
        _playing = false;
        _recording = true;
      });
    }
  }

  Future<void> _submitVoice(String localPath) async {
    setState(() => _voiceBusy = true);
    try {
      final String url = await ref
          .read(publishApiProvider)
          .uploadFile(localPath, fileType: 'm4a');
      final Map<String, dynamic> data = await ref
          .read(merchantApiProvider)
          .chapterNodeNpcVoiceEnroll(nodeId: widget.nodeId, voiceSample: url);
      if (!mounted) return;
      setState(
        () => _npc = _npc.copyWith(
          voiceStatus: int.tryParse('${data['voiceStatus']}') ?? 1,
          voiceSample: data['voiceSample'] as String?,
        ),
      );
      _syncVoicePoll();
      CyNativeNotice.show(context, stringsOf(context).merchantNodeVoiceSubmitted);
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
      // 可能已经提交成功:回读一次状态,别让人对着旧状态重录、白烧一次生成。
      unawaited(_refreshVoiceStatus());
    } finally {
      if (mounted) setState(() => _voiceBusy = false);
    }
  }

  Future<void> _refreshVoiceStatus() async {
    try {
      final Map<String, dynamic> data = await ref
          .read(merchantApiProvider)
          .chapterNodeNpcVoiceStatus(widget.nodeId);
      if (!mounted) return;
      setState(
        () => _npc = _npc.copyWith(
          voiceStatus: int.tryParse('${data['voiceStatus']}'),
          voiceSample: data['voiceSample'] as String?,
        ),
      );
      _syncVoicePoll();
    } catch (_) {
      // 同上:查询失败不改判。
    }
  }

  Future<void> _resetVoice() async {
    final bool ok = await cyConfirm(
      context,
      title: stringsOf(context).merchantNodeClearVoiceTitle,
      content: stringsOf(context).merchantNodeClearVoiceBody,
      confirmText: stringsOf(context).merchantNodeClear,
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _voiceBusy = true);
    try {
      await ref
          .read(merchantApiProvider)
          .chapterNodeNpcVoiceReset(widget.nodeId);
      // 清除后回读:服务端的四态才是界面的输入。
      await _refreshVoiceStatus();
      if (!mounted) return;
      CyNativeNotice.show(context, stringsOf(context).merchantNodeCleared);
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _voiceBusy = false);
    }
  }

  Future<void> _playSample() async {
    final String? url = _npc.voiceSample;
    if (url == null || url.isEmpty || _recording) return;
    if (_playing) {
      await _player.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    setState(() => _playing = true);
    try {
      // tag = MediaItem 是给 just_audio_background 的锁屏/控制中心元数据,
      // 标题/形象图都取角色真实字段。
      await _player.setUrl(
        url,
        tag: MediaItem(
          id: 'node-npc-voice-${widget.nodeId}-$url',
          title: _npc.name,
          artUri: mediaArtUri(_npc.avatar),
          // 1ms 防炸兜底:just_audio_background 锁屏拖动对 duration! 强解包。
          duration: const Duration(milliseconds: 1),
        ),
      );
      await _player.play();
      await _player.processingStateStream.firstWhere(
        (ProcessingState s) => s == ProcessingState.completed,
      );
    } catch (_) {
      // 试听失败不影响声音本身,静默收尾。
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          widget.nodeName?.trim().isNotEmpty == true
              ? stringsOf(context).merchantNodeCharacterTitle(widget.nodeName!.trim())
              : stringsOf(context).merchantNodeNodeCharacter,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: _loading
              ? const Center(child: CupertinoActivityIndicator())
              : _loadError != null
              ? merchantErrorView(
                  context,
                  _loadError!,
                  onRetry: _load,
                  what: stringsOf(context).merchantNodeNodeCharacter,
                )
              : ListView(
                  padding: const EdgeInsets.all(CyTokens.space4),
                  children: <Widget>[
                    Text(
                      stringsOf(context).merchantNodeNodeCharacterIntro,
                      style: t.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                    const SizedBox(height: CyTokens.space4),

                    CySectionTitle(stringsOf(context).merchantNodeCharacterAppearance),
                    const SizedBox(height: CyTokens.space2),
                    _avatarBlock(p, t),
                    const SizedBox(height: CyTokens.space4),

                    _textField(
                      key: 'node-npc-name',
                      controller: _name,
                      label: stringsOf(context).merchantNodeCharacterName,
                      hint: stringsOf(context).merchantNodeCharacterNameHint,
                    ),
                    _textField(
                      key: 'node-npc-greeting',
                      controller: _greeting,
                      label: stringsOf(context).merchantNodeGreetingOptional,
                      hint: stringsOf(context).merchantNodeNodeGreetingHint,
                      maxLines: 2,
                    ),

                    const SizedBox(height: CyTokens.space2),
                    CySectionTitle(stringsOf(context).merchantNodeCharacterVoice),
                    const SizedBox(height: CyTokens.space1),
                    _voiceBlock(p, t),

                    const SizedBox(height: CyTokens.space4),
                    CyNativeButton(
                      key: const Key('node-npc-save'),
                      label: _saving ? stringsOf(context).merchantNodeSaving : stringsOf(context).merchantNodeSave,
                      loading: _saving,
                      onPressed: _saving ? null : _save,
                    ),
                    const SizedBox(height: CyTokens.space6),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _avatarBlock(CyPalette p, TextTheme t) {
    final String avatar = _npc.avatar;
    if (avatar.trim().isEmpty) {
      return CyNativeButton(
        key: const Key('node-npc-avatar-upload'),
        onPressed: _uploading ? null : _pickAvatar,
        role: CyNativeButtonRole.secondary,
        label: _uploading ? stringsOf(context).merchantNodeUploading : stringsOf(context).merchantNodeUploadCharacter,
      );
    }
    return Row(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          child: CyNetImage(avatar, width: 72, height: 72, fit: BoxFit.cover),
        ),
        const SizedBox(width: CyTokens.space3),
        CupertinoButton(
          key: const Key('node-npc-avatar-replace'),
          padding: EdgeInsets.zero,
          minimumSize: const Size(88, 44),
          onPressed: _uploading ? null : _pickAvatar,
          child: Text(_uploading ? stringsOf(context).merchantNodeUploading : stringsOf(context).merchantNodeChangeImage),
        ),
        if (_uploading) const CupertinoActivityIndicator(),
      ],
    );
  }

  Widget _voiceBlock(CyPalette p, TextTheme t) {
    final ChapterNodeNpc npc = _npc;
    final Widget line = Text(
      merchantNodeLocalText(context, npc.voiceLabel),
      key: const Key('node-npc-voice-status'),
      style: t.bodySmall?.copyWith(
        color: npc.isVoiceFailed ? p.statusWarning : p.textSecondary,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          stringsOf(context).merchantNodeVoiceHint,
          style: t.bodySmall?.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: CyTokens.space2),
        line,
        const SizedBox(height: CyTokens.space2),
        Wrap(
          spacing: CyTokens.space2,
          runSpacing: CyTokens.space2,
          children: <Widget>[
            if (!npc.isVoiceGenerating && !npc.isVoiceReady)
              CyNativeButton(
                key: const Key('node-npc-voice-record'),
                label: _recording
                    ? stringsOf(context).merchantNodeStopSubmit
                    : _voiceBusy
                    ? stringsOf(context).merchantNodeSubmitting
                    : npc.isVoiceFailed
                    ? stringsOf(context).merchantNodeRecordAgain
                    : stringsOf(context).merchantNodeRecordVoice,
                role: CyNativeButtonRole.secondary,
                loading: _voiceBusy && !_recording,
                onPressed: (_voiceBusy && !_recording) ? null : _toggleRecord,
              ),
            if (npc.isVoiceReady)
              CyNativeButton(
                key: const Key('node-npc-voice-play'),
                label: _playing ? stringsOf(context).merchantNodeStopPlaying : stringsOf(context).merchantNodeListen,
                role: CyNativeButtonRole.secondary,
                onPressed: _playSample,
              ),
            if (npc.isVoiceReady || npc.isVoiceFailed)
              CyNativeButton(
                key: const Key('node-npc-voice-reset'),
                label: stringsOf(context).merchantNodeClearVoice,
                role: CyNativeButtonRole.secondary,
                loading: _voiceBusy,
                onPressed: _voiceBusy ? null : _resetVoice,
              ),
            if (npc.isVoiceGenerating)
              CyNativeButton(
                key: const Key('node-npc-voice-refresh'),
                label: stringsOf(context).merchantNodeRefreshStatus,
                role: CyNativeButtonRole.secondary,
                onPressed: _refreshVoiceStatus,
              ),
          ],
        ),
      ],
    );
  }

  Widget _textField({
    required String key,
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: CyTokens.space1),
          CupertinoTextField(
            key: Key(key),
            controller: controller,
            minLines: 1,
            maxLines: maxLines,
            placeholder: hint,
            padding: const EdgeInsets.symmetric(
              horizontal: CyTokens.space3,
              vertical: 12,
            ),
            textInputAction: maxLines > 1
                ? TextInputAction.newline
                : TextInputAction.next,
            clearButtonMode: OverlayVisibilityMode.editing,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }
}
