import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../../../core/theme/cy_palette.dart';
import '../../../../core/theme/cy_tokens.dart';
import '../../../../core/widgets/cy_native_button.dart';
import '../../../../core/widgets/cy_net_image.dart';
import '../playkit_fullscreen.dart';
import '../playkit_projection.dart';
import 'playkit_fullscreen_parts.dart';
import 'playkit_prefab_data.dart';
import 'playkit_quiz_data.dart';
import 'playkit_quiz_views.dart';
import 'playkit_timer_logic.dart';
import 'playkit_timer_parts.dart';

/// 《预制人生》四段的整屏组件(profile · photoCheck · note · typeIn)。
///
/// 真源 = 小程序 `pages/play/components/playkit-{profile,photocheck,note,typein}/`,
/// 四屏共用 `cy-play-stage` 的 `skin="qadark"` 台面 —— 与问答族同一个壳,
/// 所以直接坐 [PlayKitQuizStage] 上(§7.2:同样的信息顺序,iOS 原生化控件)。
///
/// ## 硬约束(四屏共用)
/// 1. **结果一律由服务端定**:建档提交即锁档、拍照按视觉模型判、打字限时
///    按服务器时间复核 —— 组件不改状态,判定回来由新投影重建卡片。
/// 2. **两步链不落直发**:photoCheck 只抛 [kPhotoCheckShootAction] 与临时路径;
///    建档头像走 [PlayKitFullscreenContext.onUploadPhoto] 拿地址,**不发任何动作**,
///    地址留着随 SUBMIT_PROFILE 一起报(真源 `_submitKitPhoto` 的 avatar 分支)。
/// 3. **fail-forward**:拍照审核的降级态只说「这次没能审」,不出现假结论 ——
///    文案分支在 [PlayKitPhotoCheckData.verdict],组件照摆。
///
/// ⚠️ typeIn 的限时条真源画在共享台面(`limit-seconds`),到点判负也是台面的
///    `failByTime`;App 侧台面未落地(停表那批同理),本组件自带同参计数与
///    到点收表 —— 判定仍是服务端的事,这里只是不让玩家对着输入框永远打下去。

// ── ① 出生登记(profile)──────────────────────────────────────

class PlayKitProfileView extends StatefulWidget {
  const PlayKitProfileView({
    super.key,
    required this.data,
    this.photoPicker = playKitPickQaPhoto,
  });

  final PlayKitFullscreenContext data;

  /// 取头像的实现。默认弹系统来源选择;测试注入替身,不弹系统相册。
  final Future<PlayKitQaPhoto?> Function(BuildContext context) photoPicker;

  @override
  State<PlayKitProfileView> createState() => _PlayKitProfileViewState();
}

