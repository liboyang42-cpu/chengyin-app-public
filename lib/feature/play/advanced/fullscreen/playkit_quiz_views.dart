import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/cy_palette.dart';
import '../../../../core/theme/cy_tokens.dart';
import '../../../../core/widgets/cy_image_source_sheet.dart';
import '../../../../core/widgets/cy_native_button.dart';
import '../../../../core/widgets/cy_net_image.dart';
import '../playkit_fullscreen.dart';
import 'playkit_fullscreen_parts.dart';
import '../playkit_projection.dart';
import 'playkit_quiz_data.dart';

/// 问答 / 判定族五屏的整屏组件(qa · branch · estimate · pricePair · hiddenObject)。
///
/// 真源 = 小程序 `pages/play/components/playkit-<...>/index.wxml` 的结构,
/// 视觉按 iOS 27 原生化(§7.2):选项行是系统列表行(CyCell / 发丝线),
/// 输入是 `CupertinoTextField`,滚筒是系统 `CupertinoPicker`,CTA 是 `CyNativeButton`。
///
/// ## 三条硬约束(整族共用)
/// 1. **结果一律由服务端定**:五屏都不判对错、不算走向。选项只带 id 与文案;
///    判定结果从新投影回来(卡片重建),组件不自己改判。
/// 2. **载荷换算在 [playkit_quiz_data] 里做**,组件只把玩家输入原样交过去:
///    `qa:submit → SUBMIT_QA{input|optionId}`、`branch:choose → CHOOSE{optionId}`、
///    `estimate:submit → SUBMIT_ESTIMATE{value}`、
///    `pricepair:submit → SUBMIT_PRICE_PAIR{pickId}`、
///    `hidden:submit → SUBMIT_HIDDEN_OBJECT{x,y}`(百分比 → 比例)。
/// 3. **拍照问答是两步**(先上传拿地址、再连地址提交):组件只抛
///    [kQaShootAction] 与临时路径,绝不把它塞进 `SUBMIT_QA` 一步直发。
///
/// ⚠️ 与小程序的两处有意差异(§7.2 允许,已在 PR 说明):
/// - 选项题的 CTA:小程序留了一个点了没反应的「提交」按钮(选项本身即提交);
///   App 不画死按钮,改为一行说明 —— 可点件按下去必须有事发生。
/// - 估数的滚筒:小程序手绘三条刻度道;App 用系统 `CupertinoPicker`
///   (惯性与吸附由系统给,减少自绘)。

/// 整屏台面:五屏共用的一套读法 —— 一行小字 → 题干 → 内容 → 反馈 → 底部 CTA。
class PlayKitQuizStage extends StatelessWidget {
  const PlayKitQuizStage({
    super.key,
    required this.data,
    this.eyebrow = '',
    this.title = '',
    this.lead = '',
    this.media,
    this.body,
    this.feedback,
    this.feedbackHead = '',
    this.footer,
    this.scrollable = true,
  });

  final PlayKitFullscreenContext data;
  final String eyebrow;
  final String title;
  final String lead;
  final Widget? media;
  final Widget? body;
  final String? feedback;
  final String feedbackHead;
  final Widget? footer;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final List<Widget> content = <Widget>[
      if (eyebrow.isNotEmpty)
        Text(
          eyebrow,
          style: TextStyle(
            fontSize: CyTokens.typeCaption,
            color: palette.textTertiary,
          ),
        ),
      if (title.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: CyTokens.space2),
          child: Text(
            title,
            style: TextStyle(
              fontSize: CyTokens.typePageTitle,
              fontWeight: FontWeight.w600,
              height: CyTokens.leadingTight,
              color: palette.textPrimary,
            ),
          ),
        ),
      if (lead.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: CyTokens.space2),
          child: Text(
            lead,
            style: TextStyle(
              fontSize: CyTokens.typeBody,
              height: CyTokens.leadingNormal,
              color: palette.textSecondary,
            ),
          ),
        ),
      if (media != null)
        Padding(
          padding: const EdgeInsets.only(top: CyTokens.space3),
          child: media,
        ),
      if (body != null)
        Padding(
          padding: const EdgeInsets.only(top: CyTokens.space4),
          child: body,
        ),
      if (feedback != null && feedback!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: CyTokens.space4),
          child: PlayKitQuizFeedback(head: feedbackHead, text: feedback!),
        ),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: CyTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: scrollable
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.only(top: CyTokens.space4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: content,
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.only(top: CyTokens.space4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: content,
                      ),
                    ),
            ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.only(
                  top: CyTokens.space3,
                  bottom: CyTokens.space3,
                ),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

/// 反馈块:上面一行小字说这是什么,下面才是内容(不是一行浮字)。
class PlayKitQuizFeedback extends StatelessWidget {
  const PlayKitQuizFeedback({
    super.key,
    required this.head,
    required this.text,
  });

