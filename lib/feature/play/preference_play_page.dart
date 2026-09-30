import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/play_api.dart';
import '../../data/models/preference_play.dart';
import 'play_session_controller.dart';

class PreferencePlayPage extends ConsumerStatefulWidget {
  const PreferencePlayPage({
    super.key,
    required this.sessionKey,
    required this.nodeId,
  });

  final PlaySessionKey sessionKey;
  final int nodeId;

  @override
  ConsumerState<PreferencePlayPage> createState() => _PreferencePlayPageState();
}

class _PreferencePlayPageState extends ConsumerState<PreferencePlayPage> {
  bool _loading = true;
  bool _submitting = false;
  String? _loadError;
  String? _answerError;
  List<PreferenceStep> _steps = const <PreferenceStep>[];
  List<PreferenceInheritedTag> _inheritedTags =
      const <PreferenceInheritedTag>[];
  final Map<String, String> _choices = <String, String>{};
  int _stepIndex = 0;
  int? _selectedInheritedTagId;
  bool _answerHere = false;
  PreferenceSubmission? _completed;
  PreferenceInheritedTag? _pendingTag;
  bool _tagWriting = false;
  String? _tagError;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final PreferenceQuestionnaire questionnaire = await ref
          .read(playSessionProvider(widget.sessionKey).notifier)
          .preference(widget.nodeId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _steps = questionnaire.nodeId == widget.nodeId
            ? questionnaire.steps
            : const <PreferenceStep>[];
        _inheritedTags = questionnaire.nodeId == widget.nodeId
            ? questionnaire.inheritedTags
            : const <PreferenceInheritedTag>[];
        if (_steps.isEmpty && _inheritedTags.isEmpty) {
          _loadError = '偏好题暂无可用题目，请联系活动方';
        }
      });
    } on PlayException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '偏好题暂时没加载出来';
      });
    }
  }

  void _select(PreferenceStep step, PreferenceOption option) {
    if (_submitting) return;
    setState(() {
      _choices[step.key] = option.key;
      _answerError = null;
    });
  }

  Future<void> _advance() async {
    if (_submitting || _steps.isEmpty) return;
    final PreferenceStep step = _steps[_stepIndex];
    if (!_choices.containsKey(step.key)) {
      setState(() => _answerError = '请选择一个答案');
      return;
    }
    if (_stepIndex < _steps.length - 1) {
      setState(() {
        _stepIndex += 1;
        _answerError = null;
      });
      return;
    }

    await _submitPreference();
  }

  Future<void> _submitPreference({String? reuseTagCode}) async {
    setState(() {
      _submitting = true;
      _answerError = null;
    });
    try {
      final PreferenceSubmission submission = await ref
          .read(playSessionProvider(widget.sessionKey).notifier)
          .submitPreference(
            widget.nodeId,
            reuseTagCode == null ? _choices : const <String, String>{},
            reuseTagCode: reuseTagCode,
          );
      if (!mounted) return;
      if (submission.needsTiebreak) {
        final PreferenceStep tiebreak = submission.tiebreak!;
        setState(() {
          _answerHere = true;
          if (!_steps.any((PreferenceStep item) => item.key == tiebreak.key)) {
            _steps = <PreferenceStep>[..._steps, tiebreak];
          }
          _stepIndex = _steps.indexWhere(
            (PreferenceStep item) => item.key == tiebreak.key,
          );
        });
      } else {
        setState(() {
          _completed = submission;
          _pendingTag = submission.pendingTag;
        });
      }
    } on PlayException catch (error) {
      if (mounted) setState(() => _answerError = error.message);
    } on DioException {
      if (mounted) setState(() => _answerError = '网络连接失败，请重试');
    } catch (_) {
      if (mounted) setState(() => _answerError = '结果没有生成，请重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmInheritedTag() async {
    final PreferenceInheritedTag? selected = _inheritedTags
        .where(
          (PreferenceInheritedTag tag) => tag.id == _selectedInheritedTagId,
        )
        .firstOrNull;
    if (selected == null || _submitting) return;
    final bool confirmed = await cyConfirm(
      context,
      title: '确认沿用这个条件？',
      content:
          '沿用 ${selected.tagCode} · ${selected.tagValue} 后，本次将不再回答现场题组，直接生成本站建议。',
      confirmText: '确认沿用',
    );
    if (confirmed && mounted) {
      await _submitPreference(reuseTagCode: selected.tagCode);
    }
  }

  Future<void> _confirmPendingTag() async {
    final PreferenceInheritedTag? tag = _pendingTag;
    if (tag == null || _tagWriting || tag.status == 1) return;
    setState(() {
      _tagWriting = true;
      _tagError = null;
    });
    try {
      final PreferenceInheritedTag confirmed = await ref
          .read(playSessionProvider(widget.sessionKey).notifier)
          .confirmPreferenceTag(tag.id);
      if (mounted) setState(() => _pendingTag = confirmed);
    } on PlayException catch (error) {
      if (mounted) setState(() => _tagError = error.message);
    } catch (_) {
      if (mounted) setState(() => _tagError = '标签没有确认成功');
    } finally {
      if (mounted) setState(() => _tagWriting = false);
    }
  }

  Future<void> _correctPendingTag() async {
    final PreferenceInheritedTag? tag = _pendingTag;
    final List<String> values = _completed?.availableTagValues ?? const [];
    if (tag == null || _tagWriting || values.length < 2) return;
    final String? value = await showCupertinoModalPopup<String>(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        // 真源 cy-option-sheet 标题(index.wxml:1864):问的是改哪个结果。
        title: const Text('改成哪个结果'),
        actions: values
            .map(
              (String value) => CupertinoActionSheetAction(
                onPressed: () => Navigator.of(context).pop(value),
                child: Text(value),
              ),
            )
            .toList(growable: false),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    if (value == null || value == tag.tagValue || !mounted) return;
    setState(() {
      _tagWriting = true;
      _tagError = null;
    });
    try {
      final PreferenceInheritedTag corrected = await ref
          .read(playSessionProvider(widget.sessionKey).notifier)
          .correctPreferenceTag(tag.id, value);
      if (mounted) setState(() => _pendingTag = corrected);
    } on PlayException catch (error) {
      if (mounted) setState(() => _tagError = error.message);
    } catch (_) {
      if (mounted) setState(() => _tagError = '标签档位没有改成功');
    } finally {
      if (mounted) setState(() => _tagWriting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AppColors.bgDeep,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: AppColors.bgDeep,
        border: null,
        middle: const Text('偏好题组'),
        leading: CupertinoButton(
          minimumSize: const Size(CyTokens.btnH, CyTokens.btnH),
          padding: EdgeInsets.zero,
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Icon(CupertinoIcons.xmark, semanticLabel: '关闭偏好题组'),
        ),
      ),
      child: SafeArea(
        child: _loading
            ? Semantics(
                label: '正在加载偏好题组',
                liveRegion: true,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      CupertinoActivityIndicator(),
                      SizedBox(height: CyTokens.space2),
                      // 小程序 `pages/play/index.wxml:1028` 的 .pref-load 原句。
                      Text('正在校准本站题组…'),
                    ],
                  ),
                ),
              )
            : _loadError != null
            ? StatusView(
                icon: CupertinoIcons.exclamationmark_circle,
                message: _loadError!,
                retryLabel: '重试',
                onRetry: _load,
              )
            : _completed != null
            ? _PreferenceResultView(
                submission: _completed!,
                pendingTag: _pendingTag,
                tagWriting: _tagWriting,
                tagError: _tagError,
                onCorrectTag: _correctPendingTag,
                onConfirmTag: _confirmPendingTag,
                onSkipTag: () => setState(() => _pendingTag = null),
                onDone: () => Navigator.of(context).pop(_completed),
              )
            : _inheritedTags.isNotEmpty && !_answerHere
            ? _inheritanceView()
            : _questionView(),
      ),
    );
  }

  Widget _inheritanceView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space4,
        CyTokens.pageX,
        CyTokens.space4,
      ),
      children: <Widget>[
        const Text(
          '上一站已经问过',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: CyTokens.typeLabel,
          ),
        ),
        const SizedBox(height: CyTokens.space2),
        const Text(
          '沿用你确认过的条件',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: CyTokens.typeSectionTitle,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: CyTokens.space2),
        const Text(
          '选择一个已确认标签并再次确认，可跳过本站题目；也可以现场重新作答。',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: CyTokens.typeBody,
          ),
        ),
        const SizedBox(height: CyTokens.space4),
        ..._inheritedTags.map((PreferenceInheritedTag tag) {
          final bool selected = tag.id == _selectedInheritedTagId;
          final String label = '${tag.tagCode} · ${tag.tagValue}';
          return Padding(
            padding: const EdgeInsets.only(bottom: CyTokens.space2),
            child: _PreferenceSelectableCard(
              semanticsKey: Key('preference-inherited-tag-${tag.id}'),
              label: label,
              selected: selected,
              onPressed: _submitting
                  ? null
                  : () => setState(() {
                      _selectedInheritedTagId = tag.id;
                      _answerError = null;
                    }),
            ),
          );
        }),
        if (_answerError != null) ...<Widget>[
          Text(
            _answerError!,
            style: const TextStyle(
              color: AppColors.danger,
              fontSize: CyTokens.typeLabel,
            ),
          ),
          const SizedBox(height: CyTokens.space2),
        ],
        const SizedBox(height: CyTokens.space2),
        CyNativeButton(
          label: _submitting ? '正在生成' : '确认沿用，生成本站建议',
          loading: _submitting,
          onPressed: _submitting || _selectedInheritedTagId == null
              ? null
              : _confirmInheritedTag,
        ),
        CupertinoButton(
          minimumSize: const Size(CyTokens.btnH, CyTokens.btnH),
          onPressed: _submitting || _steps.isEmpty
              ? null
              : () => setState(() {
                  _answerHere = true;
                  _answerError = null;
                }),
          // 小程序 .pref-inherit__again 原句(「情况变了」是这句话的重点:不说
          // 为什么给这条路,玩家会以为重复问是 bug)。
          child: const Text('情况变了，现场重新答'),
        ),
      ],
    );
  }

  Widget _questionView() {
    final PreferenceStep step = _steps[_stepIndex];
    final String? selectedKey = _choices[step.key];
    final bool isLast = _stepIndex == _steps.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space4,
        CyTokens.pageX,
        CyTokens.space4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '第 ${_stepIndex + 1} / ${_steps.length} 题',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: CyTokens.typeLabel,
            ),
          ),
          const SizedBox(height: CyTokens.space2),
          Text(
            step.title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: CyTokens.typeSectionTitle,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CyTokens.space4),
          Expanded(
            child: ListView.separated(
              itemCount: step.options.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: CyTokens.space2),
              itemBuilder: (BuildContext context, int index) {
                final PreferenceOption option = step.options[index];
                final bool selected = selectedKey == option.key;
                return _PreferenceSelectableCard(
                  semanticsKey: Key(
                    'preference-option-${step.key}-${option.key}',
                  ),
                  label: option.text,
                  selected: selected,
                  onPressed: _submitting ? null : () => _select(step, option),
                );
              },
            ),
          ),
          if (_answerError != null) ...<Widget>[
            Semantics(
              liveRegion: true,
              child: Text(
                _answerError!,
                key: const Key('preference-error'),
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: CyTokens.typeLabel,
                ),
              ),
            ),
            const SizedBox(height: CyTokens.space2),
          ],
          Row(
            children: <Widget>[
              if (_stepIndex > 0) ...<Widget>[
                CupertinoButton(
                  minimumSize: const Size(CyTokens.btnH, CyTokens.btnH),
                  onPressed: _submitting
                      ? null
                      : () => setState(() {
                          _stepIndex -= 1;
                          _answerError = null;
                        }),
                  child: const Text('上一题'),
                ),
                const SizedBox(width: CyTokens.space2),
              ],
              Expanded(
                child: CyNativeButton(
                  label: _submitting
                      ? '正在生成'
                      : isLast
                      ? '生成我的结果'
                      : '下一题',
                  loading: _submitting,
                  onPressed: _submitting ? null : _advance,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreferenceSelectableCard extends StatelessWidget {
  const _PreferenceSelectableCard({
    required this.semanticsKey,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final Key semanticsKey;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: semanticsKey,
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: CupertinoButton(
          minimumSize: const Size(CyTokens.btnH, CyTokens.btnH),
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: CyTokens.btnH),
            padding: const EdgeInsets.symmetric(
              horizontal: CyTokens.space3,
              vertical: CyTokens.space2,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? CyTokens.actionSecondaryBg
                  : AppColors.bgSurface,
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              border: Border.all(
                color: selected ? AppColors.textPrimary : AppColors.divider,
              ),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: CyTokens.typeBody,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(
                    CupertinoIcons.check_mark_circled_solid,
                    color: AppColors.textPrimary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreferenceResultView extends StatelessWidget {
  const _PreferenceResultView({
    required this.submission,
    required this.pendingTag,
    required this.tagWriting,
    required this.tagError,
    required this.onCorrectTag,
    required this.onConfirmTag,
    required this.onSkipTag,
    required this.onDone,
  });

  final PreferenceSubmission submission;
  final PreferenceInheritedTag? pendingTag;
  final bool tagWriting;
  final String? tagError;
  final VoidCallback onCorrectTag;
  final VoidCallback onConfirmTag;
  final VoidCallback onSkipTag;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final PreferenceEvaluation evaluation = submission.evaluation!;
    final progress = submission.progress!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space5,
        CyTokens.pageX,
        CyTokens.space4,
      ),
      children: <Widget>[
        Semantics(
          key: const Key('preference-result-icon'),
          label: '偏好结果已生成',
          image: true,
          child: const ExcludeSemantics(
            child: Icon(
              CupertinoIcons.check_mark_circled_solid,
              color: AppColors.success,
              size: CyTokens.space6,
            ),
          ),
        ),
        const SizedBox(height: CyTokens.space3),
        Text(
          evaluation.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: CyTokens.typeSectionTitle,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: CyTokens.space3),
        Text(
          evaluation.body,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: CyTokens.typeBody,
            height: CyTokens.leadingLoose,
          ),
        ),
        if (evaluation.nextStep.isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space4),
          Container(
            padding: const EdgeInsets.all(CyTokens.space3),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              border: Border.all(color: AppColors.divider),
            ),
            child: Text(
              evaluation.nextStep,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: CyTokens.typeBody,
              ),
            ),
          ),
        ],
        if (progress.xpAwarded > 0) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          Text(
            '+${progress.xpAwarded} 探索值',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.success,
              fontSize: CyTokens.typeButton,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (progress.completed) ...<Widget>[
          const SizedBox(height: CyTokens.space2),
          const Text(
            '主题已完成',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: CyTokens.typeLabel,
            ),
          ),
        ],
        if (pendingTag != null) ...<Widget>[
          const SizedBox(height: CyTokens.space4),
          _PreferenceTagConsent(
            tag: pendingTag!,
            disclosure: submission.tagDisclosure,
            availableValues: submission.availableTagValues,
            writing: tagWriting,
            error: tagError,
            onCorrect: onCorrectTag,
            onConfirm: onConfirmTag,
            onSkip: onSkipTag,
          ),
        ],
        const SizedBox(height: CyTokens.space5),
        // 真源 gp2 CTA(index.wxml:982):结果页那一下是**收下建议**,
        // 不是泛泛的「完成」。
        CyNativeButton(label: '收下本站建议', onPressed: onDone),
      ],
    );
  }
}

class _PreferenceTagConsent extends StatelessWidget {
  const _PreferenceTagConsent({
    required this.tag,
    required this.disclosure,
    required this.availableValues,
    required this.writing,
    required this.error,
    required this.onCorrect,
    required this.onConfirm,
    required this.onSkip,
  });

  final PreferenceInheritedTag tag;
  final PreferenceTagDisclosure? disclosure;
  final List<String> availableValues;
  final bool writing;
  final String? error;
  final VoidCallback onCorrect;
  final VoidCallback onConfirm;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final bool confirmed = tag.status == 1;
    return Container(
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            '保存为我的主题标签?',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: CyTokens.typeBody,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CyTokens.space2),
          Text(
            '${tag.tagCode} · ${tag.tagValue}',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: CyTokens.typeBody,
            ),
          ),
          if (disclosure != null) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Text(
              disclosure!.purpose,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: CyTokens.typeLabel,
              ),
            ),
            Text(
              '传给：${disclosure!.recipientLabel}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: CyTokens.typeLabel,
              ),
            ),
            if (disclosure!.revocable)
              const Text(
                '保存后仍可在完局页随时撤回。',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: CyTokens.typeLabel,
                ),
              ),
          ],
          if (disclosure == null) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            const Text(
              '标签用途说明不可用，暂不保存',
              style: TextStyle(
                color: AppColors.danger,
                fontSize: CyTokens.typeLabel,
              ),
            ),
          ],
          if (disclosure != null && availableValues.length > 1 && !confirmed)
            CupertinoButton(
              minimumSize: const Size(CyTokens.btnH, CyTokens.btnH),
              padding: EdgeInsets.zero,
              onPressed: writing ? null : onCorrect,
              // 小程序 pref-consent__correct 原句(同一条判据:只在一档以上时出现)。
              child: const Text('结果不准？改一下标签档位'),
            ),
          if (error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                error!,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: CyTokens.typeLabel,
                ),
              ),
            ),
          Row(
            children: <Widget>[
              if (!confirmed)
                Expanded(
                  child: CupertinoButton(
                    minimumSize: const Size(CyTokens.btnH, CyTokens.btnH),
                    onPressed: writing ? null : onSkip,
                    child: const Text('先不保存'),
                  ),
                ),
              if (disclosure != null)
                Expanded(
                  child: CupertinoButton(
                    minimumSize: const Size(CyTokens.btnH, CyTokens.btnH),
                    onPressed: writing || confirmed ? null : onConfirm,
                    child: Text(confirmed ? '已确认' : '确认保存'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
