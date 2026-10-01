import 'club_api_messages.dart';
import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../data/models/ai_quota.dart';
import '../../data/models/publish_draft.dart';
import '../../core/widgets/ai_generated_note.dart';
import '../../core/widgets/cy_native_notice.dart';

const List<String> kClubAiIdeaChips = <String>[
  '静安 情侣 夜间 Citywalk 90分钟',
  '外滩 亲子 半天 城市打卡',
  '苏州河 摄影 徒步 2小时',
];

class ClubAiNode {
  const ClubAiNode({
    required this.order,
    required this.name,
    this.fallbackNameNumber,
    this.address = '',
    this.longitude = '',
    this.latitude = '',
    this.businessTime = '',
  });

  final int order;
  final String name;
  // Display-only metadata; publishing continues to use the original draft name.
  final int? fallbackNameNumber;
  final String address;
  final String longitude;
  final String latitude;
  final String businessTime;

  factory ClubAiNode.fromJson(Map<String, dynamic> json, int index) {
    String text(String key) => (json[key] ?? '').toString().trim();
    return ClubAiNode(
      order: (json['order'] as num?)?.toInt() ?? index + 1,
      name: text('merchantName').isEmpty
          ? '节点${index + 1}'
          : text('merchantName'),
      fallbackNameNumber: text('merchantName').isEmpty ? index + 1 : null,
      address: text('address'),
      longitude: text('longitude'),
      latitude: text('latitude'),
      businessTime: text('businessTime'),
    );
  }
}

/// AI 策划一场俱乐部活动(`/api/ai/club/design`)。
///
/// ★★★ 后端返回体有**三种"失败"**,性质各不相同,合并任何两种都会误导主理人:
///   ① `parseError != null` → AI 的回答**解析炸了**,
///      此时 `plan / merchantSuggestions / promoCopy` **全部不可信**(后端 VO javadoc)。
///      ⇒ 一个字段都不许渲染,只说这次没成。
///   ② `plan == null` 且没有 parseError → AI **没给出方案**(静默空成功)。
///      和①是两回事:①是我们没读懂它,②是它没说。文案要分开。
///   ③ code != 200 → 走 [AiGateResult] 分流:身份问题不给重试,故障才给。
///      其中「今日AI次数已用完」属于**配额**,重试同样无用。
class ClubAiDesign {
  const ClubAiDesign({
    required this.plan,
    this.traceId,
    this.title = '',
    this.titleIsFallback = false,
    this.subtitle,
    this.storyline,
    this.tags = const <String>[],
    this.estDurationMin,
    this.fitReason,
    this.nodes = const <ClubAiNode>[],
    this.risks = const <String>[],
    this.merchantSuggestions = const <String>[],
    this.promoCopy,
  });

  final String plan;
  final String? traceId;
  final String title;
  final bool titleIsFallback;
  final String? subtitle;
  final String? storyline;
  final List<String> tags;
  final int? estDurationMin;
  final String? fitReason;
  final List<ClubAiNode> nodes;
  final List<String> risks;
  final List<String> merchantSuggestions;
  final String? promoCopy;

