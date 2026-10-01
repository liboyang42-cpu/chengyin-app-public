import '../../core/theme/cy_palette.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_inline_error.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_native_progress.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/merchant_api.dart';
import '../../l10n/strings.dart';
import '../../data/models/merchant_apply.dart';
import '../../data/models/merchant_application.dart';
import '../../core/widgets/cy_net_image.dart';
import '../publisher/publisher_identity.dart';
import '../publisher/publisher_identity_fields.dart';

/// 进页先问「这个账号名下有没有已提交的申请」(真源 `checkExisting`)。
///
/// 三态互斥:在查 / 查出一行(→ 状态页)/ 后端明说 NONE → null(→ 四步表单)。
/// 单独一个 provider 而不是一进 initState 手发请求:重试只要 invalidate 一次,
/// 页面自己不再持有一份状态。
final merchantApplicationProvider =
    FutureProvider.autoDispose<MerchantApplication?>(
      (ref) => ref.watch(merchantApiProvider).application(),
    );

/// 商家入驻申请(四步向导)。对齐小程序 `pages/merchant/apply`。
///
/// ★★ 校验只有这一道:后端 MerchantRegistrationDTO:21 的 @NotBlank
///    是**被注释掉的**,服务端一个字段都不校验,空名字也会被建成商家记录。
class MerchantApplyPage extends ConsumerStatefulWidget {
  const MerchantApplyPage({super.key});

  @override
  ConsumerState<MerchantApplyPage> createState() => _MerchantApplyPageState();
}

String _applicationStatusLabel(BuildContext context, MerchantApplication a) {
  if (a.isDisabled) return stringsOf(context).merchantHomeDisabled;
  if (a.status == 1 && a.accountStatus == 1) return stringsOf(context).merchantHomeActive;
  if (a.isRejected) return stringsOf(context).merchantHomeRejected;
  if (a.status == 1) return stringsOf(context).merchantHomeAwaitingActivation;
  if (a.status == 0) return stringsOf(context).merchantHomeUnderReview;
  return stringsOf(context).merchantHomeUnknownStatus;
}

String _applicationStatusText(BuildContext context, MerchantApplication a) {
  if (a.isDisabled) {
    final reason = a.disableReason.trim();
    return reason.isEmpty ? stringsOf(context).merchantHomeDisabledNoReason : stringsOf(context).merchantHomeDisabledReason(reason);
  }
  if (a.status == 1 && a.accountStatus == 1) return stringsOf(context).merchantHomeActiveExplanation;
  if (a.isRejected) {
    final reason = a.rejectReason.trim();
    return reason.isEmpty ? stringsOf(context).merchantHomeRejectedNoReason : stringsOf(context).merchantHomeRejectedReason(reason);
  }
  if (a.status == 1) return stringsOf(context).merchantHomeActivationExplanation;
  if (a.status == 0) return stringsOf(context).merchantHomeReviewExplanation;
  return stringsOf(context).merchantHomeUnknownExplanation;
}

class _MerchantApplyPageState extends ConsumerState<MerchantApplyPage> {
  int _step = 1;
  MerchantApplyForm _form = const MerchantApplyForm();
  bool _submitting = false;
  bool _uploading = false;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _preferenceController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final List<bool> _businessDays = List<bool>.filled(7, true);
  DateTime _businessStart = DateTime(2000, 1, 1, 10);
  DateTime _businessEnd = DateTime(2000, 1, 1, 22);

  /// Only a server-reported conflict blocks submission. Club leadership itself
  /// does not prevent a pending merchant application on current backend master.
  String? _blockedReason;

  /// 状态页上按了「重新申请」—— 落回向导,资料已回填。
  bool _editing = false;

  // 发布者实名(RUN-52):第 4 步(预览确认)收一次,登记过就不再出现这两个字段。
  final PublisherIdentityController _publisherIdentity =
      PublisherIdentityController(source: kIdentitySourceMerchantApply);
  bool _identityStatusRequested = false;
  // 实名那一发的失败 = 页内错误条(真源 apply/index.wxml `cy-inline-error`
  // 「申请暂未提交」+「重新提交」),不弹 toast —— 弹层不该丢已填的格子。
  String? _identityError;

  @override
  void initState() {
    super.initState();
    _publisherIdentity.addListener(_onIdentityChanged);
  }

