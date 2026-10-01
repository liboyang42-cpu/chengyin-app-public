import 'merchant_customer_detail_strings.dart';
import '../../l10n/strings.dart';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart'
    show
        Border,
        BorderRadius,
        BorderSide,
        BoxDecoration,
        Color,
        Colors,
        FontWeight,
        Material;

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/merchant_customer_detail_api.dart';
import '../../data/models/merchant_customer_detail.dart';

enum _CustomerDetailPageState { loading, ready, noPermission, error }

/// 商家客户详情。路由只传客户 ID，商家主体与权限由后端核定。
class MerchantCustomerDetailPage extends StatefulWidget {
  const MerchantCustomerDetailPage({
    super.key,
    required this.api,
    required this.customerMemberId,
  });

  final MerchantCustomerDetailGateway api;
  final int customerMemberId;

  @override
  State<MerchantCustomerDetailPage> createState() =>
      _MerchantCustomerDetailPageState();
}

class _MerchantCustomerDetailPageState
    extends State<MerchantCustomerDetailPage> {
  _CustomerDetailPageState _pageState = _CustomerDetailPageState.loading;
  MerchantCustomerAccess _access = MerchantCustomerAccess.inactive;
  MerchantCustomerDetail? _detail;
  String _errorMessage = '';
  int _requestToken = 0;
  final TextEditingController _tagController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final math.Random _random = math.Random();
  int _mutationSequence = 0;
  String? _tagRequestId;
  String? _tagFingerprint;
  String? _noteRequestId;
  String? _noteFingerprint;
  int? _correctsNoteId;
  bool _tagSubmitting = false;
  bool _noteSubmitting = false;
  int? _hidingNoteId;
  int? _removingTagId;
  String _tagError = '';
  String _noteError = '';
  final Map<int, String> _hideRequestIds = <int, String>{};
  final Map<int, String> _removeTagRequestIds = <int, String>{};

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadAccessAndDetail);
  }

  @override
  void dispose() {
    _requestToken += 1;
    _tagController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadAccessAndDetail() async {
    final int token = ++_requestToken;
    if (widget.customerMemberId <= 0) {
      setState(() {
        _pageState = _CustomerDetailPageState.error;
        _errorMessage = stringsOf(context).merchantCustomerDetailInvalidId;
      });
      return;
    }
    setState(() {
      _pageState = _CustomerDetailPageState.loading;
      _errorMessage = '';
    });
    try {
      final MerchantCustomerAccess access = await widget.api.access();
      if (!mounted || token != _requestToken) return;
      if (!access.active || !access.canReadCrm) {
        setState(() {
          _access = access;
          _detail = null;
          _pageState = _CustomerDetailPageState.noPermission;
        });
        return;
      }
      _access = access;
      await _loadDetail(token: token);
    } on MerchantCustomerDetailApiException catch (error) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _pageState = error.isPermissionDenied
            ? _CustomerDetailPageState.noPermission
            : _CustomerDetailPageState.error;
        _errorMessage = merchantCustomerApiError(context, error);
      });
    } on Object {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _pageState = _CustomerDetailPageState.error;
        _errorMessage = stringsOf(context).merchantCustomerDetailNetwork;
      });
    }
  }

  Future<void> _loadDetail({required int token}) async {
    final MerchantCustomerDetail detail = await widget.api.detail(
      widget.customerMemberId,
    );
    if (!mounted || token != _requestToken) return;
    setState(() {
      _detail = detail;
      _pageState = _CustomerDetailPageState.ready;
      _errorMessage = '';
    });
  }

  String _requestId(String kind) {
    _mutationSequence += 1;
    final String stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(
      36,
    );
    final String entropy = _random
        .nextInt(0xFFFFFF)
        .toRadixString(36)
        .padLeft(5, '0');
    return 'crm-$kind-$stamp-$entropy-$_mutationSequence';
  }

  Future<void> _submitTag() async {
    if (!_access.canSegmentCrm || _tagSubmitting) return;
    final String name = _tagController.text.trim();
    if (name.isEmpty) {
      setState(() => _tagError = stringsOf(context).merchantCustomerDetailTagRequired);
      return;
    }
    if (name.length > 16) {
      setState(() => _tagError = stringsOf(context).merchantCustomerDetailTagLength);
      return;
    }
    final String fingerprint = '$name|#2E6D5A';
    if (_tagRequestId == null || _tagFingerprint != fingerprint) {
      _tagRequestId = _requestId('tag');
      _tagFingerprint = fingerprint;
    }
    setState(() {
      _tagSubmitting = true;
      _tagError = '';
    });
    try {
      final MerchantCustomerMutationReceipt receipt = await widget.api
          .assignTag(
            customerMemberId: widget.customerMemberId,
            tagName: _tagController.text,
            tagColor: '#2E6D5A',
            requestId: _tagRequestId!,
          );
      if (!mounted) return;
      _tagRequestId = null;
      _tagFingerprint = null;
      _tagController.clear();
      setState(() {
        _tagSubmitting = false;
        _tagError = '';
      });
      await _refreshAfterMutation(merchantCustomerApiReceipt(context, receipt));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _tagSubmitting = false;
        _tagError = _message(context, error, stringsOf(context).merchantCustomerDetailTagError);
      });
    }
  }

  Future<void> _submitNote() async {
    if (!_access.canSegmentCrm || _noteSubmitting) return;
    final String content = _noteController.text.trim();
    if (content.isEmpty) {
      setState(() => _noteError = stringsOf(context).merchantCustomerDetailNoteRequired);
      return;
    }
    if (content.length > 500) {
      setState(() => _noteError = stringsOf(context).merchantCustomerDetailNoteLength);
      return;
    }
    final String fingerprint = '${_correctsNoteId ?? ''}|$content';
    if (_noteRequestId == null || _noteFingerprint != fingerprint) {
      _noteRequestId = _requestId('note');
      _noteFingerprint = fingerprint;
    }
    setState(() {
      _noteSubmitting = true;
      _noteError = '';
    });
    try {
      final MerchantCustomerMutationReceipt receipt = await widget.api.addNote(
        customerMemberId: widget.customerMemberId,
        content: _noteController.text,
        requestId: _noteRequestId!,
        correctsNoteId: _correctsNoteId,
      );
      if (!mounted) return;
      _noteRequestId = null;
      _noteFingerprint = null;
      _correctsNoteId = null;
      _noteController.clear();
      setState(() {
        _noteSubmitting = false;
        _noteError = '';
      });
      await _refreshAfterMutation(merchantCustomerApiReceipt(context, receipt));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _noteSubmitting = false;
        _noteError = _message(context, error, stringsOf(context).merchantCustomerDetailNoteError);
      });
    }
  }

  Future<void> _refreshAfterMutation(String receiptMessage) async {
    if (!mounted) return;
    CyNativeNotice.show(context, receiptMessage);
    final int token = ++_requestToken;
    try {
      final MerchantCustomerDetail detail = await widget.api.detail(
        widget.customerMemberId,
      );
      if (!mounted || token != _requestToken) return;
      setState(() => _detail = detail);
    } on Object {
      if (!mounted || token != _requestToken) return;
      CyNativeNotice.show(context, stringsOf(context).merchantCustomerDetailRefreshError, isError: true);
    }
  }

  void _cancelCorrection() {
    _noteRequestId = null;
    _noteFingerprint = null;
    _noteController.clear();
    setState(() {
      _correctsNoteId = null;
      _noteError = '';
    });
  }

  void _startCorrection(int noteId) {
    if (!_access.canSegmentCrm || noteId <= 0) return;
    _noteRequestId = null;
    _noteFingerprint = null;
    _noteController.clear();
    setState(() {
      _correctsNoteId = noteId;
      _noteError = '';
    });
  }

  Future<void> _confirmHideNote(MerchantCustomerTimelineItem item) async {
    if (!_access.canSegmentCrm ||
        !item.canManageNote ||
        _hidingNoteId != null) {
      return;
    }
    final bool confirmed = await cyConfirm(
      context,
      title: stringsOf(context).merchantCustomerDetailHideTitle,
      content: stringsOf(context).merchantCrmPolicyHideAudit,
      confirmText: stringsOf(context).merchantCustomerDetailHide,
      danger: true,
    );
    if (!confirmed || !mounted) return;
    await _hideNote(item.noteId!, item.noteVersion!);
  }

  Future<void> _hideNote(int noteId, int expectedVersion) async {
    final String requestId = _hideRequestIds.putIfAbsent(
      noteId,
      () => _requestId('note'),
    );
    setState(() => _hidingNoteId = noteId);
    try {
      final MerchantCustomerMutationReceipt receipt = await widget.api.hideNote(
        customerMemberId: widget.customerMemberId,
        noteId: noteId,
        expectedVersion: expectedVersion,
        requestId: requestId,
      );
      if (!mounted) return;
      _hideRequestIds.remove(noteId);
      setState(() => _hidingNoteId = null);
      await _refreshAfterMutation(merchantCustomerApiReceipt(context, receipt));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _hidingNoteId = null);
      CyNativeNotice.show(context, _message(context, error, stringsOf(context).merchantCustomerDetailHideError), isError: true);
    }
  }

  Future<void> _confirmRemoveTag(MerchantCustomerTag tag) async {
    if (!_access.canSegmentCrm || _removingTagId != null) return;
    final bool confirmed = await cyConfirm(
      context,
      title: stringsOf(context).merchantCustomerDetailRemoveTitle,
      content: stringsOf(context).merchantCrmPolicyRemoveRelation,
      confirmText: stringsOf(context).merchantCustomerDetailRemove,
      danger: true,
    );
    if (!confirmed || !mounted) return;
    await _removeTag(tag.id);
  }

  Future<void> _removeTag(int tagId) async {
    final String requestId = _removeTagRequestIds.putIfAbsent(
      tagId,
      () => _requestId('tag'),
    );
    setState(() => _removingTagId = tagId);
    try {
      final MerchantCustomerMutationReceipt receipt = await widget.api
          .removeTag(
            customerMemberId: widget.customerMemberId,
            tagId: tagId,
            requestId: requestId,
          );
      if (!mounted) return;
      _removeTagRequestIds.remove(tagId);
      setState(() => _removingTagId = null);
      await _refreshAfterMutation(merchantCustomerApiReceipt(context, receipt));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _removingTagId = null);
      CyNativeNotice.show(context, _message(context, error, stringsOf(context).merchantCustomerDetailRemoveError), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantCustomerDetailTitle)),
      child: SafeArea(bottom: false, child: _body()),
    );
  }

  Widget _body() {
    switch (_pageState) {
      case _CustomerDetailPageState.loading:
        return const CySkeleton(type: CySkeletonType.card, count: 4);
      case _CustomerDetailPageState.noPermission:
        return StatusView(
          message: stringsOf(context).merchantCustomerDetailDenied,
          sub: stringsOf(context).merchantCustomerDetailDeniedHint,
          icon: CupertinoIcons.lock_fill,
          large: true,
        );
      case _CustomerDetailPageState.error:
        return StatusView(
          message: stringsOf(context).merchantCustomerDetailLoadError,
          sub: _errorMessage,
          retryLabel: stringsOf(context).merchantCustomerDetailReload,
          onRetry: _loadAccessAndDetail,
          large: true,
        );
      case _CustomerDetailPageState.ready:
        return _ReadyCustomerDetail(
          detail: _detail!,
          canEdit: _access.canSegmentCrm,
          tagController: _tagController,
          noteController: _noteController,
          tagSubmitting: _tagSubmitting,
          noteSubmitting: _noteSubmitting,
          tagError: _tagError,
          noteError: _noteError,
          correctsNoteId: _correctsNoteId,
          hidingNoteId: _hidingNoteId,
          removingTagId: _removingTagId,
          onSubmitTag: _submitTag,
          onSubmitNote: _submitNote,
          onCancelCorrection: _cancelCorrection,
          onCorrectNote: _startCorrection,
          onHideNote: _confirmHideNote,
          onRemoveTag: _confirmRemoveTag,
        );
    }
  }
}