  final String head;
  final String text;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: palette.bgSurfaceSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (head.isNotEmpty)
            Text(
              head,
              style: TextStyle(
                fontSize: CyTokens.typeCaption,
                fontWeight: FontWeight.w600,
                color: palette.textSecondary,
              ),
            ),
          if (text.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: head.isEmpty ? 0 : CyTokens.space1),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: CyTokens.typeBody,
                  height: CyTokens.leadingNormal,
                  color: palette.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 发丝行选项(qa 的选项题与 branch 共用一套读法)。
/// 小程序原文:「选项不是东西,是一行字」—— 所以行,不是圆角框。
class PlayKitQuizOptionRow extends StatelessWidget {
  const PlayKitQuizOptionRow({
    super.key,
    required this.marker,
    required this.label,
    required this.onTap,
    this.state = PlayKitQuizOptionState.idle,
  });

  final String marker;
  final String label;
  final VoidCallback? onTap;
  final PlayKitQuizOptionState state;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final (IconData? icon, Color? tone) = switch (state) {
      PlayKitQuizOptionState.idle => (null, null),
      PlayKitQuizOptionState.picked => (
        CupertinoIcons.check_mark,
        palette.textPrimary,
      ),
      PlayKitQuizOptionState.right => (
        CupertinoIcons.check_mark_circled_solid,
        palette.statusSuccess,
      ),
      PlayKitQuizOptionState.wrong => (
        CupertinoIcons.xmark_circle_fill,
        palette.statusDanger,
      ),
      PlayKitQuizOptionState.dimmed => (null, null),
    };
    final bool dimmed = state == PlayKitQuizOptionState.dimmed;
    // 状态不只靠颜色(V5):每个终态都带自己的形状,读屏里也各有一句话。
    final String stateText = switch (state) {
      PlayKitQuizOptionState.right => ',服务端判定这条是对的',
      PlayKitQuizOptionState.wrong => ',这条不对',
      PlayKitQuizOptionState.picked => ',已选',
      PlayKitQuizOptionState.dimmed || PlayKitQuizOptionState.idle => '',
    };
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: '选项 $marker:$label$stateText',
      child: ExcludeSemantics(
        child: Opacity(
          opacity: dimmed ? 0.45 : 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.borderSubtle)),
            ),
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 56),
              pressedOpacity: 0.6,
              onPressed: onTap,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  SizedBox(
                    width: CyTokens.space5,
                    child: Text(
                      marker,
                      style: TextStyle(
                        fontSize: CyTokens.typeBody,
                        fontWeight: FontWeight.w600,
                        color: palette.textTertiary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: CyTokens.space2,
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: CyTokens.typeBody,
                          height: CyTokens.leadingNormal,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  if (icon != null)
                    Padding(
                      padding: const EdgeInsets.only(left: CyTokens.space2),
                      child: Icon(icon, size: 20, color: tone),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum PlayKitQuizOptionState { idle, picked, right, wrong, dimmed }

/// 底部的第二行小字(限时 / 次数 / 说明)。
class PlayKitQuizFootnote extends StatelessWidget {
  const PlayKitQuizFootnote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: CyTokens.space3),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: CyTokens.typeCaption,
        color: CyPalette.of(context).textTertiary,
      ),
    ),
  );
}

// ── ① 问答(qa:type / pick / shot 三种模式共用一屏)────────────

class PlayKitQaView extends StatefulWidget {
  const PlayKitQaView({
    super.key,
    required this.data,
    this.photoPicker = playKitPickQaPhoto,
  });

  final PlayKitFullscreenContext data;

  /// 取照片的实现。默认弹系统来源选择;测试注入替身,不弹系统相册。
  final Future<PlayKitQaPhoto?> Function(BuildContext context) photoPicker;

  @override
  State<PlayKitQaView> createState() => _PlayKitQaViewState();
}

class _PlayKitQaViewState extends State<PlayKitQaView> {
  final TextEditingController _typed = TextEditingController();

  /// 选项题点了哪一条 —— 只是本地的「点了」标记,对错由服务端回。
  int _picked = -1;

  /// 选项题的说明行。小程序在这一档也画了一个点了没反应的「提交」按钮
  /// (选项本身即提交)—— 这里不画死按钮,改为一行说明(§7.2 有意差异)。
  String get _modeFootnote => switch (_data.mode) {
    PlayKitQaMode.type => '',
    PlayKitQaMode.pick =>
      _data.triesCap > 0
          ? '点一下你的答案。错满 ${_data.triesCap} 次这一题就结束了。'
          : '点一下你的答案。',
    PlayKitQaMode.shot => '照片要传上去才算交 —— 判定在服务端。',
  };

  PlayKitQaData get _data => PlayKitQaData.fromKit(widget.data.card.kit);

  /// 上一帧的投影 —— 只用来认「判定回来了」这一下(见 [didUpdateWidget])。
  PlayKitQaData? _lastData;

  @override
  void initState() {
    super.initState();
    _lastData = _data;
    // 输入框一变,底部那个 CTA 的可点性就跟着变 —— 不监听的话
    // 打完字按钮还是灰的(上一次 build 时输入还是空的)。
    _typed.addListener(_onTypedChanged);
  }