  void _onIdentityChanged() {
    if (mounted) setState(() {});
  }

  // 实名登记状态:走到第四屏才问一次(与本页「身份检查完成前不得请求」的
  // 既有口径一致)。已登记的人据此收起那两个字段。
  Future<void> _ensureIdentityStatus() async {
    if (_identityStatusRequested) return;
    _identityStatusRequested = true;
    if (await ref.read(publisherIdentityApiProvider).status()) {
      if (!mounted) return;
      _publisherIdentity.markRegistered();
    }
  }

  /// 某一步能不能进下一步/提交:第 4 步在既有三项资料之外还要过实名闸,
  /// 规则只有 publisher_identity.dart 一份。
  bool _stepReady(int step) =>
      applyStepReady(step, _form) &&
      (step != kApplyStepTitles.length || _publisherIdentity.satisfied);

  String? _localizedBlocker(String? message) => switch (message) {
    '请填写品牌名称' => stringsOf(context).merchantApplyNameRequired,
    '请填写联系手机号' => stringsOf(context).merchantApplyPhoneRequired,
    '请填写门店地址' => stringsOf(context).merchantApplyAddressRequired,
    '请填写营业时间' => stringsOf(context).merchantApplyHoursRequired,
    '请上传营业执照' => stringsOf(context).merchantApplyLicenseRequired,
    '请填写真实姓名' => stringsOf(context).merchantApplyRealNameRequired,
    '请填写真实姓名(2-20 个字)' => stringsOf(context).merchantApplyRealNameLength,
    '姓名里不应包含数字' => stringsOf(context).merchantApplyRealNameDigits,
    '身份证号格式不正确，请核对后重填' => stringsOf(context).merchantApplyIdInvalid,
    '请先同意提供真实姓名与身份证号' => stringsOf(context).merchantApplyConsentRequired,
    _ => message,
  };

  String? _stepBlocker(int step) {
    final problem = applyStepBlocker(step, _form);
    if (problem != null) return _localizedBlocker(problem);
    if (step == kApplyStepTitles.length) return _localizedBlocker(_publisherIdentity.firstProblem);
    return null;
  }

  /// 驳回后重提:把申请行回填进向导(真源 `onReapply` + 那段「故意不回填坐标」的注释)。
  void _reapply(MerchantApplication a) {
    _nameController.text = a.name;
    _preferenceController.text = a.preference;
    _phoneController.text = a.phone;
    _addressController.text = a.address;
    _descriptionController.text = a.description;
    setState(() {
      // ★ id 只在**驳回**态带(status===2)。审核中/已通过都带的话,
      //   后端 update 分支的守卫(status ∈ {0,2})会拒,或在已生效的账号上改资料。
      _form = MerchantApplyForm(
        id: a.status == 2 ? a.id : null,
        name: a.name,
        preference: a.preference,
        phone: a.phone,
        address: a.address,
        businessTime: a.businessTime,
        description: a.description,
        businessLicense: a.businessLicense,
      );
      _step = 1;
      _editing = true;
    });
  }