  /// 解析返回体。★ 不合法时返回 null,由调用方按①②分流 —— 这里不编内容。
  static ClubAiDesign? tryParse(Map<String, dynamic> data) {
    String? optional(Object? value) {
      final String text = (value ?? '').toString().trim();
      return text.isEmpty ? null : text;
    }

    List<String> strings(Object? value) =>
        ((value as List<dynamic>?) ?? const <dynamic>[])
            .map((Object? item) => item.toString().trim())
            .where((String item) => item.isNotEmpty)
            .toList(growable: false);

    final Object? rawPlan = data['plan'];
    if (rawPlan == null) return null;
    if (rawPlan is String) {
      final String legacy = rawPlan.trim();
      if (legacy.isEmpty) return null;
      return ClubAiDesign(
        plan: legacy,
        title: legacy,
        traceId: optional(data['traceId']),
        merchantSuggestions: strings(data['merchantSuggestions']),
        promoCopy: optional(data['promoCopy']),
      );
    }
    if (rawPlan is! Map) return null;
    final Map<String, dynamic> map = rawPlan.cast<String, dynamic>();
    final String title = optional(map['title']) ?? '未命名方案';
    final String? storyline = optional(map['storyline']);
    final List<ClubAiNode> nodes =
        ((map['nodes'] as List<dynamic>?) ?? const <dynamic>[])
            .whereType<Map>()
            .toList(growable: false)
            .asMap()
            .entries
            .map(
              (MapEntry<int, Map<dynamic, dynamic>> entry) =>
                  ClubAiNode.fromJson(
                    entry.value.cast<String, dynamic>(),
                    entry.key,
                  ),
            )
            .toList(growable: false);
    return ClubAiDesign(
      plan: storyline ?? title,
      traceId: optional(data['traceId']),
      title: title,
      titleIsFallback: optional(map['title']) == null,
      subtitle: optional(map['subtitle']),
      storyline: storyline,
      tags: strings(map['tags']),
      estDurationMin: (map['estDurationMin'] as num?)?.toInt(),
      fitReason: optional(map['fitReason']),
      nodes: nodes,
      risks: strings(map['risks']),
      merchantSuggestions: strings(data['merchantSuggestions']),
      promoCopy: optional(data['promoCopy']),
    );
  }

  PublishDraft toPublishDraft({int? clubId}) {
    final PublishChapter chapter = PublishChapter()
      ..name = '第1章'
      ..localId = 'ai_chapter_1'
      ..nodes = nodes
          .asMap()
          .entries
          .map(
            (MapEntry<int, ClubAiNode> entry) => PublishNode()
              ..name = entry.value.name
              ..description = entry.value.address
              ..address = entry.value.address
              ..longitude = entry.value.longitude
              ..latitude = entry.value.latitude
              ..businessTime = entry.value.businessTime
              ..sortID = entry.value.order
              ..localId = 'ai_node_${entry.key + 1}',
          )
          .toList(growable: false);
    return PublishDraft()
      ..name = title == '未命名方案' ? '' : title
      ..subtitle = subtitle ?? ''
      ..description = <String>[
        if ((storyline ?? '').isNotEmpty) storyline!,
        '[AI 辅助生成]',
      ].join('\n\n')
      ..productType = kProductCity
      ..publishMode = 'pro'
      ..clubId = clubId
      ..chapters = <PublishChapter>[chapter];
  }
}

/// 配额用尽的文案标记(与小程序 `AI_QUOTA_MARK` 同一句)。
const String kAiQuotaMark = '今日AI次数已用完';

/// 这条错误值不值得重试。★ 身份问题和配额用尽都不值得 ——
/// 给重试钮等于让人一直点一个不会成功的按钮。
bool aiDesignRetryable(String message) =>
    AiGateResult.retryable(message) && !message.contains(kAiQuotaMark);

Future<void> showClubAiDesignSheet(BuildContext context, {int? clubId}) async {
  await showCupertinoSheet<void>(
    context: context,
    enableDrag: false,
    showDragHandle: true,
    topGap: 0.08,
    scrollableBuilder:
        (BuildContext context, ScrollController scrollController) =>
            _DesignSheet(scrollController: scrollController, clubId: clubId),
  );
}

class _DesignSheet extends ConsumerStatefulWidget {
  const _DesignSheet({required this.scrollController, this.clubId});

  final ScrollController scrollController;
  final int? clubId;

  @override
  ConsumerState<_DesignSheet> createState() => _DesignSheetState();
}

class _DesignSheetState extends ConsumerState<_DesignSheet> {
  final TextEditingController _idea = TextEditingController();
  final TextEditingController _style = TextEditingController();
  final TextEditingController _duration = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _errorRetryable = false;
  ClubAiDesign? _result;
  int _requestToken = 0;

  @override
  void initState() {
    super.initState();
    _idea.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _requestToken++;
    _idea.dispose();
    _style.dispose();
    _duration.dispose();
    super.dispose();
  }

