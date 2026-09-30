import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../data/api/template_api.dart';
import '../../data/models/category.dart';
import '../../data/models/template_draft.dart';
import '../../data/models/validation_method_labels.dart';
import 'advanced_game_configurator.dart';
import 'advanced_game_configurator_view.dart';
import 'template_dict.dart';

final _templateCategoriesProvider = FutureProvider.autoDispose<List<Category>>(
  (ref) => ref.watch(categoryApiProvider).list(type: '4'),
);

const _venues = <String>['景区', '公园绿地', '商圈街区', '古镇老街', '博物馆', '校园', '室内场馆'];

// ★ 文案取自全 App 共用的核验方式码表;这里只列**可创作**的 0–5,
//   不把 6/7 放进来 —— 那会顺手开放本批没要的创作能力。
final Map<int, String> _methods = <int, String>{
  for (final int code in const <int>[1, 3, 2, 4, 5, 0])
    code: validationMethodLabel(code)!,
};

class TemplateEditPage extends ConsumerStatefulWidget {
  const TemplateEditPage({super.key, this.initialTitle = '', this.seed});

  final String initialTitle;

  /// 从模板库「套用」过来时的初值。
  ///
  /// ★★ 它必须带上 `originalTemplateId` —— 后端在发布时按这个字段给来源库模板
  ///   `use_num +1`(TemplatePublishServiceImpl)。丢了它,采用数永远是 0,
  ///   而模板市场的排序就是按采用数来的,等于整个热度榜是死的。
  final TemplateDraft? seed;

  @override
  ConsumerState<TemplateEditPage> createState() => _TemplateEditPageState();
}

class _TemplateEditPageState extends ConsumerState<TemplateEditPage> {
  late TemplateDraft _draft;
  late final TextEditingController _titleController;
  late final AdvancedConfigDraft _adv;
  bool _busy = false;
  bool _preview = false;
  bool _hintEnabled = false;
  bool _couponOn = false;
  bool _textOn = false;
  bool _medalOn = false;
  final List<_StoryBeat> _beats = <_StoryBeat>[_StoryBeat()];
  final List<_ChoiceDraft> _choices = <_ChoiceDraft>[
    _ChoiceDraft(letter: 'A'),
    _ChoiceDraft(letter: 'B'),
  ];
  int _correctChoice = 0;

  @override
  void initState() {
    super.initState();
    // 套用来的草稿优先;它已经带好了标题与 originalTemplateId。
    final TemplateDraft? seed = widget.seed;
    final String initialTitle = seed?.title.isNotEmpty == true
        ? seed!.title
        : widget.initialTitle;
    _draft = seed ?? TemplateDraft(title: initialTitle);
    _titleController = TextEditingController(text: initialTitle);
    _adv = AdvancedConfigDraft.fromJson(
      _draft.advancedConfigJson,
      adopted: (_draft.originalTemplateId ?? 0) > 0,
    );
    _adv.addListener(_commitAdv);
  }

