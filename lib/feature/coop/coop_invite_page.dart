import 'coop_strings.dart';
import '../../l10n/strings.dart';
import '../auth/auth_controller.dart';
import '../../core/network/request_session_scope.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../data/models/coop_invite.dart';
import '../../data/models/topic.dart';
import 'coop_target_picker.dart';
import '../../core/widgets/cy_native_notice.dart';
import 'coop_guard.dart';

/// 无 `topicId` 入口时只列当前登录人发布的主题。
/// 这与后端 `/invite` 的「只能为自己发布的主题」授权闸使用同一判据。
final coopInviteTopicsProvider = FutureProvider.autoDispose<List<Topic>>((
  Ref ref,
) {
  return ref.watch(topicApiProvider).list(isMy: 1, pageSize: 100);
});

/// 发起合作邀约。对齐小程序 `pages/coop/invite`。
///
/// ★ 后端一次只收一个受邀方,这里多选后**逐个提交并逐个记成败** ——
///   一个失败就把整批说成失败,用户会把已经发出去的又发一遍。
class CoopInvitePage extends ConsumerStatefulWidget {
  const CoopInvitePage({
    super.key,
    this.topicId,
    this.topicName,
    this.type = CoopInviteType.club,
    this.toId,
    this.toName,
    this.originApplyId,
    this.scope,
  });

  final int? topicId;
  final String? topicName;
  final CoopInviteType type;
  final int? toId;
  final String? toName;
  final int? originApplyId;

  /// 归属标记(`MERCHANT`)。商家员工代 owner 的主题发邀约时必须回传,
  /// 见 [CoopInviteForm.scope]。
  final String? scope;

  @override
  ConsumerState<CoopInvitePage> createState() => _CoopInvitePageState();
}

class _CoopInvitePageState extends ConsumerState<CoopInvitePage> {
  late final RequestSessionScope _requestScope;

  late CoopInviteForm _form;
  final _msgCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();
  bool _busy = false;
  bool get _hasPreset => widget.toId != null && widget.toId! > 0;

