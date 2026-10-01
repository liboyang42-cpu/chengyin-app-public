import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../data/models/ai_quota.dart';
import '../../core/widgets/ai_generated_note.dart';

/// AI 帮写节点内容(`/api/ai/template/fill` —— 旧 `/api/ai/node/generate` 两端零调用方,已删)。
///
/// ★★ 后端两条拒绝文案**性质完全不同**(ApiAiController:38/41,
///   已抽成 AiGateResult):
///   · 「当前身份暂不支持AI创作…」→ **身份问题,重试无用**
///     ⇒ 不给重试钮,给「怎么换身份」的下一步。
///   · 「AI 服务暂时不可用,请稍后重试」→ **故障,重试有用** ⇒ 给重试钮。
///   合并成一个「生成失败,请重试」,前一种的人会一直点一个永远不会成功的按钮。
///
/// ⚠️ 生产 AI **已通电**(2026-08-20 读生产进程 environ 实测:
///   `CHENGYIN_AI_API_KEY` 未注入,但 yml 回退到 `CHENGYIN_DEEPSEEK_API_KEY`,
///   而那个**已注入**)。所以这不是"接一个必然失败的按钮"。
///   ⚠️ 当初判「AI 没通电」是只查了主变量、没读回退链 —— 判配置生效
///   要读完整条链,不是查单个变量名。
/// 整表填充的返回(`/api/ai/template/fill`)。
///
/// ★ 字段名**照抄真源取用处**(`pages/publish/temp/index.js:865-890`),
///   不按 App 自己的习惯改名 —— 这张表是服务端定的。
///
/// ★★ 这里只做**搬运与判定**,不做业务裁剪:哪些字段 App 今天填不进表单,
///   由调用方([NodeTemplateEditPage._aiAssist])决定,并在那里说清。
///   在模型层悄悄丢掉字段,下一个人会以为服务端没回。
@immutable
class AiNodeAssistResult {
  const AiNodeAssistResult({
    this.title,
    this.medalName,
    this.description,
    this.storyText,
    this.ruleInstructions,
    this.validationMethod,
    this.questionName,
    this.questionAnswer,
    this.hint1,
    this.hint2,
    this.answerReveal,
    this.feedbackText,
    this.optionA,
    this.optionB,
    this.optionC,
    this.optionD,
    this.correctAnswer,
  });

  final String? title;
  final String? medalName;
  final String? description;
  final String? storyText;
  final String? ruleInstructions;
  final int? validationMethod;
  final String? questionName;
  final String? questionAnswer;
  final String? hint1;
  final String? hint2;
  final String? answerReveal;
  final String? feedbackText;
  final String? optionA;
  final String? optionB;
  final String? optionC;
  final String? optionD;

  /// 正确项的**字母**(A/B/C/D),不是下标 —— 与真源 `optionItems[].letter` 同义。
  final String? correctAnswer;

  /// 真源 `:857-859` 的空判:**六格全空**才算「AI 没生成出内容」。
  ///
  /// ⚠️ 别缩成「description 为空就算空」—— 选项题可以没有描述、
  ///   只有题目与选项,缩窄会把一次成功的生成说成失败。
  bool get isEmpty => <String?>[
    storyText,
    ruleInstructions,
    questionName,
    questionAnswer,
    hint1,
    hint2,
  ].every((String? v) => (v ?? '').trim().isEmpty);

  /// 真源 `:852`:`data.template` 与 `data.node` **两种外壳都认**,前者优先。
  /// 两个都不是对象时,把 [data] 自己当那张表 —— 与真源 `|| node` 的兜底同形。
  factory AiNodeAssistResult.fromResponse(Map<String, dynamic> data) {
    final Object? inner = data['template'] ?? data['node'];
    return AiNodeAssistResult.fromJson(
      inner is Map<String, dynamic> ? inner : data,
    );
  }

  factory AiNodeAssistResult.fromJson(Map<String, dynamic> json) {
    String? t(String k) {
      final String v = (json[k] ?? '').toString().trim();
      return v.isEmpty ? null : v;
    }

    int? i(String k) {
      final Object? raw = json[k];
      if (raw == null) return null;
      return raw is num ? raw.toInt() : int.tryParse('$raw'.trim());
    }

    return AiNodeAssistResult(
      title: t('title'),
      medalName: t('medalName'),
      description: t('description'),
      storyText: t('storyText'),
      ruleInstructions: t('ruleInstructions'),
      validationMethod: i('validationMethod'),
      questionName: t('questionName'),
      questionAnswer: t('questionAnswer'),
      hint1: t('hint1'),
      hint2: t('hint2'),
      answerReveal: t('answerReveal'),
      feedbackText: t('feedbackText'),
      optionA: t('optionA'),
      optionB: t('optionB'),
      optionC: t('optionC'),
      optionD: t('optionD'),
      correctAnswer: t('correctAnswer'),
    );
  }
}

