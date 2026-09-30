import '../../core/theme/cy_palette.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_swipe_actions.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_system_date_picker.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/coop_perk_template.dart';
import '../../core/widgets/cy_native_notice.dart';
import 'coop_guard.dart';

final coopPerkTemplatesProvider =
    FutureProvider.autoDispose<List<CoopPerkTemplate>>((ref) async {
      final rows = await ref.watch(coopApiProvider).perkTemplates();
      return rows.map(CoopPerkTemplate.fromJson).toList();
    });

/// 常备权益模板。对齐小程序 `pages/merchant/decor/perks`。
///
/// ★ 「已保存」不等于「已生效」——模板本身随时生效,但**申报到某次合作**
///   才会真正挂到那次合作上;这里的「保存」措辞只指模板本身。
/// ★ 后端只新增不更新,这里没有编辑入口,只有新增/删除。
class CoopPerkTemplatePage extends ConsumerWidget {
  const CoopPerkTemplatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const String title = '常备权益';
    const String needLogin = '登录后查看常备权益';
    final Widget? gate = coopLoginGate(
      context,
      ref,
      navTitle: title,
      message: needLogin,
    );
    if (gate != null) return gate;
    final async = ref.watch(coopPerkTemplatesProvider);
    return CupertinoPageScaffold(
      // 显式给浅色底:根 CupertinoTheme 恒暗、Material `Theme` 换不动它,
      // 不传的话这里就是黑底配浅色盘的黑字(见 coop_guard.dart)。
      backgroundColor: CyPalette.of(context).bgPage,
      navigationBar: const CupertinoNavigationBar(middle: Text(title)),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: async.when(
              loading: () => const Center(child: CupertinoActivityIndicator()),
              error: (Object e, _) => isCoopUnauthorized(e)
                  ? coopLoginStatus(
                      context,
                      ref,
                      message: needLogin,
                      refetch: () => ref.invalidate(coopPerkTemplatesProvider),
                    )
                  : StatusView(
                      // 照小程序真源原文(pages/merchant/decor/perks 的
                      // cy-error title),换措辞会让 copy_parity 掉一格。
                      message: '权益加载失败',
                      sub: coopErrorSub(e),
                      large: true,
                      onRetry: () => ref.invalidate(coopPerkTemplatesProvider),
                    ),
              data: (List<CoopPerkTemplate> perks) {
                if (perks.isEmpty) {
                  return const StatusView(
                    message: '还没有常备权益',
                    sub: '把可核销的礼品、优惠券或折扣整理成清单',
                    large: true,
                  );
                }
                return _PerkList(perks: perks);
              },
            ),
          ),
          // 列表没加载出来时不露「＋添加权益」:这一刻用户不知道已有清单长什么样,
          // 点进去只会加重复项(b1 报告 P2-4)。
          if (!async.hasError)
            PositionedDirectional(
              end: CyTokens.pageX,
              bottom: CyTokens.pageX,
              child: SafeArea(
                minimum: const EdgeInsets.only(bottom: CyTokens.space2),
                child: CyNativeButton(
                  onPressed: () => showCupertinoSheet<void>(
                    context: context,
                    showDragHandle: true,
                    topGap: 0.12,
                    scrollableBuilder:
                        (
                          BuildContext context,
                          ScrollController scrollController,
                        ) => _PerkFormSheet(scrollController: scrollController),
                  ),
                  label: '添加权益',
                  icon: const CyNativeButtonIcon(
                    sfSymbol: 'plus',
                    fallback: CupertinoIcons.add,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PerkList extends ConsumerStatefulWidget {
  const _PerkList({required this.perks});
  final List<CoopPerkTemplate> perks;

  @override
  ConsumerState<_PerkList> createState() => _PerkListState();
}

class _PerkListState extends ConsumerState<_PerkList> {
  /// 同一时刻只允许开一行(iOS 行为),由列表持有。
  Object? _openRow;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator.adaptive(
      onRefresh: () async => ref.invalidate(coopPerkTemplatesProvider),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          CyTokens.pageX,
          CyTokens.pageX,
          CyTokens.pageX,
          96,
        ),
        itemCount: widget.perks.length,
        // 卡间距挪到行外:留在行内会被算进「行高」,左滑钮的垂直中心
        // 就比卡片中心高出一截(钮浮在页底上,对齐的是行,不是卡)。
        separatorBuilder: (_, _) => const SizedBox(height: CyTokens.space3),
        itemBuilder: (_, int i) => _PerkCard(
          perk: widget.perks[i],
          openKey: _openRow,
          onOpenChanged: (Object? opened) => setState(() => _openRow = opened),
        ),
      ),
    );
  }
}

class _PerkCard extends ConsumerStatefulWidget {
  const _PerkCard({
    required this.perk,
    required this.openKey,
    required this.onOpenChanged,
  });
  final CoopPerkTemplate perk;
  final Object? openKey;
  final ValueChanged<Object?> onOpenChanged;

  @override
  ConsumerState<_PerkCard> createState() => _PerkCardState();
}

class _PerkCardState extends ConsumerState<_PerkCard> {
  bool _busy = false;

  Future<void> _delete() async {
    // ⚠️ 拿不到"删除后已挂载的合作是否受影响"这句话的后端确认,就不编影响面,
    //   只说清删的是模板本身、已经申报出去的供给独立存快照。
    final bool ok = await cyConfirm(
      context,
      title: '删除「${widget.perk.name}」?',
      content: '删除的是这个模板本身;已经申报到具体合作里的供给是独立记录,不会跟着变。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(coopApiProvider).deletePerkTemplate(widget.perk.id);
      ref.invalidate(coopPerkTemplatesProvider);
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.perk;
    final textTheme = Theme.of(context).textTheme;
    final meta = <String>[
      if (p.retailValue != null) '零售价 ¥${p.retailValue!.toStringAsFixed(2)}',
      if (p.unitCost != null) '成本 ¥${p.unitCost!.toStringAsFixed(2)}',
      // quota 是 0 和没填是两回事:没填不提;真是 0 就照实说 0 份。
      if (p.quota != null) '可接待 ${p.quota} 份',
      if (p.validText != null) '至 ${p.validText}',
    ];
    return CySwipeActionsRow(
      key: Key('coop-perk-row-${p.id}'),
      rowKey: p.id,
      openKey: widget.openKey,
      onOpenChanged: widget.onOpenChanged,
      enabled: !_busy,
      // 行内单删按钮收进左滑(#382 P0「我的内容列表左滑操作」rollout);
      // 动作/接口/cyConfirm 二次确认的既有语义一条没动 —— 组件默认
      // 「划到底不执行、必须点一下」,和原来的确认闸是叠加不是替换。
      trailing: <CyContextualAction>[
        CyContextualAction(
          id: 'coop-perk-delete-${p.id}',
          label: '删除',
          // VoiceOver 文案逐字沿用旧行内钮「删除 {名称}」,删的是哪条要自解释。
          semanticLabel: '删除 ${p.name}',
          icon: CupertinoIcons.delete,
          destructive: true,
          isEnabled: !_busy,
          onPressed: _delete,
        ),
      ],
      child: Container(
        padding: const EdgeInsets.all(CyTokens.space3),
        decoration: BoxDecoration(
          color: CyPalette.of(context).bgSurface,
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          border: Border.all(color: CyPalette.of(context).borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(p.name, style: textTheme.titleMedium)),
                const SizedBox(width: CyTokens.space2),
                // ★ 「需删除重建」是内部术语,商家看不懂 —— 说清后果:这条已经
                //   不满足申报门槛了,选不了。
                CyTag(label: p.usable ? p.typeText : '已失效 · 请重新添加'),
              ],
            ),
            if (meta.isNotEmpty) ...<Widget>[
              const SizedBox(height: CyTokens.space1),
              Text(
                meta.join(' · '),
                style: textTheme.bodySmall?.copyWith(
                  color: CyPalette.of(context).textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PerkFormSheet extends ConsumerStatefulWidget {
  const _PerkFormSheet({required this.scrollController});

  final ScrollController scrollController;

  @override
  ConsumerState<_PerkFormSheet> createState() => _PerkFormSheetState();
}

class _PerkFormSheetState extends ConsumerState<_PerkFormSheet> {
  int _perkType = 0;
  final _nameCtrl = TextEditingController();
  final _retailCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _quotaCtrl = TextEditingController();
  DateTime? _validEnd;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _retailCtrl.dispose();
    _costCtrl.dispose();
    _quotaCtrl.dispose();
    super.dispose();
  }

  // 与后端五道校验闸逐条对齐(ApiCoopController.perkTemplateSave),
  // 原话作为提示,省一次往返。
  String? _validate() {
    if (_nameCtrl.text.trim().isEmpty) return '请填写权益名称';
    final retailText = _retailCtrl.text.trim();
    final retail = double.tryParse(retailText);
    if (!_amountPattern.hasMatch(retailText) ||
        retail == null ||
        retail <= 0 ||
        retail > 99999999.99) {
      return '权益零售价须为不超过99999999.99的正数,最多两位小数';
    }
    if (_costCtrl.text.trim().isNotEmpty) {
      final costText = _costCtrl.text.trim();
      final cost = double.tryParse(costText);
      if (!_amountPattern.hasMatch(costText) ||
          cost == null ||
          cost < 0 ||
          cost > 99999999.99) {
        return '成本价须为0至99999999.99,最多两位小数';
      }
    }
    final quota = int.tryParse(_quotaCtrl.text.trim());
    if (quota == null || quota <= 0) return '请填写正整数可接待份数';
    return null;
  }

  static final RegExp _amountPattern = RegExp(r'^\d{1,8}(\.\d{1,2})?$');

  Future<void> _save() async {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(coopApiProvider).savePerkTemplate(<String, dynamic>{
        'perkType': _perkType,
        'name': _nameCtrl.text.trim(),
        'retailValue': double.parse(_retailCtrl.text.trim()),
        if (_costCtrl.text.trim().isNotEmpty)
          'unitCost': double.parse(_costCtrl.text.trim()),
        'quota': int.parse(_quotaCtrl.text.trim()),
        'validEnd': _validEnd == null ? null : _formatDate(_validEnd!),
      });
      ref.invalidate(coopPerkTemplatesProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _saving = false;
      });
      return;
    }
  }

  Future<void> _pickValidEnd() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showCySystemDatePicker(
      context: context,
      mode: CupertinoDatePickerMode.date,
      initialDateTime: _validEnd ?? today,
      minimumDate: today,
      maximumDate: DateTime(today.year + 10, today.month, today.day),
      title: '选择有效期',
    );
    if (picked != null && mounted) setState(() => _validEnd = picked);
  }

  static String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required String placeholder,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final palette = CyPalette.of(context);
    return CupertinoTextField(
      key: key,
      controller: controller,
      placeholder: placeholder,
      onChanged: (_) => setState(() => _error = null),
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      minLines: 1,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: palette.bgSurface,
        border: Border.all(color: palette.borderSubtle),
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('添加常备权益'),
        leading: CupertinoButton(
          key: const Key('coop-perk-cancel'),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          controller: widget.scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space4,
            CyTokens.pageX,
            MediaQuery.viewInsetsOf(context).bottom + CyTokens.space4,
          ),
          children: <Widget>[
            CupertinoSlidingSegmentedControl<int>(
              groupValue: _perkType,
              children: <int, Widget>{
                for (int i = 0; i < CoopPerkTemplate.typeLabels.length; i++)
                  i: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(CoopPerkTemplate.typeLabels[i]),
                  ),
              },
              onValueChanged: (int? value) {
                if (value != null) setState(() => _perkType = value);
              },
            ),
            const SizedBox(height: CyTokens.space3),
            _field(
              key: const Key('coop-perk-name'),
              controller: _nameCtrl,
              placeholder: '权益名称（必填）',
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: CyTokens.space2),
            _field(
              key: const Key('coop-perk-retail'),
              controller: _retailCtrl,
              placeholder: '权益零售价（必填）',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: CyTokens.space2),
            _field(
              key: const Key('coop-perk-cost'),
              controller: _costCtrl,
              placeholder: '成本价（可选，仅自己可见）',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: CyTokens.space2),
            _field(
              key: const Key('coop-perk-quota'),
              controller: _quotaCtrl,
              placeholder: '可接待份数（必填）',
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
            ),
            const SizedBox(height: CyTokens.space2),
            Semantics(
              button: true,
              label: _validEnd == null
                  ? '选择有效期，可选'
                  : '有效期 ${_formatDate(_validEnd!)}',
              child: CupertinoButton(
                key: const Key('coop-perk-valid-end'),
                minimumSize: const Size.fromHeight(44),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                color: palette.bgSurface,
                foregroundColor: _validEnd == null
                    ? palette.textSecondary
                    : palette.textPrimary,
                onPressed: _pickValidEnd,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        _validEnd == null ? '有效期（可选）' : _formatDate(_validEnd!),
                        textAlign: TextAlign.left,
                      ),
                    ),
                    const Icon(CupertinoIcons.calendar, size: 20),
                  ],
                ),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: CyTokens.space2),
              Text(
                _error!,
                style: TextStyle(color: CyPalette.of(context).statusDanger),
              ),
            ],
            const SizedBox(height: CyTokens.space4),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton.filled(
                key: const Key('coop-perk-save'),
                minimumSize: const Size.fromHeight(44),
                onPressed: (_saving || _validate() != null) ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CupertinoActivityIndicator(),
                      )
                    : const Text('保存权益'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