  @override
  void dispose() {
    _publisherIdentity.removeListener(_onIdentityChanged);
    _publisherIdentity.dispose();
    _nameController.dispose();
    _preferenceController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickBusinessTime() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final List<bool> days = List<bool>.of(_businessDays);
    DateTime start = _businessStart;
    DateTime end = _businessEnd;

    await showCupertinoModalPopup<void>(
      context: context,
      semanticsDismissible: true,
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setSheetState) {
          final CyPalette palette = CyPalette.of(context);
          return CupertinoPopupSurface(
            isSurfacePainted: true,
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 460,
                child: Column(
                  children: <Widget>[
                    SizedBox(
                      height: 52,
                      child: Row(
                        children: <Widget>[
                          CupertinoButton(
                            minimumSize: const Size(44, 44),
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            child: Text(stringsOf(context).cancel),
                          ),
                          Expanded(
                            child: Text(
                              stringsOf(context).merchantApplyHoursTitle,
                              textAlign: TextAlign.center,
                              style: CupertinoTheme.of(
                                context,
                              ).textTheme.navTitleTextStyle,
                            ),
                          ),
                          CupertinoButton(
                            minimumSize: const Size(44, 44),
                            onPressed: () {
                              if (!days.contains(true)) {
                                CyNativeNotice.show(
                                  this.context,
                                  stringsOf(context).merchantApplyDayRequired,
                                  isError: true,
                                );
                                return;
                              }
                              setState(() {
                                _businessDays.setAll(0, days);
                                _businessStart = start;
                                _businessEnd = end;
                                _form = _form.copyWith(
                                  businessTime: _formatBusinessTime(
                                    days,
                                    start,
                                    end,
                                  ),
                                );
                              });
                              Navigator.of(sheetContext).pop();
                            },
                            child: Text(stringsOf(context).done),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: CyTokens.space3,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            stringsOf(context).merchantApplyDays,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: palette.textSecondary),
                          ),
                          const SizedBox(height: CyTokens.space2),
                          LayoutBuilder(
                            builder:
                                (
                                  BuildContext context,
                                  BoxConstraints constraints,
                                ) {
                                  const double minimumRowWidth = 44 * 7;
                                  void toggleDay(int index) {
                                    HapticFeedback.selectionClick();
                                    setSheetState(
                                      () => days[index] = !days[index],
                                    );
                                  }

                                  return SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: SizedBox(
                                      width:
                                          constraints.maxWidth < minimumRowWidth
                                          ? minimumRowWidth
                                          : constraints.maxWidth,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: <Widget>[
                                          for (
                                            int index = 0;
                                            index < _weekdayLabels.length;
                                            index++
                                          )
                                            SizedBox.square(
                                              dimension: 44,
                                              child: Semantics(
                                                selected: days[index],
                                                button: true,
                                                label:
                                                    <String>[stringsOf(context).merchantApplyWeekday1, stringsOf(context).merchantApplyWeekday2, stringsOf(context).merchantApplyWeekday3, stringsOf(context).merchantApplyWeekday4, stringsOf(context).merchantApplyWeekday5, stringsOf(context).merchantApplyWeekday6, stringsOf(context).merchantApplyWeekday7][index],
                                                onTap: () => toggleDay(index),
                                                excludeSemantics: true,
                                                child: CupertinoButton(
                                                  key: Key(
                                                    'merchant-hours-day-${index + 1}',
                                                  ),
                                                  minimumSize: const Size(
                                                    44,
                                                    44,
                                                  ),
                                                  padding: EdgeInsets.zero,
                                                  color: days[index]
                                                      ? palette.actionPrimaryBg
                                                      : palette
                                                            .actionSecondaryBg,
                                                  onPressed: () =>
                                                      toggleDay(index),
                                                  child: Text(
                                                    <String>[stringsOf(context).merchantApplyDay1, stringsOf(context).merchantApplyDay2, stringsOf(context).merchantApplyDay3, stringsOf(context).merchantApplyDay4, stringsOf(context).merchantApplyDay5, stringsOf(context).merchantApplyDay6, stringsOf(context).merchantApplyDay7][index],
                                                    style: TextStyle(
                                                      color: days[index]
                                                          ? palette
                                                                .actionPrimaryFg
                                                          : palette
                                                                .textSecondary,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: CyTokens.space3),
                    Expanded(
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: _BusinessTimePicker(
                              label: stringsOf(context).merchantApplyStartTime,
                              value: start,
                              onChanged: (DateTime value) =>
                                  setSheetState(() => start = value),
                            ),
                          ),
                          Text(
                            stringsOf(context).merchantApplyTo,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: palette.textSecondary),
                          ),
                          Expanded(
                            child: _BusinessTimePicker(
                              label: stringsOf(context).merchantApplyEndTime,
                              value: end,
                              onChanged: (DateTime value) =>
                                  setSheetState(() => end = value),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Persist the existing businessTime format; localized picker labels never
  // change the submitted business data.
  static const List<String> _weekdayLabels = <String>[
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '日',
  ];

  String _formatBusinessTime(List<bool> days, DateTime start, DateTime end) {
    final List<String> selected = <String>[
      for (int index = 0; index < days.length; index++)
        if (days[index]) _weekdayLabels[index],
    ];
    final String dayText = selected.length == _weekdayLabels.length
        ? '周一至周日'
        : '周${selected.join('、')}';
    String two(int value) => value.toString().padLeft(2, '0');
    return '$dayText ${two(start.hour)}:${two(start.minute)}-'
        '${two(end.hour)}:${two(end.minute)}';
  }

  Future<void> _pickLicense() async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final url = await ref.read(playApiProvider).uploadImage(file.path);
      if (!mounted) return;
      setState(() => _form = _form.copyWith(businessLicense: url));
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        stringsOf(context).merchantApplyUploadError(e.toString().replaceFirst('Exception: ', '')),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    // 实名登记是入驻单【之前】的一发独立写:先落身份、再落入驻单。
    // 顺序不能反 —— /api/merchant/merchant_registration 对新 Registration 会查
    // 实名是否已登记(ApiMerchantController 的闸),并发发会被拦成「请先登记实名信息」。
    if (!_publisherIdentity.registered) {
      setState(() => _identityError = null);
      _publisherIdentity.setBusy(true);
      final outcome = await registerPublisherIdentity(
        ref.read(publisherIdentityApiProvider),
        _publisherIdentity.form,
        strings: stringsOf(context),
      );
      _publisherIdentity.setBusy(false);
      if (!mounted) return;
      if (!outcome.ok) {
        // 停在这一步:入驻单不许跟着发出去;报错条原地,「重新提交」再走一次。
        setState(() {
          _submitting = false;
          _identityError = outcome.network
              ? stringsOf(context).merchantApplyIdentityNetworkError
              : outcome.message;
        });
        return;
      }
      // 登记成功当场把字段收起:口径是只回状态,值不再看第二遍。
      _publisherIdentity.markRegistered();
      setState(() {});
    }
    try {
      await ref.read(merchantApiProvider).submitApply(_form);
      if (!mounted) return;
      CyNativeNotice.show(context, stringsOf(context).merchantApplySubmittedNotice);
      if (context.canPop()) context.pop();
    } catch (e) {
      if (!mounted) return;
      if (e is MerchantApiException && e.isClubLeaderConflict) {
        // Preserve the server rejection without inventing a permanent role rule.
        setState(() => _blockedReason = e.message);
        return;
      }
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _back() {
    if (_step == 1) {
      if (context.canPop()) context.pop();
    } else {
      setState(() => _step -= 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    // ★ 先问「有没有已提交的申请」再决定画哪一屏(真源 bootstrapState)。
    if (!_editing) {
      final asyncApplication = ref.watch(merchantApplicationProvider);
      if (asyncApplication.isLoading) {
        return CupertinoPageScaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantApplyTitle)),
          child: const SafeArea(
            bottom: false,
            child: Center(child: CupertinoActivityIndicator()),
          ),
        );
      }
      if (asyncApplication.hasError) {
        final Object error = asyncApplication.error!;
        return CupertinoPageScaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantApplyTitle)),
          child: SafeArea(
            bottom: false,
            child: StatusView(
              message: stringsOf(context).merchantApplyStateUnavailable,
              sub: error is MerchantApiException
                  ? error.message
                  : stringsOf(context).merchantApplyCheckNetwork,
              large: true,
              onRetry: () => ref.invalidate(merchantApplicationProvider),
              retryLabel: stringsOf(context).merchantApplyCheckAgain,
            ),
          ),
        );
      }
      final MerchantApplication? applied = asyncApplication.value;
      if (applied != null) {
        return _statusPage(applied, textTheme);
      }
    }

    if (_blockedReason != null) {
      return CupertinoPageScaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantApplyCannotApply)),
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(CyTokens.pageX),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    CupertinoIcons.nosign,
                    size: 48,
                    color: CyPalette.of(context).textSecondary,
                  ),
                  const SizedBox(height: CyTokens.space3),
                  Text(stringsOf(context).merchantApplyCannotApplyTitle, style: textTheme.titleLarge),
                  const SizedBox(height: CyTokens.space2),
                  Text(
                    _blockedReason!,
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: CyPalette.of(context).textSecondary,
                    ),
                  ),
                  const SizedBox(height: CyTokens.space2),
                  Text(
                    stringsOf(context).merchantApplyCannotApplyHint,
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: CyPalette.of(context).textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final ready = _stepReady(_step);
    final blocker = _stepBlocker(_step);
    final String backLabel = _step == 1 ? stringsOf(context).merchantApplyBack : stringsOf(context).merchantApplyPrevious;

    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(
        middle: Text(stringsOf(context).merchantApplyStepTitle(<String>[stringsOf(context).merchantApplyStepBasics, stringsOf(context).merchantApplyStepBusiness, stringsOf(context).merchantApplyStepCredentials, stringsOf(context).merchantApplyStepPreview][_step - 1])),
        leading: Semantics(
          container: true,
          button: true,
          label: backLabel,
          onTap: _back,
          excludeSemantics: true,
          child: CupertinoButton(
            key: const Key('merchant-apply-back'),
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
            onPressed: _back,
            child: const Icon(CupertinoIcons.back),
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              CyNativeProgress(
                progress: _step / kApplyStepTitles.length,
                height: 4,
                semanticLabel: stringsOf(context).merchantApplyProgress,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(CyTokens.pageX),
                  children: <Widget>[_stepBody(_step)],
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
                      // ★ 差什么就说什么,不给灰按钮让用户猜。
                      if (blocker != null)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: CyTokens.space2,
                          ),
                          child: Text(
                            blocker,
                            style: textTheme.bodySmall?.copyWith(
                              color: CyPalette.of(context).statusWarning,
                            ),
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: CupertinoButton.filled(
                          key: const Key('merchant-apply-next'),
                          minimumSize: const Size.fromHeight(44),
                          onPressed: (!ready || _submitting)
                              ? null
                              : () {
                                  if (_step < kApplyStepTitles.length) {
                                    setState(() => _step += 1);
                                    if (_step == kApplyStepTitles.length) {
                                      _ensureIdentityStatus();
                                    }
                                  } else {
                                    _submit();
                                  }
                                },
                          child: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CupertinoActivityIndicator(),
                                )
                              : Text(
                                  _step < kApplyStepTitles.length ? stringsOf(context).merchantApplyContinue : stringsOf(context).merchantApplySubmit,
                                ),
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

  Widget _stepBody(int step) {
    switch (step) {
      case 1:
        return Column(
          children: <Widget>[
            _field(
              key: const Key('merchant-apply-name'),
              label: stringsOf(context).merchantApplyName,
              hint: stringsOf(context).merchantApplyNameHint,
              controller: _nameController,
              onChanged: (String v) => _form = _form.copyWith(name: v),
              keyboard: TextInputType.name,
              autofillHints: const <String>[AutofillHints.organizationName],
            ),
            _field(
              key: const Key('merchant-apply-preference'),
              label: stringsOf(context).merchantApplyCategory,
              hint: stringsOf(context).merchantApplyCategoryHint,
              controller: _preferenceController,
              onChanged: (String v) => _form = _form.copyWith(preference: v),
            ),
            _field(
              key: const Key('merchant-apply-phone'),
              label: stringsOf(context).merchantApplyPhone,
              hint: stringsOf(context).merchantApplyPhoneHint,
              controller: _phoneController,
              onChanged: (String v) => _form = _form.copyWith(phone: v),
              keyboard: TextInputType.phone,
              autofillHints: const <String>[AutofillHints.telephoneNumber],
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
            ),
          ],
        );
      case 2:
        return Column(
          children: <Widget>[
            _field(
              key: const Key('merchant-apply-address'),
              label: stringsOf(context).merchantApplyAddress,
              hint: stringsOf(context).merchantApplyAddressHint,
              controller: _addressController,
              onChanged: (String v) => _form = _form.copyWith(address: v),
              keyboard: TextInputType.streetAddress,
              autofillHints: const <String>[AutofillHints.fullStreetAddress],
            ),
            CyField(
              label: stringsOf(context).merchantApplyHours,
              child: Semantics(
                button: true,
                label: stringsOf(context).merchantApplyHoursSemantics,
                onTap: _pickBusinessTime,
                excludeSemantics: true,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: CyPalette.of(context).bgSurface,
                    border: Border.all(
                      color: CyPalette.of(context).borderSubtle,
                    ),
                    borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                  ),
                  child: CupertinoButton(
                    key: const Key('merchant-apply-business-time'),
                    minimumSize: const Size.fromHeight(44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                    onPressed: _pickBusinessTime,
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            _form.businessTime.isEmpty
                                ? stringsOf(context).merchantApplyHoursHint
                                : _form.businessTime,
                            style: TextStyle(
                              color: _form.businessTime.isEmpty
                                  ? CyPalette.of(context).textPlaceholder
                                  : CyPalette.of(context).textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: CyTokens.space2),
                        Icon(
                          CupertinoIcons.chevron_down,
                          size: 18,
                          color: CyPalette.of(context).textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _field(
              key: const Key('merchant-apply-description'),
              label: stringsOf(context).merchantApplyDescription,
              hint: stringsOf(context).merchantApplyDescriptionHint,
              controller: _descriptionController,
              onChanged: (String v) => _form = _form.copyWith(description: v),
              maxLines: 4,
              textInputAction: TextInputAction.newline,
            ),
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CySectionTitle(stringsOf(context).merchantApplyLicense),
            const SizedBox(height: CyTokens.space2),
            if (_form.businessLicense.isEmpty)
              CupertinoButton(
                key: const Key('merchant-apply-license'),
                minimumSize: const Size.fromHeight(44),
                color: CyPalette.of(context).bgSurfaceStrong,
                onPressed: _uploading ? null : _pickLicense,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(CupertinoIcons.photo_on_rectangle),
                    const SizedBox(width: CyTokens.space2),
                    Text(_uploading ? stringsOf(context).merchantApplyUploading : stringsOf(context).merchantApplyUploadLicense),
                  ],
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                    child: CyNetImage(
                      _form.businessLicense,
                      height: 180,
                      fit: BoxFit.cover,
                    ),
                  ),
                  CupertinoButton(
                    minimumSize: const Size(44, 44),
                    onPressed: _uploading ? null : _pickLicense,
                    child: Text(stringsOf(context).merchantApplyUploadAgain),
                  ),
                ],
              ),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CySectionTitle(stringsOf(context).merchantApplyConfirm),
            const SizedBox(height: CyTokens.space2),
            _preview(stringsOf(context).merchantApplyName, _form.name),
            _preview(stringsOf(context).merchantApplyCategory, _form.preference),
            _preview(stringsOf(context).merchantApplyPhone, _form.phone),
            _preview(stringsOf(context).merchantApplyAddress, _form.address),
            _preview(stringsOf(context).merchantApplyHours, _form.businessTime),
            _preview(stringsOf(context).merchantApplyDescription, _form.description),
            const SizedBox(height: CyTokens.space3),
            // RUN-52 经营者实名:与 pages/merchant/apply 第 4 步同一个后端闸,
            // 不登记这两张单都提交不上去。已登记的人只看到一句状态。
            PublisherIdentityFields(
              controller: _publisherIdentity,
              title: stringsOf(context).merchantApplyIdentityTitle,
              // Preserve the original financial identity disclosure verbatim.
              footHint: '执照核验到主体,这一项核验到人 —— 能收款就得可追溯,二者不互相替代。',
            ),
            if (_identityError case final String message) ...<Widget>[
              const SizedBox(height: CyTokens.space2),
              CyInlineError(
                key: const Key('merchant-apply-submit-error'),
                title: stringsOf(context).merchantApplyNotSubmitted,
                detail: message,
                actionLabel: stringsOf(context).merchantApplyResubmit,
                onAction: _submit,
              ),
            ],
          ],
        );
    }
  }

  Widget _field({
    required Key key,
    required String label,
    required String hint,
    required TextEditingController controller,
    required void Function(String) onChanged,
    TextInputType? keyboard,
    Iterable<String>? autofillHints,
    List<TextInputFormatter>? inputFormatters,
    TextInputAction? textInputAction,
    int maxLines = 1,
  }) {
    return CyField(
      label: label,
      child: CupertinoTextField(
        key: key,
        controller: controller,
        keyboardType: keyboard,
        autofillHints: autofillHints,
        inputFormatters: inputFormatters,
        textInputAction:
            textInputAction ??
            (maxLines == 1 ? TextInputAction.next : TextInputAction.newline),
        maxLines: maxLines,
        placeholder: hint,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: CyPalette.of(context).bgSurface,
          border: Border.all(color: CyPalette.of(context).borderSubtle),
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        ),
        onChanged: (String v) => setState(() => onChanged(v)),
      ),
    );
  }

  /// 已有一行申请 → **状态页**(真源 `mode==='status'`,`index.wxml:88-112`)。
  ///
  /// ★ 这一屏存在的意义是**驳回能重提**:没有它,被驳回的商家打开这页
  ///   看到的是空白向导,再交一份只会撞上后端那句「已提交过商家入驻申请」。
  String _timelineText(MerchantApplication a) {
    if (a.isDisabled) return stringsOf(context).merchantHomeDisabled;
    if (a.status == 1 && a.accountStatus == 1) return stringsOf(context).merchantHomeActive;
    if (a.isRejected) return stringsOf(context).merchantApplyNotApproved;
    if (a.status == 1) return stringsOf(context).merchantApplyAwaitingConditions;
    return stringsOf(context).merchantApplyAwaitingPrevious;
  }

  Widget _statusPage(MerchantApplication a, TextTheme textTheme) {
    final palette = CyPalette.of(context);
    final Color badge = switch (a.badgeVariant) {
      'danger' => palette.statusDanger,
      'success' => palette.statusSuccess,
      'warning' => palette.statusWarning,
      _ => palette.textSecondary,
    };
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantApplyTitle)),
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
                    CySectionTitle(stringsOf(context).merchantApplyFullTitle),
                    const SizedBox(height: CyTokens.space2),
                    _ApplyCard(
                      children: <Widget>[
                        _StatusPill(label: _applicationStatusLabel(context, a), color: badge),
                        const SizedBox(height: CyTokens.space3),
                        Text(_applicationStatusText(context, a), style: textTheme.bodyMedium),
                        const SizedBox(height: CyTokens.space3),
                        _preview(stringsOf(context).merchantApplyName, a.name),
                        _preview(stringsOf(context).merchantApplyPhone, a.phone),
                        _preview(stringsOf(context).merchantApplyAddress, a.address),
                      ],
                    ),
                    const SizedBox(height: CyTokens.space3),
                    _ApplyCard(
                      children: <Widget>[
                        _TimelineItem(
                          title: stringsOf(context).merchantApplySubmitApplication,
                          sub: a.createTime.isEmpty ? stringsOf(context).merchantApplySubmitted : a.createTime,
                          dot: palette.brand,
                        ),
                        _TimelineItem(
                          title: stringsOf(context).merchantApplyInitialReview,
                          sub: a.status == 0 ? stringsOf(context).merchantApplyTeamReviewing : stringsOf(context).merchantApplyCompleted,
                          dot: a.status == 0
                              ? palette.statusWarning
                              : palette.brand,
                        ),
                        _TimelineItem(
                          title: stringsOf(context).merchantApplyReviewResult,
                          sub: _timelineText(a),
                          dot: a.timelineRejected
                              ? palette.statusDanger
                              : a.timelineDone
                              ? palette.brand
                              : palette.textPlaceholder,
                          last: true,
                        ),
                      ],
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
                  child: SizedBox(
                    width: double.infinity,
                    child: CupertinoButton.filled(
                      key: const Key('merchant-apply-status-action'),
                      minimumSize: const Size.fromHeight(44),
                      onPressed: a.canReapply ? () => _reapply(a) : _exitApply,
                      child: Text(a.canReapply ? stringsOf(context).merchantApplyReapply : stringsOf(context).merchantApplyBack),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _exitApply() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(kHomeRoute);
    }
  }

  Widget _preview(String label, String value) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: CyPalette.of(context).textSecondary,
              ),
            ),
          ),
          Expanded(
            // 选填项留空时显破折号,不留一片空白让人以为没渲染。
            child: Text(
              value.trim().isEmpty ? '—' : value,
              style: textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessTimePicker extends StatelessWidget {
  const _BusinessTimePicker({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Column(
      children: <Widget>[
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: CyTokens.space1),
        Expanded(
          child: CupertinoDatePicker(
            mode: CupertinoDatePickerMode.time,
            initialDateTime: value,
            use24hFormat: true,
            onDateTimeChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// 状态页的卡片容器(真源 `.status-card` / `.timeline`,内边距 space-4)。
class _ApplyCard extends StatelessWidget {
  const _ApplyCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: palette.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// 状态签(真源 `<cy-badge type="status" variant="{{apply.badgeVariant}}">`)。
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(CyTokens.radiusPill),
      ),
      child: Text(
        label,
        style: CyType.caption1.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 审核时间线的一节(真源 `.tl-item`,节点色分 done/cur/rej/默认)。
class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.title,
    required this.sub,
    required this.dot,
    this.last = false,
  });

  final String title;
  final String sub;
  final Color dot;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: CyTokens.space1_5),
                decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(
                      vertical: CyTokens.space1,
                    ),
                    color: palette.borderSubtle,
                  ),
                ),
            ],
          ),
          const SizedBox(width: CyTokens.space3),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : CyTokens.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: CyTokens.space1),
                  Text(
                    sub,
                    style: textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
