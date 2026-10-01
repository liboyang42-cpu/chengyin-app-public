import 'club_api_messages.dart';
import 'club_customer_labels.dart';
import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/club_crm_api.dart';
import '../../data/models/club_crm.dart';
import 'club_access_gate.dart';
import 'club_controller.dart';

/// K2 客户详情。三条服务端裁决,前端不猜:
///   ① 手机号只显示服务端 `phoneText`(脱敏或替代说明);
///   ② `paidAmount` 为 null = 本岗位无金额查看权限(K2-B),不是 0;
///   ③ 能不能编辑标签备注由 `canEdit` 下发。
class ClubCustomerDetailPage extends ConsumerStatefulWidget {
  const ClubCustomerDetailPage({
    super.key,
    required this.clubId,
    required this.memberId,
  });

  final int clubId;
  final int memberId;

  @override
  ConsumerState<ClubCustomerDetailPage> createState() =>
      _ClubCustomerDetailPageState();
}

class _ClubCustomerDetailPageState
    extends ConsumerState<ClubCustomerDetailPage> {
  bool _editing = false;
  List<String> _draftTags = <String>[];
  String _draftRemark = '';
  String _draftError = '';

  /// 这条错是**保存请求失败**(而不是草稿校验没过)。
  /// 小程序对前者给的是带标题的 cy-inline-error(「标签与备注没保存成功」+ 重试保存)。
  bool _draftErrorFromSave = false;
  bool _saving = false;
  int _requestSeq = 0;
  final TextEditingController _tagCtrl = TextEditingController();
  final TextEditingController _remarkCtrl = TextEditingController();

  ({int clubId, int memberId}) get _key =>
      (clubId: widget.clubId, memberId: widget.memberId);

  @override
  void dispose() {
    _tagCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/club/${widget.clubId}/customers');
  }

  void _startEdit(ClubCustomerDetail detail) {
    if (!detail.canEdit) return;
    setState(() {
      _editing = true;
      _draftErrorFromSave = false;
      _draftTags = List<String>.of(detail.tags);
      _draftRemark = detail.remark;
      _draftError = '';
    });
    _tagCtrl.clear();
    _remarkCtrl.text = detail.remark;
  }

  void _cancelEdit() {
    setState(() {
      _editing = false;
      _draftError = '';
      _draftErrorFromSave = false;
    });
  }

  void _addTag() {
    final String name = _tagCtrl.text.trim();
    if (name.isEmpty) return;
    final draft = buildClubTagRemarkDraft(<String>[
      ..._draftTags,
      name,
    ], _draftRemark);
    if (!draft.valid) {
      setState(() {
        _draftError = _draftErrorLabel(context, draft.error);
        _draftErrorFromSave = false;
      });
      return;
    }
    setState(() {
      _draftTags = draft.tags;
      _draftError = '';
      _draftErrorFromSave = false;
    });
    _tagCtrl.clear();
  }

  void _removeTag(int index) {
    if (index < 0 || index >= _draftTags.length) return;
    setState(() {
      _draftTags = List<String>.of(_draftTags)..removeAt(index);
      _draftError = '';
      _draftErrorFromSave = false;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final draft = buildClubTagRemarkDraft(_draftTags, _draftRemark);
    if (!draft.valid) {
      setState(() {
        _draftError = _draftErrorLabel(context, draft.error);
        _draftErrorFromSave = false;
      });
      return;
    }
    final int seq = _requestSeq + 1;
    _requestSeq = seq;
    final String requestId =
        'club-crm-app-${DateTime.now().millisecondsSinceEpoch}-$seq';
    setState(() {
      _saving = true;
      _draftError = '';
    });
    try {
      await ref
          .read(clubCrmApiProvider)
          .saveCustomerTagRemark(
            clubId: widget.clubId,
            memberId: widget.memberId,
            tags: draft.tags,
            remark: draft.remark,
            requestId: requestId,
          );
      if (!mounted) return;
      setState(() => _editing = false);
      CyNativeNotice.show(context, stringsOf(context).clubCustomerSaved);
      ref.invalidate(clubCustomerDetailProvider(_key));
    } on Exception catch (error) {
      if (!mounted) return;
      final bool unknown = error is ClubCrmApiException && error.outcomeUnknown;
      setState(() {
        // ★ 这里照说后端原话(clubCrmApi 已把 DioException 归一成中文)——
        //   换成通用人话会抹掉「为什么没保存上」。
        _draftError = unknown
            ? stringsOf(context).clubCustomerSaveUncertain
            : clubApiErrorMessage(context, error, fallback: stringsOf(context).clubCustomerSaveFailed);
        _draftErrorFromSave = true;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gate = evaluateClubAccess(
      ref.watch(clubAccessProvider(widget.clubId)),
      clubId: widget.clubId,
      permission: kClubMemberListRead,
    );
    final detail = ref.watch(clubCustomerDetailProvider(_key));
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: detail.when(
            loading: () => CySkeleton(label: stringsOf(context).clubCustomerLoading),
            error: (Object error, StackTrace _) => _errorView(error),
            data: (ClubCustomerDetail value) => switch (gate.decision) {
              ClubAccessDecision.deny => _noPermissionView(localizedClubAccessReason(context, gate)),
              ClubAccessDecision.checking => const CySkeleton(),
              _ => _body(context, value),
            },
          ),
        ),
      ),
    );
  }

  Widget _errorView(Object error) {
    final failure = classifyClubCrmFailure(error);
    if (failure.auth) {
      return _noPermissionView(
        clubApiErrorMessage(context, error, fallback: stringsOf(context).clubCustomerContactHost),
      );
    }
    if (widget.memberId <= 0) {
      return StatusView(
        message: stringsOf(context).clubCustomerCannotOpen,
        sub: stringsOf(context).clubCustomerMissing,
        icon: CupertinoIcons.person_crop_circle_badge_xmark,
        large: true,
        onRetry: _goBack,
        retryLabel: stringsOf(context).clubCustomerBack,
      );
    }
    return StatusView(
      message: stringsOf(context).clubCustomerLoadFailed,
      sub: failure.network
          ? stringsOf(context).clubCustomerNetworkRetry
          : clubApiErrorMessage(context, error, fallback: stringsOf(context).clubCustomerRetryLater),
      icon: CupertinoIcons.cloud,
      large: true,
      onRetry: () => ref.invalidate(clubCustomerDetailProvider(_key)),
    );
  }

  Widget _noPermissionView(String reason) {
    return StatusView(
      message: stringsOf(context).clubCustomersNoPermission,
      sub: reason.isEmpty ? stringsOf(context).clubCustomerPermissionHelp : reason,
      icon: CupertinoIcons.lock,
      large: true,
      onRetry: _goBack,
      retryLabel: stringsOf(context).clubCustomerBack,
    );
  }

  Widget _body(BuildContext context, ClubCustomerDetail detail) {
    final CyPalette palette = CyPalette.of(context);
    final ClubCustomerSummary summary = detail.summary;
    return ListView(
      padding: const EdgeInsets.only(
        left: CyTokens.pageX,
        right: CyTokens.pageX,
        bottom: CyTokens.space6,
      ),
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: CyTokens.space4),
                child: Text(
                  clubCustomerSummaryName(context, summary),
                  style: TextStyle(
                    fontSize: CyTokens.typePageTitle,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ),
            CyAvatar(
              url: summary.avatar,
              fallback: clubCustomerSummaryName(context, summary),
              size: 56,
            ),
          ],
        ),
        const SizedBox(height: CyTokens.space1),
        Text(
          clubCustomerInteraction(context, summary),
          style: TextStyle(color: palette.textSecondary),
        ),
        const SizedBox(height: CyTokens.space4),
        Container(
          padding: const EdgeInsets.all(CyTokens.space4),
          decoration: BoxDecoration(
            color: palette.bgSurface,
            borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            border: Border.all(color: palette.cardBorder),
          ),
          child: Row(
            children: <Widget>[
              Text(stringsOf(context).clubCustomerPaidTotal, style: TextStyle(color: palette.textSecondary)),
              const Spacer(),
              Text(
                summary.amountVisible ? summary.paidAmountText : stringsOf(context).clubCustomerAmountHidden,
                style: TextStyle(
                  color: summary.amountVisible
                      ? palette.textPrimary
                      : palette.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (summary.phoneText.isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space2),
          Text(
            summary.phoneText,
            style: TextStyle(color: palette.textSecondary),
          ),
        ],
        const SizedBox(height: CyTokens.space5),
        CySectionTitle(stringsOf(context).clubCustomerOverview),
        const SizedBox(height: CyTokens.space2),
        Row(
          children: <Widget>[
            _Stat(label: stringsOf(context).clubCustomerVisits, value: '${summary.arrivedCount}'),
            _Stat(label: stringsOf(context).clubCustomerPending, value: '${summary.pendingCount}'),
            _Stat(label: stringsOf(context).clubCustomerRefunded, value: '${summary.refundedCount}'),
          ],
        ),
        const SizedBox(height: CyTokens.space5),
        CySectionTitle(stringsOf(context).clubCustomerActivity),
        const SizedBox(height: CyTokens.space2),
        if (detail.records.isEmpty)
          StatusView(
            message: stringsOf(context).clubCustomerActivityEmpty,
            sub: stringsOf(context).clubCustomerActivityEmptyBody,
            icon: CupertinoIcons.doc_text,
          )
        else
          CupertinoListSection.insetGrouped(
            margin: const EdgeInsets.symmetric(vertical: CyTokens.space2),
            children: <Widget>[
              for (final ClubCustomerRecord record in detail.records)
                CupertinoListTile(
                  key: Key('club-customer-record-${record.key}'),
                  onTap: record.topicId == null
                      ? null
                      : () => context.push('/topic/${record.topicId}'),
                  leading: SizedBox(
                    width: 40,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          record.dayText,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          clubCustomerRecordMonth(context, record),
                          style: CyType.caption1.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  title: Text(clubCustomerRecordTitle(context, record)),
                  subtitle: _RecordStatus(record: record),
                  trailing: Icon(
                    CupertinoIcons.chevron_forward,
                    size: 16,
                    color: palette.textTertiary,
                  ),
                ),
            ],
          ),
        const SizedBox(height: CyTokens.space5),
        Row(
          children: <Widget>[
            Expanded(child: CySectionTitle(_editing ? stringsOf(context).clubCustomerEditNotes : stringsOf(context).clubCustomerNotes)),
            if (_editing)
              Semantics(
                button: true,
                excludeSemantics: true,
                label: stringsOf(context).clubCustomerCancelNotes,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  onPressed: _cancelEdit,
                  child: Text(stringsOf(context).clubCustomerCancel),
                ),
              ),
          ],
        ),
        const SizedBox(height: CyTokens.space2),
        if (!_editing)
          _tagCard(context, palette, detail)
        else
          _tagEditor(context, palette),
      ],
    );
  }

  Widget _tagCard(
    BuildContext context,
    CyPalette palette,
    ClubCustomerDetail detail,
  ) {
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: palette.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (detail.tags.isNotEmpty)
            Wrap(
              spacing: CyTokens.space2,
              runSpacing: CyTokens.space2,
              children: <Widget>[
                for (final String tag in detail.tags) CyTag(label: tag),
              ],
            ),
          const SizedBox(height: CyTokens.space2),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  detail.remarkText,
                  style: TextStyle(color: palette.textSecondary),
                ),
              ),
              if (detail.canEdit)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  onPressed: () => _startEdit(detail),
                  child: Text(stringsOf(context).clubCustomerEdit),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tagEditor(BuildContext context, CyPalette palette) {
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: palette.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_draftTags.isNotEmpty)
            Wrap(
              spacing: CyTokens.space2,
              runSpacing: CyTokens.space2,
              children: <Widget>[
                for (int i = 0; i < _draftTags.length; i += 1)
                  CupertinoButton(
                    key: Key('club-customer-tag-remove-$i'),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(44, 44),
                    onPressed: () => _removeTag(i),
                    child: CyTag(label: '${_draftTags[i]} ×'),
                  ),
              ],
            ),
          Row(
            children: <Widget>[
              Expanded(
                child: CupertinoTextField(
                  key: const Key('club-customer-tag-input'),
                  controller: _tagCtrl,
                  maxLength: kClubTagMaxLength,
                  placeholder: stringsOf(context).clubCustomerTagPlaceholder,
                  onSubmitted: (_) => _addTag(),
                ),
              ),
              const SizedBox(width: CyTokens.space2),
              Semantics(
                button: true,
                excludeSemantics: true,
                label: stringsOf(context).clubCustomerAddTag,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  onPressed: _addTag,
                  child: Text(stringsOf(context).clubCustomerAdd),
                ),
              ),
            ],
          ),
          const SizedBox(height: CyTokens.space2),
          CupertinoTextField(
            key: const Key('club-customer-remark-input'),
            controller: _remarkCtrl,
            maxLength: kClubRemarkMaxLength,
            maxLines: 3,
            minLines: 3,
            placeholder: stringsOf(context).clubCustomerNotePlaceholder,
            onChanged: (String value) => _draftRemark = value,
          ),
          if (_draftError.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            if (_draftErrorFromSave)
              Text(
                stringsOf(context).clubCustomerSaveErrorTitle,
                style: TextStyle(color: CyTokens.statusDanger),
              ),
            Text(
              _draftError,
              style: const TextStyle(color: CyTokens.statusDanger),
            ),
          ],
          const SizedBox(height: CyTokens.space3),
          CyNativeButton(
            label: stringsOf(context).clubCustomerSave,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            value,
            style: CyType.title2.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: CyTokens.space1),
          Text(label, style: TextStyle(color: palette.textSecondary)),
        ],
      ),
    );
  }
}

class _RecordStatus extends StatelessWidget {
  const _RecordStatus({required this.record});

  final ClubCustomerRecord record;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final Color color = switch (record.tone) {
      'success' => CyTokens.statusSuccess,
      'warning' => CyTokens.statusWarning,
      'danger' => CyTokens.statusDanger,
      _ => palette.textTertiary,
    };
    return Text(stringsOf(context).clubCustomerRegistration(clubCustomerRecordStatus(context, record)), style: TextStyle(color: color));
  }
}

String _draftErrorLabel(BuildContext context, String error) => switch (error) {
  '备注最多 $kClubRemarkMaxLength 字' => stringsOf(context).clubCustomerRemarkLimit(kClubRemarkMaxLength),
  '单个标签最多 $kClubTagMaxLength 字' => stringsOf(context).clubCustomerTagLength(kClubTagMaxLength),
  '标签最多 $kClubTagMaxCount 个' => stringsOf(context).clubCustomerTagCount(kClubTagMaxCount),
  _ => error,
};