  @override
  void initState() {
    super.initState();
    _requestScope = ref.read(authControllerProvider.notifier).requestScope(
      ref.read(authControllerProvider).user?.id ?? 0,
    );
    final bool hasPreset = _hasPreset;
    _form = CoopInviteForm(
      topicId: widget.topicId,
      topicName: widget.topicName,
      type: widget.type,
      targets: hasPreset
          ? <CoopInviteTarget>[
              CoopInviteTarget(
                toId: widget.toId!,
                isLocalDefaultName: widget.toName?.trim().isNotEmpty != true,
                name: widget.toName?.trim().isNotEmpty == true
                    ? widget.toName!.trim()
                    : (widget.type == CoopInviteType.club ? '该俱乐部' : '该商家'),
              ),
            ]
          : const <CoopInviteTarget>[],
      originApplyId:
          widget.type == CoopInviteType.club &&
              hasPreset &&
              widget.originApplyId != null &&
              widget.originApplyId! > 0
          ? widget.originApplyId
          : null,
      scope: widget.scope,
    );
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _feeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTopic(List<Topic> topics) async {
    final int? selected = await showCupertinoSheet<int>(
      context: context,
      showDragHandle: true,
      topGap: 0.18,
      scrollableBuilder:
          (BuildContext sheetContext, ScrollController scrollController) {
            final CyPalette palette = CyPalette.of(sheetContext);
            return CupertinoPageScaffold(
              backgroundColor: palette.bgPage,
              navigationBar: CupertinoNavigationBar(
                middle: Text(stringsOf(context).coopChooseMyTheme),
              ),
              child: SafeArea(
                top: false,
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(
                    vertical: CyTokens.space2,
                  ),
                  itemCount: topics.length,
                  separatorBuilder: (_, _) => Container(
                    height: 1,
                    margin: const EdgeInsets.only(left: CyTokens.pageX),
                    color: CupertinoColors.separator.resolveFrom(context),
                  ),
                  itemBuilder: (BuildContext context, int index) {
                    final Topic topic = topics[index];
                    final bool isSelected = topic.id == _form.topicId;
                    return CupertinoButton(
                      minimumSize: const Size.fromHeight(52),
                      padding: const EdgeInsets.symmetric(
                        horizontal: CyTokens.pageX,
                        vertical: CyTokens.space2,
                      ),
                      alignment: Alignment.centerLeft,
                      onPressed: () => Navigator.of(sheetContext).pop(index),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              topic.name,
                              style: TextStyle(color: palette.textPrimary),
                            ),
                          ),
                          if (isSelected)
                            const Icon(CupertinoIcons.check_mark, size: 20),
                        ],
                      ),
                    );
                  },
                ),
              ),
            );
          },
    );
    if (selected == null || !mounted) return;
    final Topic topic = topics[selected];
    setState(
      () => _form = _form.copyWith(topicId: topic.id, topicName: topic.name),
    );
  }

  void _setShareMode(CoopShareMode? mode) {
    if (mode == null || mode == _form.shareMode) return;
    setState(() {
      _form = _form.copyWith(
        shareMode: mode,
        clearFixedFee: mode == CoopShareMode.traffic,
      );
      if (mode == CoopShareMode.traffic) _feeCtrl.clear();
    });
  }

  void _onFeeChanged(String raw) {
    final double? value = double.tryParse(raw.trim());
    setState(
      () => _form = _form.copyWith(
        fixedFee: value != null && value > 0 ? value : 0,
      ),
    );
  }

  Future<void> _openInviteSheet() async {
    if (!_form.canSubmit || _busy) return;
    final String targetText = _form.targets.length == 1
        ? coopTargetName(context, _form.targets.first, _form.type)
        : stringsOf(context).coopTargetsSummary(coopTargetName(context, _form.targets.first, _form.type), _form.targets.length);
    await showCupertinoSheet<void>(
      context: context,
      showDragHandle: true,
      topGap: 0.18,
      scrollableBuilder:
          (BuildContext sheetContext, ScrollController scrollController) {
            final CyPalette palette = CyPalette.of(sheetContext);
            return CupertinoPageScaffold(
              backgroundColor: palette.bgPage,
              navigationBar: CupertinoNavigationBar(
                middle: Text(stringsOf(context).coopEditMessage),
                leading: CupertinoButton(
                  minimumSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text(stringsOf(context).cancel),
                ),
              ),
              child: SafeArea(
                top: false,
                child: ListView(
                  controller: scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    CyTokens.pageX,
                    CyTokens.space4,
                    CyTokens.pageX,
                    MediaQuery.viewInsetsOf(sheetContext).bottom +
                        CyTokens.space4,
                  ),
                  children: <Widget>[
                    Text(
                      targetText,
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                    const SizedBox(height: CyTokens.space1),
                    Text(stringsOf(context).coopInvitation),
                    const SizedBox(height: CyTokens.space1),
                    Text(
                      _form.topicName == null
                          ? stringsOf(context).coopThemeReference('#${_form.topicId}')
                          : stringsOf(context).coopThemeReference(_form.topicName ?? ''),
                      style: Theme.of(sheetContext).textTheme.bodySmall
                          ?.copyWith(color: palette.textSecondary),
                    ),
                    const SizedBox(height: CyTokens.space3),
                    Text(
                      stringsOf(context).coopRecipientConfirms,
                      style: Theme.of(sheetContext).textTheme.bodySmall
                          ?.copyWith(color: palette.textSecondary),
                    ),
                    const SizedBox(height: CyTokens.space3),
                    CupertinoTextField(
                      key: const Key('coop-invite-message'),
                      controller: _msgCtrl,
                      placeholder: stringsOf(context).coopMessagePlaceholder,
                      maxLength: 100,
                      minLines: 4,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      autocorrect: true,
                      enableSuggestions: true,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: palette.bgSurface,
                        border: Border.all(color: palette.borderSubtle),
                        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                      ),
                      onChanged: (String value) =>
                          _form = _form.copyWith(message: value),
                    ),
                    const SizedBox(height: CyTokens.space4),
                    CupertinoButton.filled(
                      key: const Key('coop-confirm-invite'),
                      minimumSize: const Size.fromHeight(44),
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _submit();
                      },
                      child: Text(stringsOf(context).coopSendCount(_form.targets.length)),
                    ),
                  ],
                ),
              ),
            );
          },
    );
  }

  Future<void> _submit() => RequestSessionScope.run(
    _requestScope,
    () => _submitScoped(),
  );

  Future<void> _submitScoped() async {
    if (!_form.canSubmit || _busy) return;
    setState(() => _busy = true);
    final api = ref.read(coopApiProvider);
    final ok = <String>[];
    final completedIds = <int>{};
    final failed = <String, String>{};

    for (final CoopInviteTarget t in _form.targets) {
      try {
        await api.invite(_form, t);
        if (!mounted || !_requestScope.isCurrent()) return;
        completedIds.add(t.toId);
        ok.add(coopTargetName(context, t, _form.type));
      } catch (e) {
        if (!mounted || !_requestScope.isCurrent()) return;
        failed[coopTargetName(context, t, _form.type)] = coopErrorSub(e, context: context);
      }
    }

    if (!mounted) return;
    setState(() => _busy = false);

    // ★ 逐个报结果。全成 / 全败 / 部分成功,三种说法各不相同。
    if (failed.isEmpty) {
      CyNativeNotice.show(context, stringsOf(context).coopSentCount(ok.length));
      Navigator.of(context).maybePop();
      return;
    }
    final detail = failed.entries
        .map((MapEntry<String, String> e) => '${e.key}:${e.value}')
        .join('\n');
    await cyConfirm(
      context,
      title: ok.isEmpty ? stringsOf(context).coopInviteNotSent : stringsOf(context).coopSomeInvitesNotSent,
      content: ok.isEmpty ? detail : stringsOf(context).coopPartialSent(ok.join('、'), detail),
      confirmText: stringsOf(context).coopGotIt,
      showCancel: false,
    );
    // 已成功的从待发列表里去掉,用户重试时不会重复发送。
    if (ok.isNotEmpty && mounted) {
      setState(() {
        _form = _form.copyWith(
          targets: _form.targets
              .where((CoopInviteTarget t) => !completedIds.contains(t.toId))
              .toList(),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget? gate = coopLoginGate(
      context,
      ref,
      navTitle: stringsOf(context).coopNewInvitation,
      message: stringsOf(context).coopLoginNewInvitation,
    );
    if (gate != null) return gate;
    final textTheme = Theme.of(context).textTheme;
    final blocker = coopInviteBlocker(context, _form);
    final AsyncValue<List<Topic>>? topics = _form.topicId == null
        ? ref.watch(coopInviteTopicsProvider)
        : null;
    final CyPalette palette = CyPalette.of(context);

    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).coopNewInvitation)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(CyTokens.pageX),
                  children: <Widget>[
                    CySectionTitle(stringsOf(context).coopAssociatedTheme),
                    const SizedBox(height: CyTokens.space1),
                    if (_form.topicId != null)
                      Text(
                        _form.topicName ?? stringsOf(context).coopThemeNumber(_form.topicId.toString()),
                        style: textTheme.bodyMedium,
                      )
                    else
                      topics!.when(
                        loading: () => const Align(
                          alignment: Alignment.centerLeft,
                          child: CupertinoActivityIndicator(),
                        ),
                        error: (Object error, StackTrace _) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              stringsOf(context).coopThemeLoadFailed,
                              style: textTheme.bodySmall?.copyWith(
                                color: palette.statusWarning,
                              ),
                            ),
                            CupertinoButton.tinted(
                              minimumSize: const Size(44, 44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              onPressed: () =>
                                  ref.invalidate(coopInviteTopicsProvider),
                              child: Text(stringsOf(context).retry),
                            ),
                          ],
                        ),
                        data: (List<Topic> rows) => rows.isEmpty
                            ? Text(
                                stringsOf(context).coopPublishThemeFirst,
                                style: textTheme.bodySmall?.copyWith(
                                  color: palette.textSecondary,
                                ),
                              )
                            : Semantics(
                                button: true,
                                label: stringsOf(context).coopChooseMyTheme,
                                child: CupertinoButton(
                                  key: const Key('coop-pick-topic'),
                                  minimumSize: const Size.fromHeight(44),
                                  color: palette.bgSurface,
                                  foregroundColor: palette.textSecondary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  alignment: Alignment.centerLeft,
                                  onPressed: () => _pickTopic(rows),
                                  child: Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          stringsOf(context).coopChooseMyTheme,
                                          textAlign: TextAlign.left,
                                        ),
                                      ),
                                      Icon(
                                        CupertinoIcons.chevron_forward,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                    const SizedBox(height: CyTokens.space2),
                    Text(
                      _form.type == CoopInviteType.club
                          ? stringsOf(context).coopClubAcceptHint
                          : stringsOf(context).coopMerchantAcceptHint,
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: CyTokens.space4),
                    CySectionTitle(stringsOf(context).coopNumberedTerms),
                    const SizedBox(height: CyTokens.space2),
                    CupertinoSlidingSegmentedControl<CoopShareMode>(
                      groupValue: _form.shareMode,
                      children: <CoopShareMode, Widget>{
                        CoopShareMode.traffic: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(stringsOf(context).coopTrafficCooperation),
                        ),
                        CoopShareMode.fixed: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            _form.type == CoopInviteType.club
                                ? stringsOf(context).coopFixedLeaderFee
                                : stringsOf(context).coopPayPerRedemption,
                          ),
                        ),
                      },
                      onValueChanged: _setShareMode,
                    ),
                    if (_form.shareMode == CoopShareMode.fixed) ...<Widget>[
                      const SizedBox(height: CyTokens.space3),
                      CupertinoTextField(
                        key: const Key('coop-fixed-fee'),
                        controller: _feeCtrl,
                        placeholder: '0.00',
                        prefix: const Padding(
                          padding: EdgeInsets.only(left: 14),
                          child: Text('¥'),
                        ),
                        suffix: Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: Text(
                            _form.type == CoopInviteType.club
                                ? stringsOf(context).coopPerRedeemedPerson
                                : stringsOf(context).coopPerPerson,
                          ),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.done,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d{0,8}(?:\.\d{0,2})?$'),
                          ),
                        ],
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          color: palette.bgSurface,
                          border: Border.all(color: palette.borderSubtle),
                          borderRadius: BorderRadius.circular(
                            CyTokens.radiusMd,
                          ),
                        ),
                        onChanged: _onFeeChanged,
                      ),
                    ],
                    const SizedBox(height: CyTokens.space4),
                    CySectionTitle(stringsOf(context).coopRecipients),
                    const SizedBox(height: CyTokens.space3),
                    // ★ 页内选人。原来只写了一句「从别处选」——
                    //   于是这页自己**没有「选谁」这一步**,
                    //   两条目录接口(club/merchants、merchant/clubs)也零调用方。
                    if (!_hasPreset)
                      CupertinoButton.tinted(
                        key: const Key('coop-pick-targets'),
                        minimumSize: const Size.fromHeight(44),
                        padding: const EdgeInsets.symmetric(
                          horizontal: CyTokens.space3,
                          vertical: CyTokens.space2,
                        ),
                        onPressed: _busy
                            ? null
                            : () async {
                                final List<CoopInviteTarget>? added =
                                    await pickCoopTargets(
                                      context,
                                      type: _form.type,
                                      already: _form.targets,
                                    );
                                if (added == null ||
                                    added.isEmpty ||
                                    !mounted) {
                                  return;
                                }
                                setState(
                                  () => _form = _form.copyWith(
                                    targets: <CoopInviteTarget>[
                                      ..._form.targets,
                                      ...added,
                                    ],
                                  ),
                                );
                              },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            const Icon(CupertinoIcons.person_add, size: 18),
                            const SizedBox(width: CyTokens.space1),
                            Text(stringsOf(context).coopChooseType(coopInviteTypeLabel(context, _form.type))),
                          ],
                        ),
                      ),
                    const SizedBox(height: CyTokens.space2),
                    if (_form.targets.isEmpty)
                      Text(
                        stringsOf(context).coopNoRecipients,
                        style: textTheme.bodySmall?.copyWith(
                          color: CyPalette.of(context).textSecondary,
                        ),
                      )
                    else
                      Wrap(
                        spacing: CyTokens.space2,
                        runSpacing: CyTokens.space2,
                        children: _form.targets
                            .map(
                              (CoopInviteTarget target) => Semantics(
                                container: true,
                                selected: true,
                                label: stringsOf(context).coopSelectedName(coopTargetName(context, target, _form.type)),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: CyPalette.of(context).bgSurface,
                                    border: Border.all(
                                      color: CyPalette.of(context).borderSubtle,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      CyTokens.radiusPill,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: CyTokens.space3,
                                        ),
                                        child: Text(coopTargetName(context, target, _form.type)),
                                      ),
                                      if (!_hasPreset)
                                        Semantics(
                                          button: true,
                                          label: stringsOf(context).coopRemoveName(coopTargetName(context, target, _form.type)),
                                          child: CupertinoButton(
                                            key: Key(
                                              'coop-remove-target-${target.toId}',
                                            ),
                                            minimumSize: const Size(44, 44),
                                            padding: EdgeInsets.zero,
                                            onPressed: _busy
                                                ? null
                                                : () => setState(() {
                                                    _form = _form.copyWith(
                                                      targets: _form.targets
                                                          .where(
                                                            (
                                                              CoopInviteTarget
                                                              item,
                                                            ) =>
                                                                item.toId !=
                                                                target.toId,
                                                          )
                                                          .toList(),
                                                    );
                                                  }),
                                            child: const Icon(
                                              CupertinoIcons.xmark_circle_fill,
                                              size: 18,
                                            ),
                                          ),
                                        )
                                      else
                                        const Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: CyTokens.space3,
                                          ),
                                          child: Icon(
                                            CupertinoIcons
                                                .check_mark_circled_solid,
                                            size: 18,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    // 真源 invite/index.wxml:91 —— 只邀商家且没锁定时常驻一行,
                    // 选了人也在。goNearby 带当前主题过去(invite/index.js:386)。
                    if (_form.type == CoopInviteType.merchant && !_hasPreset)
                      CupertinoButton(
                        key: const Key('coop-invite-nearby'),
                        onPressed: _busy
                            ? null
                            : () => context.push(
                                Uri(
                                  path: '/coop/nearby',
                                  queryParameters: _form.topicId == null
                                      ? null
                                      : <String, String>{
                                          'topicId': '${_form.topicId}',
                                          if (_form.topicName != null)
                                            'topicName': _form.topicName!,
                                        },
                                ).toString(),
                              ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: CyTokens.space2,
                          vertical: CyTokens.space2,
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                stringsOf(context).coopNearbyContactHint,
                                style: textTheme.labelLarge?.copyWith(
                                  color: CyPalette.of(context).textSecondary,
                                ),
                              ),
                            ),
                            Icon(
                              CupertinoIcons.right_chevron,
                              size: 14,
                              color: CyPalette.of(context).textTertiary,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CyTokens.pageX,
                    CyTokens.space2,
                    CyTokens.pageX,
                    CyTokens.space3,
                  ),
                  child: Column(
                    children: <Widget>[
                      // 差什么就说什么。
                      if (blocker != null)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: CyTokens.space2,
                          ),
                          child: Text(
                            blocker,
                            style: textTheme.bodySmall?.copyWith(
                              color: palette.statusWarning,
                            ),
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: CupertinoButton.filled(
                          key: const Key('coop-send-invite'),
                          minimumSize: const Size.fromHeight(44),
                          onPressed: (!_form.canSubmit || _busy)
                              ? null
                              : _openInviteSheet,
                          child: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CupertinoActivityIndicator(),
                                )
                              : Text(stringsOf(context).coopSendCount(_form.targets.length)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