  void _fail(String msg, {required bool retryable}) {
    setState(() {
      _error = msg;
      _errorRetryable = retryable;
      _busy = false;
      _result = null;
    });
  }

  Future<void> _generate() async {
    final String idea = _idea.text.trim();
    if (idea.isEmpty || _busy) return;
    final int token = ++_requestToken;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final int? duration = int.tryParse(_duration.text.trim());
      final Map<String, dynamic> data = await ref
          .read(aiCreatorApiProvider)
          .clubDesign(
            idea: idea,
            clubStyle: _style.text.trim().isEmpty ? null : _style.text.trim(),
            targetDurationMin: duration != null && duration > 0
                ? duration
                : null,
          );
      if (!mounted || token != _requestToken) return;

      // ① 解析炸了 —— 其余字段全不可信,一个都不许渲染。
      final String parseError = (data['parseError'] ?? '').toString().trim();
      if (parseError.isNotEmpty) {
        _fail(parseError, retryable: true);
        return;
      }
      // ② AI 没给方案(静默空成功)—— 和①分开说。
      final ClubAiDesign? parsed = ClubAiDesign.tryParse(data);
      if (parsed == null) {
        _fail(stringsOf(context).clubAuxAiNoPlan, retryable: true);
        return;
      }
      setState(() {
        _result = parsed;
        _busy = false;
      });
    } catch (e) {
      if (!mounted || token != _requestToken) return;
      final String msg = clubApiErrorMessage(context, e);
      // ③ 身份 / 配额 / 故障三分。
      _fail(msg, retryable: aiDesignRetryable(msg));
    }
  }

  void _cancelGeneration() {
    _requestToken++;
    setState(() {
      _busy = false;
      _error = null;
      _result = null;
    });
  }

  Future<void> _copyPromo() async {
    final String? text = _result?.promoCopy;
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    // 纯告知不弹 alert(S7):页内轻提示,与俱乐部其它「已复制」反馈同一写法。
    CyNativeNotice.show(context, stringsOf(context).clubAuxPromoCopied);
  }

  void _adopt() {
    final ClubAiDesign? result = _result;
    if (result == null) return;
    final GoRouter router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(
      '/publish/pro',
      extra: result.toPublishDraft(clubId: widget.clubId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final CyPalette p = CyPalette.of(context);
    final String? err = _error;
    final String? nextStep = err == null ? null : AiGateResult.nextStep(err);

    return CupertinoPageScaffold(
      backgroundColor: p.bgPage,
      resizeToAvoidBottomInset: true,
      child: SafeArea(
        top: false,
        child: ListView(
          controller: widget.scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space2,
            CyTokens.pageX,
            CyTokens.space5 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    stringsOf(context).clubAuxAiTitle,
                    style: textTheme.titleLarge?.copyWith(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Semantics(
                  label: stringsOf(context).clubAuxCloseAi,
                  button: true,
                  child: CupertinoButton(
                    key: const Key('club-ai-close'),
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    foregroundColor: p.textSecondary,
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: const ExcludeSemantics(
                      child: Icon(CupertinoIcons.xmark_circle_fill),
                    ),
                  ),
                ),
              ],
            ),
            Text(
              stringsOf(context).clubAuxAiExplanation,
              style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: CyTokens.space3),
            Wrap(
              spacing: CyTokens.space2,
              runSpacing: CyTokens.space2,
              children: kClubAiIdeaChips
                  .map(
                    (String sourceChip) {
                      final chip = switch (kClubAiIdeaChips.indexOf(sourceChip)) {
                        0 => stringsOf(context).clubAuxIdeaJingan,
                        1 => stringsOf(context).clubAuxIdeaBund,
                        2 => stringsOf(context).clubAuxIdeaSuzhou,
                        _ => sourceChip,
                      };
                      return CupertinoButton.tinted(
                      key: Key('club-ai-chip-$sourceChip'),
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      onPressed: _busy
                          ? null
                          : () {
                              _idea.text = chip;
                              _idea.selection = TextSelection.collapsed(
                                offset: chip.length,
                              );
                            },
                      child: Text(chip),
                    );
                    },
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: CyTokens.space3),
            Semantics(
              textField: true,
              label: stringsOf(context).clubAuxIdea,
              child: CupertinoTextField(
                controller: _idea,
                minLines: 2,
                maxLines: 4,
                maxLength: 200,
                enabled: !_busy,
                clearButtonMode: OverlayVisibilityMode.editing,
                placeholder: stringsOf(context).clubAuxIdeaPlaceholder,
                padding: const EdgeInsets.all(CyTokens.space3),
                decoration: BoxDecoration(
                  color: p.bgSurface,
                  border: Border.all(color: p.borderSubtle),
                  borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                ),
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            Row(
              children: <Widget>[
                Expanded(
                  child: Semantics(
                    textField: true,
                    label: stringsOf(context).clubAuxStyleLabel,
                    child: CupertinoTextField(
                      controller: _style,
                      enabled: !_busy,
                      maxLength: 20,
                      clearButtonMode: OverlayVisibilityMode.editing,
                      placeholder: stringsOf(context).clubAuxStylePlaceholder,
                      padding: const EdgeInsets.all(CyTokens.space3),
                      decoration: BoxDecoration(
                        color: p.bgSurface,
                        border: Border.all(color: p.borderSubtle),
                        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: CyTokens.space2),
                SizedBox(
                  width: 124,
                  child: Semantics(
                    textField: true,
                    label: stringsOf(context).clubAuxDurationLabel,
                    child: CupertinoTextField(
                      controller: _duration,
                      enabled: !_busy,
                      maxLength: 4,
                      keyboardType: TextInputType.number,
                      placeholder: stringsOf(context).clubAuxDurationPlaceholder,
                      padding: const EdgeInsets.all(CyTokens.space3),
                      decoration: BoxDecoration(
                        color: p.bgSurface,
                        border: Border.all(color: p.borderSubtle),
                        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: CyTokens.space3),
            Row(
              children: <Widget>[
                Expanded(
                  child: CupertinoButton(
                    key: const Key('club-ai-generate'),
                    minimumSize: const Size.fromHeight(CyTokens.btnH),
                    color: p.actionPrimaryBg,
                    disabledColor: p.bgSubtle,
                    foregroundColor: (_busy || _idea.text.trim().isEmpty)
                        ? p.textPlaceholder
                        : p.actionPrimaryFg,
                    borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                    onPressed: (_busy || _idea.text.trim().isEmpty)
                        ? null
                        : _generate,
                    child: _busy
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              const CupertinoActivityIndicator(),
                              const SizedBox(width: CyTokens.space2),
                              Text(stringsOf(context).clubAuxGenerating),
                            ],
                          )
                        : Text(_result == null ? stringsOf(context).clubAuxGenerate : stringsOf(context).clubAuxRegenerate),
                  ),
                ),
                if (_busy) ...<Widget>[
                  const SizedBox(width: CyTokens.space2),
                  CupertinoButton(
                    key: const Key('club-ai-cancel'),
                    minimumSize: const Size(44, 44),
                    onPressed: _cancelGeneration,
                    child: Text(stringsOf(context).cancel),
                  ),
                ],
              ],
            ),
            // 合规:AI 生成内容来源标注(见 ai_generated_note.dart)。
            const AiGeneratedNote(),
            if (err != null) ...<Widget>[
              const SizedBox(height: CyTokens.space3),
              Text(err, style: textTheme.bodyMedium),
              if (nextStep != null) ...<Widget>[
                const SizedBox(height: CyTokens.space1),
                Text(
                  nextStep,
                  style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
                ),
              ],
              if (_errorRetryable) ...<Widget>[
                const SizedBox(height: CyTokens.space2),
                CupertinoButton.tinted(
                  key: const Key('club-ai-retry'),
                  minimumSize: const Size(44, 44),
                  onPressed: _generate,
                  child: Text(stringsOf(context).retry),
                ),
              ],
            ],
            if (_result != null) ...<Widget>[
              const SizedBox(height: CyTokens.space4),
              _ResultCard(result: _result!, onCopy: _copyPromo),
              if (_result!.merchantSuggestions.isNotEmpty)
                _Block(
                  stringsOf(context).clubAuxMerchantSuggestions,
                  _result!.merchantSuggestions
                      .map((String item) => '· $item')
                      .join('\n'),
                ),
              const SizedBox(height: CyTokens.space3),
              Text(
                stringsOf(context).clubAuxDraftOnly,
                style: textTheme.labelSmall?.copyWith(color: p.textTertiary),
              ),
              const SizedBox(height: CyTokens.space2),
              CupertinoButton(
                key: const Key('club-ai-adopt'),
                minimumSize: const Size.fromHeight(CyTokens.btnH),
                color: p.actionPrimaryBg,
                foregroundColor: p.actionPrimaryFg,
                borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                onPressed: _adopt,
                child: Text(stringsOf(context).clubAuxUsePlan),
              ),
              const SizedBox(height: CyTokens.space1),
              Text(
                stringsOf(context).clubAuxCompletePlanHint,
                style: textTheme.labelSmall?.copyWith(color: p.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.onCopy});

  final ClubAiDesign result;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final CyPalette palette = CyPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.bgSurface,
        border: Border.all(color: palette.borderSubtle),
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.all(CyTokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              result.titleIsFallback
                  ? stringsOf(context).clubAuxUnnamedPlan
                  : result.title,
              style: textTheme.titleLarge,
            ),
            if (result.subtitle != null) ...<Widget>[
              const SizedBox(height: CyTokens.space1),
              Text(result.subtitle!, style: textTheme.bodyMedium),
            ],
            if (result.tags.isNotEmpty ||
                result.estDurationMin != null) ...<Widget>[
              const SizedBox(height: CyTokens.space2),
              Wrap(
                spacing: CyTokens.space1,
                runSpacing: CyTokens.space1,
                children: <Widget>[
                  ...result.tags.map((String tag) => _ResultTag(tag)),
                  if (result.estDurationMin != null)
                    _ResultTag(stringsOf(context).clubAuxMinutes(result.estDurationMin!)),
                ],
              ),
            ],
            if (result.storyline != null) _Block(stringsOf(context).clubAuxStory, result.storyline!),
            if (result.fitReason != null)
              _Block(stringsOf(context).clubAuxFitReason, stringsOf(context).clubAuxFitReasonBody(result.fitReason!)),
            if (result.nodes.isNotEmpty) ...<Widget>[
              Text(
                stringsOf(context).clubAuxNodeCount(result.nodes.length),
                style: textTheme.labelLarge,
              ),
              const SizedBox(height: CyTokens.space1),
              ...result.nodes.map(
                (ClubAiNode node) => Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: CyTokens.space1,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(width: 28, child: Text('${node.order}')),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              node.fallbackNameNumber == null
                                  ? node.name
                                  : stringsOf(context).clubAuxFallbackNode(node.fallbackNameNumber!),
                              style: textTheme.titleSmall,
                            ),
                            if (node.address.isNotEmpty)
                              Text(
                                node.address,
                                style: textTheme.bodySmall?.copyWith(
                                  color: palette.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (result.risks.isNotEmpty)
              _Block(
                stringsOf(context).clubAuxRisks,
                result.risks.map((String item) => '· $item').join('\n'),
              ),
            if (result.promoCopy != null) ...<Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: Text(stringsOf(context).clubAuxPromoCopy, style: textTheme.labelLarge)),
                  CupertinoButton(
                    key: const Key('club-ai-copy'),
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: onCopy,
                    child: Text(stringsOf(context).clubAuxCopy),
                  ),
                ],
              ),
              SelectableText(result.promoCopy!, style: textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultTag extends StatelessWidget {
  const _ResultTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.bgSurfaceSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusPill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: palette.textSecondary),
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block(this.label, this.text);
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space3),
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
          SelectableText(text, style: textTheme.bodyMedium),
        ],
      ),
    );
  }
}
