import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'ai_node_assist.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_tabs.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/merchant_api.dart';
import '../../data/models/node_template.dart';
import '../club/club_image_picker.dart';
import '../../core/widgets/upload_hints.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_widgets.dart';

/// 节点玩法配置。对齐小程序 `pages/publish/temp`。
///
/// ★★ 这一页决定「玩家到了这个点之后怎么算完成」。配不全的后果
///   **不是提交报错,是玩家怎么做都不对** —— 后端注释原话:
///   「vm=3 比 correctAnswer,且正确项得真有内容 ——
///     缺了后端拿 null 去比,玩家怎么答都错」。
///   所以表单按当前验证方式**只显示要填的那几栏**,并在提交前拦一道。
///
/// ★ 验证方式初值是 **null**,不预设:
///   预设成"拍照"的话,商家可能一路点到提交都没意识到自己选过。
///
/// ⚠️ 提交走 `/api/merchant/city-node/template/submit`,那条是**免人工审**的
///   (过内容安全即上线),所以成功可以说「已生效」——与别处的"待审"不同。
class NodeTemplateEditPage extends ConsumerStatefulWidget {
  const NodeTemplateEditPage({super.key, this.templateId});

  /// null = 新建。
  final int? templateId;

  @override
  ConsumerState<NodeTemplateEditPage> createState() =>
      _NodeTemplateEditPageState();
}

class _NodeTemplateEditPageState extends ConsumerState<NodeTemplateEditPage> {
  NodeTemplateDraft _draft = const NodeTemplateDraft();

  bool _loading = false;
  bool _saving = false;
  String? _error;

  final Map<String, TextEditingController> _c = <String, TextEditingController>{
    'title': TextEditingController(),
    'description': TextEditingController(),
    'questionAnswer': TextEditingController(),
    'questionName': TextEditingController(),
    'a': TextEditingController(),
    'b': TextEditingController(),
    'c': TextEditingController(),
    'd': TextEditingController(),
    'feedback': TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    if (widget.templateId != null) _load();
  }