/// 弹一个「AI 帮我写」的浮层,返回生成结果(用户取消返回 null)。
Future<AiNodeAssistResult?> showAiNodeAssist(
  BuildContext context, {
  required String nodeName,
  int? validationMethod,
}) {
  return showCupertinoSheet<AiNodeAssistResult>(
    context: context,
    showDragHandle: true,
    topGap: 0.22,
    scrollableBuilder:
        (BuildContext context, ScrollController scrollController) =>
            _AssistSheet(
              nodeName: nodeName,
              validationMethod: validationMethod,
              scrollController: scrollController,
            ),
  );
}

class _AssistSheet extends ConsumerStatefulWidget {
  const _AssistSheet({
    required this.nodeName,
    required this.scrollController,
    this.validationMethod,
  });
  final String nodeName;
  final int? validationMethod;
  final ScrollController scrollController;

  @override
  ConsumerState<_AssistSheet> createState() => _AssistSheetState();
}

class _AssistSheetState extends ConsumerState<_AssistSheet> {
  bool _busy = false;
  String? _error;
  bool _hasLocalPromptError = false;
  AiNodeAssistResult? _result;

  /// 真源把这条叫 `prompt`,是**必填**的:
  /// `pages/publish/temp/index.js:826-827` 空着就报「请先描述想生成的节点玩法」,
  /// 压根不发请求。所以这里也不自动生成 —— 打开浮层先让商家说一句想做什么。
  final TextEditingController _prompt = TextEditingController();

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final String prompt = _prompt.text.trim();
    if (prompt.isEmpty) {
      setState(() {
        _result = null;
        _error = '请先描述想生成的节点玩法';
        _hasLocalPromptError = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _hasLocalPromptError = false;
    });
    try {
      final Map<String, dynamic> data = await ref
          .read(aiCreatorApiProvider)
          .templateFill(
            shopName: widget.nodeName,
            extraNote: prompt,
            validationMethod: widget.validationMethod,
          );
      if (!mounted) return;
      setState(() {
        _result = AiNodeAssistResult.fromResponse(data);
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _busy = false;
      });
    }
  }

  /// 选项按 A→D 拼一行;一个都没有时返回 null(不渲染空标题)。
  String? get _optionsLine {
    final List<String> opts = <String>[
      ?_result?.optionA,
      ?_result?.optionB,
      ?_result?.optionC,
      ?_result?.optionD,
    ];
    if (opts.isEmpty) return null;
    const List<String> letters = <String>['A', 'B', 'C', 'D'];
    return <String>[
      for (int i = 0; i < opts.length; i++) '${letters[i]}. ${opts[i]}',
    ].join('  ');
  }