  void _onTypedChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(PlayKitQaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final PlayKitQaData data = _data;
    final PlayKitQaData? previous = _lastData;
    _lastData = data;
    if (previous == null) return;
    // 判定回来这一下:答**错**才清空输入框(小程序 settle(ok=false) 里那条)——
    // 留着错答案,人得先自己删一遍才能再试。答对时不清:那一格已经锁上,
    // 清了反而像「刚才那次没发出去」。
    if (!data.passed && data.feedback != previous.feedback) {
      _typed.clear();
    }
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  void _emit(String action, Map<String, Object?> payload) {
    playKitHaptic(context, PlayKitHaptic.selection);
    widget.data.onAction?.call(
      PlayKitAction(label: '', action: action, payload: payload),
    );
  }

  void _submitTyped() {
    final String input = _typed.text.trim();
    if (input.isEmpty || !widget.data.enabled || widget.data.acting) return;
    _emit(
      kQaSubmitAction,
      qaSubmitPayload(mode: PlayKitQaMode.type, input: input),
    );
  }

  void _pick(int index, PlayKitQuizOption option) {
    if (!widget.data.enabled || widget.data.acting || _data.finished) return;
    setState(() => _picked = index);
    _emit(
      kQaSubmitAction,
      qaSubmitPayload(mode: PlayKitQaMode.pick, optionId: option.id),
    );
  }

  /// 拍照:交上来的是**图片地址**,不是「我拍过了」——
  /// 所以这里只抛临时路径与大小,上传与提交由宿主的两步链处理。
  Future<void> _shoot() async {
    if (!widget.data.enabled || widget.data.acting) return;
    final PlayKitQaPhoto? result = await widget.photoPicker(context);
    if (result == null || !mounted) return;
    _emit(kQaShootAction, result.toPayload());
  }

  @override
  Widget build(BuildContext context) {
    final PlayKitQaData data = _data;
    final List<Widget> body = <Widget>[];
    switch (data.mode) {
      case PlayKitQaMode.type:
        body.add(
          CupertinoTextField(
            key: const Key('playkit-qa-input'),
            controller: _typed,
            enabled: widget.data.enabled && !data.finished,
            placeholder: '在这里作答',
            placeholderStyle: TextStyle(
              color: CyPalette.of(context).textPlaceholder,
            ),
            padding: const EdgeInsets.all(CyTokens.space3),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submitTyped(),
            style: TextStyle(
              fontSize: CyTokens.typeBody,
              color: CyPalette.of(context).textPrimary,
            ),
            decoration: BoxDecoration(
              color: CyPalette.of(context).inputBgEmpty,
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              border: Border.all(color: CyPalette.of(context).borderSubtle),
            ),
          ),
        );
      case PlayKitQaMode.pick:
        body.addAll(<Widget>[
          for (final (int index, PlayKitQuizOption option)
              in data.options.indexed)
            PlayKitQuizOptionRow(
              key: Key(
                'playkit-qa-option-${option.id.isEmpty ? index : option.id}',
              ),
              marker: PlayKitQuizOption.keyLabel(index),
              label: option.label,
              state: _optionState(data, index),
              onTap: widget.data.enabled && !data.finished
                  ? () => _pick(index, option)
                  : null,
            ),
        ]);
      case PlayKitQaMode.shot:
        // 拍照那一档中间没有可填的东西:大字(shotLead)与题干在台面上,
        // 这一屏剩下的就是底部那个「拍一张」。
        break;
    }
    return PlayKitQuizStage(
      data: widget.data,
      title: data.headline,
      lead: data.mode == PlayKitQaMode.shot ? '' : data.lead,
      media: data.imageUrl.isEmpty
          ? null
          : ClipRRect(
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              child: CyNetImage(
                data.imageUrl,
                height: 180,
                width: double.infinity,
              ),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: body,
      ),
      feedback: data.feedback.isEmpty ? null : data.feedback,
      feedbackHead: data.finished ? (data.passed ? '答对了' : '这一关结束了') : '再想想',
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (data.mode == PlayKitQaMode.pick)
            PlayKitQuizFootnote(text: _modeFootnote)
          else
            CyNativeButton(
              key: const Key('playkit-qa-cta'),
              label: _ctaLabel(data),
              width: double.infinity,
              loading: widget.data.acting,
              onPressed: _ctaEnabled(data)
                  ? (data.mode == PlayKitQaMode.shot
                        ? () => unawaited(_shoot())
                        : _submitTyped)
                  : null,
            ),
        ],
      ),
    );
  }

  PlayKitQuizOptionState _optionState(PlayKitQaData data, int index) {
    if (!data.finished && _picked < 0) return PlayKitQuizOptionState.idle;
    // 服务端没给对错位之前,只画「你选了哪条」;判定回来之后再画对错。
    if (!data.finished) {
      return index == _picked
          ? PlayKitQuizOptionState.picked
          : PlayKitQuizOptionState.idle;
    }
    if (index == _picked) {
      return data.passed
          ? PlayKitQuizOptionState.right
          : PlayKitQuizOptionState.wrong;
    }
    return PlayKitQuizOptionState.dimmed;
  }

  bool _ctaEnabled(PlayKitQaData data) {
    if (!widget.data.enabled || widget.data.acting || data.finished) {
      return false;
    }
    if (data.mode == PlayKitQaMode.type) return _typed.text.trim().isNotEmpty;
    return true;
  }

  String _ctaLabel(PlayKitQaData data) {
    // 文案逐字照小程序:答对 →「继续」;答错还有次数 →「再试一次」;
    // 次数用完 → 保留原按钮文案(它已经锁上了)。选项档不画按钮,见 _modeFootnote。
    if (data.finished) {
      return data.passed
          ? '继续'
          : (data.mode == PlayKitQaMode.shot ? '拍一张' : '提交');
    }
    if (data.feedback.isNotEmpty) return '再试一次';
    return data.mode == PlayKitQaMode.shot ? '拍一张' : '提交';
  }
}

