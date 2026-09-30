import 'dart:io';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_image_source_sheet.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/merchant_aftercare_api.dart';
import '../../data/api/merchant_api.dart';
import '../../data/models/merchant_aftercare.dart';

typedef MerchantAftercareEvidencePicker =
    Future<MerchantAftercareEvidence?> Function(
      BuildContext context,
      MerchantAftercareGateway api,
    );
typedef MerchantAftercareRequestIdFactory = String Function();
typedef MerchantAftercareEvidencePurposeConfirmer =
    Future<bool> Function(BuildContext context);
typedef MerchantAftercareSettingsOpener = Future<bool> Function();

Future<bool> _confirmEvidencePurpose(BuildContext context) => cyConfirm(
  context,
  title: '添加售后凭证',
  content: '仅在你主动选择后访问相机或照片，用于拍摄并上传本次售后的真实凭证；不会在后台访问其他图片。',
  cancelText: '暂不添加',
  confirmText: '继续选择',
);

Future<bool> _openSystemSettings() => Geolocator.openAppSettings();

class MerchantAftercareDetailPage extends StatefulWidget {
  const MerchantAftercareDetailPage({
    super.key,
    required this.api,
    required this.refundId,
    this.evidencePicker,
    this.requestIdFactory,
    this.confirmEvidencePurpose = _confirmEvidencePurpose,
    this.openSystemSettings = _openSystemSettings,
  });

  final MerchantAftercareGateway api;
  final int refundId;
  final MerchantAftercareEvidencePicker? evidencePicker;
  final MerchantAftercareRequestIdFactory? requestIdFactory;
  final MerchantAftercareEvidencePurposeConfirmer confirmEvidencePurpose;
  final MerchantAftercareSettingsOpener openSystemSettings;

  @override
  State<MerchantAftercareDetailPage> createState() =>
      _MerchantAftercareDetailPageState();
}