  @override
  void dispose() {
    for (final TextEditingController c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final Map<String, dynamic> m = await ref
          .read(merchantApiProvider)
          .myTemplateInfo(widget.templateId!);
      if (!mounted) return;
      final NodeTemplateDraft d = NodeTemplateDraft.fromJson(m);
      _c['title']!.text = d.title;
      _c['description']!.text = d.description;
      _c['questionAnswer']!.text = d.questionAnswer;
      _c['questionName']!.text = d.questionName;
      _c['a']!.text = d.optionA;
      _c['b']!.text = d.optionB;
      _c['c']!.text = d.optionC;
      _c['d']!.text = d.optionD;
      _c['feedback']!.text = d.feedbackText;
      setState(() {
        _draft = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  NodeTemplateDraft get _current => _draft.copyWith(
    title: _c['title']!.text,
    description: _c['description']!.text,
    questionAnswer: _c['questionAnswer']!.text,
    questionName: _c['questionName']!.text,
    optionA: _c['a']!.text,
    optionB: _c['b']!.text,
    optionC: _c['c']!.text,
    optionD: _c['d']!.text,
    feedbackText: _c['feedback']!.text,
  );

  /// 当前还差哪一条。null = 可以保存。
  ///
  /// ★ 与 `NodeTemplateDraft.validate()` 同一份判据 —— 不另写一套,
  ///   否则按钮的可点状态和提交时的校验会漂。
  String? get _blocker => _current.validate();

  bool _uploading = false;

  /// 传封面。★ 失败**不清掉已有的图** —— 换图失败还把旧图弄没了,
  /// 用户要重新找一张;保留旧的最坏只是没换成。
  Future<void> _pickCover() async {
    setState(() => _uploading = true);
    try {
      final List<String> urls = await pickAndUploadImages(
        context,
        ref,
        maxCount: 1,
      );
      if (urls.isNotEmpty && mounted) {
        setState(() => _draft = _draft.copyWith(imgUrl: urls.first));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final NodeTemplateDraft d = _current;
    // ★ 先本地拦一道:让商家在填的时候就知道缺什么,而不是提交完被打回。
    final String? why = d.validate();
    if (why != null) {
      setState(() => _error = why);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final int id = await ref
          .read(merchantApiProvider)
          .submitNodeTemplate(d.toJson());
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(<String, dynamic>{'id': id, 'title': d.title.trim()});
    } on MerchantApiException catch (e) {
      if (!mounted) return;
      // ★ 服务端的校验话术比本地的准(它知道全部规则),原文显示。
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '没能保存,请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return CupertinoPageScaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        navigationBar: const CupertinoNavigationBar(middle: Text('节点玩法')),
        child: const Material(
          color: Colors.transparent,
          child: SafeArea(bottom: false, child: CySkeleton()),
        ),
      );
    }
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    final NodeValidationMethod? m = _draft.method;

    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.templateId == null ? '创建节点玩法' : '编辑节点玩法'),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.all(CyTokens.space4),
            children: <Widget>[
              Text(
                '完善以下内容,为路线打造可落地的现场互动方案',
                style: t.bodySmall?.copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: CyTokens.space4),
              _field('title', '玩法名称', hint: '给这个玩法起个名字'),
              _field('description', '玩法说明', hint: '玩家到店后看到的介绍', maxLines: 3),
              // ★ 封面。`NodeTemplateDraft.toJson` 里一直有 imgUrl,
              //   但编辑器**没有这个输入** —— 保存时永远发空,
              //   于是玩法在列表和详情里都没有图。小程序那页有「上传玩法封面」。
              const SizedBox(height: CyTokens.space3),
              const CySectionTitle('玩法封面'),
              const SizedBox(height: CyTokens.space2),
              if ((_draft.imgUrl ?? '').isEmpty)
                CyNativeButton(
                  key: const Key('template-cover-upload'),
                  onPressed: _uploading ? null : _pickCover,
                  role: CyNativeButtonRole.secondary,
                  icon: const CyNativeButtonIcon(
                    sfSymbol: 'photo',
                    fallback: CupertinoIcons.photo,
                  ),
                  label: _uploading ? '上传中…' : uploadHint('上传玩法封面', kHint16x9),
                  loading: _uploading,
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                      child: CyNetImage(
                        _draft.imgUrl,
                        height: 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: CyTokens.space2),
                    Row(
                      children: <Widget>[
                        CupertinoButton(
                          key: const Key('template-cover-replace'),
                          onPressed: _uploading ? null : _pickCover,
                          padding: EdgeInsets.zero,
                          child: const Text('换一张'),
                        ),
                        CupertinoButton(
                          key: const Key('template-cover-remove'),
                          onPressed: _uploading
                              ? null
                              : () => setState(
                                  () => _draft = _draft.copyWith(imgUrl: ''),
                                ),
                          padding: EdgeInsets.zero,
                          child: const Text('移除'),
                        ),
                      ],
                    ),
                  ],
                ),
              // ★ AI 帮写。判据是**玩法名称已填** —— 没有名字生成不出东西,
              //   后端也会拒;禁用比让用户点下去撞拒绝好。
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  key: const Key('ai-node-assist'),
                  onPressed: _c['title']!.text.trim().isEmpty
                      ? null
                      : _aiAssist,
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: <Widget>[
                      const Icon(CupertinoIcons.sparkles, size: 16),
                      const SizedBox(width: CyTokens.space1),
                      Expanded(
                        child: Text(
                          _c['title']!.text.trim().isEmpty
                              ? '先填玩法名称,AI 才能帮你写'
                              : 'AI 帮我写',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: CyTokens.space2),

              const SizedBox(height: CyTokens.space3),
              Text('玩家怎么算完成', style: t.labelLarge),
              const SizedBox(height: CyTokens.space2),
              // ★ 五种方式各带一句说明 —— 只写名字的话,商家分不清
              //   「扫张贴码」和「拍照打卡」差在哪。
              RadioGroup<NodeValidationMethod>(
                groupValue: m,
                onChanged: (NodeValidationMethod? value) =>
                    setState(() => _draft = _draft.copyWith(method: value)),
                child: Column(
                  children: NodeValidationMethod.values
                      .map(
                        (NodeValidationMethod value) => _methodRow(value, p, t),
                      )
                      .toList(),
                ),
              ),

              // ★★ 按验证方式**只显示要填的那几栏**。全都摆出来的话,
              //   商家会填一堆根本不生效的字段。
              if (m == NodeValidationMethod.secretWord) ...<Widget>[
                const SizedBox(height: CyTokens.space3),
                _field('questionAnswer', '暗号答案', hint: '玩家要输入的那串字'),
              ],
              if (m == NodeValidationMethod.quiz) ...<Widget>[
                const SizedBox(height: CyTokens.space3),
                _field('questionName', '题目'),
                _field('a', '选项 A'),
                _field('b', '选项 B'),
                _field('c', '选项 C(可空)'),
                _field('d', '选项 D(可空)'),
                const SizedBox(height: CyTokens.space2),
                Text('正确答案', style: t.labelLarge),
                const SizedBox(height: CyTokens.space1),
                // 用 CyTabs 的 chip 变体,不用 Material 的 ChoiceChip ——
                // 后者与全站分段控件不是一套(门禁 no_material_segmented 禁它)。
                CyTabs(
                  variant: CyTabsVariant.chip,
                  tabs: const <CyTab>[
                    CyTab(key: 'A', label: 'A'),
                    CyTab(key: 'B', label: 'B'),
                    CyTab(key: 'C', label: 'C'),
                    CyTab(key: 'D', label: 'D'),
                  ],
                  active: _draft.correctAnswer.toUpperCase(),
                  onChanged: (String k) => setState(
                    () => _draft = _draft.copyWith(correctAnswer: k),
                  ),
                ),
                const SizedBox(height: CyTokens.space1),
                // ★ 说清"指到空选项等于没答案" —— 那是最容易犯又最难发现的错。
                Text(
                  '正确答案要指到一个**填了内容**的选项;指到空的等于没答案,'
                  '玩家怎么选都不对。',
                  style: t.bodySmall?.copyWith(color: p.textSecondary),
                ),
              ],

              const SizedBox(height: CyTokens.space3),
              _field('feedback', '完成后的反馈', hint: '玩家完成时看到的一句话', maxLines: 2),

              if (_error != null) ...<Widget>[
                const SizedBox(height: CyTokens.space3),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: CyTokens.space5),
              // ★ 与「据点报名」「提现」两页一致:**不能提交时说出是哪一条**,
              //   而不是给个可点的按钮让用户点完才知道。
              //   2026-08-19 看 golden 图发现这页漏了这条:没选验证方式时
              //   「保存」仍是可点的白色主按钮。
              if (_blocker != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: CyTokens.space2),
                  child: Text(
                    _blocker!,
                    style: t.bodySmall?.copyWith(color: CyPalette.of(context).statusWarning),
                  ),
                ),
              CyNativeButton(
                onPressed: (_saving || _blocker != null) ? null : _save,
                label: '保存',
                width: double.infinity,
                loading: _saving,
              ),
              const SizedBox(height: CyTokens.space3),
              // 这条接口免人工审,说清楚,免得商家一直等审核。
              Text(
                '保存后即刻生效(只过内容安全检查,不需要人工审核)。',
                style: t.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// AI 帮写。★ 只**填进表单**,不直接保存 —— 生成的内容要让商家改过再存。
  /// ⚠️ 已填的字段不覆盖:商家自己写的比 AI 生成的要紧。
  Future<void> _aiAssist() async {
    final AiNodeAssistResult? r = await showAiNodeAssist(
      context,
      nodeName: _c['title']!.text.trim(),
      validationMethod: _draft.method?.wire,
    );
    if (r == null || !mounted) return;
    setState(() {
      void fill(String key, String? v) {
        if (v == null || v.trim().isEmpty) return;
        // 不覆盖商家已经写了的内容。
        if (_c[key]!.text.trim().isNotEmpty) return;
        _c[key]!.text = v.trim();
      }

      // 真源 `pages/publish/temp/index.js:865-890` 的落点。
      fill('title', r.title);
      // 描述那一格真源有回退链:AI 没给 description 才拿 storyText 的前 30 字。
      fill('description', r.description ?? _clip(r.storyText));
      fill('questionName', r.questionName);
      fill('questionAnswer', r.questionAnswer);
      fill('a', r.optionA);
      fill('b', r.optionB);
      fill('c', r.optionC);
      fill('d', r.optionD);
      fill('feedback', r.feedbackText);

      // 验证方式与正确项不在 controller 上,落在 draft 里。
      //
      // ⚠️ 与真源**故意有一处不同**:真源 `:868` 只要 AI 回的 validationMethod
      //   在码表里就无条件覆盖;App 这边【已选过就不覆盖】——
      //   和上面 `fill()` 同一条原则(商家自己选的比 AI 猜的要紧)。
      //   商家没选过时才采用 AI 的,免得一路点到提交都没意识到选过验证方式。
      final NodeValidationMethod? aiMethod =
          NodeValidationMethod.fromWire(r.validationMethod);
      if (_draft.method == null && aiMethod != null) {
        _draft = _draft.copyWith(method: aiMethod);
      }

      // 选择题的正确项:真源要求「选项 ≥2 且字母合法」才落,否则不猜。
      final NodeValidationMethod? m = _draft.method;
      if (m == NodeValidationMethod.quiz && _draft.correctAnswer.trim().isEmpty) {
        final int filledOptions = _draft.options
            .where((String o) => o.trim().isNotEmpty)
            .length;
        final String letter = (r.correctAnswer ?? '').toUpperCase();
        if (filledOptions >= 2 && const <String>['A', 'B', 'C', 'D'].contains(letter)) {
          _draft = _draft.copyWith(correctAnswer: letter);
        }
      }
    });
  }

  /// 真源 `:871` 的 `.slice(0, 30)` —— 描述那格是摘要,不是全文。
  static String? _clip(String? s) {
    final String v = (s ?? '').trim();
    if (v.isEmpty) return null;
    return v.length <= 30 ? v : v.substring(0, 30);
  }

  Widget _field(String key, String label, {String? hint, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: CyTokens.space1),
          CupertinoTextField(
            controller: _c[key],
            minLines: 1,
            maxLines: maxLines,
            placeholder: hint,
            padding: const EdgeInsets.symmetric(
              horizontal: CyTokens.space3,
              vertical: 12,
            ),
            textInputAction: key == 'feedback'
                ? TextInputAction.done
                : maxLines > 1
                ? TextInputAction.newline
                : TextInputAction.next,
            clearButtonMode: OverlayVisibilityMode.editing,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _methodRow(
    NodeValidationMethod value,
    CyPalette palette,
    TextTheme textTheme,
  ) {
    final bool selected = _draft.method == value;
    return Semantics(
      selected: selected,
      button: true,
      label: value.label,
      child: CupertinoButton(
        key: Key('node-method-${value.wire}'),
        minimumSize: const Size.fromHeight(56),
        padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
        alignment: Alignment.centerLeft,
        foregroundColor: palette.textPrimary,
        onPressed: () =>
            setState(() => _draft = _draft.copyWith(method: value)),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(value.label, style: textTheme.bodyLarge),
                  Text(
                    value.hint,
                    style: textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: CyTokens.space2),
            ExcludeSemantics(
              child: CupertinoRadio<NodeValidationMethod>(
                value: value,
                activeColor: palette.brand,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