  @override
  void dispose() {
    _adv.removeListener(_commitAdv);
    _adv.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _set(TemplateDraft next) => setState(() => _draft = next);

  /// 玩法配置器改动 → 写回不可变草稿,驱动发布闸门与 payload。
  void _commitAdv() {
    setState(() {
      _draft = _draft.copyWith(
        advancedConfigJson: _adv.serialize(),
        validationMethod: _adv.validationMethod ?? _draft.validationMethod,
      );
    });
  }

  /// 发布/预览闸门:先过草稿基础字段,再挡玩法配置器校验不过的情况。
  String? get _gate {
    final String? blocker = _draft.publishBlocker;
    if (blocker != null) return blocker;
    final String err = _adv.error;
    if (err.isNotEmpty) return err;
    return null;
  }

  Future<void> _run(
    Future<void> Function(TemplateApi api) action, {
    required String okMsg,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action(ref.read(templateApiProvider));
      if (!mounted) return;
      CyNativeNotice.show(context, okMsg);
      Navigator.of(context).maybePop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<void> _pickImage(ValueChanged<String> onUploaded) async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final url = await ref.read(publishApiProvider).uploadImage(file.path);
      if (mounted) onUploaded(url);
    } catch (e) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAudio(ValueChanged<String> onUploaded) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['mp3', 'm4a', 'aac'],
    );
    final file = result?.files.singleOrNull;
    final path = file?.path;
    if (file == null || path == null) return;
    setState(() => _busy = true);
    try {
      final extension = file.name.contains('.')
          ? file.name.split('.').last.toLowerCase()
          : null;
      final url = await ref
          .read(publishApiProvider)
          .uploadFile(path, fileType: extension, fileName: file.name);
      if (mounted) onUploaded(url);
    } catch (e) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _syncStory() {
    final rows = _beats
        .where((b) => b.text.trim().isNotEmpty || b.images.isNotEmpty)
        .map(
          (b) => <String, dynamic>{
            'text': b.text,
            'tag': b.tag,
            'imgs': b.images,
          },
        )
        .toList();
    _set(_draft.copyWith(storyJson: rows.isEmpty ? null : jsonEncode(rows)));
  }

  void _syncChoices() {
    for (int i = 0; i < _choices.length; i++) {
      _choices[i].letter = String.fromCharCode(65 + i);
    }
    final media = <String, dynamic>{
      for (final choice in _choices)
        if (choice.image.isNotEmpty || choice.audio.isNotEmpty)
          choice.letter: <String, String>{
            if (choice.image.isNotEmpty) 'img': choice.image,
            if (choice.audio.isNotEmpty) 'audio': choice.audio,
          },
    };
    String? textAt(int index) =>
        index < _choices.length ? _choices[index].text : null;
    _set(
      _draft.copyWith(
        questionA: textAt(0),
        questionB: textAt(1),
        questionC: textAt(2),
        questionD: textAt(3),
        correctAnswer: _choices[_correctChoice].letter,
        questionOptionMediaJson: media.isEmpty ? null : jsonEncode(media),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_preview) return _previewPage();
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(middle: Text('创建节点玩法')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    CyTokens.pageX,
                    CyTokens.space3,
                    CyTokens.pageX,
                    112,
                  ),
                  children: <Widget>[
                    const Text(
                      '创建节点玩法',
                      // 真源 <cy-page-title title="创建节点玩法"> = --cy-font-page-title
                      // (58rpx = 29)→ 梯级最近档 Title1 28(T2);
                      // T3:强调用 bold(700),w800 属堆重。
                      style: CyType.title1,
                    ),
                    const SizedBox(height: 4),
                    const Text('完善以下内容，为路线打造可落地的现场互动方案'),
                    const SizedBox(height: 18),
                    _field(
                      '玩法名称',
                      key: const Key('template-field-title'),
                      controller: _titleController,
                      hint: '给这个节点玩法起个名字',
                      maxLength: 20,
                      onChanged: (v) => _set(_draft.copyWith(title: v)),
                    ),
                    _section('基本信息', <Widget>[
                      _field(
                        '玩法描述',
                        hint: '一句话介绍这个节点的看点',
                        maxLines: 2,
                        maxLength: 30,
                        onChanged: (v) => _set(_draft.copyWith(description: v)),
                      ),
                      _responsivePair(
                        _DictPicker(
                          label: '玩家人数',
                          dictType: 'app_template_players',
                          value: _draft.players,
                          fieldKey: const Key('template-field-players'),
                          onChanged: (v) => _set(_draft.copyWith(players: v)),
                        ),
                        _DictPicker(
                          label: '玩法时长',
                          dictType: 'app_template_duration',
                          value: _draft.duration?.toString(),
                          fieldKey: const Key('template-field-duration'),
                          onChanged: (v) => _set(
                            _draft.copyWith(duration: _durationMinutes(v)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _DictPicker(
                        label: '玩法难度',
                        dictType: 'app_template_difficulty',
                        value: _draft.difficulty,
                        onChanged: (v) => _set(_draft.copyWith(difficulty: v)),
                      ),
                      const SizedBox(height: 12),
                      _responsivePair(
                        _field(
                          '所需材料',
                          hint: '如：手机、笔',
                          onChanged: (v) =>
                              _set(_draft.copyWith(requiredMaterials: v)),
                        ),
                        _CupertinoOptionPicker<String>(
                          label: '适用场所',
                          sheetTitle: '选择适用场所',
                          value: _draft.usageLocation,
                          options: <_PickerOption<String>>[
                            for (final String venue in _venues)
                              _PickerOption<String>(value: venue, label: venue),
                          ],
                          onChanged: (v) =>
                              _set(_draft.copyWith(usageLocation: v)),
                        ),
                      ),
                      _ImageSlot(
                        label: '玩法封面',
                        url: _draft.imgUrl,
                        onPick: () => _pickImage(
                          (url) => _set(_draft.copyWith(imgUrl: url)),
                        ),
                        onClear: () => _set(_draft.copyWith(imgUrl: null)),
                      ),
                      _CategorySelector(
                        selected: _draft.activityCategoryids,
                        onChanged: (ids) => _set(
                          _draft.copyWith(
                            activityCategoryids: ids.join(','),
                            categoryId: ids.isEmpty ? null : ids.first,
                          ),
                        ),
                      ),
                    ]),
                    _section('玩法规则', <Widget>[
                      _field(
                        '玩法规则',
                        key: const Key('template-field-rules'),
                        hint: '向玩家说明这一关怎么玩、注意事项等',
                        maxLines: 4,
                        onChanged: (v) =>
                            _set(_draft.copyWith(ruleInstructions: v)),
                      ),
                    ]),
                    // 真源 `.cg-modsec-tit`(32rpx = 16, w800)→ 区块标题走共用件
                    // CySectionTitle(Title3 20 + Semibold + Semantics header,
                    // 手册 §6 P2 / L2 / T3)。
                    const CySectionTitle('玩法模块'),
                    const Text('玩法的核心 · 决定玩家如何完成关卡、获得什么奖励'),
                    const SizedBox(height: 12),
                    if (_draft.finishEnabled) _finishModule(),
                    if (_draft.rewardEnabled) _rewardModule(),
                    if (_draft.storyEnabled) _storyModule(),
                    if (_draft.voiceEnabled) _voiceModule(),
                    _addModules(),
                    // 真源的「完成方式」本质是一个玩法槽位(gameKey 单选 + 段配置)。
                    // 编辑页保留了历史 validationMethod 0–5 的简化选择器,故这里把完整
                    // 玩法配置器单列一张卡放在模块底部,不与旧选择器抢同一个槽位。
                    if (_draft.finishEnabled)
                      _section('玩法配置', <Widget>[
                        AdvancedGameConfigurator(draft: _adv),
                      ]),
                    _CupertinoSwitchRow(
                      key: const Key('template-sync-switch-row'),
                      title: const Text('同步到模板库'),
                      value: _draft.isSync == 1,
                      onChanged: (v) =>
                          _set(_draft.copyWith(isSync: v ? 1 : 0)),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.all(16),
                child: CyNativeButton(
                  key: const Key('template-preview'),
                  onPressed: (_busy || _gate != null)
                      ? null
                      : () => setState(() => _preview = true),
                  label: _gate ?? '查看预览',
                  loading: _busy,
                  width: double.infinity,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _finishModule() => _module(
    '完成方式',
    '玩家用什么方式通过这一关',
    onRemove: () => _set(_draft.copyWith(finishEnabled: false)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          key: const Key('template-validation-method'),
          spacing: 8,
          runSpacing: 8,
          children: _methods.entries
              .map(
                (e) => _TemplateChoice(
                  label: e.value,
                  selected: _draft.validationMethod == e.key,
                  onPressed: () =>
                      _set(_draft.copyWith(validationMethod: e.key)),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        if (_draft.validationMethod == 1) ...<Widget>[
          _field(
            '问题',
            onChanged: (v) => _set(_draft.copyWith(questionName: v)),
          ),
          _field(
            '正确答案',
            hint: '可填多个，用、分隔',
            onChanged: (v) => _set(_draft.copyWith(questionAnswer: v)),
          ),
          _questionMedia(),
        ],
        if (_draft.validationMethod == 3) _choiceEditor(),
        if (_draft.validationMethod == 2) ...<Widget>[
          _field(
            '拍照要求',
            maxLines: 2,
            onChanged: (v) => _set(_draft.copyWith(photoRequireDesc: v)),
          ),
          _CupertinoSwitchRow(
            title: const Text('需人工审核照片'),
            contentPadding: EdgeInsets.zero,
            value: _draft.photoReview == 1,
            onChanged: (v) => _set(_draft.copyWith(photoReview: v ? 1 : 0)),
          ),
        ],
        if (_draft.validationMethod == 4) const Text('二维码内容在路线层绑定'),
        if (_draft.validationMethod == 5) const Text('GPS 坐标在路线层绑定'),
        if (_draft.validationMethod == 0) const Text('玩家到达后点击「完成」即可通过'),
        if (<int>{1, 3, 5}.contains(_draft.validationMethod)) ...<Widget>[
          _CupertinoSwitchRow(
            title: const Text('提示（选填）'),
            contentPadding: EdgeInsets.zero,
            value: _hintEnabled,
            onChanged: (v) {
              setState(() => _hintEnabled = v);
              if (!v) {
                _set(
                  _draft.copyWith(hint1: null, hint2: null, answerReveal: null),
                );
              }
            },
          ),
          if (_hintEnabled) ...<Widget>[
            _field('一级提示', onChanged: (v) => _set(_draft.copyWith(hint1: v))),
            _field('二级提示', onChanged: (v) => _set(_draft.copyWith(hint2: v))),
            _field(
              '兜底答案',
              onChanged: (v) => _set(_draft.copyWith(answerReveal: v)),
            ),
          ],
        ],
      ],
    ),
  );

  Widget _choiceEditor() {
    return Column(
      children: <Widget>[
        _field('问题', onChanged: (v) => _set(_draft.copyWith(questionName: v))),
        for (int i = 0; i < _choices.length; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      _CupertinoIconAction(
                        tooltip: '设为正确答案',
                        icon: Icon(
                          _correctChoice == i
                              ? CupertinoIcons.check_mark_circled_solid
                              : CupertinoIcons.circle,
                        ),
                        onPressed: () {
                          setState(() => _correctChoice = i);
                          _syncChoices();
                        },
                      ),
                      Expanded(
                        child: _field(
                          '选项 ${_choices[i].letter}',
                          onChanged: (v) {
                            _choices[i].text = v;
                            _syncChoices();
                          },
                        ),
                      ),
                      if (_choices.length > 2)
                        _CupertinoIconAction(
                          tooltip: '删除选项',
                          icon: const Icon(CupertinoIcons.delete),
                          onPressed: () {
                            setState(() {
                              _choices.removeAt(i);
                              if (_correctChoice >= _choices.length) {
                                _correctChoice = _choices.length - 1;
                              } else if (_correctChoice > i) {
                                _correctChoice--;
                              }
                            });
                            _syncChoices();
                          },
                        ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      _CupertinoInlineAction(
                        onPressed: () => _pickImage((url) {
                          _choices[i].image = url;
                          _syncChoices();
                        }),
                        icon: CupertinoIcons.photo,
                        label: _choices[i].image.isEmpty ? '＋ 图' : '图 ✓',
                      ),
                      _CupertinoInlineAction(
                        onPressed: () => _pickAudio((url) {
                          _choices[i].audio = url;
                          _syncChoices();
                        }),
                        icon: CupertinoIcons.speaker_2,
                        label: _choices[i].audio.isEmpty ? '＋ 音' : '音 ✓',
                      ),
                      if (_choices[i].image.isNotEmpty ||
                          _choices[i].audio.isNotEmpty)
                        _CupertinoInlineAction(
                          onPressed: () {
                            _choices[i].image = '';
                            _choices[i].audio = '';
                            _syncChoices();
                          },
                          label: '清除',
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (_choices.length < 4)
          _CupertinoInlineAction(
            key: const Key('template-add-choice'),
            onPressed: () {
              setState(() => _choices.add(_ChoiceDraft(letter: '')));
              _syncChoices();
            },
            icon: CupertinoIcons.add_circled,
            label: '添加选项',
          ),
        _questionMedia(),
      ],
    );
  }

  Widget _questionMedia() => Row(
    children: <Widget>[
      Expanded(
        child: _ImageSlot(
          label: '题干配图',
          url: _draft.questionImg,
          onPick: () =>
              _pickImage((url) => _set(_draft.copyWith(questionImg: url))),
          onClear: () => _set(_draft.copyWith(questionImg: null)),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _AudioSlot(
          // 已配音频:小程序上传位一旦有文件就改叫「已配音频」(真源 `publish/temp/index.wxml`)。
          label: (_draft.questionAudio ?? '').isEmpty ? '题干配音' : '已配音频',
          url: _draft.questionAudio,
          onPick: () =>
              _pickAudio((url) => _set(_draft.copyWith(questionAudio: url))),
          onClear: () => _set(_draft.copyWith(questionAudio: null)),
        ),
      ),
    ],
  );

  Widget _rewardModule() => _module(
    '完成奖励',
    '优惠券 / 文字反馈 / 勋章',
    onRemove: () => _set(_draft.copyWith(rewardEnabled: false)),
    child: Column(
      children: <Widget>[
        _CupertinoSwitchRow(
          title: const Text('优惠券'),
          value: _couponOn,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) {
            setState(() => _couponOn = v);
            if (!v) _set(_draft.copyWith(couponId: null));
          },
        ),
        if (_couponOn)
          _CouponPicker(
            value: _draft.couponId,
            onChanged: (id) => _set(_draft.copyWith(couponId: id)),
          ),
        _CupertinoSwitchRow(
          title: const Text('文字反馈'),
          value: _textOn,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) {
            setState(() => _textOn = v);
            if (!v) _set(_draft.copyWith(feedbackText: null));
          },
        ),
        if (_textOn)
          _field(
            '通关后展示的一段话',
            maxLines: 2,
            onChanged: (v) => _set(_draft.copyWith(feedbackText: v)),
          ),
        _CupertinoSwitchRow(
          title: const Text('勋章'),
          value: _medalOn,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) {
            setState(() => _medalOn = v);
            if (!v) _set(_draft.copyWith(medalImg: null, medalName: null));
          },
        ),
        if (_medalOn) ...<Widget>[
          _ImageSlot(
            label: '勋章图',
            url: _draft.medalImg,
            onPick: () =>
                _pickImage((url) => _set(_draft.copyWith(medalImg: url))),
            onClear: () => _set(_draft.copyWith(medalImg: null)),
          ),
          _field('勋章名称', onChanged: (v) => _set(_draft.copyWith(medalName: v))),
          const Text('勋章展示样式由玩家端统一渲染，当前提交接口不保存样式选择。'),
        ],
      ],
    ),
  );

  Widget _storyModule() => _module(
    '剧情故事',
    '到达时的时间流叙事 · 逐节展开',
    onRemove: () => _set(_draft.copyWith(storyEnabled: false, storyJson: null)),
    child: Column(
      children: <Widget>[
        for (int i = 0; i < _beats.length; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '时间节点 ${i + 1}',
                          // 真源 `.cg-beat-tag` = label(24rpx = 12)/600
                          // → Footnote 13 + Semibold(T2/T3)。
                          style: CyType.footnote.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_beats.length > 1)
                        _CupertinoIconAction(
                          tooltip: '删除时间节点',
                          icon: const Icon(CupertinoIcons.delete),
                          onPressed: () {
                            setState(() => _beats.removeAt(i));
                            _syncStory();
                          },
                        ),
                    ],
                  ),
                  _field(
                    '这一刻发生了什么？',
                    maxLines: 3,
                    onChanged: (v) {
                      _beats[i].text = v;
                      _syncStory();
                    },
                  ),
                  _field(
                    '时刻标签（选填）',
                    onChanged: (v) {
                      _beats[i].tag = v;
                      _syncStory();
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Text('配图(选填,最多6张)'),
                      Text('${_beats[i].images.length}/6'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: <Widget>[
                      for (final image in _beats[i].images)
                        Semantics(
                          button: true,
                          label: '删除剧情图片',
                          child: CupertinoButton(
                            minimumSize: const Size(44, 44),
                            padding: const EdgeInsets.symmetric(
                              horizontal: CyTokens.space2,
                            ),
                            color: CyPalette.of(context).bgSurfaceSubtle,
                            onPressed: () {
                              setState(() => _beats[i].images.remove(image));
                              _syncStory();
                            },
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(CupertinoIcons.photo, size: 16),
                                SizedBox(width: CyTokens.space1),
                                Icon(CupertinoIcons.xmark, size: 12),
                              ],
                            ),
                          ),
                        ),
                      if (_beats[i].images.length < 6)
                        _CupertinoInlineAction(
                          icon: CupertinoIcons.add,
                          label: '加图',
                          onPressed: () => _pickImage((url) {
                            setState(() => _beats[i].images.add(url));
                            _syncStory();
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        _CupertinoInlineAction(
          onPressed: () => setState(() => _beats.add(_StoryBeat())),
          icon: CupertinoIcons.add,
          label: '添加时间节点 · 延长时间线',
        ),
      ],
    ),
  );

  Widget _voiceModule() => _module(
    '语音讲解',
    '为这个点位配一段音频导览',
    onRemove: () => _set(
      _draft.copyWith(voiceEnabled: false, audioUrl: null, audioDuration: null),
    ),
    child: Column(
      children: <Widget>[
        _AudioSlot(
          label: '语音讲解文件',
          key: const Key('template-audio-url'),
          url: _draft.audioUrl,
          onPick: () =>
              _pickAudio((url) => _set(_draft.copyWith(audioUrl: url))),
          onClear: () => _set(_draft.copyWith(audioUrl: null)),
        ),
        _field(
          '时长（秒，可选）',
          number: true,
          onChanged: (v) =>
              _set(_draft.copyWith(audioDuration: int.tryParse(v))),
        ),
      ],
    ),
  );

  Widget _addModules() {
    final entries = <(String, VoidCallback)>[
      if (!_draft.finishEnabled)
        ('完成方式', () => _set(_draft.copyWith(finishEnabled: true))),
      if (!_draft.rewardEnabled)
        ('完成奖励', () => _set(_draft.copyWith(rewardEnabled: true))),
      if (!_draft.storyEnabled)
        ('剧情故事', () => _set(_draft.copyWith(storyEnabled: true))),
      if (!_draft.voiceEnabled)
        ('语音讲解', () => _set(_draft.copyWith(voiceEnabled: true))),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '添加模块',
              // 真源 `.cg-addmod` = body(28rpx = 14)/700
              // → Subhead 15 + Semibold(T2/T3)。
              style: CyType.subhead.copyWith(fontWeight: FontWeight.w600),
            ),
            for (final entry in entries)
              _CupertinoInlineAction(
                onPressed: entry.$2,
                icon: CupertinoIcons.add_circled,
                label: entry.$1,
              ),
          ],
        ),
      ),
    );
  }

  Widget _previewPage() => CupertinoPageScaffold(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    navigationBar: CupertinoNavigationBar(
      leading: _CupertinoIconAction(
        tooltip: '返回编辑',
        icon: const Icon(CupertinoIcons.back),
        onPressed: () => setState(() => _preview = false),
      ),
      middle: const Text('玩家视角预览'),
    ),
    child: Material(
      color: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  if ((_draft.imgUrl ?? '').isNotEmpty)
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: CyNetImage(_draft.imgUrl!, fit: BoxFit.cover),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    _draft.title,
                    // 真源 `.cg-pv-cover-tit` = --cy-font-page-title(58rpx = 29)→
                    // 梯级 Title1 28;T3 强调用 bold(700)。
                    style: CyType.title1.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(_draft.description),
                  const SizedBox(height: 20),
                  Text(_methods[_draft.validationMethod] ?? '完成方式'),
                  if ((_draft.questionName ?? '').isNotEmpty)
                    Text(_draft.questionName!),
                  if (_draft.storyEnabled)
                    const CupertinoListTile(
                      leading: Icon(CupertinoIcons.book),
                      title: Text('剧情时间流'),
                    ),
                  if (_draft.rewardEnabled)
                    const CupertinoListTile(
                      leading: Icon(CupertinoIcons.gift),
                      title: Text('完成后获得奖励'),
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: CyNativeButton(
                      key: const Key('template-save-draft'),
                      onPressed: (_busy || _draft.draftBlocker != null)
                          ? null
                          : () => _run(
                              (TemplateApi api) => api.saveDraft(_draft),
                              okMsg: '草稿已存',
                            ),
                      label: _draft.draftBlocker ?? '保存草稿',
                      role: CyNativeButtonRole.secondary,
                      loading: _busy,
                      width: double.infinity,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: CyNativeButton(
                      key: const Key('template-publish'),
                      onPressed: (_busy || _gate != null)
                          ? null
                          : () => _run(
                              (TemplateApi api) => api.publish(_draft),
                              okMsg: '已提交审核',
                            ),
                      label: _gate ?? '发布路线',
                      loading: _busy,
                      width: double.infinity,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _module(
    String title,
    String subtitle, {
    required VoidCallback onRemove,
    required Widget child,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      // 真源 `.cg-mod-tit` = card-title(32rpx = 16)/ iOS 侧行标题档
                      // Headline 17 Semibold(T2/T3)。
                      style: CyType.headline,
                    ),
                    Text(
                      subtitle,
                      // 真源 `.cg-mod-desc` = label(24rpx = 12)→ Footnote 13(T2);
                      // 原来不写字号 = 吃 Material 默认 14,不在 iOS 阶梯上。
                      style: CyType.footnote.copyWith(
                        color: CyPalette.of(context).textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _CupertinoIconAction(
                tooltip: '移除模块',
                onPressed: onRemove,
                icon: const Icon(CupertinoIcons.xmark_circle),
              ),
            ],
          ),
          // 分隔线交给系统语义色(iOS:CupertinoColors.separator 随亮度解析),
          // 不用 Material `Divider`。
          Padding(
            padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
            child: SizedBox(
              height: 1 / MediaQuery.devicePixelRatioOf(context),
              child: ColoredBox(
                color: CupertinoDynamicColor.resolve(
                  CupertinoColors.separator,
                  context,
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    ),
  );

  Widget _section(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 真源 `.cg-card-tit`(32rpx = 16, w700)→ 区块标题走共用件
          // CySectionTitle(Title3 20 + Semibold + Semantics header);T3 用 Semibold。
          CySectionTitle(title),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );

  Widget _responsivePair(Widget first, Widget second) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final bool stack =
          constraints.maxWidth < 320 ||
          MediaQuery.textScalerOf(context).scale(16) >= 24;
      if (stack) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            first,
            const SizedBox(height: CyTokens.space3),
            second,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: first),
          const SizedBox(width: 10),
          Expanded(child: second),
        ],
      );
    },
  );

  Widget _field(
    String label, {
    Key? key,
    TextEditingController? controller,
    String? hint,
    int maxLines = 1,
    int? maxLength,
    bool number = false,
    required ValueChanged<String> onChanged,
  }) => Padding(
    key: key,
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: CyType.subhead.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: CyTokens.space1),
        CupertinoTextField(
          controller: controller,
          minLines: 1,
          maxLines: maxLines,
          maxLength: maxLength,
          keyboardType: number
              ? TextInputType.number
              : maxLines > 1
              ? TextInputType.multiline
              : TextInputType.text,
          textInputAction: number
              ? TextInputAction.done
              : maxLines > 1
              ? TextInputAction.newline
              : TextInputAction.next,
          clearButtonMode: OverlayVisibilityMode.editing,
          padding: const EdgeInsets.symmetric(
            horizontal: CyTokens.space3,
            vertical: 12,
          ),
          placeholder: hint,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _StoryBeat {
  String text = '';
  String tag = '';
  final List<String> images = <String>[];
}

class _ChoiceDraft {
  _ChoiceDraft({required this.letter});
  String letter;
  String text = '';
  String image = '';
  String audio = '';
}

int? _durationMinutes(String raw) {
  final match = RegExp(r'\d+').firstMatch(raw);
  return match == null ? null : int.tryParse(match.group(0)!);
}

class _DictPicker extends ConsumerWidget {
  const _DictPicker({
    required this.label,
    required this.dictType,
    required this.value,
    required this.onChanged,
    this.fieldKey,
  });
  final String label, dictType;
  final String? value;
  final ValueChanged<String> onChanged;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options =
        ref.watch(dictProvider(dictType)).value ?? const <DictOption>[];
    return _CupertinoOptionPicker<String>(
      key: fieldKey,
      label: label,
      sheetTitle: '选择$label',
      value: options.any((DictOption option) => option.label == value)
          ? value
          : null,
      options: <_PickerOption<String>>[
        for (final DictOption option in options)
          _PickerOption<String>(value: option.label, label: option.label),
      ],
      onChanged: onChanged,
    );
  }
}

class _PickerOption<T> {
  const _PickerOption({required this.value, required this.label});

  final T value;
  final String label;
}

class _CupertinoOptionPicker<T> extends StatelessWidget {
  const _CupertinoOptionPicker({
    super.key,
    required this.label,
    required this.sheetTitle,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String sheetTitle;
  final T? value;
  final List<_PickerOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    String? selectedLabel;
    for (final _PickerOption<T> option in options) {
      if (option.value == value) {
        selectedLabel = option.label;
        break;
      }
    }
    final Color border = CupertinoDynamicColor.resolve(
      CupertinoColors.separator,
      context,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: CyType.subhead.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: CyTokens.space1),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(CyTokens.radiusSm),
          ),
          child: CupertinoButton(
            minimumSize: const Size.fromHeight(48),
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
            alignment: Alignment.centerLeft,
            onPressed: options.isEmpty ? null : () => _present(context),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    selectedLabel ?? '请选择',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    // 真源 `.cg-pick` = body(28rpx = 14)→ Subhead 15(T2)。
                    style: CyType.subhead.copyWith(
                      color: selectedLabel == null
                          ? CupertinoColors.placeholderText
                          : CupertinoColors.label,
                    ),
                  ),
                ),
                const SizedBox(width: CyTokens.space1),
                const ExcludeSemantics(
                  child: Icon(CupertinoIcons.chevron_down, size: 16),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _present(BuildContext context) async {
    final T? selected = await showCupertinoModalPopup<T>(
      context: context,
      builder: (BuildContext sheetContext) => CupertinoActionSheet(
        title: Text(sheetTitle),
        actions: <Widget>[
          for (final _PickerOption<T> option in options)
            CupertinoActionSheetAction(
              isDefaultAction: option.value == value,
              onPressed: () => Navigator.of(sheetContext).pop(option.value),
              child: Text(option.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    if (selected != null) onChanged(selected);
  }
}

class _CupertinoSwitchRow extends StatelessWidget {
  const _CupertinoSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.contentPadding = EdgeInsets.zero,
  });

  final Widget title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return MergeSemantics(
      child: Semantics(
        toggled: value,
        onTap: () => onChanged(!value),
        child: Padding(
          padding: contentPadding,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Row(
              children: <Widget>[
                Expanded(child: title),
                const SizedBox(width: CyTokens.space3),
                ExcludeSemantics(
                  child: CupertinoSwitch(
                    value: value,
                    activeTrackColor: palette.brand,
                    onChanged: onChanged,
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

class _CategorySelector extends ConsumerWidget {
  const _CategorySelector({required this.selected, required this.onChanged});
  final String? selected;
  final ValueChanged<List<int>> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = (selected ?? '')
        .split(',')
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
    final async = ref.watch(_templateCategoriesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '玩法类别 *',
          // 真源 `.cg-label` = body(28rpx = 14)/600 → Subhead 15 + Semibold(T2/T3)。
          style: CyType.subhead.copyWith(fontWeight: FontWeight.w600),
        ),
        async.when(
          loading: () => const Text('正在加载玩法类别…'),
          // ★ 空与错共用同一条出路,文案照真源
          //   `components/cy/category-sheet/index.wxml`:
          //   `cy-empty title="暂无可选分类" sub="分类没有加载出来，或当前类型下还没有
          //    配置分类。" cta="重试"`。原先失败只写「发布前必须重试」却**没有可点的
          //   入口**,而类别是必填项 —— 用户看到这句就卡在发布前面了。
          error: (_, _) => _CategoryEmptyOrFailed(
            onRetry: () => ref.invalidate(_templateCategoriesProvider),
          ),
          data: (rows) => rows.isEmpty
              ? _CategoryEmptyOrFailed(
                  onRetry: () => ref.invalidate(_templateCategoriesProvider),
                )
              : Wrap(
                  spacing: 8,
                  children: rows
                      .map(
                        (c) => _TemplateChoice(
                          label: c.name,
                          selected: ids.contains(c.id),
                          onPressed: () {
                            final next = ids.toSet();
                            ids.contains(c.id)
                                ? next.remove(c.id)
                                : next.add(c.id);
                            onChanged(next.toList());
                          },
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }
}

/// 类别「没有配置」与「没拉出来」的同一个落点(真源把两者合成一条)。
class _CategoryEmptyOrFailed extends StatelessWidget {
  const _CategoryEmptyOrFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '暂无可选分类',
                style: CyType.subhead.copyWith(color: p.textPrimary),
              ),
              const SizedBox(height: CyTokens.space1),
              Text(
                '分类没有加载出来，或当前类型下还没有配置分类。',
                style: CyType.caption1.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
        CupertinoButton(
          key: const Key('template-categories-retry'),
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
          onPressed: onRetry,
          child: const Text('重试'),
        ),
      ],
    );
  }
}

class _TemplateChoice extends StatelessWidget {
  const _TemplateChoice({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: CupertinoButton(
        minimumSize: const Size.square(44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        color: selected ? colors.onSurface : colors.surfaceContainerHighest,
        onPressed: onPressed,
        child: Text(
          label,
          // 真源 `.cg-chip` = label(24rpx = 12)→ Footnote 13(T2)。
          style: CyType.footnote.copyWith(
            color: selected ? colors.surface : colors.onSurface,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _CouponPicker extends ConsumerWidget {
  const _CouponPicker({required this.value, required this.onChanged});
  final int? value;
  final ValueChanged<int?> onChanged;
  @override
  Widget build(BuildContext context, WidgetRef ref) => CupertinoButton(
    minimumSize: const Size.fromHeight(44),
    padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
    color: CyPalette.of(context).bgSurfaceSubtle,
    onPressed: () async {
      try {
        final rows = await ref.read(couponApiProvider).myPublishedList();
        if (!context.mounted) return;
        await showCupertinoModalPopup<void>(
          context: context,
          builder: (sheetContext) => CupertinoActionSheet(
            title: const Text('选择优惠券'),
            actions: rows
                .map(
                  (row) => CupertinoActionSheetAction(
                    onPressed: () {
                      onChanged((row['id'] as num?)?.toInt());
                      Navigator.pop(sheetContext);
                    },
                    child: Text((row['name'] ?? '未命名优惠券').toString()),
                  ),
                )
                .toList(),
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext),
              child: const Text('取消'),
            ),
          ),
        );
      } catch (e) {
        if (context.mounted) {
          CyNativeNotice.show(context, e.toString(), isError: true);
        }
      }
    },
    child: Text(value == null ? '选择优惠券' : '已选优惠券 #$value'),
  );
}

class _ImageSlot extends StatelessWidget {
  const _ImageSlot({
    required this.label,
    required this.url,
    required this.onPick,
    required this.onClear,
  });
  final String label;
  final String? url;
  final VoidCallback onPick, onClear;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          // 真源 `.cg-label` = body(28rpx = 14)/600 → Subhead 15 + Semibold(T2/T3)。
          style: CyType.subhead.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        if ((url ?? '').isEmpty)
          _CupertinoInlineAction(
            onPressed: onPick,
            icon: CupertinoIcons.photo_on_rectangle,
            label: '上传图片',
          )
        else
          Row(
            children: <Widget>[
              Expanded(
                child: Text(url!, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              _CupertinoIconAction(
                tooltip: '清除图片',
                onPressed: onClear,
                icon: const Icon(CupertinoIcons.delete),
              ),
            ],
          ),
      ],
    ),
  );
}

class _AudioSlot extends StatelessWidget {
  const _AudioSlot({
    super.key,
    required this.label,
    required this.url,
    required this.onPick,
    required this.onClear,
  });
  final String label;
  final String? url;
  final VoidCallback onPick, onClear;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          // 真源 `.cg-label` = body(28rpx = 14)/600 → Subhead 15 + Semibold(T2/T3)。
          style: CyType.subhead.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        if ((url ?? '').isEmpty)
          _CupertinoInlineAction(
            onPressed: onPick,
            icon: CupertinoIcons.waveform,
            label: '选择音频文件',
          )
        else
          Row(
            children: <Widget>[
              const Icon(CupertinoIcons.check_mark_circled_solid),
              const SizedBox(width: 6),
              const Expanded(child: Text('音频已上传')),
              _CupertinoIconAction(
                tooltip: '清除音频',
                onPressed: onClear,
                icon: const Icon(CupertinoIcons.delete),
              ),
            ],
          ),
        Text(
          '支持 mp3 / m4a / aac',
          // 裸字号 → 梯级 Caption1 12(手册 T2)。
          style: CyType.caption1.copyWith(
            color: CyPalette.of(context).textSecondary,
          ),
        ),
      ],
    ),
  );
}

class _CupertinoIconAction extends StatelessWidget {
  const _CupertinoIconAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tooltip,
    child: CupertinoButton(
      minimumSize: const Size.square(44),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: icon,
    ),
  );
}

class _CupertinoInlineAction extends StatelessWidget {
  const _CupertinoInlineAction({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => CupertinoButton(
    minimumSize: const Size(44, 44),
    padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
    onPressed: onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 17),
          const SizedBox(width: CyTokens.space1),
        ],
        Text(label),
      ],
    ),
  );
}