class _ReadyCustomerDetail extends StatelessWidget {
  const _ReadyCustomerDetail({
    required this.detail,
    required this.canEdit,
    required this.tagController,
    required this.noteController,
    required this.tagSubmitting,
    required this.noteSubmitting,
    required this.tagError,
    required this.noteError,
    required this.correctsNoteId,
    required this.hidingNoteId,
    required this.removingTagId,
    required this.onSubmitTag,
    required this.onSubmitNote,
    required this.onCancelCorrection,
    required this.onCorrectNote,
    required this.onHideNote,
    required this.onRemoveTag,
  });

  final MerchantCustomerDetail detail;
  final bool canEdit;
  final TextEditingController tagController;
  final TextEditingController noteController;
  final bool tagSubmitting;
  final bool noteSubmitting;
  final String tagError;
  final String noteError;
  final int? correctsNoteId;
  final int? hidingNoteId;
  final int? removingTagId;
  final VoidCallback onSubmitTag;
  final VoidCallback onSubmitNote;
  final VoidCallback onCancelCorrection;
  final ValueChanged<int> onCorrectNote;
  final ValueChanged<MerchantCustomerTimelineItem> onHideNote;
  final ValueChanged<MerchantCustomerTag> onRemoveTag;

  @override
  Widget build(BuildContext context) {
    final MerchantCustomerSummary summary = detail.summary;
    return Material(
      color: Colors.transparent,
      child: ListView(
        key: const Key('merchant-customer-detail-scroll'),
        padding: const EdgeInsets.fromLTRB(
          CyTokens.pageX,
          CyTokens.space2,
          CyTokens.pageX,
          CyTokens.space8,
        ),
        children: <Widget>[
          _Surface(
            child: Row(
              children: <Widget>[
                CyAvatar(
                  url: summary.avatar,
                  fallback: summary.hasNameFallback
                      ? null
                      : summary.displayName,
                  size: 48,
                ),
                const SizedBox(width: CyTokens.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        summary.hasNameFallback ? stringsOf(context).merchantCrmUnnamed : summary.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: CyPalette.of(context).textPrimary,
                          fontSize: CyTokens.typeCardTitle,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: CyTokens.space1),
                      Text(
                        stringsOf(context).merchantCustomerDetailLastInteraction(summary.lastInteractionTimeText.isEmpty ? stringsOf(context).merchantCustomerDetailTimeUnknown : summary.lastInteractionTimeText),
                        style: TextStyle(
                          color: CyPalette.of(context).textSecondary,
                          fontSize: CyTokens.typeCaption,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: CyTokens.space2),
                Text(
                  summary.paidAmount == null ? stringsOf(context).merchantCustomerDetailAmountDenied : summary.paidAmountText,
                  style: TextStyle(
                    color: CyPalette.of(context).textPrimary,
                    fontSize: CyTokens.typeBody,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: CyTokens.space3),
          _Surface(
            padding: EdgeInsets.zero,
            child: Row(
              children: <Widget>[
                _Stat(value: summary.arrivedCount, label: stringsOf(context).merchantCustomerDetailArrived),
                _Divider(),
                _Stat(value: summary.pendingCount, label: stringsOf(context).merchantCustomerDetailPending),
                _Divider(),
                _Stat(value: summary.refundedCount, label: stringsOf(context).merchantCustomerDetailRefunded),
              ],
            ),
          ),
          const SizedBox(height: CyTokens.space5),
          _SectionHeader(title: stringsOf(context).merchantCustomerDetailTags, hint: stringsOf(context).merchantCustomerDetailTagHint),
          _GroupLabel(stringsOf(context).merchantCustomerDetailSystemTags),
          _TagGroup(
            emptyText: stringsOf(context).merchantCustomerDetailSystemEmpty,
            children: <Widget>[
              for (final MerchantCustomerSystemTag tag in detail.systemTags)
                _TagChip(label: tag.label),
            ],
          ),
          const SizedBox(height: CyTokens.space4),
          _GroupLabel(stringsOf(context).merchantCustomerDetailStoreTags),
          _TagGroup(
            emptyText: stringsOf(context).merchantCustomerDetailStoreEmpty,
            children: <Widget>[
              for (final MerchantCustomerTag tag in detail.merchantTags)
                _TagChip(
                  label: tag.tagName,
                  color: _color(tag.tagColor),
                  onRemove: canEdit && removingTagId == null
                      ? () => onRemoveTag(tag)
                      : null,
                  removing: removingTagId == tag.id,
                  removeKey: Key('merchant-customer-remove-tag-${tag.id}'),
                ),
            ],
          ),
          if (canEdit) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            Row(
              children: <Widget>[
                Expanded(
                  child: CupertinoTextField(
                    key: const Key('merchant-customer-tag-input'),
                    controller: tagController,
                    placeholder: stringsOf(context).merchantCustomerDetailTagExample,
                    textInputAction: TextInputAction.done,
                    inputFormatters: <TextInputFormatter>[
                      LengthLimitingTextInputFormatter(16),
                    ],
                    onSubmitted: (_) => onSubmitTag(),
                    onChanged: (_) {},
                    padding: const EdgeInsets.symmetric(
                      horizontal: CyTokens.space3,
                      vertical: CyTokens.space2_5,
                    ),
                    decoration: BoxDecoration(
                      color: CyPalette.of(context).inputBgEmpty,
                      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                    ),
                  ),
                ),
                const SizedBox(width: CyTokens.space2),
                CyNativeButton(
                  label: stringsOf(context).merchantCustomerDetailAdd,
                  onPressed: onSubmitTag,
                  loading: tagSubmitting,
                  role: CyNativeButtonRole.secondary,
                ),
              ],
            ),
            if (tagError.isNotEmpty) _InlineError(tagError),
          ],
          if (canEdit) ...<Widget>[
            const SizedBox(height: CyTokens.space5),
            _SectionHeader(
              title: correctsNoteId == null ? stringsOf(context).merchantCustomerDetailFollowUp : stringsOf(context).merchantCustomerDetailCorrection,
              trailing: correctsNoteId == null
                  ? null
                  : CupertinoButton(
                      minimumSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                      onPressed: onCancelCorrection,
                      child: Text(stringsOf(context).merchantCustomerDetailCancelCorrection),
                    ),
            ),
            if (correctsNoteId != null)
              Padding(
                padding: const EdgeInsets.only(bottom: CyTokens.space2),
                child: Text(
                  stringsOf(context).merchantCrmPolicyCorrection(correctsNoteId!),
                  style: TextStyle(
                    color: CupertinoColors.systemOrange.resolveFrom(context),
                    fontSize: CyTokens.typeCaption,
                  ),
                ),
              ),
            CupertinoTextField(
              key: const Key('merchant-customer-note-input'),
              controller: noteController,
              placeholder: stringsOf(context).merchantCustomerDetailNoteHint,
              minLines: 4,
              maxLines: 6,
              textInputAction: TextInputAction.newline,
              inputFormatters: <TextInputFormatter>[
                LengthLimitingTextInputFormatter(500),
              ],
              padding: const EdgeInsets.all(CyTokens.space3),
              decoration: BoxDecoration(
                color: CyPalette.of(context).inputBgEmpty,
                borderRadius: BorderRadius.circular(CyTokens.radiusLg),
              ),
            ),
            if (noteError.isNotEmpty) _InlineError(noteError),
            const SizedBox(height: CyTokens.space3),
            SizedBox(
              width: double.infinity,
              child: CyNativeButton(
                label: stringsOf(context).merchantCustomerDetailSaveNote,
                onPressed: onSubmitNote,
                loading: noteSubmitting,
              ),
            ),
          ],
          const SizedBox(height: CyTokens.space5),
          _SectionHeader(title: stringsOf(context).merchantCustomerDetailTimeline),
          if (detail.timeline.isEmpty)
            _EmptyLine(stringsOf(context).merchantCustomerDetailTimelineEmpty)
          else
            _Surface(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  for (int index = 0; index < detail.timeline.length; index++)
                    _TimelineRow(
                      item: detail.timeline[index],
                      showBorder: index > 0,
                      canEdit: canEdit,
                      onCorrectNote: onCorrectNote,
                      onHideNote: onHideNote,
                      hiding: hidingNoteId == detail.timeline[index].noteId,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static Color _color(String hex) =>
      Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);
}

class _Surface extends StatelessWidget {
  const _Surface({
    required this.child,
    this.padding = const EdgeInsets.all(CyTokens.space4),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: CyPalette.of(context).bgSurface,
      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      border: CyPalette.of(context).cardBorder == Colors.transparent
          ? null
          : Border.all(color: CyPalette.of(context).cardBorder),
      boxShadow: CyPalette.of(context).cardShadow,
    ),
    child: child,
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.all(CyTokens.space3),
      child: Column(
        children: <Widget>[
          Text(
            '$value',
            style: TextStyle(
              color: CyPalette.of(context).textPrimary,
              fontSize: CyTokens.typeSectionTitle,
              fontWeight: FontWeight.w700,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            label,
            style: TextStyle(
              color: CyPalette.of(context).textSecondary,
              fontSize: CyTokens.typeCaption,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 44,
    color: CyPalette.of(context).borderSubtle,
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.hint, this.trailing});

  final String title;
  final String? hint;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: CyTokens.space2_5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: CyPalette.of(context).textPrimary,
              fontSize: CyTokens.typeCardTitle,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (trailing != null)
          trailing!
        else if (hint != null)
          Text(
            hint!,
            style: TextStyle(
              color: CyPalette.of(context).textSecondary,
              fontSize: CyTokens.typeCaption,
            ),
          ),
      ],
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.only(top: CyTokens.space2),
      child: Text(
        message,
        style: TextStyle(
          color: CupertinoColors.systemRed.resolveFrom(context),
          fontSize: CyTokens.typeCaption,
        ),
      ),
    ),
  );
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: CyTokens.space2),
    child: Text(
      label,
      style: TextStyle(
        color: CyPalette.of(context).textSecondary,
        fontSize: CyTokens.typeCaption,
      ),
    ),
  );
}

class _TagGroup extends StatelessWidget {
  const _TagGroup({required this.emptyText, required this.children});

  final String emptyText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => children.isEmpty
      ? _EmptyLine(emptyText)
      : Wrap(
          spacing: CyTokens.space2,
          runSpacing: CyTokens.space2,
          children: children,
        );
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    this.color,
    this.onRemove,
    this.removing = false,
    this.removeKey,
  });

  final String label;
  final Color? color;
  final VoidCallback? onRemove;
  final bool removing;
  final Key? removeKey;

  @override
  Widget build(BuildContext context) {
    final Color foreground = color ?? CyPalette.of(context).textSecondary;
    return Container(
      constraints: const BoxConstraints(minHeight: CyTokens.btnHSm),
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2_5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color == null
            ? CyPalette.of(context).bgSubtle
            : CyPalette.of(context).bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusPill),
        border: Border.all(color: color ?? CyPalette.of(context).borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(color: foreground, fontSize: CyTokens.typeCaption),
          ),
          if (onRemove != null || removing) ...<Widget>[
            const SizedBox(width: CyTokens.space1),
            Semantics(
              button: true,
              enabled: onRemove != null && !removing,
              label: stringsOf(context).merchantCustomerDetailRemoveSemantics(label),
              child: CupertinoButton(
                key: removeKey,
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
                onPressed: removing ? null : onRemove,
                child: removing
                    ? const CupertinoActivityIndicator(radius: 8)
                    : Icon(CupertinoIcons.xmark, size: 15, color: foreground),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(CyTokens.space4),
    decoration: BoxDecoration(
      color: CyPalette.of(context).bgSurface,
      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: CyPalette.of(context).textSecondary,
        fontSize: CyTokens.typeLabel,
      ),
    ),
  );
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.item,
    required this.showBorder,
    required this.canEdit,
    required this.onCorrectNote,
    required this.onHideNote,
    required this.hiding,
  });

  final MerchantCustomerTimelineItem item;
  final bool showBorder;
  final bool canEdit;
  final ValueChanged<int> onCorrectNote;
  final ValueChanged<MerchantCustomerTimelineItem> onHideNote;
  final bool hiding;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(CyTokens.space3),
    decoration: BoxDecoration(
      border: showBorder
          ? Border(top: BorderSide(color: CyPalette.of(context).borderSubtle))
          : null,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: CyTokens.space1_5),
          decoration: BoxDecoration(
            color: CyPalette.of(context).brand,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: CyTokens.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      item.title,
                      style: TextStyle(
                        color: CyPalette.of(context).textPrimary,
                        fontSize: CyTokens.typeBody,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    switch(item.type) {
'NOTE' => stringsOf(context).merchantCustomerDetailNoteType,
'NOTE_CORRECTION' => stringsOf(context).merchantCustomerDetailCorrectionType,
'ARRIVED' => stringsOf(context).merchantCustomerDetailArrivedType,
'REFUNDED' => stringsOf(context).merchantCustomerDetailRefundedType,
'REGISTERED' => stringsOf(context).merchantCustomerDetailRegisteredType,
'CAMPAIGN' => stringsOf(context).merchantCustomerDetailCampaignType,
_ => item.typeText,
},
                    style: TextStyle(
                      color: CyPalette.of(context).textSecondary,
                      fontSize: CyTokens.typeCaption,
                    ),
                  ),
                ],
              ),
              if (item.description.isNotEmpty) ...<Widget>[
                const SizedBox(height: CyTokens.space1),
                Text(
                  item.description,
                  style: TextStyle(
                    color: CyPalette.of(context).textSecondary,
                    fontSize: CyTokens.typeLabel,
                    height: CyTokens.leadingNormal,
                  ),
                ),
              ],
              const SizedBox(height: CyTokens.space1),
              Text(
                item.occurredAtText.isEmpty ? stringsOf(context).merchantCustomerDetailTimeUnknown : item.occurredAtText,
                style: TextStyle(
                  color: CyPalette.of(context).textSecondary,
                  fontSize: CyTokens.typeCaption,
                ),
              ),
              if (canEdit && item.canManageNote) ...<Widget>[
                const SizedBox(height: CyTokens.space2),
                Row(
                  children: <Widget>[
                    CupertinoButton(
                      key: Key('merchant-customer-correct-note-${item.noteId}'),
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: CyTokens.space2,
                      ),
                      onPressed: hiding
                          ? null
                          : () => onCorrectNote(item.noteId!),
                      child: Text(stringsOf(context).merchantCustomerDetailCorrection),
                    ),
                    const SizedBox(width: CyTokens.space2),
                    CupertinoButton(
                      key: Key('merchant-customer-hide-note-${item.noteId}'),
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: CyTokens.space2,
                      ),
                      onPressed: hiding ? null : () => onHideNote(item),
                      child: Text(
                        hiding ? stringsOf(context).merchantCustomerDetailProcessing : stringsOf(context).merchantCustomerDetailHide,
                        style: TextStyle(
                          color: CupertinoColors.systemRed.resolveFrom(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

String _message(BuildContext context, Object error, String fallback) {
  if (error is MerchantCustomerDetailApiException &&
      error.message.trim().isNotEmpty) {
    return merchantCustomerApiError(context, error);
  }
  final String text = error.toString().replaceFirst('Exception: ', '').trim();
  return text.isEmpty ? fallback : text;
}