/// 拍照问答的取图结果:临时路径 + 大小(拿不到大小按未知处理,不伪造)。
///
/// ⚠️ 这只是**出了这台手机就不存在**的临时路径。真正的提交是两步:宿主先把
/// 照片传上去拿到地址,再连地址一起提交(小程序 `_submitQaPhoto` 同一条)。
@immutable
class PlayKitQaPhoto {
  const PlayKitQaPhoto({required this.path, this.size});

  final String path;
  final int? size;

  /// 抛给宿主的那一份(对齐小程序 `shoot` 事件的 detail)。
  Map<String, Object?> toPayload() => <String, Object?>{
    'tempFilePath': path,
    if (size != null) 'size': size,
  };
}

/// 取一张照片(相机 / 相册)。返回 null = 用户取消。
///
/// 走仓内共用的来源选择(系统 action sheet),与发布/俱乐部/游玩拍照同一条 ——
/// 不自己弹一套「拍照 / 相册」。
Future<PlayKitQaPhoto?> playKitPickQaPhoto(BuildContext context) async {
  final CyImagePickSource? source = await cyChooseImageSource(context);
  if (source == null || !context.mounted) return null;
  final XFile? file = await ImagePicker().pickImage(
    source: source == CyImagePickSource.camera
        ? ImageSource.camera
        : ImageSource.gallery,
  );
  if (file == null || !context.mounted) return null;
  int? size;
  try {
    size = await file.length();
  } catch (_) {
    // 拿不到大小按未知处理 —— 超限由服务端拦截,不伪造一个数。
    size = null;
  }
  return PlayKitQaPhoto(path: file.path, size: size);
}

// ── ② 分支剧情(branch)───────────────────────────────────────

class PlayKitBranchView extends StatefulWidget {
  const PlayKitBranchView({super.key, required this.data});

  final PlayKitFullscreenContext data;

  @override
  State<PlayKitBranchView> createState() => _PlayKitBranchViewState();
}

class _PlayKitBranchViewState extends State<PlayKitBranchView> {
  /// 选中就锁住,等服务端给下一步 —— 不锁的话手快的人能连点两条,
  /// 而第二条会带着上一步的 id 发出去(服务端那边是「当前步骤没有这个选项」)。
  int _picked = -1;

  PlayKitBranchData get _data =>
      PlayKitBranchData.fromKit(widget.data.card.kit);

  @override
  Widget build(BuildContext context) {
    final PlayKitBranchData data = _data;
    return PlayKitQuizStage(
      data: widget.data,
      title: data.title,
      lead: data.body,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (!data.ended)
            for (final (int index, PlayKitQuizOption option)
                in data.options.indexed)
              PlayKitQuizOptionRow(
                key: Key(
                  'playkit-branch-option-${option.id.isEmpty ? index : option.id}',
                ),
                marker: '${index + 1}',
                label: option.label,
                // 不判对错,所以只有「选了」与「没选」两态。
                state: _picked == index
                    ? PlayKitQuizOptionState.picked
                    : PlayKitQuizOptionState.idle,
                onTap: widget.data.enabled && _picked < 0
                    ? () {
                        setState(() => _picked = index);
                        playKitHaptic(context, PlayKitHaptic.selection);
                        widget.data.onAction?.call(
                          PlayKitAction(
                            label: option.label,
                            action: kBranchChooseAction,
                            payload: branchChoosePayload(option.id),
                          ),
                        );
                      }
                    : null,
              ),
        ],
      ),
      footer: data.ended
          // 走到终点:小程序这一步只有「结局」两个字(正文本就在上面)。
          ? const PlayKitQuizFootnote(text: '结局')
          : null,
    );
  }
}

// ── ③ 估数(estimate)─────────────────────────────────────────

class PlayKitEstimateView extends StatefulWidget {
  const PlayKitEstimateView({super.key, required this.data});

  final PlayKitFullscreenContext data;

  @override
  State<PlayKitEstimateView> createState() => _PlayKitEstimateViewState();
}

class _PlayKitEstimateViewState extends State<PlayKitEstimateView> {
  List<num> _ticks = const <num>[];
  FixedExtentScrollController? _controller;
  int _index = 0;