class _MerchantAftercareDetailPageState
    extends State<MerchantAftercareDetailPage> {
  final TextEditingController _content = TextEditingController();

  MerchantAftercareDetail? _detail;
  MerchantAftercareDecision? _decision;

  /// 三档意见各自的说明(快照 index.wxml:134-143 的 decision-sub)。
  String get _decisionHint => switch (_decision) {
    MerchantAftercareDecision.agree => '同意平台继续审核',
    MerchantAftercareDecision.reject => '必须填写原因',
    MerchantAftercareDecision.evidence => '只追加材料',
    null => '',
  };
  MerchantAftercareEvidence? _evidence;
  Object? _error;
  String? _submitError;
  bool _loading = true;
  bool _submitting = false;
  bool _uploading = false;
  bool _evidencePurposeAccepted = false;
  int _requestToken = 0;
  String? _requestId;
  String? _requestFingerprint;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  @override
  void dispose() {
    _requestToken += 1;
    _content.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final int token = ++_requestToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final MerchantAftercareDetail detail = await widget.api.detail(
        refundId: widget.refundId,
      );
      if (!mounted || token != _requestToken) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  MerchantAftercareResponseDraft? _draft() {
    final MerchantAftercareDecision? decision = _decision;
    if (decision == null) return null;
    return MerchantAftercareResponseDraft(
      decision: decision,
      content: _content.text,
      evidenceKey: _evidence?.objectKey,
    );
  }

  void _selectDecision(MerchantAftercareDecision decision) {
    if (_submitting || _detail?.allowedDecisions.contains(decision) != true) {
      return;
    }
    setState(() {
      _decision = decision;
      _submitError = null;
    });
  }

  Future<void> _pickEvidence() async {
    if (_uploading || _submitting) return;
    if (!_evidencePurposeAccepted) {
      final bool accepted = await widget.confirmEvidencePurpose(context);
      if (!accepted || !mounted) return;
      _evidencePurposeAccepted = true;
    }
    setState(() {
      _uploading = true;
      _submitError = null;
    });
    try {
      final MerchantAftercareEvidence? evidence =
          await (widget.evidencePicker ?? _defaultEvidencePicker)(
            context,
            widget.api,
          );
      if (!mounted) return;
      if (evidence != null &&
          MerchantAftercareEvidence.isObjectKey(evidence.objectKey)) {
        setState(() => _evidence = evidence);
      }
    } on PlatformException {
      if (!mounted) return;
      // 权限提示在等待用户决定时不应继续显示上传进度。
      setState(() => _uploading = false);
      final bool shouldOpenSettings = await cyConfirm(
        context,
        title: '无法访问相机或照片',
        content: '请前往系统“设置”允许城瘾访问相机或照片，然后返回重试。',
        cancelText: '取消',
        confirmText: '打开设置',
      );
      if (shouldOpenSettings) {
        await widget.openSystemSettings();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting || _uploading) return;
    final MerchantAftercareResponseDraft? draft = _draft();
    if (draft == null) {
      setState(() => _submitError = '请选择处理意见');
      return;
    }
    final String? validationError = draft.validationError;
    if (validationError != null) {
      setState(() => _submitError = validationError);
      return;
    }
    if (_requestId == null || _requestFingerprint != draft.fingerprint) {
      _requestId = (widget.requestIdFactory ?? _newRequestId)();
      _requestFingerprint = draft.fingerprint;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final MerchantAftercareReceipt receipt = await widget.api.respond(
        refundId: widget.refundId,
        draft: draft,
        requestId: _requestId!,
      );
      if (!mounted) return;
      _requestId = null;
      _requestFingerprint = null;
      _content.clear();
      setState(() {
        _decision = null;
        _evidence = null;
        _submitting = false;
      });
      CyNativeNotice.show(
        context,
        receipt.decision == MerchantAftercareDecision.evidence
            ? '凭证已提交，等待平台处理'
            : '意见已提交，等待平台处理',
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _previewEvidence(Uri url) {
    return showCupertinoModalPopup<void>(
      context: context,
      semanticsDismissible: true,
      builder: (BuildContext previewContext) => CupertinoPopupSurface(
        isSurfacePainted: true,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.sizeOf(previewContext).height * 0.72,
            child: Column(
              children: <Widget>[
                Align(
                  alignment: Alignment.centerRight,
                  child: CupertinoButton(
                    minimumSize: const Size(44, 44),
                    onPressed: () => Navigator.of(previewContext).pop(),
                    child: const Icon(
                      CupertinoIcons.xmark_circle_fill,
                      semanticLabel: '关闭凭证预览',
                    ),
                  ),
                ),
                Expanded(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: CyNetImage(
                        url.toString(),
                        width: double.infinity,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CyPalette.of(context).bgPage,
      navigationBar: const CupertinoNavigationBar(middle: Text('退款售后')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(bottom: false, child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading && _detail == null) {
      // 真源 pages/merchant/aftercare/detail 用 card 档 count=3。
      return const CySkeleton(type: CySkeletonType.card, count: 3);
    }
    final Object? error = _error;
    if (error is MerchantAccessDeniedException) {
      return StatusView(
        icon: CupertinoIcons.lock,
        message: error.message,
        sub: '请联系店主调整经营团队权限',
        large: true,
      );
    }
    if (error is MerchantAftercareApiException && error.isForbidden) {
      return const StatusView(
        icon: CupertinoIcons.lock,
        message: '当前岗位没有售后查看权限',
        sub: '请联系店主调整经营团队权限',
        large: true,
      );
    }
    if (error is MerchantAftercareApiException && error.isNotFound) {
      return const StatusView(
        icon: CupertinoIcons.doc_text,
        message: '售后单不存在或无权访问',
        sub: '这笔申请可能已撤回，或不属于当前门店',
        large: true,
      );
    }
    if (error != null && _detail == null) {
      return StatusView(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: '退款售后没能加载出来',
        sub: error.toString(),
        large: true,
        onRetry: _load,
        retryLabel: '重新加载',
      );
    }
    final MerchantAftercareDetail detail = _detail!;
    return RefreshIndicator.adaptive(
      onRefresh: _load,
      child: ListView(
        key: const Key('aftercare-detail-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          CyTokens.pageX,
          CyTokens.space2,
          CyTokens.pageX,
          CyTokens.space8,
        ),
        children: <Widget>[
          _hero(context, detail),
          const SizedBox(height: CyTokens.space5),
          _sectionTitle(context, '当前状态'),
          _statusCard(context, detail),
          const SizedBox(height: CyTokens.space5),
          _sectionTitle(context, '商家意见与处理记录'),
          _history(context, detail),
          const SizedBox(height: CyTokens.space5),
          if (detail.canRespond)
            _responseForm(context, detail)
          else
            _readonly(context),
        ],
      ),
    );
  }

  Widget _hero(BuildContext context, MerchantAftercareDetail detail) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      detail.sourceText,
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: CyTokens.space1),
                    Text(detail.refundNoText, style: textTheme.titleSmall),
                  ],
                ),
              ),
              Text(
                detail.refundAmountText,
                style: textTheme.headlineSmall?.copyWith(
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          if (detail.reason != null) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            Divider(height: 1, color: palette.borderSubtle),
            const SizedBox(height: CyTokens.space3),
            Text('申请原因', style: textTheme.bodySmall),
            const SizedBox(height: CyTokens.space1),
            Text(detail.reason!, style: textTheme.bodyMedium),
          ],
          if (detail.refundPolicyCode != null ||
              detail.refundPolicyVersion != null ||
              detail.refundDeadline != null) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            Divider(height: 1, color: palette.borderSubtle),
            const SizedBox(height: CyTokens.space3),
            Text('退款政策快照', style: textTheme.bodySmall),
            const SizedBox(height: CyTokens.space1),
            Text(detail.refundPolicyText, style: textTheme.bodyMedium),
            if (detail.refundPolicyVersion != null)
              Text(
                '政策版本 ${detail.refundPolicyVersion}',
                style: textTheme.bodySmall,
              ),
            if (detail.refundDeadline != null)
              Text(
                '可退截止 ${_minute(detail.refundDeadline)}',
                style: textTheme.bodySmall,
              ),
          ],
        ],
      ),
    );
  }

  Widget _statusCard(BuildContext context, MerchantAftercareDetail detail) {
    return Container(
      decoration: _cardDecoration(context),
      child: Column(
        children: <Widget>[
          _statusRow(
            context,
            label: '平台处理',
            value: detail.processing.label,
            hint: detail.processing.hint,
          ),
          _line(context),
          _statusRow(
            context,
            label: '商家意见',
            value: detail.merchantOpinion.label,
            hint: detail.merchantOpinion.hint,
          ),
          _line(context),
          _statusRow(
            context,
            label: '款项结果',
            value: detail.refunded ? '已确认退回' : '尚未确认退回',
            hint: detail.refunded ? '款项结果已由平台确认' : '不要根据商家意见推断退款结果',
          ),
        ],
      ),
    );
  }

  Widget _statusRow(
    BuildContext context, {
    required String label,
    required String value,
    required String hint,
  }) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(CyTokens.space3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: textTheme.titleSmall),
                const SizedBox(height: CyTokens.space1),
                Text(
                  hint,
                  style: textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: CyTokens.space2),
          _Pill(label: value),
        ],
      ),
    );
  }

  Widget _history(BuildContext context, MerchantAftercareDetail detail) {
    if (detail.responses.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(CyTokens.space5),
        alignment: Alignment.center,
        decoration: _cardDecoration(context),
        child: const Text('暂无商家补充记录'),
      );
    }
    return Container(
      decoration: _cardDecoration(context),
      child: Column(
        children: <Widget>[
          for (
            int index = 0;
            index < detail.responses.length;
            index++
          ) ...<Widget>[
            if (index > 0) _line(context),
            _historyRow(context, detail.responses[index]),
          ],
        ],
      ),
    );
  }

  Widget _historyRow(BuildContext context, MerchantAftercareResponse response) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(CyTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _Pill(label: response.decision.label),
              const Spacer(),
              Text(
                '${response.actorText}${response.createTime == null ? '' : ' · ${_minute(response.createTime)}'}',
                style: textTheme.bodySmall?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
          if (response.content != null) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Text(response.content!, style: textTheme.bodyMedium),
          ],
          if (response.evidenceUrl != null) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            CupertinoButton(
              key: Key('aftercare-response-evidence-${response.id}'),
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
              minimumSize: const Size.fromHeight(44),
              color: palette.bgSubtle,
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              onPressed: () => _previewEvidence(response.evidenceUrl!),
              child: Row(
                children: <Widget>[
                  const Text('售后凭证'),
                  const Spacer(),
                  Text(
                    '短时授权查看',
                    style: textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(width: CyTokens.space1),
                  const Icon(CupertinoIcons.chevron_forward, size: 15),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _responseForm(BuildContext context, MerchantAftercareDetail detail) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            detail.allowedDecisions.contains(MerchantAftercareDecision.agree)
                ? '追加商家意见'
                : '补充售后凭证',
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            detail.allowedDecisions.contains(MerchantAftercareDecision.agree)
                ? '平台独立审核；选择“同意”也不会直接改变退款或打款状态。'
                : '当前岗位仅可补充审核材料，不能同意或建议驳回。',
            style: textTheme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: CyTokens.space3),
          Wrap(
            spacing: CyTokens.space2,
            runSpacing: CyTokens.space2,
            children: <Widget>[
              for (final MerchantAftercareDecision decision
                  in detail.allowedDecisions)
                CupertinoButton(
                  key: Key('aftercare-decision-${decision.wire}'),
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space3,
                  ),
                  color: _decision == decision
                      ? palette.actionPrimaryBg
                      : palette.bgSubtle,
                  borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                  onPressed: _submitting
                      ? null
                      : () => _selectDecision(decision),
                  child: Text(
                    decision.label,
                    style: TextStyle(
                      color: _decision == decision
                          ? palette.actionPrimaryFg
                          : palette.textPrimary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: CyTokens.space3),
          if (_decisionHint.isNotEmpty) ...<Widget>[
            Text(
              _decisionHint,
              key: const Key('aftercare-decision-hint'),
              style: textTheme.bodySmall?.copyWith(
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: CyTokens.space3),
          ],
          Row(
            children: <Widget>[
              Text(
                '意见说明${_decision == MerchantAftercareDecision.reject ? '（必填）' : '（选填）'}',
                style: textTheme.titleSmall,
              ),
              const Spacer(),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _content,
                builder: (_, TextEditingValue value, _) => Text(
                  '${value.text.length} / 500',
                  style: textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CyTokens.space2),
          CupertinoTextField(
            key: const Key('aftercare-content'),
            controller: _content,
            minLines: 3,
            maxLines: 5,
            maxLength: 500,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            placeholder: '写下可供平台审核的订单事实',
            padding: const EdgeInsets.all(CyTokens.space3),
            decoration: BoxDecoration(
              color: palette.inputBgEmpty,
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            ),
            onChanged: (_) => setState(() => _submitError = null),
          ),
          const SizedBox(height: CyTokens.space3),
          if (_evidence == null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Semantics(
                  label: '选择图片并上传凭证',
                  button: true,
                  child: CyNativeButton(
                    label: '选择图片并上传',
                    role: CyNativeButtonRole.secondary,
                    loading: _uploading,
                    onPressed: _submitting ? null : _pickEvidence,
                    icon: const CyNativeButtonIcon(
                      sfSymbol: 'photo.badge.plus',
                      fallback: CupertinoIcons.photo_on_rectangle,
                    ),
                  ),
                ),
                const SizedBox(height: CyTokens.space1),
                Text(
                  '支持相册或拍摄，上传成功后才可提交补充凭证',
                  style: textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.all(CyTokens.space2),
              decoration: BoxDecoration(
                color: palette.bgSubtle,
                borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              ),
              child: Row(
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                    child: Image.file(
                      File(_evidence!.localPath),
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => SizedBox(
                        width: 52,
                        height: 52,
                        child: ColoredBox(color: palette.bgSurfaceSubtle),
                      ),
                    ),
                  ),
                  const SizedBox(width: CyTokens.space2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('凭证已上传'),
                        Text(
                          '点击预览，可移除后重新选择',
                          style: textTheme.bodySmall?.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    label: '移除凭证',
                    button: true,
                    child: CyNativeButton(
                      label: '移除凭证',
                      role: CyNativeButtonRole.destructive,
                      onPressed: _submitting
                          ? null
                          : () => setState(() => _evidence = null),
                    ),
                  ),
                ],
              ),
            ),
          if (_submitError != null) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Text(
              _submitError!,
              key: const Key('aftercare-submit-error'),
              style: textTheme.bodySmall?.copyWith(
                color: CyPalette.of(context).statusDanger,
              ),
            ),
          ],
          const SizedBox(height: CyTokens.space4),
          CyNativeButton(
            key: const Key('aftercare-submit'),
            label: '提交商家意见',
            loading: _submitting,
            onPressed: _submitting || _uploading ? null : _submit,
          ),
        ],
      ),
    );
  }

  Widget _readonly(BuildContext context) => Container(
    padding: const EdgeInsets.all(CyTokens.space4),
    decoration: _cardDecoration(context),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('当前不可追加意见'),
        SizedBox(height: CyTokens.space1),
        Text('平台审核已结束，请以当前处理和款项状态为准。'),
      ],
    ),
  );

  Widget _sectionTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: CyTokens.space2),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _line(BuildContext context) => Divider(
    height: 1,
    indent: CyTokens.space3,
    endIndent: CyTokens.space3,
    color: CyPalette.of(context).borderSubtle,
  );

  BoxDecoration _cardDecoration(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return BoxDecoration(
      color: palette.bgSurface,
      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      border: Border.all(color: palette.cardBorder),
      boxShadow: palette.cardShadow,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: CyTokens.space2,
      vertical: CyTokens.space1,
    ),
    decoration: BoxDecoration(
      color: CyPalette.of(context).bgSubtle,
      borderRadius: BorderRadius.circular(CyTokens.radiusPill),
    ),
    child: Text(label, style: Theme.of(context).textTheme.bodySmall),
  );
}

Future<MerchantAftercareEvidence?> _defaultEvidencePicker(
  BuildContext context,
  MerchantAftercareGateway api,
) async {
  final CyImagePickSource? source = await cyChooseImageSource(context);
  if (source == null || !context.mounted) return null;
  final XFile? file = await ImagePicker().pickImage(
    source: source == CyImagePickSource.camera
        ? ImageSource.camera
        : ImageSource.gallery,
    imageQuality: 85,
  );
  if (file == null) return null;
  return api.uploadEvidence(file.path);
}

String _newRequestId() {
  final int now = DateTime.now().millisecondsSinceEpoch;
  final String random = Random.secure().nextInt(0x7fffffff).toRadixString(36);
  return 'ma:${now.toRadixString(36)}:1:$random';
}

String? _minute(DateTime? value) {
  if (value == null) return null;
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
