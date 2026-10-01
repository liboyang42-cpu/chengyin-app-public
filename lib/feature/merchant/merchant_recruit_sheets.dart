import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_system_date_picker.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../data/models/merchant_recruit.dart';
import '../../data/models/template.dart';
import '../../data/models/topic.dart';
import '../club/club_image_picker.dart';

class _CupertinoFormTextField extends StatelessWidget {
  const _CupertinoFormTextField({
    this.fieldKey,
    required this.label,
    required this.controller,
    required this.placeholder,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.inputFormatters,
    this.maxLines = 1,
    this.maxLength,
    this.onChanged,
  });

  final Key? fieldKey;
  final String label;
  final TextEditingController controller;
  final String placeholder;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      label: label,
      textField: true,
      child: CupertinoTextField(
        key: fieldKey,
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        textCapitalization: textCapitalization,
        autofillHints: autofillHints,
        inputFormatters: inputFormatters,
        minLines: 1,
        maxLines: maxLines,
        maxLength: maxLength,
        placeholder: placeholder,
        placeholderStyle: t.bodyMedium?.copyWith(color: p.textPlaceholder),
        style: t.bodyMedium?.copyWith(color: p.textPrimary),
        padding: const EdgeInsets.all(CyTokens.space3),
        decoration: BoxDecoration(
          color: p.inputBgEmpty,
          border: Border.all(color: p.borderSubtle),
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _CupertinoChoice<T> {
  const _CupertinoChoice({required this.value, required this.label});
  final T value;
  final String label;
}

class _CupertinoChoiceField<T> extends StatelessWidget {
  const _CupertinoChoiceField({
    super.key,
    required this.title,
    required this.hint,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String hint;
  final List<_CupertinoChoice<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;

  Future<T?> _showShortChoices(BuildContext context) {
    return showCupertinoModalPopup<T>(
      context: context,
      semanticsDismissible: true,
      builder: (BuildContext sheetContext) => CupertinoActionSheet(
        title: Text(title),
        actions: options
            .map((_CupertinoChoice<T> option) {
              return CupertinoActionSheetAction(
                onPressed: () => Navigator.of(sheetContext).pop(option.value),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        option.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (option.value == value)
                      const Icon(CupertinoIcons.check_mark, size: 18),
                  ],
                ),
              );
            })
            .toList(growable: false),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: Text(stringsOf(context).merchantRecruitUiCancel),
        ),
      ),
    );
  }

  Future<T?> _showLongChoices(BuildContext context) async {
    int selectedIndex = options.indexWhere(
      (_CupertinoChoice<T> option) => option.value == value,
    );
    if (selectedIndex < 0) selectedIndex = 0;
    final FixedExtentScrollController controller = FixedExtentScrollController(
      initialItem: selectedIndex,
    );
    final CyPalette p = CyPalette.of(context);
    final T? result = await showCupertinoModalPopup<T>(
      context: context,
      semanticsDismissible: true,
      builder: (BuildContext sheetContext) => CupertinoPopupSurface(
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 360,
            child: ColoredBox(
              color: p.bgSurface,
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      CupertinoButton(
                        minimumSize: const Size(44, 44),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: Text(stringsOf(context).merchantRecruitUiCancel),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      CupertinoButton(
                        minimumSize: const Size(44, 44),
                        onPressed: () => Navigator.of(
                          sheetContext,
                        ).pop(options[selectedIndex].value),
                        child: Text(stringsOf(context).merchantRecruitUiDone),
                      ),
                    ],
                  ),
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: controller,
                      itemExtent: 44,
                      useMagnifier: true,
                      magnification: 1.05,
                      onSelectedItemChanged: (int index) {
                        selectedIndex = index;
                      },
                      children: options
                          .map(
                            (_CupertinoChoice<T> option) => Center(
                              child: Text(
                                option.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    String? selected;
    for (final _CupertinoChoice<T> option in options) {
      if (option.value == value) selected = option.label;
    }
    return Semantics(
      button: true,
      label: title,
      value: selected ?? hint,
      child: CupertinoButton(
        minimumSize: const Size.fromHeight(44),
        padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
        color: p.bgSurfaceSubtle,
        foregroundColor: p.textPrimary,
        onPressed: options.isEmpty
            ? null
            : () async {
                final T? picked = options.length <= 3
                    ? await _showShortChoices(context)
                    : await _showLongChoices(context);
                if (picked != null) onChanged(picked);
              },
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                selected ?? hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
                style: TextStyle(
                  color: selected == null ? p.textSecondary : p.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: CyTokens.space2),
            const Icon(CupertinoIcons.chevron_down, size: 16),
          ],
        ),
      ),
    );
  }
}

DateTime _timeToday(int hour, int minute) {
  final DateTime now = DateTime.now();
  return DateTime(now.year, now.month, now.day, hour, minute);
}

List<DateTime> _parseTimeRange(String raw) {
  final RegExpMatch? match = RegExp(
    r'^(\d{1,2}):(\d{2})-(\d{1,2}):(\d{2})$',
  ).firstMatch(raw.trim());
  if (match == null) return <DateTime>[_timeToday(9, 0), _timeToday(18, 0)];
  final int? sh = int.tryParse(match.group(1)!);
  final int? sm = int.tryParse(match.group(2)!);
  final int? eh = int.tryParse(match.group(3)!);
  final int? em = int.tryParse(match.group(4)!);
  final bool valid =
      sh != null &&
      sh >= 0 &&
      sh <= 23 &&
      sm != null &&
      sm >= 0 &&
      sm <= 59 &&
      eh != null &&
      eh >= 0 &&
      eh <= 23 &&
      em != null &&
      em >= 0 &&
      em <= 59;
  if (!valid) return <DateTime>[_timeToday(9, 0), _timeToday(18, 0)];
  return <DateTime>[_timeToday(sh, sm), _timeToday(eh, em)];
}

String _formatTimeRange(DateTime start, DateTime end) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(start.hour)}:${two(start.minute)}-'
      '${two(end.hour)}:${two(end.minute)}';
}

Future<String?> _showCupertinoTimeRangePicker(
  BuildContext context,
  String current,
) async {
  final List<DateTime> initial = _parseTimeRange(current);
  final DateTime minimum = _timeToday(0, 0);
  final DateTime maximum = _timeToday(23, 59);
  final DateTime? start = await showCySystemDatePicker(
    context: context,
    mode: CupertinoDatePickerMode.time,
    initialDateTime: initial[0],
    minimumDate: minimum,
    maximumDate: maximum,
    title: stringsOf(context).merchantRecruitUiStart,
  );
  if (start == null || !context.mounted) return null;
  final DateTime? end = await showCySystemDatePicker(
    context: context,
    mode: CupertinoDatePickerMode.time,
    initialDateTime: initial[1],
    minimumDate: minimum,
    maximumDate: maximum,
    title: stringsOf(context).merchantRecruitUiEnd,
  );
  if (end == null) return null;
  return _formatTimeRange(start, end);
}

/// 承接链路上的三张表单。抽出来是因为招商页本身已经够长了,
/// 而这三张各自都有**必须说清楚的取舍**,混在页面里会被读成样板代码。

/// 「申请承接并配置点位」提交出来的内容。
///
/// ⚠️ **没有探索值(xpValue)这一项**,不是漏了:
///   服务端 `ChapterMerchantNodeServiceImpl.submit` 的落库白名单是
///   name/description/address/longitude/latitude/imgUrl/businessTime/templateId
///   —— xpValue 会被拿去校验上限、然后**丢掉**。
///   摆一个填了不生效的输入框,比没有这个输入框更糟。
class ChapterNodeDraft {
  const ChapterNodeDraft({
    required this.name,
    required this.templateId,
    this.address,
    this.message,
  });

  final String name;
  final int templateId;
  final String? address;
  final String? message;
}

/// 申请承接 + 配点位。返回 null = 用户放弃。
Future<ChapterNodeDraft?> showChapterApplyForm(
  BuildContext context,
  WidgetRef ref, {
  required String chapterName,
}) {
  return showCupertinoSheet<ChapterNodeDraft>(
    context: context,
    showDragHandle: true,
    topGap: 0.12,
    scrollableBuilder:
        (BuildContext context, ScrollController scrollController) =>
            _ChapterApplySheet(
              chapterName: chapterName,
              scrollController: scrollController,
            ),
  );
}

class _ChapterApplySheet extends ConsumerStatefulWidget {
  const _ChapterApplySheet({
    required this.chapterName,
    required this.scrollController,
  });

  final String chapterName;
  final ScrollController scrollController;

  @override
  ConsumerState<_ChapterApplySheet> createState() => _ChapterApplySheetState();
}

class _ChapterApplySheetState extends ConsumerState<_ChapterApplySheet> {
  final TextEditingController _message = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _address = TextEditingController();

  List<PlayTemplate>? _templates;
  String? _templateError;
  int? _templateId;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
    _loadDefaultAddress();
  }

  @override
  void dispose() {
    _message.dispose();
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    try {
      final List<PlayTemplate> rows = await ref
          .read(templateApiProvider)
          .myList();
      if (!mounted) return;
      setState(() => _templates = rows);
    } catch (e) {
      if (!mounted) return;
      // ★ 读不到不能渲成「你还没有玩法」—— 那会让商家去重做一个已经存在的模板。
      setState(
        () => _templateError = e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> _loadDefaultAddress() async {
    try {
      final Map<String, dynamic> m = await ref
          .read(merchantApiProvider)
          .merchantInfo();
      final String a = (m['address'] ?? '').toString().trim();
      if (!mounted || a.isEmpty || _address.text.isNotEmpty) return;
      _address.text = a;
    } catch (_) {
      // 店址取不到不拦这张表单 —— 它是选填,商家自己也能写。
    }
  }

  bool get _canSubmit => _name.text.trim().isNotEmpty && _templateId != null;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    return CupertinoPageScaffold(
      backgroundColor: p.bgPage,
      resizeToAvoidBottomInset: true,
      navigationBar: CupertinoNavigationBar(
        middle: Text(stringsOf(context).merchantRecruitUiApplyTitle),
        leading: CupertinoButton(
          key: const Key('apply-cancel'),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(stringsOf(context).merchantRecruitUiCancel),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          controller: widget.scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space4,
            CyTokens.pageX,
            CyTokens.space4 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: CyTokens.space1),
              Text(
                widget.chapterName,
                style: t.bodySmall?.copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: CyTokens.space4),
              CyField(
                label: stringsOf(context).merchantRecruitUiMessage,
                child: _CupertinoFormTextField(
                  fieldKey: const Key('apply-message'),
                  label: stringsOf(context).merchantRecruitUiMessageSemantics,
                  controller: _message,
                  placeholder: stringsOf(context).merchantRecruitUiMessageHint,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
              CyField(
                label: stringsOf(context).merchantRecruitUiName,
                child: _CupertinoFormTextField(
                  fieldKey: const Key('apply-node-name'),
                  label: stringsOf(context).merchantRecruitUiNameSemantics,
                  controller: _name,
                  placeholder: stringsOf(context).merchantRecruitUiNameHint,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              CyField(
                label: stringsOf(context).merchantRecruitUiAddress,
                child: _CupertinoFormTextField(
                  fieldKey: const Key('apply-node-address'),
                  label: stringsOf(context).merchantRecruitUiAddress,
                  controller: _address,
                  placeholder: stringsOf(context).merchantRecruitUiAddressHint,
                  textInputAction: TextInputAction.done,
                  autofillHints: const <String>[
                    AutofillHints.streetAddressLine1,
                  ],
                ),
              ),
              CyField(label: stringsOf(context).merchantRecruitUiTemplate, child: _templatePicker(p, t)),
              const SizedBox(height: CyTokens.space2),
              Text(
                stringsOf(context).merchantRecruitUiReviewHint,
                style: t.bodySmall?.copyWith(color: p.textTertiary),
              ),
              const SizedBox(height: CyTokens.space4),
              CupertinoButton(
                key: const Key('apply-submit'),
                minimumSize: const Size.fromHeight(44),
                color: p.actionPrimaryBg,
                disabledColor: p.bgSubtle,
                foregroundColor: _canSubmit
                    ? p.actionPrimaryFg
                    : p.textPlaceholder,
                onPressed: _canSubmit
                    ? () => Navigator.of(context).pop(
                        ChapterNodeDraft(
                          name: _name.text.trim(),
                          templateId: _templateId!,
                          address: _address.text.trim().isEmpty
                              ? null
                              : _address.text.trim(),
                          message: _message.text.trim().isEmpty
                              ? null
                              : _message.text.trim(),
                        ),
                      )
                    : null,
                child: Text(stringsOf(context).merchantRecruitUiSubmit),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _templatePicker(CyPalette p, TextTheme t) {
    if (_templateError != null) {
      return Text(
        stringsOf(context).merchantRecruitUiTemplatesError(_templateError!),
        key: const Key('apply-template-error'),
        style: t.bodySmall?.copyWith(color: CyPalette.of(context).statusWarning),
      );
    }
    final List<PlayTemplate>? rows = _templates;
    if (rows == null) {
      return Text(
        stringsOf(context).merchantRecruitUiTemplatesLoading,
        style: t.bodySmall?.copyWith(color: p.textSecondary),
      );
    }
    if (rows.isEmpty) {
      return Text(
        stringsOf(context).merchantRecruitUiTemplatesEmpty,
        key: const Key('apply-template-empty'),
        style: t.bodySmall?.copyWith(color: p.textSecondary),
      );
    }
    return _CupertinoChoiceField<int>(
      key: const Key('apply-template-picker'),
      title: stringsOf(context).merchantRecruitUiChooseTemplate,
      value: _templateId,
      hint: stringsOf(context).merchantRecruitUiTemplateHint,
      options: rows
          .map(
            (PlayTemplate x) =>
                _CupertinoChoice<int>(value: x.id, label: x.title),
          )
          .toList(),
      onChanged: (int v) => setState(() => _templateId = v),
    );
  }
}

/// 填写实际供给。返回可直接发给 `/api/coop/offer/enroll` 的 body。
///
/// ★★ 表单形状由**章节的条款档**决定,不由前端挑:
///   服务端会拿章节档位和提交的档位对比,不一致直接拒
///   (「本章节是「权益承接」,不能按「计酬承接」入驻」)。
Future<Map<String, dynamic>?> showChapterOfferForm(
  BuildContext context,
  WidgetRef ref, {
  required int chapterId,
  required String chapterName,
  required String termsMode,
}) {
  return showCupertinoSheet<Map<String, dynamic>>(
    context: context,
    showDragHandle: true,
    topGap: 0.22,
    scrollableBuilder:
        (BuildContext context, ScrollController scrollController) =>
            _ChapterOfferSheet(
              chapterId: chapterId,
              chapterName: chapterName,
              termsMode: termsMode,
              scrollController: scrollController,
            ),
  );
}

class _ChapterOfferSheet extends ConsumerStatefulWidget {
  const _ChapterOfferSheet({
    required this.chapterId,
    required this.chapterName,
    required this.termsMode,
    required this.scrollController,
  });

  final int chapterId;
  final String chapterName;
  final String termsMode;
  final ScrollController scrollController;

  @override
  ConsumerState<_ChapterOfferSheet> createState() => _ChapterOfferSheetState();
}

class _ChapterOfferSheetState extends ConsumerState<_ChapterOfferSheet> {
  final TextEditingController _quota = TextEditingController();
  final TextEditingController _fee = TextEditingController();

  List<Map<String, dynamic>>? _perks;
  String? _perkError;
  int? _perkTemplateId;

  bool get _isPerk => widget.termsMode == 'PERK';
  bool get _isRevshare => widget.termsMode == 'REVSHARE';

  @override
  void initState() {
    super.initState();
    if (_isPerk) _loadPerks();
  }

  @override
  void dispose() {
    _quota.dispose();
    _fee.dispose();
    super.dispose();
  }

  Future<void> _loadPerks() async {
    try {
      final List<Map<String, dynamic>> rows = await ref
          .read(coopApiProvider)
          .perkTemplates();
      if (!mounted) return;
      // 零售价与额度都得是正数 —— 服务端复制快照时按这两项算容量,
      // 缺一样的模板选了也会在入驻那一步被拒。
      setState(
        () => _perks = rows.where((Map<String, dynamic> r) {
          final double v = (r['retailValue'] as num?)?.toDouble() ?? 0;
          final int q = (r['quota'] as num?)?.toInt() ?? 0;
          return v > 0 && q > 0;
        }).toList(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _perkError = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// 能不能提交。★ 每一档各自的必填项,和服务端 `assertTermsShape` 同口径。
  bool get _canSubmit {
    if (_isPerk) {
      final int? q = int.tryParse(_quota.text.trim());
      return _perkTemplateId != null && q != null && q >= 1;
    }
    if (_isRevshare) {
      final double? f = double.tryParse(_fee.text.trim());
      return f != null && f >= 0;
    }
    // TRAFFIC:引流档不收数字,确认即可。
    return widget.termsMode == 'TRAFFIC';
  }

  Map<String, dynamic> _payload() {
    final Map<String, dynamic> body = <String, dynamic>{
      'chapterId': widget.chapterId,
      'termsMode': widget.termsMode,
    };
    if (_isPerk) {
      body['perkTemplateId'] = _perkTemplateId;
      body['quotaTotal'] = int.parse(_quota.text.trim());
    }
    if (_isRevshare) body['perHeadFee'] = double.parse(_fee.text.trim());
    return body;
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    return CupertinoPageScaffold(
      backgroundColor: p.bgPage,
      resizeToAvoidBottomInset: true,
      navigationBar: CupertinoNavigationBar(
        middle: Text(stringsOf(context).merchantRecruitUiOfferTitle),
        leading: CupertinoButton(
          key: const Key('offer-cancel'),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(stringsOf(context).merchantRecruitUiCancel),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          controller: widget.scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space4,
            CyTokens.pageX,
            CyTokens.space4 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: CyTokens.space1),
              Text(
                '${widget.chapterName} · ${termsModeLabel(widget.termsMode) ?? stringsOf(context).merchantRecruitUiUnknownTerms}',
                style: t.bodySmall?.copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: CyTokens.space4),
              if (_isPerk) ...<Widget>[
                CyField(label: stringsOf(context).merchantRecruitUiPerk, child: _perkPicker(p, t)),
                CyField(
                  label: stringsOf(context).merchantRecruitUiQuota,
                  child: _CupertinoFormTextField(
                    fieldKey: const Key('offer-quota'),
                    label: stringsOf(context).merchantRecruitUiQuotaSemantics,
                    controller: _quota,
                    placeholder: stringsOf(context).merchantRecruitUiQuotaHint,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
              if (_isRevshare)
                CyField(
                  label: stringsOf(context).merchantRecruitUiFee,
                  child: _CupertinoFormTextField(
                    fieldKey: const Key('offer-fee'),
                    label: stringsOf(context).merchantRecruitUiFeeSemantics,
                    controller: _fee,
                    placeholder: stringsOf(context).merchantResidualPolicyFeeHint,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              if (widget.termsMode == 'TRAFFIC')
                Text(
                  stringsOf(context).merchantResidualPolicyTraffic,
                  style: t.bodySmall?.copyWith(color: p.textSecondary),
                ),
              const SizedBox(height: CyTokens.space2),
              Text(
                stringsOf(context).merchantResidualPolicySupplyChange,
                style: t.bodySmall?.copyWith(color: p.textTertiary),
              ),
              const SizedBox(height: CyTokens.space4),
              CupertinoButton(
                key: const Key('offer-submit'),
                minimumSize: const Size.fromHeight(44),
                color: p.actionPrimaryBg,
                disabledColor: p.bgSubtle,
                foregroundColor: _canSubmit
                    ? p.actionPrimaryFg
                    : p.textPlaceholder,
                onPressed: _canSubmit
                    ? () => Navigator.of(context).pop(_payload())
                    : null,
                child: Text(stringsOf(context).merchantRecruitUiOfferConfirm),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _perkPicker(CyPalette p, TextTheme t) {
    if (_perkError != null) {
      return Text(
        stringsOf(context).merchantRecruitUiPerksError(_perkError!),
        key: const Key('offer-perk-error'),
        style: t.bodySmall?.copyWith(color: CyPalette.of(context).statusWarning),
      );
    }
    final List<Map<String, dynamic>>? rows = _perks;
    if (rows == null) {
      return Text(
        stringsOf(context).merchantRecruitUiPerksLoading,
        style: t.bodySmall?.copyWith(color: p.textSecondary),
      );
    }
    if (rows.isEmpty) {
      return Text(
        stringsOf(context).merchantRecruitUiPerksEmpty,
        key: const Key('offer-perk-empty'),
        style: t.bodySmall?.copyWith(color: p.textSecondary),
      );
    }
    return _CupertinoChoiceField<int>(
      key: const Key('offer-perk-picker'),
      title: stringsOf(context).merchantRecruitUiChoosePerk,
      value: _perkTemplateId,
      hint: stringsOf(context).merchantRecruitUiChoosePerk,
      options: rows
          .map(
            (Map<String, dynamic> r) => _CupertinoChoice<int>(
              value: (r['id'] as num?)?.toInt() ?? 0,
              label: (r['name'] ?? stringsOf(context).merchantRecruitUiUnnamedPerk).toString(),
            ),
          )
          .toList(),
      onChanged: (int v) => setState(() => _perkTemplateId = v),
    );
  }
}

/// 经典定向的站点报名。返回可直接发给 `/api/registration/merchant/create` 的 body。
Future<Map<String, dynamic>?> showNodeRegistrationForm(
  BuildContext context,
  WidgetRef ref, {
  required int topicId,
  required List<TopicNode> nodes,
}) {
  return showCupertinoSheet<Map<String, dynamic>>(
    context: context,
    showDragHandle: true,
    topGap: 0.06,
    scrollableBuilder:
        (BuildContext context, ScrollController scrollController) =>
            _NodeRegistrationSheet(
              topicId: topicId,
              nodes: nodes,
              scrollController: scrollController,
            ),
  );
}

class _NodeRegistrationSheet extends ConsumerStatefulWidget {
  const _NodeRegistrationSheet({
    required this.topicId,
    required this.nodes,
    required this.scrollController,
  });

  final int topicId;
  final List<TopicNode> nodes;
  final ScrollController scrollController;

  @override
  ConsumerState<_NodeRegistrationSheet> createState() =>
      _NodeRegistrationSheetState();
}

class _NodeRegistrationSheetState
    extends ConsumerState<_NodeRegistrationSheet> {
  int? _nodeId;
  final MerchantRegistrationFormState _form = MerchantRegistrationFormState();

  /// 可配合时间(`cooperateDate`,形如 09:00-18:00)。
  ///
  /// ★★ **只在这张"建报名"的表里出现,改报名那张里没有** ——
  ///   服务端的可改白名单不含 cooperateDate,建完就改不了了。
  ///   把它渲进编辑表单会变成一个"填了不生效"的假输入框。
  final TextEditingController _cooperate = TextEditingController();

  @override
  void initState() {
    super.initState();
    _form.addListener(_onFormChanged);
    _form.loadDefaultAddress(ref);
    _loadBusinessTime();
  }

  Future<void> _loadBusinessTime() async {
    try {
      final Map<String, dynamic> m = await ref
          .read(merchantApiProvider)
          .merchantInfo();
      final String bt = (m['businessTime'] ?? '').toString().trim();
      if (!mounted || bt.isEmpty || _cooperate.text.isNotEmpty) return;
      setState(() => _cooperate.text = bt);
    } catch (_) {
      // 取不到营业时间不拦表单 —— 它是选填,商家自己填得了。
    }
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _form.removeListener(_onFormChanged);
    _form.dispose();
    _cooperate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    return CupertinoPageScaffold(
      backgroundColor: p.bgPage,
      resizeToAvoidBottomInset: true,
      navigationBar: CupertinoNavigationBar(
        middle: Text(stringsOf(context).merchantRecruitUiRegisterTitle),
        leading: CupertinoButton(
          key: const Key('register-cancel'),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(stringsOf(context).merchantRecruitUiCancel),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          controller: widget.scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space4,
            CyTokens.pageX,
            CyTokens.space4 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: CyTokens.space1),
              Text(
                stringsOf(context).merchantResidualPolicyIntent,
                style: t.bodySmall?.copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: CyTokens.space4),
              CyField(
                label: stringsOf(context).merchantRecruitUiNode,
                child: _CupertinoChoiceField<int>(
                  key: const Key('register-node-picker'),
                  title: stringsOf(context).merchantRecruitUiChooseNode,
                  value: _nodeId,
                  hint: stringsOf(context).merchantRecruitUiNodeHint,
                  options: widget.nodes
                      .map(
                        (TopicNode n) => _CupertinoChoice<int>(
                          value: n.id,
                          label: n.name.trim().isEmpty ? stringsOf(context).merchantRecruitUiUnnamedNode : n.name,
                        ),
                      )
                      .toList(),
                  onChanged: (int v) => setState(() => _nodeId = v),
                ),
              ),
              CyField(
                label: stringsOf(context).merchantRecruitUiAvailable,
                child: CupertinoButton(
                  key: const Key('register-cooperate-date'),
                  minimumSize: const Size.fromHeight(44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space3,
                  ),
                  color: p.bgSurfaceSubtle,
                  foregroundColor: p.textPrimary,
                  onPressed: () async {
                    final String? value = await _showCupertinoTimeRangePicker(
                      context,
                      _cooperate.text,
                    );
                    if (value == null || !mounted) return;
                    setState(() => _cooperate.text = value);
                  },
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _cooperate.text.isEmpty
                          ? stringsOf(context).merchantRecruitUiAvailableHint
                          : _cooperate.text,
                      style: TextStyle(
                        color: _cooperate.text.isEmpty
                            ? p.textSecondary
                            : p.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
              ..._form.fields(context, ref),
              const SizedBox(height: CyTokens.space2),
              Text(
                stringsOf(context).merchantRecruitUiAvailableWarning,
                style: t.bodySmall?.copyWith(color: p.textTertiary),
              ),
              const SizedBox(height: CyTokens.space4),
              CupertinoButton(
                key: const Key('register-submit'),
                minimumSize: const Size.fromHeight(44),
                color: p.actionPrimaryBg,
                disabledColor: p.bgSubtle,
                foregroundColor: _nodeId != null && _form.isComplete
                    ? p.actionPrimaryFg
                    : p.textPlaceholder,
                onPressed: _nodeId != null && _form.isComplete
                    ? () => Navigator.of(context).pop(<String, dynamic>{
                        'topicId': widget.topicId,
                        // 服务端只认经典定向走这条入口(自由探索会被拒),
                        // mode 写死 1 与它一致。
                        'mode': 1,
                        'nodeId': _nodeId,
                        ..._form.toJson(),
                        if (_cooperate.text.trim().isNotEmpty)
                          'cooperateDate': _cooperate.text.trim(),
                      })
                    : null,
                child: Text(stringsOf(context).merchantRecruitUiRegisterSubmit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 报名内容的九个可写字段。**建报名和改报名共用同一份** ——
/// 服务端 `MerchantRegistrationEditServiceImpl` 的白名单正是这九个:
/// picUrl / address / addressName / longitude / latitude /
/// activityDesc / limitNum / startDate / endDate。
///
/// ★★ 抽成一个类是为了让「改报名」拿到的是**完整表单**,而不是几个字段。
///   只提交其中几项虽然不会把别的清空(mapper 是 `<if test="x != null">` 的
///   增量更新),但界面上少一项,商家就永远改不了那一项 —— 而
///   「被驳回后补一张现场图」正是改报名这条路存在的理由。
class MerchantRegistrationFormState extends ChangeNotifier {
  final TextEditingController addressName = TextEditingController();
  final TextEditingController address = TextEditingController();
  final TextEditingController longitude = TextEditingController();
  final TextEditingController latitude = TextEditingController();
  final TextEditingController activityDesc = TextEditingController();
  final TextEditingController limitNum = TextEditingController();

  final List<String> pics = <String>[];
  String? startDate;
  String? endDate;

  bool _uploading = false;

  /// 必填:场地名、地址、承接说明。与小程序那张表同口径。
  bool get isComplete =>
      addressName.text.trim().isNotEmpty &&
      address.text.trim().isNotEmpty &&
      activityDesc.text.trim().isNotEmpty;

  void seed(MerchantRegistrationDetail d) {
    addressName.text = d.addressName ?? '';
    address.text = d.address ?? '';
    longitude.text = d.longitude ?? '';
    latitude.text = d.latitude ?? '';
    activityDesc.text = d.activityDesc ?? '';
    // ★ limitNum 为 null 时留空,**不填 0** —— 0 在这里的含义是"不限人数",
    //   把"没设置过"写成 0 会在保存时把它变成一个真实设定。
    limitNum.text = d.limitNum == null ? '' : d.limitNum.toString();
    pics
      ..clear()
      ..addAll(d.pics);
    startDate = d.startDate;
    endDate = d.endDate;
    notifyListeners();
  }

  Future<void> loadDefaultAddress(WidgetRef ref) async {
    try {
      final Map<String, dynamic> m = await ref
          .read(merchantApiProvider)
          .merchantInfo();
      if (address.text.trim().isEmpty) {
        address.text = (m['address'] ?? '').toString().trim();
      }
      if (addressName.text.trim().isEmpty) {
        addressName.text = (m['name'] ?? '').toString().trim();
      }
      final String lng = (m['locationLng'] ?? m['longitude'] ?? '').toString();
      final String lat = (m['locationLat'] ?? m['latitude'] ?? '').toString();
      if (longitude.text.isEmpty && lng.isNotEmpty) longitude.text = lng;
      if (latitude.text.isEmpty && lat.isNotEmpty) latitude.text = lat;
      notifyListeners();
    } catch (_) {
      // 店铺资料取不到不拦表单,商家自己填得了。
    }
  }

  /// ⚠️ **每一项都无条件发出去**,不做「空就不发」的省略。
  ///
  /// 改报名走的是增量更新(mapper 逐字段 `<if test="x != null">`),
  /// 省略掉的字段会把**上一次的值留在库里** —— 而界面上它已经被清空了。
  /// 表现出来就是"我明明删掉了照片,保存后又回来了"。
  ///
  /// ⚠️ startDate / endDate 这两项**有意不发**:App 和小程序都没有采集它们的控件
  ///   (小程序那张表提交的是两个空串),而把详情里读回来的时间串原样发回去
  ///   要赌服务端的日期格式,赌输就是把一条本来好好的时间改坏。
  ///   不发 = 保持原样,这是这里唯一安全的选择。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'addressName': addressName.text.trim(),
    'address': address.text.trim(),
    'longitude': longitude.text.trim(),
    'latitude': latitude.text.trim(),
    'activityDesc': activityDesc.text.trim(),
    // ★ 空 = 不限人数,发 0(服务端 limit_num 的"不限"就是 0)。
    'limitNum': int.tryParse(limitNum.text.trim()) ?? 0,
    'picUrl': pics.join(','),
  };

  Future<void> pickPics(BuildContext context, WidgetRef ref) async {
    if (_uploading) return;
    _uploading = true;
    notifyListeners();
    try {
      final List<String> urls = await pickAndUploadImages(
        context,
        ref,
        maxCount: 9 - pics.length,
      );
      pics.addAll(urls);
    } finally {
      _uploading = false;
      notifyListeners();
    }
  }

  List<Widget> fields(BuildContext context, WidgetRef ref) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    return <Widget>[
      CyField(
        label: stringsOf(context).merchantCatalogVenueName,
        child: _CupertinoFormTextField(
          fieldKey: const Key('reg-address-name'),
          label: stringsOf(context).merchantCatalogVenueNameSemantics,
          controller: addressName,
          placeholder: stringsOf(context).merchantCatalogVenueNameHint,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => notifyListeners(),
        ),
      ),
      CyField(
        label: stringsOf(context).merchantCatalogAddress,
        child: _CupertinoFormTextField(
          fieldKey: const Key('reg-address'),
          label: stringsOf(context).merchantCatalogAddressSemantics,
          controller: address,
          placeholder: stringsOf(context).merchantCatalogAddressHint,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.streetAddressLine1],
          onChanged: (_) => notifyListeners(),
        ),
      ),
      CyField(
        label: stringsOf(context).merchantCatalogDescription,
        child: _CupertinoFormTextField(
          fieldKey: const Key('reg-activity-desc'),
          label: stringsOf(context).merchantCatalogDescriptionSemantics,
          controller: activityDesc,
          placeholder: stringsOf(context).merchantCatalogDescriptionHint,
          maxLines: 4,
          maxLength: 500,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => notifyListeners(),
        ),
      ),
      CyField(
        label: stringsOf(context).merchantCatalogCapacity,
        child: _CupertinoFormTextField(
          fieldKey: const Key('reg-limit-num'),
          label: stringsOf(context).merchantCatalogCapacity,
          controller: limitNum,
          placeholder: stringsOf(context).merchantCatalogCapacityHint,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          onChanged: (_) => notifyListeners(),
        ),
      ),
      CyField(
        label: stringsOf(context).merchantCatalogLongitude,
        child: _CupertinoFormTextField(
          fieldKey: const Key('reg-longitude'),
          label: stringsOf(context).merchantCatalogLongitude,
          controller: longitude,
          placeholder: stringsOf(context).merchantCatalogCoordinatesHint,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          textInputAction: TextInputAction.next,
        ),
      ),
      CyField(
        label: stringsOf(context).merchantCatalogLatitude,
        child: _CupertinoFormTextField(
          fieldKey: const Key('reg-latitude'),
          label: stringsOf(context).merchantCatalogLatitude,
          controller: latitude,
          placeholder: stringsOf(context).merchantCatalogCoordinatesHint,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          textInputAction: TextInputAction.done,
        ),
      ),
      CyField(
        label: stringsOf(context).merchantCatalogPhotos,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (pics.isEmpty)
              Text(
                stringsOf(context).merchantCatalogPhotosEmpty,
                style: t.bodySmall?.copyWith(color: p.textSecondary),
              )
            else
              Text(
                stringsOf(context).merchantCatalogPhotoCount(pics.length),
                key: const Key('reg-pic-count'),
                style: t.bodySmall?.copyWith(color: p.textSecondary),
              ),
            const SizedBox(height: CyTokens.space2),
            // 两颗系统按钮等分可用宽度，并保持 44pt 命中区。
            Row(
              children: <Widget>[
                Expanded(
                  child: CupertinoButton.tinted(
                    key: const Key('reg-pick-pics'),
                    minimumSize: const Size.fromHeight(44),
                    onPressed: _uploading || pics.length >= 9
                        ? null
                        : () => pickPics(context, ref),
                    child: Text(_uploading ? stringsOf(context).merchantCatalogUploading : stringsOf(context).merchantCatalogAddPhotos),
                  ),
                ),
                if (pics.isNotEmpty) ...<Widget>[
                  const SizedBox(width: CyTokens.space2),
                  Expanded(
                    child: CupertinoButton(
                      key: const Key('reg-clear-pics'),
                      minimumSize: const Size.fromHeight(44),
                      onPressed: _uploading
                          ? null
                          : () {
                              pics.clear();
                              notifyListeners();
                            },
                      child: Text(stringsOf(context).merchantCatalogRemovePhotos),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    ];
  }

  @override
  void dispose() {
    addressName.dispose();
    address.dispose();
    longitude.dispose();
    latitude.dispose();
    activityDesc.dispose();
    limitNum.dispose();
    super.dispose();
  }
}