  PlayKitEstimateData get _data =>
      PlayKitEstimateData.fromKit(widget.data.card.kit);

  void _ensureTicks(PlayKitEstimateData data) {
    if (_controller != null) return;
    _ticks = data.ticks;
    _index = estimateInitialIndex(_ticks);
    _controller = FixedExtentScrollController(initialItem: _index);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PlayKitEstimateData data = _data;
    _ensureTicks(data);
    final CyPalette palette = CyPalette.of(context);
    final bool locked = data.submitted;
    return PlayKitQuizStage(
      data: widget.data,
      title: data.title,
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 滚筒:屏上只留三个数(中间实,上下两个是邻数 —— 真源特意纠正过:
          // 字形一个都不翻,靠缩 8%/发虚/淡到 .34 说「离得远」),手势交给系统。
          SizedBox(
            height: 216,
            child: Semantics(
              label: '${data.title},上下滑动选一个数',
              child: CupertinoPicker.builder(
                key: const Key('playkit-estimate-picker'),
                scrollController: _controller,
                itemExtent: 44,
                useMagnifier: true,
                magnification: 1.12,
                // 真源滚筒没有 Flutter 默认那条选中灰带:中间靠「实/淡」分层
                // (`.es__lane--mid` vs 上下 .34 淡),灰带反而把那条读成表格行。
                selectionOverlay: const SizedBox.shrink(),
                // 锁了也照转:真源禁的是「提交」那颗钮(g-btn--disabled),
                // 不是滚动手势 —— 押完还要看得见数、转得回去核对。
                // 每落一格一记轻触感(真源 onScroll 的 motion.haptic light)。
                onSelectedItemChanged: (int index) {
                  playKitHaptic(context, PlayKitHaptic.light);
                  setState(() => _index = index);
                },
                childCount: _ticks.length,
                itemBuilder: (BuildContext context, int index) => Center(
                  child: Text(
                    estimateNumberText(_ticks[index]),
                    style: TextStyle(
                      fontSize: CyTokens.typePageTitle,
                      fontWeight: index == _index
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: index == _index
                          ? palette.textPrimary
                          : palette.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (data.unit.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space2),
              child: Text(
                data.unit,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: CyTokens.typeBody,
                  color: palette.textSecondary,
                ),
              ),
            ),
        ],
      ),
      feedback: data.feedback.isEmpty ? null : data.feedback,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CyNativeButton(
            key: const Key('playkit-estimate-submit'),
            label: locked ? '这一关结束了' : '就这个数',
            width: double.infinity,
            loading: widget.data.acting,
            onPressed: locked || !widget.data.enabled || widget.data.acting
                ? null
                : () {
                    final num guess = _ticks.isEmpty ? 0 : _ticks[_index];
                    playKitHaptic(context, PlayKitHaptic.medium);
                    widget.data.onAction?.call(
                      PlayKitAction(
                        label: '就这个数',
                        action: kEstimateSubmitAction,
                        payload: estimateSubmitPayload(guess),
                      ),
                    );
                  },
          ),
          // 揭晓时间不下发(服务端投影明确剥掉 reveal),所以这一屏不承诺何时揭晓。
          //
          // 次数:小程序把 `maxAttempts` 喂给舞台、在页眉画「还能错」的点;
          // 这里换成一行说明(§7.2:同样的信息,iOS 原生化的呈现)。
          if (data.maxTries > 0 && !locked)
            PlayKitQuizFootnote(text: '可以错 ${data.maxTries} 次'),
        ],
      ),
    );
  }
}

// ── ④ 猜图(pricePair)────────────────────────────────────────

class PlayKitPricePairView extends StatefulWidget {
  const PlayKitPricePairView({super.key, required this.data});

  final PlayKitFullscreenContext data;

  @override
  State<PlayKitPricePairView> createState() => _PlayKitPricePairViewState();
}

class _PlayKitPricePairViewState extends State<PlayKitPricePairView> {
  /// 点过哪一张 —— 本地只记「点过」,对错由服务端回。
  final Set<String> _pickedIds = <String>{};

  /// 最近点的那一张:判定回来时只有它带对错角标(其余点过的压暗)。
  String? _lastPickedId;

  PlayKitPricePairData get _data =>
      PlayKitPricePairData.fromKit(widget.data.card.kit);

  @override
  Widget build(BuildContext context) {
    final PlayKitPricePairData data = _data;
    return PlayKitQuizStage(
      data: widget.data,
      title: data.title,
      body: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: CyTokens.space3,
        crossAxisSpacing: CyTokens.space3,
        childAspectRatio: 0.78,
        children: <Widget>[
          for (final PlayKitPricePairItem item in data.items)
            _PricePairPoster(
              key: Key('playkit-pricepair-item-${item.id}'),
              item: item,
              state: _posterState(data, item),
              revealed: data.finished,
              onTap:
                  widget.data.enabled &&
                      !data.finished &&
                      !_pickedIds.contains(item.id)
                  ? () {
                      setState(() {
                        _pickedIds.add(item.id);
                        _lastPickedId = item.id;
                      });
                      playKitHaptic(context, PlayKitHaptic.selection);
                      widget.data.onAction?.call(
                        PlayKitAction(
                          label: item.name,
                          action: kPricePairSubmitAction,
                          payload: pricePairSubmitPayload(item.id),
                        ),
                      );
                    }
                  : null,
            ),
        ],
      ),
      feedback: data.feedback.isEmpty ? null : data.feedback,
      footer: data.attempts > 0 && !data.finished && data.maxTries > 0
          ? PlayKitQuizFootnote(text: '还能试 ${data.maxTries - data.attempts} 次。')
          : null,
    );
  }

