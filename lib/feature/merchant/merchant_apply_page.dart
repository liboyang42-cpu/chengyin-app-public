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

  /// 撞上「已是俱乐部主理人」时置真:这条不是失败,是**永远不能申请**,
  /// 界面要整页说清,而不是弹个 toast 让用户再试一次。
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

  String? _stepBlocker(int step) {
    final problem = applyStepBlocker(step, _form);
    if (problem != null) return problem;
    if (step == kApplyStepTitles.length) return _publisherIdentity.firstProblem;
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
                            child: const Text('取消'),
                          ),
                          Expanded(
                            child: Text(
                              '设置经营时间',
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
                                  '至少选择一个经营日',
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
                            child: const Text('完成'),
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
                            '经营日',
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
                                                    '周${_weekdayLabels[index]}',
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
                                                    _weekdayLabels[index],
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
                              label: '开始时间',
                              value: start,
                              onChanged: (DateTime value) =>
                                  setSheetState(() => start = value),
                            ),
                          ),
                          Text(
                            '至',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: palette.textSecondary),
                          ),
                          Expanded(
                            child: _BusinessTimePicker(
                              label: '结束时间',
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
        '营业执照没传上去:${e.toString().replaceFirst('Exception: ', '')}',
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
      );
      _publisherIdentity.setBusy(false);
      if (!mounted) return;
      if (!outcome.ok) {
        // 停在这一步:入驻单不许跟着发出去;报错条原地,「重新提交」再走一次。
        setState(() {
          _submitting = false;
          _identityError = outcome.message;
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
      CyNativeNotice.show(context, '申请已提交,等待审核');
      if (context.canPop()) context.pop();
    } catch (e) {
      if (!mounted) return;
      if (e is MerchantApiException && e.isClubLeaderConflict) {
        // ★ 整页拦下并说清原因。这条规则重试一万次也不会变。
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
          navigationBar: const CupertinoNavigationBar(middle: Text('入驻申请')),
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
          navigationBar: const CupertinoNavigationBar(middle: Text('入驻申请')),
          child: SafeArea(
            bottom: false,
            child: StatusView(
              message: '暂时无法确认申请状态',
              sub: error is MerchantApiException
                  ? error.message
                  : '检查网络后重新检查。',
              large: true,
              onRetry: () => ref.invalidate(merchantApplicationProvider),
              retryLabel: '重新检查',
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
        navigationBar: const CupertinoNavigationBar(middle: Text('无法申请')),
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
                  Text('无法申请入驻', style: textTheme.titleLarge),
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
                    '如需改为商户身份,请先处理俱乐部主理人身份。',
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
    final String backLabel = _step == 1 ? '返回' : '返回上一步';

    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(
        middle: Text('入驻申请 · ${kApplyStepTitles[_step - 1]}'),
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
                semanticLabel: '入驻申请进度',
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
                                  _step < kApplyStepTitles.length ? '继续' : '提交',
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
              label: '店铺名称',
              hint: '品牌名称',
              controller: _nameController,
              onChanged: (String v) => _form = _form.copyWith(name: v),
              keyboard: TextInputType.name,
              autofillHints: const <String>[AutofillHints.organizationName],
            ),
            _field(
              key: const Key('merchant-apply-preference'),
              label: '经营类目',
              hint: '如：餐饮、零售、文创',
              controller: _preferenceController,
              onChanged: (String v) => _form = _form.copyWith(preference: v),
            ),
            _field(
              key: const Key('merchant-apply-phone'),
              label: '联系电话',
              hint: '11位手机号',
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
              label: '店铺地址',
              hint: '详细到门牌号',
              controller: _addressController,
              onChanged: (String v) => _form = _form.copyWith(address: v),
              keyboard: TextInputType.streetAddress,
              autofillHints: const <String>[AutofillHints.fullStreetAddress],
            ),
            CyField(
              label: '经营时间',
              child: Semantics(
                button: true,
                label: '经营时间，必填，点击设置营业日与时段',
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
                                ? '点击设置营业日与时段'
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
              label: '店铺介绍',
              hint: '介绍你的品牌、特色产品或服务，让用户快速了解你。',
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
            const CySectionTitle('营业执照'),
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
                    Text(_uploading ? '上传中…' : '上传营业执照'),
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
                    child: const Text('重新上传'),
                  ),
                ],
              ),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const CySectionTitle('确认信息'),
            const SizedBox(height: CyTokens.space2),
            _preview('店铺名称', _form.name),
            _preview('经营类目', _form.preference),
            _preview('联系电话', _form.phone),
            _preview('店铺地址', _form.address),
            _preview('经营时间', _form.businessTime),
            _preview('店铺介绍', _form.description),
            const SizedBox(height: CyTokens.space3),
            // RUN-52 经营者实名:与 pages/merchant/apply 第 4 步同一个后端闸,
            // 不登记这两张单都提交不上去。已登记的人只看到一句状态。
            PublisherIdentityFields(
              controller: _publisherIdentity,
              title: '经营者实名',
              footHint: '执照核验到主体,这一项核验到人 —— 能收款就得可追溯,二者不互相替代。',
            ),
            if (_identityError case final String message) ...<Widget>[
              const SizedBox(height: CyTokens.space2),
              CyInlineError(
                key: const Key('merchant-apply-submit-error'),
                title: '申请暂未提交',
                detail: message,
                actionLabel: '重新提交',
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
      navigationBar: const CupertinoNavigationBar(middle: Text('入驻申请')),
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
                    const CySectionTitle('商家入驻申请'),
                    const SizedBox(height: CyTokens.space2),
                    _ApplyCard(
                      children: <Widget>[
                        _StatusPill(label: a.statusLabel, color: badge),
                        const SizedBox(height: CyTokens.space3),
                        Text(a.statusText, style: textTheme.bodyMedium),
                        const SizedBox(height: CyTokens.space3),
                        _preview('店铺名称', a.name),
                        _preview('联系电话', a.phone),
                        _preview('店铺地址', a.address),
                      ],
                    ),
                    const SizedBox(height: CyTokens.space3),
                    _ApplyCard(
                      children: <Widget>[
                        _TimelineItem(
                          title: '提交申请',
                          sub: a.createTime.isEmpty ? '已提交' : a.createTime,
                          dot: palette.brand,
                        ),
                        _TimelineItem(
                          title: '资料初审',
                          sub: a.status == 0 ? '审核团队审核中' : '已完成',
                          dot: a.status == 0
                              ? palette.statusWarning
                              : palette.brand,
                        ),
                        _TimelineItem(
                          title: '审核结果',
                          sub: a.timelineText,
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
                      child: Text(a.canReapply ? '重新申请' : '返回'),
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
