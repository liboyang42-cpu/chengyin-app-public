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
  late CoopInviteForm _form;
  final _msgCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();
  bool _busy = false;
  bool get _hasPreset => widget.toId != null && widget.toId! > 0;

  @override
  void initState() {
    super.initState();
    final bool hasPreset = _hasPreset;
    _form = CoopInviteForm(
      topicId: widget.topicId,
      topicName: widget.topicName,
      type: widget.type,
      targets: hasPreset
          ? <CoopInviteTarget>[
              CoopInviteTarget(
                toId: widget.toId!,
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
              navigationBar: const CupertinoNavigationBar(
                middle: Text('选择我发布的主题'),
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
        ? _form.targets.first.name
        : '${_form.targets.first.name} 等 ${_form.targets.length} 个对象';
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
                middle: const Text('编辑邀约语'),
                leading: CupertinoButton(
                  minimumSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('取消'),
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
                    const Text('协作邀请'),
                    const SizedBox(height: CyTokens.space1),
                    Text(
                      _form.topicName == null
                          ? '关联主题 · #${_form.topicId}'
                          : '关联主题 · ${_form.topicName}',
                      style: Theme.of(sheetContext).textTheme.bodySmall
                          ?.copyWith(color: palette.textSecondary),
                    ),
                    const SizedBox(height: CyTokens.space3),
                    Text(
                      '对方会在「收到的」中确认本次协作。',
                      style: Theme.of(sheetContext).textTheme.bodySmall
                          ?.copyWith(color: palette.textSecondary),
                    ),
                    const SizedBox(height: CyTokens.space3),
                    CupertinoTextField(
                      key: const Key('coop-invite-message'),
                      controller: _msgCtrl,
                      placeholder: '写下想对对方说的话',
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
                      child: Text('发送邀约(${_form.targets.length})'),
                    ),
                  ],
                ),
              ),
            );
          },
    );
  }

  Future<void> _submit() async {
    if (!_form.canSubmit || _busy) return;
    setState(() => _busy = true);
    final api = ref.read(coopApiProvider);
    final ok = <String>[];
    final failed = <String, String>{};

    for (final CoopInviteTarget t in _form.targets) {
      try {
        await api.invite(_form, t);
        ok.add(t.name);
      } catch (e) {
        failed[t.name] = e.toString().replaceFirst('Exception: ', '');
      }
    }

    if (!mounted) return;
    setState(() => _busy = false);

    // ★ 逐个报结果。全成 / 全败 / 部分成功,三种说法各不相同。
    if (failed.isEmpty) {
      CyNativeNotice.show(context, '已发起 ${ok.length} 条，等待对方确认');
      Navigator.of(context).maybePop();
      return;
    }
    final detail = failed.entries
        .map((MapEntry<String, String> e) => '${e.key}:${e.value}')
        .join('\n');
    await cyConfirm(
      context,
      title: ok.isEmpty ? '邀约没有发出' : '部分邀约没发出',
      content: ok.isEmpty ? detail : '已成功:${ok.join('、')}\n\n未成功:\n$detail',
      confirmText: '知道了',
      showCancel: false,
    );
    // 已成功的从待发列表里去掉,用户重试时不会重复发送。
    if (ok.isNotEmpty && mounted) {
      setState(() {
        _form = _form.copyWith(
          targets: _form.targets
              .where((CoopInviteTarget t) => !ok.contains(t.name))
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
      navTitle: '发起协作邀请',
      message: '登录后发起协作邀请',
    );
    if (gate != null) return gate;
    final textTheme = Theme.of(context).textTheme;
    final blocker = _form.blocker;
    final AsyncValue<List<Topic>>? topics = _form.topicId == null
        ? ref.watch(coopInviteTopicsProvider)
        : null;
    final CyPalette palette = CyPalette.of(context);

    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(middle: Text('发起协作邀请')),
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
                    const CySectionTitle('① 关联主题'),
                    const SizedBox(height: CyTokens.space1),
                    if (_form.topicId != null)
                      Text(
                        _form.topicName ?? '主题 #${_form.topicId}',
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
                              '主题没加载出来',
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
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                        data: (List<Topic> rows) => rows.isEmpty
                            ? Text(
                                '还没有可关联的主题。先发布主题后再发起协作邀请。',
                                style: textTheme.bodySmall?.copyWith(
                                  color: palette.textSecondary,
                                ),
                              )
                            : Semantics(
                                button: true,
                                label: '选择我发布的主题',
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
                                  child: const Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          '选择我发布的主题',
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
                          ? '俱乐部同意后，可带成员参加该路线场次'
                          : '商家同意后，按下方条款承接主题合作',
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: CyTokens.space4),
                    const CySectionTitle('② 合作条款'),
                    const SizedBox(height: CyTokens.space2),
                    CupertinoSlidingSegmentedControl<CoopShareMode>(
                      groupValue: _form.shareMode,
                      children: <CoopShareMode, Widget>{
                        CoopShareMode.traffic: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('引流合作'),
                        ),
                        CoopShareMode.fixed: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            _form.type == CoopInviteType.club
                                ? '固定带队费'
                                : '按核销付费',
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
                                ? '/ 每核销 1 人'
                                : '/ 人',
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
                    const CySectionTitle('③ 邀请对象'),
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
                            Text('选择${_form.type.label}'),
                          ],
                        ),
                      ),
                    const SizedBox(height: CyTokens.space2),
                    if (_form.targets.isEmpty)
                      Text(
                        '还没选人。也可以从「附近商家」或「伙伴」里带过来。',
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
                                label: '已选 ${target.name}',
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
                                        child: Text(target.name),
                                      ),
                                      if (!_hasPreset)
                                        Semantics(
                                          button: true,
                                          label: '移除 ${target.name}',
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
                                '附近商家 · 含未入驻商家可电话联系',
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
                              : Text('发送邀约(${_form.targets.length})'),
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