  /// 服务端回了、但这张表单放不下的字段 —— 有才说,没有不说。
  String? get _skippedFields {
    final AiNodeAssistResult? r = _result;
    if (r == null) return null;
    final List<String> names = <String>[
      if (r.medalName != null) stringsOf(context).merchantAiAssistMedal,
      if (r.hint1 != null || r.hint2 != null) stringsOf(context).merchantAiAssistHints,
      if (r.answerReveal != null) stringsOf(context).merchantAiAssistReveal,
      if (r.ruleInstructions != null) stringsOf(context).merchantAiAssistRules,
      if (r.storyText != null) stringsOf(context).merchantAiAssistStory,
    ];
    if (names.isEmpty) return null;
    return stringsOf(context).merchantAiAssistSkipped(names.join(stringsOf(context).merchantAiAssistSeparator));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final String? err = _error;
    // ★ 身份问题不给重试 —— 重试永远不会成功。
    final bool canRetry = err != null && AiGateResult.retryable(err);
    final String? nextStep = err == null || AiGateResult.nextStep(err) == null ? null : stringsOf(context).merchantAiAssistRoleNextStep;

    // ⚠️ 商家域是**浅色**页(路由包了 _merchantLight)——
    //   颜色一律走 CyPalette,硬编码 CyTokens 的深色值会在白底上变黑块。
    //   (门禁 light_pages_no_static_colors 抓到过我这一处。)
    final p = CyPalette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: p.bgPage,
      navigationBar: CupertinoNavigationBar(
        middle: Text(stringsOf(context).merchantAiAssistTitle),
        leading: CupertinoButton(
          key: const Key('ai-node-close'),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(stringsOf(context).merchantAiAssistClose),
        ),
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.fromLTRB(
            CyTokens.space4,
            CyTokens.space3,
            CyTokens.space4,
            CyTokens.space5,
          ),
          children: <Widget>[
            // 合规:AI 生成内容来源标注。
            const AiGeneratedNote(),
            Text(stringsOf(context).merchantAiAssistHeading(widget.nodeName), style: textTheme.titleMedium),
            const SizedBox(height: CyTokens.space1),
            Text(
              stringsOf(context).merchantAiAssistPromptHint,
              style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: CyTokens.space3),
            CupertinoTextField(
              key: const Key('ai-node-prompt'),
              controller: _prompt,
              minLines: 3,
              maxLines: 5,
              enabled: !_busy,
              placeholder: stringsOf(context).merchantAiAssistPromptExample,
              padding: const EdgeInsets.all(CyTokens.space3),
              onSubmitted: (_) => _generate(),
            ),
            const SizedBox(height: CyTokens.space3),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton.tinted(
                key: const Key('ai-node-generate'),
                minimumSize: const Size.fromHeight(44),
                onPressed: _busy ? null : _generate,
                child: Text(stringsOf(context).merchantAiAssistGenerate),
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: CyTokens.space5),
                child: Center(child: CupertinoActivityIndicator()),
              )
            else if (err != null) ...<Widget>[
              Text(_hasLocalPromptError ? stringsOf(context).merchantAiAssistPromptRequired : err, style: textTheme.bodyMedium),
              if (nextStep != null) ...<Widget>[
                const SizedBox(height: CyTokens.space1),
                Text(
                  nextStep,
                  style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
                ),
              ],
              const SizedBox(height: CyTokens.space3),
              if (canRetry)
                CupertinoButton.tinted(
                  key: const Key('ai-node-retry'),
                  minimumSize: const Size.fromHeight(44),
                  onPressed: _generate,
                  child: Text(stringsOf(context).merchantAiAssistRetry),
                ),
            ] else if (_result != null) ...<Widget>[
              // ★ 生成为空时说实话,别把空结果当成功塞进表单。
              if (_result!.isEmpty)
                Text(stringsOf(context).merchantAiAssistEmpty, style: textTheme.bodyMedium)
              else ...<Widget>[
                if (_result!.title != null) _Preview(stringsOf(context).merchantAiAssistPreviewTitle, _result!.title!),
                if (_result!.description != null)
                  _Preview(stringsOf(context).merchantAiAssistDescription, _result!.description!),
                if (_result!.questionName != null)
                  _Preview(stringsOf(context).merchantAiAssistQuestion, _result!.questionName!),
                if (_optionsLine != null) _Preview(stringsOf(context).merchantAiAssistOptions, _optionsLine!),
                if (_result!.correctAnswer != null)
                  _Preview(stringsOf(context).merchantAiAssistCorrect, _result!.correctAnswer!),
                if (_result!.questionAnswer != null)
                  _Preview(stringsOf(context).merchantAiAssistAnswer, _result!.questionAnswer!),
                if (_result!.feedbackText != null)
                  _Preview(stringsOf(context).merchantAiAssistFeedback, _result!.feedbackText!),
                // ★ 服务端回得比这张表单宽:勋章名/提示/故事线/模块 本编辑器没有格子。
                //   说出来,而不是静默丢掉 —— 否则商家会以为 AI 没生成那几项。
                if (_skippedFields != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: CyTokens.space2),
                    child: Text(
                      _skippedFields!,
                      key: const Key('ai-node-skipped'),
                      style: textTheme.bodySmall?.copyWith(
                        color: p.textTertiary,
                      ),
                    ),
                  ),
                const SizedBox(height: CyTokens.space3),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    key: const Key('ai-node-apply'),
                    minimumSize: const Size.fromHeight(44),
                    color: p.actionPrimaryBg,
                    disabledColor: p.bgSubtle,
                    foregroundColor: p.actionPrimaryFg,
                    onPressed: () => Navigator.of(context).pop(_result),
                    // 说清会发生什么:填进表单,不是直接保存。
                    child: Text(stringsOf(context).merchantAiAssistApply),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview(this.label, this.text);
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: CyPalette.of(context).textTertiary,
            ),
          ),
          const SizedBox(height: 2),
          Text(text, style: textTheme.bodyMedium),
        ],
      ),
    );
  }
}