  PlayKitQuizOptionState _posterState(
    PlayKitPricePairData data,
    PlayKitPricePairItem item,
  ) {
    final bool picked = _pickedIds.contains(item.id);
    if (!data.finished) {
      return picked
          ? PlayKitQuizOptionState.picked
          : PlayKitQuizOptionState.idle;
    }
    // 判定回来:只有最后点的那张带对错角标(对错由服务端给),其余压暗。
    if (item.id != _lastPickedId) return PlayKitQuizOptionState.dimmed;
    return data.passed
        ? PlayKitQuizOptionState.right
        : PlayKitQuizOptionState.wrong;
  }
}

class _PricePairPoster extends StatelessWidget {
  const _PricePairPoster({
    super.key,
    required this.item,
    required this.state,
    required this.revealed,
    this.onTap,
  });

  final PlayKitPricePairItem item;
  final PlayKitQuizOptionState state;
  final bool revealed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final String mark = switch (state) {
      PlayKitQuizOptionState.right => '就是它',
      PlayKitQuizOptionState.wrong => '不是',
      _ => '',
    };
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: mark.isEmpty ? item.name : '${item.name},$mark',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                pressedOpacity: 0.7,
                onPressed: onTap,
                child: Opacity(
                  opacity: state == PlayKitQuizOptionState.dimmed ? 0.45 : 1,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                        child: item.imageUrl.isEmpty
                            ? ColoredBox(
                                color: palette.bgSurfaceSubtle,
                                child: Center(
                                  child: Icon(
                                    CupertinoIcons.photo,
                                    size: 28,
                                    color: palette.textTertiary,
                                  ),
                                ),
                              )
                            : CyNetImage(item.imageUrl, fit: BoxFit.cover),
                      ),
                      if (mark.isNotEmpty)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: palette.bgSurfaceStrong,
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(CyTokens.radiusMd),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: CyTokens.space2,
                                vertical: CyTokens.space1,
                              ),
                              child: Row(
                                children: <Widget>[
                                  Icon(
                                    state == PlayKitQuizOptionState.right
                                        ? CupertinoIcons
                                              .check_mark_circled_solid
                                        : CupertinoIcons.xmark_circle_fill,
                                    size: 16,
                                    color: state == PlayKitQuizOptionState.right
                                        ? palette.statusSuccess
                                        : palette.statusDanger,
                                  ),
                                  const SizedBox(width: CyTokens.space1),
                                  Text(
                                    mark,
                                    style: TextStyle(
                                      fontSize: CyTokens.typeCaption,
                                      color: palette.textPrimary,
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
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space2),
              child: Text(
                item.name,
                style: TextStyle(
                  fontSize: CyTokens.typeBody,
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (revealed && item.note.isNotEmpty)
              Text(
                item.note,
                style: TextStyle(
                  fontSize: CyTokens.typeCaption,
                  color: palette.textTertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── ⑤ 找东西(hiddenObject)───────────────────────────────────

class PlayKitHiddenView extends StatefulWidget {
  const PlayKitHiddenView({super.key, required this.data});

  final PlayKitFullscreenContext data;

  @override
  State<PlayKitHiddenView> createState() => _PlayKitHiddenViewState();
}

class _PlayKitHiddenViewState extends State<PlayKitHiddenView> {
  /// 命中过的点(本地只记「服务端确认过」的那些)。
  final List<PlayKitScenePercent> _hits = <PlayKitScenePercent>[];
  PlayKitScenePercent? _pending;
  PlayKitScenePercent? _miss;
  Timer? _missTimer;
  int _lastFound = 0;

  // 按下的那一下先给 .94 的回应(真源 `hover-class="hd__scene--press"`),
  // 报点等抬手 —— 真源 bindtap 是抬手发,按下发会把「点一下」提前一个来回。
  bool _scenePressed = false;
  Offset? _pressAt;

  PlayKitHiddenData get _data =>
      PlayKitHiddenData.fromKit(widget.data.card.kit);

  @override
  void initState() {
    super.initState();
    _lastFound = _data.foundCount;
  }

  @override
  void didUpdateWidget(PlayKitHiddenView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final int found = _data.foundCount;
    if (found > _lastFound) {
      // 服务端确认了一个新命中:把刚才那个点留在图上。
      if (_pending != null) _hits.add(_pending!);
      _pending = null;
      _clearMiss();
    } else if (_pending != null) {
      // 提交过了但服务端没认:那一圈涟漪画给玩家看,然后自己散掉
      // (小程序 340ms ≈ CyMotion.slow)—— 它是这一下的反馈,不是留在图上的标记。
      _armMiss(_pending!);
      _pending = null;
    }
    _lastFound = found;
  }

  void _armMiss(PlayKitScenePercent point) {
    _missTimer?.cancel();
    _miss = point;
    _missTimer = Timer(CyMotion.slow, () {
      if (mounted) setState(() => _miss = null);
    });
  }

  void _clearMiss() {
    _missTimer?.cancel();
    _missTimer = null;
    _miss = null;
  }

  @override
  void dispose() {
    _missTimer?.cancel();
    super.dispose();
  }

  void _onTap(Offset local, Size size) {
    if (!widget.data.enabled || widget.data.acting || _data.allFound) return;
    final PlayKitScenePercent? point = percentInScene(local, size);
    if (point == null) {
      // 量不到图的位置(或点在图外)时这一下不算 —— 抖一下说明「收到了,但不算」,
      // 而不是什么都不发生。越界的点不夹回 100 再发。
      playKitHaptic(context, PlayKitHaptic.light);
      setState(_clearMiss);
      return;
    }
    _pending = point;
    playKitHaptic(context, PlayKitHaptic.selection);
    widget.data.onAction?.call(
      PlayKitAction(
        label: '找一个',
        action: kHiddenSubmitAction,
        payload: hiddenSubmitPayload(point.x, point.y),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final PlayKitHiddenData data = _data;
    final CyPalette palette = CyPalette.of(context);
    final int remaining = data.total - data.foundCount;
    return PlayKitQuizStage(
      data: widget.data,
      title: data.title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AspectRatio(
            key: const Key('playkit-hidden-scene'),
            aspectRatio: 3 / 4,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final Size size = constraints.biggest;
                final bool canTap =
                    widget.data.enabled &&
                    !widget.data.acting &&
                    !data.allFound;
                return Semantics(
                  button: canTap,
                  // 非视觉替代说明:这一屏的全部内容是一张图,读屏读不出「东西藏哪」,
                  // 所以把「要找什么、还剩几个、该怎么办」说清楚(与 stepsA11y 同一口径)。
                  label:
                      '找东西:在图上点你觉得藏着东西的地方。'
                      '${data.targets.isEmpty ? '' : '要找的是 ${data.targets.map((PlayKitHiddenTarget t) => t.label).join('、')}。'}'
                      '共 ${data.total} 个,还剩 $remaining 个没找到。'
                      '看不见图时请同伴描述大致方位,或直接说一声由同伴代点。',
                  child: Opacity(
                    opacity: _scenePressed ? 0.94 : 1, // 真源 .hd__scene--press
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: canTap
                          ? (TapDownDetails details) {
                              _pressAt = details.localPosition;
                              setState(() => _scenePressed = true);
                            }
                          : null,
                      onTapCancel: canTap
                          ? () => setState(() => _scenePressed = false)
                          : null,
                      onTap: canTap
                          ? () {
                              setState(() => _scenePressed = false);
                              final Offset? at = _pressAt;
                              _pressAt = null;
                              if (at != null) _onTap(at, size);
                            }
                          : null,
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              CyTokens
                                  .radiusXl, // 真源 .hd__scene 36rpx=18pt → 走 iOS 梯级
                            ),
                            child: data.imageUrl.isEmpty
                                ? ColoredBox(
                                    color: palette.bgSurfaceSubtle,
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          // 「这儿有一张图」的画框(真源 `.hd__ph`:
                                          // 相框 + 太阳 + 山丘,不是假装某张图)。
                                          _ScenePlaceholderIcon(
                                            color: palette.textTertiary,
                                          ),
                                          const SizedBox(
                                            height: CyTokens.space3,
                                          ),
                                          Text(
                                            '这里会是你上传的那张图',
                                            style: TextStyle(
                                              color: palette.textTertiary,
                                              fontSize: CyTokens.typeLabel,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : CyNetImage(data.imageUrl, fit: BoxFit.cover),
                          ),
                          for (final (int index, PlayKitScenePercent hit)
                              in _hits.indexed)
                            _SceneDot(
                              key: Key('playkit-hidden-hit-$index'),
                              point: hit,
                              sceneSize: size,
                              tone: palette.statusSuccess,
                            ),
                          if (_miss case final PlayKitScenePercent miss)
                            _SceneDot(
                              key: const Key('playkit-hidden-miss'),
                              point: miss,
                              sceneSize: size,
                              tone: palette.statusDanger,
                              hollow: true,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space3),
            child: Wrap(
              spacing: CyTokens.space2,
              runSpacing: CyTokens.space2,
              children: <Widget>[
                for (final PlayKitHiddenTarget target in data.targets)
                  _TargetChip(
                    key: Key('playkit-hidden-target-${target.id}'),
                    target: target,
                  ),
              ],
            ),
          ),
          PlayKitQuizFootnote(text: '${data.foundCount} / ${data.total}'),
          PlayKitQuizFootnote(text: '点一下你觉得藏着的地方。'),
        ],
      ),
      feedback: data.feedback.isEmpty ? null : data.feedback,
      // 找齐了那句「全找到了」是小程序台面的通关语;没找齐时不另加判决式小字。
      feedbackHead: data.allFound ? '全找到了' : '',
    );
  }
}

/// 「这儿有一张图」的画框:相框描边 + 一颗太阳 + 一道山丘。
/// 真源 `.hd__ph-frame/--sun/--hill` 是 160×128rpx 的框、30rpx 的日、
/// 70rpx 的山,同一色 28% 白。这里按同比例缩到 60×48,不画假照片。
class _ScenePlaceholderIcon extends StatelessWidget {
  const _ScenePlaceholderIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      height: 48,
      child: Stack(
        clipBehavior: Clip.antiAlias,
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 1.5),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          Positioned(
            left: 10,
            top: 9,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          Positioned(
            left: -4,
            right: -4,
            bottom: -11,
            child: Container(
              height: 26,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.elliptical(40, 26),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SceneDot extends StatelessWidget {
  const _SceneDot({
    super.key,
    required this.point,
    required this.sceneSize,
    required this.tone,
    this.hollow = false,
  });

  final PlayKitScenePercent point;

  /// 与命中判定用**同一个盒子**。拿屏幕宽 / 写死高度换算的话,
  /// 点在图上哪儿、圈就画到别处去了(图不是全屏宽、也不是那个高度)。
  final Size sceneSize;
  final Color tone;
  final bool hollow;

  @override
  Widget build(BuildContext context) {
    // 几何逐值照真源:命中 = 14pt 实心圆点(无边)+ 一圈**一次性**扩出去的
    // 64pt 环(`.hd__dot::after`,scale .6→1 同时淡出,.18s)——「只留一个点的话,
    // 点中和没点中在屏上的差别只有颜色,手指还压着看不见」。
    // 没中 = 44pt 描边 2pt 的空环,.12s 扩到 1.4 倍并散掉(`.hd__miss`)。
    // 减动效下真源把动画一律 opacity:0 —— 那等于把反馈弄瞎(违 A2),App 的口径:
    // 命中=静态实心点、没中=静态环待到 340ms 清除,反馈不独挂在动效上。
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final double x = point.x / 100 * sceneSize.width;
    final double y = point.y / 100 * sceneSize.height;
    if (hollow) {
      return Positioned(
        left: x - 22,
        top: y - 22,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: reduceMotion
              ? Duration.zero
              : CyMotion.fast, // 真源 hd-miss .12s → iOS 动效档
          curve: Curves.easeOut,
          builder: (BuildContext context, double t, Widget? child) {
            if (reduceMotion) return Opacity(opacity: 0.9, child: child);
            return Opacity(
              opacity: (0.9 * (1 - t)).clamp(0.0, 1.0),
              child: Transform.scale(scale: 0.5 + 0.9 * t, child: child),
            );
          },
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: tone, width: 2),
            ),
          ),
        ),
      );
    }
    return Positioned(
      left: x - 32,
      top: y - 32,
      child: SizedBox(
        width: 64,
        height: 64,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: reduceMotion
              ? Duration.zero
              : CyMotion.fast, // 真源 hd-dot .18s
          curve: const Cubic(0.2, 0.8, 0.2, 1), // 真源 cubic-bezier(.2,.8,.2,1)
          builder: (BuildContext context, double t, Widget? child) {
            return Stack(
              alignment: Alignment.center,
              children: <Widget>[
                if (!reduceMotion)
                  Opacity(
                    opacity: (1 - t).clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 0.6 + 0.4 * t,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: tone, width: 2),
                        ),
                      ),
                    ),
                  ),
                Transform.scale(scale: 0.4 + 0.6 * t, child: child),
              ],
            );
          },
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

class _TargetChip extends StatelessWidget {
  const _TargetChip({super.key, required this.target});

  final PlayKitHiddenTarget target;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Semantics(
      label: '${target.label}${target.found ? ',已找到' : ',还没找到'}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 11,
            vertical: 7,
          ), // 真源 .hd__chip 14/22rpx
          decoration: BoxDecoration(
            color: target.found
                ? palette.bgSurfaceStrong
                : palette.bgSurfaceSubtle,
            // 真源注释:圆角 26rpx=13pt「比胶囊方一点,它是标签不是按钮」——
            // 用 radiusPill 会把它读成一颗可点的胶囊。
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: target.found
                  ? palette.statusSuccess
                  : palette.borderSubtle,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (target.found)
                Padding(
                  padding: const EdgeInsets.only(right: CyTokens.space1),
                  child: Icon(
                    CupertinoIcons.check_mark,
                    size: 14,
                    color: palette.statusSuccess,
                  ),
                ),
              Text(
                target.label,
                style: TextStyle(
                  fontSize: CyTokens.typeLabel, // 真源 24rpx
                  fontWeight: FontWeight.w500,
                  color: target.found
                      ? palette.textPrimary
                      : palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