class _PlayKitProfileViewState extends State<PlayKitProfileView> {
  /// 每道文本题一个控制器(题目清单由商家配置,数量不固定)。
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};

  /// 点选本题已选的 optionKey(按题目 key 归组)。
  final Map<String, String> _picks = <String, String>{};

  /// 本地刚上传的头像地址(服务端把它写回 kit 前先看得见)。
  String _uploadedAvatar = '';
  bool _avatarBusy = false;

  PlayKitProfileData get _data =>
      PlayKitProfileData.fromKit(widget.data.card.kit);

  /// 当前整份表单:文本题取控制器,点选题取已选 optionKey,
  /// 没动过的题回落服务端已存答案(重进不丢档)。
  Map<String, String> get _form {
    final PlayKitProfileData data = _data;
    return <String, String>{
      for (final PlayKitProfileQuestion q in data.questions)
        q.key:
            _controllers[q.key]?.text ??
            _picks[q.key] ??
            data.answers[q.key] ??
            '',
    };
  }

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(PlayKitProfileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllers();
  }

  /// 控制器跟着投影补建(题目由商家配置,数量不固定);
  /// done 后服务端给的就是权威答案,回填一次。
  void _syncControllers() {
    final PlayKitProfileData data = _data;
    for (final PlayKitProfileQuestion q in data.questions) {
      if (q.isPick) {
        final String answer = data.answers[q.key] ?? '';
        if (answer.isNotEmpty && _picks[q.key] == null) {
          _picks[q.key] = answer;
        }
        continue;
      }
      final TextEditingController? existing = _controllers[q.key];
      if (existing != null) {
        if (existing.text.isEmpty && (data.answers[q.key] ?? '').isNotEmpty) {
          existing.text = data.answers[q.key]!;
        }
        continue;
      }
      final TextEditingController controller = TextEditingController(
        text: data.answers[q.key] ?? '',
      )..addListener(_onFormChanged);
      _controllers[q.key] = controller;
    }
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final TextEditingController controller in _controllers.values) {
      controller.removeListener(_onFormChanged);
      controller.dispose();
    }
    super.dispose();
  }

  /// 头像只是**选一张再传上去**:不发动作,地址留着随提交一起报。
  Future<void> _pickAvatar() async {
    final PlayKitProfileData data = _data;
    if (data.done || _avatarBusy || !widget.data.enabled) return;
    final PlayKitQaPhoto? photo = await widget.photoPicker(context);
    if (photo == null || !mounted) return;
    final Future<String?> Function(Map<String, Object?> detail)? upload =
        widget.data.onUploadPhoto;
    if (upload == null) return; // 宿主没接上传:与真源无上传通道同口径,不动
    setState(() => _avatarBusy = true);
    try {
      final String? url = await upload(photo.toPayload());
      if (mounted && url != null && url.isNotEmpty) {
        setState(() => _uploadedAvatar = url);
      }
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  void _submit() {
    final PlayKitProfileData data = _data;
    if (data.done || !data.ctaEnabled(_form)) return;
    if (!widget.data.enabled || widget.data.acting) return;
    playKitHaptic(context, PlayKitHaptic.medium);
    widget.data.onAction?.call(
      PlayKitAction(
        label: '提交登记',
        action: kProfileSubmitAction,
        payload: data.submitPayload(_form, _avatar),
      ),
    );
  }

  String get _avatar {
    final PlayKitProfileData data = _data;
    // 服务端已回写的地址优先(那是过了上传那关的真地址);本地这张是刚传的预览。
    return data.avatarUrl.isNotEmpty ? data.avatarUrl : _uploadedAvatar;
  }

  @override
  Widget build(BuildContext context) {
    final PlayKitProfileData data = _data;
    final CyPalette palette = CyPalette.of(context);
    final bool writable = widget.data.enabled && !data.done;
    return PlayKitQuizStage(
      data: widget.data,
      title: data.title,
      lead: data.lead,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (data.avatarEnabled)
            Padding(
              padding: const EdgeInsets.only(bottom: CyTokens.space4),
              child: Row(
                children: <Widget>[
                  Semantics(
                    button: writable,
                    enabled: writable,
                    label: _avatar.isEmpty
                        ? (data.avatarRequired ? '放一张照片' : '放张照片（可选）')
                        : '换一张头像',
                    child: ExcludeSemantics(
                      child: CupertinoButton(
                        key: const Key('playkit-profile-avatar'),
                        padding: EdgeInsets.zero,
                        onPressed: writable
                            ? () => unawaited(_pickAvatar())
                            : null,
                        child: Column(
                          children: <Widget>[
                            Container(
                              width: 88, // .pf__ava-img 176rpx
                              height: 88,
                              decoration: BoxDecoration(
                                color: palette.bgSurfaceSubtle,
                                shape: BoxShape.circle,
                                border: Border.all(color: palette.borderSubtle),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: _avatar.isEmpty
                                  ? Icon(
                                      CupertinoIcons.camera,
                                      size: 26,
                                      color: palette.textTertiary,
                                    )
                                  : CyNetImage(_avatar, fit: BoxFit.cover),
                            ),
                            const SizedBox(height: CyTokens.space1),
                            Text(
                              _avatarBusy
                                  ? '上传中…'
                                  : (_avatar.isEmpty
                                        ? (data.avatarRequired
                                              ? '放一张照片'
                                              : '放张照片（可选）')
                                        : '换一张'),
                              style: TextStyle(
                                fontSize: CyTokens.typeCaption,
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          for (final PlayKitProfileQuestion q in data.questions)
            Padding(
              padding: const EdgeInsets.only(bottom: CyTokens.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          q.label.isEmpty ? q.key : q.label,
                          style: TextStyle(
                            fontSize: CyTokens.typeBody,
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      if (q.required)
                        Padding(
                          padding: const EdgeInsets.only(left: CyTokens.space2),
                          child: Text(
                            '必填',
                            style: TextStyle(
                              fontSize: CyTokens.typeCaption,
                              color: palette.textTertiary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: CyTokens.space2),
                  if (q.isPick)
                    for (final (int index, PlayKitQuizChoice option)
                        in q.options.indexed)
                      PlayKitQuizOptionRow(
                        key: Key(
                          'playkit-profile-${q.key}-${option.id.isEmpty ? index : option.id}',
                        ),
                        marker: PlayKitQuizOption.keyLabel(index),
                        label: option.label,
                        state: _picks[q.key] == option.id
                            ? PlayKitQuizOptionState.picked
                            : PlayKitQuizOptionState.idle,
                        onTap: writable
                            ? () {
                                playKitHaptic(context, PlayKitHaptic.selection);
                                setState(() => _picks[q.key] = option.id);
                              }
                            : null,
                      )
                  else
                    CupertinoTextField(
                      key: Key('playkit-profile-${q.key}'),
                      controller: _controllers[q.key],
                      enabled: writable,
                      maxLength: q.maxLength > 0 ? q.maxLength : null,
                      placeholder: '写在这里',
                      placeholderStyle: TextStyle(
                        color: palette.textPlaceholder,
                      ),
                      padding: const EdgeInsets.all(CyTokens.space3),
                      style: TextStyle(
                        fontSize: CyTokens.typeBody,
                        color: palette.textPrimary,
                      ),
                      decoration: BoxDecoration(
                        color: palette.inputBgEmpty,
                        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                        border: Border.all(color: palette.borderSubtle),
                      ),
                    ),
                ],
              ),
            ),
          if (data.done)
            Text(
              '档案已提交，往后翻就是你的名字了',
              style: TextStyle(
                fontSize: CyTokens.typeLabel,
                color: palette.statusSuccess, // .pf__done 真源 --ok
              ),
            ),
        ],
      ),
      footer: CyNativeButton(
        key: const Key('playkit-profile-cta'),
        label: data.done ? '已登记' : '提交登记',
        width: double.infinity,
        loading: _avatarBusy || widget.data.acting,
        onPressed: writable && data.ctaEnabled(_form) ? _submit : null,
      ),
    );
  }
}

// ── ② 拍照审核(photoCheck)───────────────────────────────────

class PlayKitPhotoCheckView extends StatefulWidget {
  const PlayKitPhotoCheckView({
    super.key,
    required this.data,
    this.photoPicker = playKitPickQaPhoto,
  });

  final PlayKitFullscreenContext data;

  /// 取照片的实现。默认弹系统来源选择;测试注入替身,不弹系统相册。
  final Future<PlayKitQaPhoto?> Function(BuildContext context) photoPicker;

  @override
  State<PlayKitPhotoCheckView> createState() => _PlayKitPhotoCheckViewState();
}

class _PlayKitPhotoCheckViewState extends State<PlayKitPhotoCheckView> {
  /// 拍照在途(选图器开着或刚选完):真源 `busy` 同一条。
  bool _busy = false;

  PlayKitPhotoCheckData get _data =>
      PlayKitPhotoCheckData.fromKit(widget.data.card.kit);

  /// 拍/选一张 → 只抛临时路径给宿主的两步链(上传 → 连地址提交);
  /// 判定全在服务端,组件不读像素。
  Future<void> _shoot() async {
    final PlayKitPhotoCheckData data = _data;
    if (_busy || data.locked || !widget.data.enabled || widget.data.acting) {
      return;
    }
    setState(() => _busy = true);
    try {
      final PlayKitQaPhoto? photo = await widget.photoPicker(context);
      if (photo == null || !mounted) return;
      playKitHaptic(context, PlayKitHaptic.medium);
      widget.data.onAction?.call(
        PlayKitAction(
          label: '拍一张',
          action: kPhotoCheckShootAction,
          payload: photo.toPayload(),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PlayKitPhotoCheckData data = _data;
    final CyPalette palette = CyPalette.of(context);
    return PlayKitQuizStage(
      data: widget.data,
      title: data.title,
      lead: data.shotNote,
      media: ClipRRect(
        borderRadius: BorderRadius.circular(
          CyTokens.radiusXl,
        ), // .pc__frame --cy-radius-xl
        child: data.lastUrl.isEmpty
            ? Container(
                height: 240, // .pc__frame 480rpx
                width: double.infinity,
                color: palette.bgSurfaceSubtle,
                child: Center(
                  child: Icon(
                    CupertinoIcons.photo,
                    size: 36,
                    color: palette.textTertiary,
                  ),
                ),
              )
            : CyNetImage(data.lastUrl, height: 240, width: double.infinity),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 「上一张提交的照片」的图在上方;这里只补一行「当时拍的是这张」的
          // 说明位 —— 真源图片自带 alt,读屏走下面的 CTA 语义。
          if (data.triesLabel.isNotEmpty &&
              data.verdict.isEmpty &&
              data.reason.isEmpty)
            PlayKitQuizFootnote(text: data.triesLabel),
        ],
      ),
      feedback: data.verdict.isEmpty && data.reason.isEmpty
          ? null
          : (data.reason.isEmpty
                ? data.verdict
                : '${data.verdict}\n${data.reason}'),
      feedbackHead: data.verdictKind == 'ok'
          ? '过了'
          : (data.verdictKind == 'no' ? '没过' : (data.degraded ? '没审成' : '')),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (data.triesLabel.isNotEmpty &&
              (data.verdict.isNotEmpty || data.reason.isNotEmpty))
            PlayKitQuizFootnote(text: data.triesLabel),
          CyNativeButton(
            key: const Key('playkit-photocheck-cta'),
            label: _busy || widget.data.acting
                ? '看一眼…'
                : (data.locked
                      ? '这一张已定'
                      : (data.lastUrl.isNotEmpty ? '再拍一张' : '拍一张')),
            width: double.infinity,
            onPressed:
                _busy ||
                    data.locked ||
                    !widget.data.enabled ||
                    widget.data.acting
                ? null
                : () => unawaited(_shoot()),
          ),
        ],
      ),
    );
  }
}

// ── ③ 留言(note)─────────────────────────────────────────────

class PlayKitNoteView extends StatefulWidget {
  const PlayKitNoteView({super.key, required this.data});

  final PlayKitFullscreenContext data;

  @override
  State<PlayKitNoteView> createState() => _PlayKitNoteViewState();
}

class _PlayKitNoteViewState extends State<PlayKitNoteView> {
  final TextEditingController _text = TextEditingController();
  bool _touched = false;

  PlayKitNoteData get _data => PlayKitNoteData.fromKit(widget.data.card.kit);

  @override
  void initState() {
    super.initState();
    _text.addListener(_onChanged);
    _prime();
  }

  @override
  void didUpdateWidget(PlayKitNoteView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _prime();
  }

  /// 留过之后输入框摆的就是自己那句(真源 observer:done 时 text = mine)。
  /// 玩家没动过之前,跟随投影里的权威值。
  void _prime() {
    final PlayKitNoteData data = _data;
    if (data.done) {
      if (_text.text != data.mine) _text.text = data.mine;
      return;
    }
    if (!_touched && _text.text.isEmpty && data.mine.isNotEmpty) {
      _text.text = data.mine;
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final PlayKitNoteData data = _data;
    final String text = _text.text.trim();
    if (data.done || text.isEmpty) return;
    if (!widget.data.enabled || widget.data.acting) return;
    playKitHaptic(context, PlayKitHaptic.medium);
    widget.data.onAction?.call(
      PlayKitAction(
        label: '留下这句',
        action: kNoteSubmitAction,
        payload: data.submitPayload(_text.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final PlayKitNoteData data = _data;
    final CyPalette palette = CyPalette.of(context);
    final bool writable = widget.data.enabled && !data.done;
    final String text = _text.text;
    return PlayKitQuizStage(
      data: widget.data,
      title: data.title,
      lead: data.prompt,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (data.previous.isNotEmpty) ...<Widget>[
            Text(
              '前面的人写过',
              style: TextStyle(
                fontSize: CyTokens.typeCaption,
                fontWeight: FontWeight.w600,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: CyTokens.space2),
            for (final PlayKitNoteEntry entry in data.previous)
              Padding(
                padding: const EdgeInsets.only(bottom: CyTokens.space2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        entry.text,
                        style: TextStyle(
                          fontSize: CyTokens.typeBody,
                          height: CyTokens.leadingNormal,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    if (entry.at != null)
                      Padding(
                        padding: const EdgeInsets.only(left: CyTokens.space2),
                        child: Text(
                          _noteDateText(entry.at!),
                          style: TextStyle(
                            fontSize: CyTokens.typeCaption,
                            color: palette.textTertiary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: CyTokens.space2),
          ],
          CupertinoTextField(
            key: const Key('playkit-note-input'),
            controller: _text,
            enabled: writable,
            maxLines: 3,
            maxLength: data.maxLength,
            placeholder: '写在下面',
            placeholderStyle: TextStyle(color: palette.textPlaceholder),
            padding: const EdgeInsets.all(CyTokens.space3),
            style: TextStyle(
              fontSize: CyTokens.typeBody,
              color: palette.textPrimary,
            ),
            decoration: BoxDecoration(
              color: palette.inputBgEmpty,
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              border: Border.all(color: palette.borderSubtle),
            ),
            onChanged: (_) => _touched = true,
          ),
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space1),
            child: Text(
              '${text.length}/${data.maxLength}',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: CyTokens.typeCaption,
                color: palette.textTertiary,
              ),
            ),
          ),
          if (!data.done && data.presets.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space3),
              child: Wrap(
                spacing: CyTokens.space2,
                runSpacing: CyTokens.space2,
                children: <Widget>[
                  for (final String preset in data.presets)
                    Semantics(
                      button: writable,
                      enabled: writable,
                      label: '用这句：$preset',
                      child: ExcludeSemantics(
                        child: CupertinoButton(
                          key: Key('playkit-note-preset-$preset'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: CyTokens.space3,
                            vertical: CyTokens.space2,
                          ),
                          minimumSize: Size.zero,
                          pressedOpacity: 0.6,
                          onPressed: writable
                              ? () {
                                  playKitHaptic(
                                    context,
                                    PlayKitHaptic.selection,
                                  );
                                  setState(() {
                                    _touched = true;
                                    _text.text = preset;
                                  });
                                }
                              : null,
                          child: Container(
                            decoration: BoxDecoration(
                              color: palette.bgSurfaceSubtle,
                              borderRadius: BorderRadius.circular(
                                CyTokens.radiusPill,
                              ),
                              border: Border.all(color: palette.borderSubtle),
                            ),
                            child: Text(
                              preset,
                              style: TextStyle(
                                fontSize: CyTokens.typeLabel,
                                color: palette.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (data.done)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space3),
              child: Text(
                '这句已经留在这儿了',
                style: TextStyle(
                  fontSize: CyTokens.typeLabel,
                  color: palette.statusSuccess, // .nt__done 真源 --ok
                ),
              ),
            ),
        ],
      ),
      footer: CyNativeButton(
        key: const Key('playkit-note-cta'),
        label: data.done ? '已留下' : '留下这句',
        width: double.infinity,
        loading: widget.data.acting,
        onPressed: writable && text.trim().isNotEmpty && !widget.data.acting
            ? _submit
            : null,
      ),
    );
  }
}

/// epoch 毫秒 → 「MM-dd HH:mm」(本地时区)。真源屏上印的是服务端给的原文,
/// App 侧按 iOS 原生时间口径格式化 —— §7.2 外观原生化,信息不变。
String _noteDateText(int epochMs) {
  final DateTime at = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
}

// ── ④ 限时打字(typeIn)───────────────────────────────────────

enum PlayKitTypeInPhase { intro, countIn, run, timedOut }

class PlayKitTypeInView extends StatefulWidget {
  const PlayKitTypeInView({
    super.key,
    required this.data,
    this.countIn = true,
    this.now,
  });

  final PlayKitFullscreenContext data;

  /// 真源 `cy-play-stage` 的 `count-in`:限时开跑前要数,不然反应在扣毫秒。
  final bool countIn;

  /// 注入时钟,测试用(与停表同一口)。
  final DateTime Function()? now;

  @override
  State<PlayKitTypeInView> createState() => _PlayKitTypeInViewState();
}

class _PlayKitTypeInViewState extends State<PlayKitTypeInView> {
  PlayKitTypeInPhase _phase = PlayKitTypeInPhase.intro;
  final TextEditingController _typed = TextEditingController();
  Timer? _countInTimer;
  Timer? _runTicker;
  DateTime? _startedAt;
  int _countInFrom = 3;
  int _leftSeconds = 0;

  DateTime get _now => (widget.now ?? DateTime.now)();

  PlayKitTypeInData get _data =>
      PlayKitTypeInData.fromKit(widget.data.card.kit);

  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    _typed.addListener(_onTypedChanged);
  }

  void _onTypedChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(PlayKitTypeInView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final PlayKitTypeInData data = _data;
    final PlayKitTypeInData previous = PlayKitTypeInData.fromKit(
      oldWidget.data.card.kit,
    );
    // 真源 observer('show, attempts, passed'):投影一变就回 intro、清空、
    // 重数 attempts —— 打对锁死,打完这一次服务端没认就等下一把。
    if (data.attempts != previous.attempts || data.passed != previous.passed) {
      _resetToIntro();
    }
  }

  @override
  void dispose() {
    _countInTimer?.cancel();
    _runTicker?.cancel();
    _typed.dispose();
    super.dispose();
  }

  void _resetToIntro() {
    _countInTimer?.cancel();
    _runTicker?.cancel();
    if (!mounted) return;
    setState(() {
      _phase = PlayKitTypeInPhase.intro;
      _typed.clear();
      _startedAt = null;
      _leftSeconds = _data.seconds;
    });
  }

  /// 「开始」→(数 3-2-1)→ 真正开跑(与停表同一条路)。
  void _requestStart() {
    final PlayKitTypeInData data = _data;
    if (data.passed || !widget.data.enabled || widget.data.acting) return;
    if (_reduced || !widget.countIn) {
      _run();
      return;
    }
    setState(() {
      _phase = PlayKitTypeInPhase.countIn;
      _countInFrom = 3;
    });
    _countInTimer?.cancel();
    _countInTimer = Timer.periodic(kCountInTickInterval, (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final int next = _countInFrom - 1;
      if (next > 0) {
        setState(() => _countInFrom = next);
        return;
      }
      timer.cancel();
      _countInTimer = null;
      _run();
    });
  }

  void _run() {
    setState(() {
      _phase = PlayKitTypeInPhase.run;
      _startedAt = _now;
      _leftSeconds = _data.seconds;
      _typed.clear();
    });
    _runTicker?.cancel();
    if (_data.seconds > 0) {
      _runTicker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
    // 开表要报给服务端:成绩按**服务器时间**复核(设备时钟玩家改得动),
    // 不先开表,SUBMIT_TYPE_IN 会被判成「还没开始」。game 值由宿主按 kind 覆写。
    widget.data.onAction?.call(
      const PlayKitAction(label: '开始', action: kTypeInStartAction),
    );
  }

  void _tick() {
    final DateTime? startedAt = _startedAt;
    if (startedAt == null) return;
    final int seconds = _data.seconds;
    if (seconds <= 0) return;
    final int elapsed = _now.difference(startedAt).inSeconds;
    if (elapsed >= seconds) {
      // 到点收表:真源是台面 failByTime 的「时间到」判定屏。这次没交出去,
      // 服务端那边次数不涨;回 intro 可以再开一局(再来一次 = 重新开表)。
      _runTicker?.cancel();
      _runTicker = null;
      if (!mounted) return;
      setState(() {
        _phase = PlayKitTypeInPhase.timedOut;
        _leftSeconds = 0;
      });
      return;
    }
    setState(() => _leftSeconds = seconds - elapsed);
  }

  void _submit() {
    final PlayKitTypeInData data = _data;
    final String text = _typed.text.trim();
    if (data.passed || _phase != PlayKitTypeInPhase.run || text.isEmpty) return;
    if (!widget.data.enabled || widget.data.acting) return;
    playKitHaptic(context, PlayKitHaptic.medium);
    _runTicker?.cancel();
    _runTicker = null;
    final int elapsedMs = _startedAt == null
        ? 0
        : _now.difference(_startedAt!).inMilliseconds;
    widget.data.onAction?.call(
      PlayKitAction(
        label: '打完提交',
        action: kTypeInSubmitAction,
        payload: data.submitPayload(_typed.text, elapsedMs),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final PlayKitTypeInData data = _data;
    final CyPalette palette = CyPalette.of(context);
    if (_phase == PlayKitTypeInPhase.countIn) {
      // 3-2-1:整屏压一层、只剩一个数字(真源 `cy-play-countin` 同一条)。
      return Semantics(
        liveRegion: true,
        label: '$_countInFrom 秒后开始',
        child: ExcludeSemantics(
          child: Center(
            child: PlayKitBigFigure(
              text: '$_countInFrom',
              size: 96,
              color: palette.textPrimary,
            ),
          ),
        ),
      );
    }
    final bool timedOut = _phase == PlayKitTypeInPhase.timedOut;
    return PlayKitQuizStage(
      data: widget.data,
      title: data.title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (data.attemptLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: CyTokens.space2),
              child: Text(
                data.attemptLabel,
                style: TextStyle(
                  fontSize: CyTokens.typeCaption,
                  color: palette.textTertiary,
                ),
              ),
            ),
          // 目标文本是明牌 —— 这玩法考的是手速不是猜谜。.ti__target:soft 底块
          // space3 内边距 + radius-lg,section-title 18pt w700 lh1.5。
          Container(
            padding: const EdgeInsets.all(CyTokens.space3),
            decoration: BoxDecoration(
              color: palette.bgSurfaceSubtle,
              borderRadius: BorderRadius.circular(CyTokens.radiusLg),
            ),
            child: Text(
              data.target,
              style: TextStyle(
                fontSize: CyTokens.typeSectionTitle,
                fontWeight: FontWeight.w700,
                height: 1.5,
                color: palette.textPrimary,
              ),
            ),
          ),
          if (data.caseSensitive)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space1),
              child: Text(
                '分大小写',
                style: TextStyle(
                  fontSize: CyTokens.typeCaption,
                  color: palette.textTertiary,
                ),
              ),
            ),
          const SizedBox(height: CyTokens.space4),
          if (_phase == PlayKitTypeInPhase.intro)
            Text(
              '${data.seconds} 秒内一字不差地打完它',
              style: TextStyle(
                fontSize: CyTokens.typeBody,
                color: palette.textSecondary,
              ),
            )
          else if (timedOut)
            Text(
              '时间到 · 这一局没交出去，再来一次',
              style: TextStyle(
                fontSize: CyTokens.typeBody,
                color: palette.textSecondary,
              ),
            )
          else
            CupertinoTextField(
              key: const Key('playkit-typein-input'),
              controller: _typed,
              enabled: !data.passed && widget.data.enabled,
              autofocus: !data.passed,
              placeholder: '在这里打',
              placeholderStyle: TextStyle(color: palette.textPlaceholder),
              padding: const EdgeInsets.all(CyTokens.space3),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              style: TextStyle(
                fontSize: CyTokens.typeBody,
                color: palette.textPrimary,
              ),
              decoration: BoxDecoration(
                color: palette.inputBgEmpty,
                borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                border: Border.all(color: palette.borderSubtle),
              ),
            ),
          if (data.passed)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space3),
              child: Text(
                '一字不差',
                style: TextStyle(
                  fontSize:
                      CyTokens.typeSectionTitle, // .ti__done 真源 section-title
                  fontWeight: FontWeight.w700,
                  color: palette.statusSuccess,
                ),
              ),
            ),
        ],
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_phase == PlayKitTypeInPhase.run && data.seconds > 0)
            PlayKitQuizFootnote(text: '还剩 $_leftSeconds 秒'),
          CyNativeButton(
            key: const Key('playkit-typein-cta'),
            label: switch (_phase) {
              // 真源 wxml:passed 之后 CTA 恒「已完成」锁死 —— 回读判定那一下
              // 屏会先回 intro,别把锁定态又印成「开始」。
              PlayKitTypeInPhase.intro ||
              PlayKitTypeInPhase.timedOut => data.passed ? '已完成' : '开始',
              PlayKitTypeInPhase.run =>
                data.passed ? '已完成' : (widget.data.acting ? '提交中…' : '打完提交'),
              PlayKitTypeInPhase.countIn => '开始',
            },
            width: double.infinity,
            loading: widget.data.acting && _phase == PlayKitTypeInPhase.run,
            onPressed: switch (_phase) {
              PlayKitTypeInPhase.run =>
                data.passed ||
                        !widget.data.enabled ||
                        widget.data.acting ||
                        _typed.text.trim().isEmpty
                    ? null
                    : _submit,
              PlayKitTypeInPhase.countIn => null,
              _ =>
                data.passed || !widget.data.enabled || widget.data.acting
                    ? null
                    : _requestStart,
            },
          ),
        ],
      ),
    );
  }
}
