// AI 起草主题的半屏 —— 对应小程序 pages/publish/simple 里那一段。
//
// ★ 起草**只填标题与简介**,不直接发布。
//   小程序那边草稿里的点位要用户逐个确认坐标才能进编辑器
//   (canEnterAiEditor,见 ai_draft_logic.dart)。App 的简易发布页
//   本来就只有名称+简介两项,所以这里把点位**如实列出来当参考**,
//   并写明它们还没有地点 —— 而不是假装点位已经建好了。
//
// ⚠️ 配额用完**不挡手动发布**:文案说「可以先手动填」,
//   把整页禁掉等于用一个附加功能废掉主功能。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../data/models/ai_quota.dart';
import 'ai_draft_logic.dart';
import '../../core/widgets/ai_generated_note.dart';

final aiQuotaProvider = FutureProvider.autoDispose<AiQuota>(
  (Ref ref) => ref.watch(aiCreatorApiProvider).quota(),
);

/// 起草结果保留点位和 traceId；快速配置页要求用户逐个确认地点后
/// 才能交给专业编辑器，不能在 Sheet 关闭时丢掉这些数据。
typedef AiDraftPick = ({
  String title,
  String description,
  List<AiDraftNode> nodes,
  String? traceId,
});

Future<AiDraftPick?> showAiDraftSheet(BuildContext context) =>
    showCupertinoSheet<AiDraftPick>(
      context: context,
      showDragHandle: true,
      topGap: 0.12,
      scrollableBuilder:
          (BuildContext context, ScrollController scrollController) =>
              _Sheet(scrollController: scrollController),
    );

class _Sheet extends ConsumerStatefulWidget {
  const _Sheet({required this.scrollController});

  final ScrollController scrollController;
  @override
  ConsumerState<_Sheet> createState() => _SheetState();
}

class _SheetState extends ConsumerState<_Sheet> {
  final TextEditingController _idea = TextEditingController();
  bool _busy = false;
  String? _error;
  AiDraft? _draft;

  @override
  void dispose() {
    _idea.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final String idea = _idea.text.trim();
    if (idea.isEmpty) {
      setState(() => _error = '先说说你想做什么路线。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> data = await ref
          .read(aiCreatorApiProvider)
          .themeDraft(idea);
      setState(() => _draft = parseAiDraft(data));
      // 后端顺带下发剩余次数时刷新配额显示。
      ref.invalidate(aiQuotaProvider);
    } on AiDraftError catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      // 后端原话优先 —— 它知道是内容安全还是配额还是模型没返好。
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final AiQuota quota = ref.watch(aiQuotaProvider).value ?? const AiQuota();
    final AiDraft? d = _draft;
    return CupertinoPageScaffold(
      backgroundColor: p.bgPage,
      resizeToAvoidBottomInset: true,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('AI 起草'),
        leading: CupertinoButton(
          key: const Key('ai-draft-cancel'),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          controller: widget.scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            CyTokens.space4,
            CyTokens.space3,
            CyTokens.space4,
            CyTokens.space5 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: <Widget>[
            const SizedBox(height: 4),
            Text(
              // ★ 这句不是免责套话,是 ai_draft_logic 那段逻辑的说明。
              'AI 只协助起草,地点与发布内容始终由你确认',
              key: const Key('ai-draft-disclaimer'),
              style: TextStyle(
                fontSize: CyTokens.typeCaption,
                color: p.textTertiary,
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            CupertinoTextField(
              controller: _idea,
              key: const Key('ai-idea-input'),
              maxLines: 3,
              minLines: 3,
              maxLength: 300,
              enabled: !_busy,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              placeholder: '描述你想做的路线',
              padding: const EdgeInsets.all(CyTokens.space3),
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: p.textPrimary),
              placeholderStyle: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: p.textPlaceholder),
              decoration: BoxDecoration(
                color: p.inputBgEmpty,
                borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                border: Border.all(color: p.borderSubtle),
              ),
            ),
            if (quota.remainingText != null ||
                quota.exhaustedHint != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                quota.exhaustedHint ?? quota.remainingText!,
                key: const Key('ai-quota-text'),
                style: TextStyle(
                  fontSize: CyTokens.typeCaption,
                  color: p.textTertiary,
                ),
              ),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: CyTokens.space2),
              Text(
                _error!,
                key: const Key('ai-draft-error'),
                style: TextStyle(
                  fontSize: CyTokens.typeCaption,
                  color: p.statusDanger,
                ),
              ),
            ],
            const SizedBox(height: CyTokens.space3),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: CupertinoButton(
                key: const Key('ai-generate'),
                minimumSize: const Size.fromHeight(44),
                color: p.actionPrimaryBg,
                disabledColor: p.bgSubtle,
                foregroundColor: _busy ? p.textPlaceholder : p.actionPrimaryFg,
                // ★ 配额用完时**按钮仍可点** —— 由后端把关并给出它的原话。
                //   客户端提前禁掉的话,配额判断错了用户连试都试不了。
                onPressed: _busy ? null : _generate,
                child: _busy
                    ? const CupertinoActivityIndicator()
                    : Text(d == null ? '生成草稿' : '换一版'),
              ),
            ),
            if (d != null) ...<Widget>[
              const Divider(height: CyTokens.space5),
              Text(
                'AI 为你整理的初稿',
                style: TextStyle(
                  fontSize: CyTokens.typeLabel,
                  color: p.textTertiary,
                ),
              ),
              // 合规:AI 生成内容来源标注(见 ai_generated_note.dart)。
              const AiGeneratedNote(),
              const SizedBox(height: CyTokens.space2),
              Text(
                d.title,
                key: const Key('ai-draft-title'),
                style: TextStyle(
                  fontSize: CyTokens.typeCardTitle,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                ),
              ),
              if (d.subtitle.isNotEmpty)
                Text(
                  d.subtitle,
                  style: TextStyle(
                    fontSize: CyTokens.typeCaption,
                    color: p.textSecondary,
                  ),
                ),
              if (d.storyline.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  d.storyline,
                  style: TextStyle(
                    fontSize: CyTokens.typeCaption,
                    color: p.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: CyTokens.space2),
              // ★ 点位**如实列出来当参考**,并说清它们还没有地点 ——
              //   不假装点位已经建好了。
              Text(
                'AI 想到的 ${d.nodes.length} 个点位(还没有地点,建路线时你来定)',
                key: const Key('ai-draft-nodes-note'),
                style: TextStyle(
                  fontSize: CyTokens.typeCaption,
                  color: p.textTertiary,
                ),
              ),
              for (final AiDraftNode n in d.nodes)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '· ${n.name}${n.description.isEmpty ? '' : ' —— ${n.description}'}',
                    style: TextStyle(
                      fontSize: CyTokens.typeCaption,
                      color: p.textSecondary,
                    ),
                  ),
                ),
              const SizedBox(height: CyTokens.space3),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: CupertinoButton.tinted(
                  key: const Key('ai-draft-use'),
                  minimumSize: const Size.fromHeight(44),
                  onPressed: () => Navigator.of(context).pop((
                    title: d.title,
                    description: <String>[
                      if (d.subtitle.isNotEmpty) d.subtitle,
                      if (d.storyline.isNotEmpty) d.storyline,
                    ].join('\n'),
                    nodes: d.nodes,
                    traceId: d.traceId,
                  )),
                  child: const Text('填进表单(可继续编辑)'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
