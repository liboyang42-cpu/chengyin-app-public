import 'club_api_messages.dart';
import '../../l10n/strings.dart';
import 'club_form_labels.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_image_source_sheet.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';
import '../publish/publish_image_cropper.dart';
import 'club_controller.dart';
import 'club_form_scaffold.dart';
import 'club_image_picker.dart';

/// 创建俱乐部(D18 表单B,轻量·填完即有)。参考 Strava 创建俱乐部向导:
/// 类型→方向→资料→城市。对齐小程序 `pages/club/create`:
/// - 进入前预检:不是主理人就先去做主理人申请(apply),别填完四步才被后端拒;
/// - 已达 2 个俱乐部上限则不再填表;
/// - 路线方向多选最多 3 个;名称与城市必填。
class ClubCreatePage extends ConsumerStatefulWidget {
  const ClubCreatePage({super.key});

  @override
  ConsumerState<ClubCreatePage> createState() => _ClubCreatePageState();
}

const List<String> _stepTitles = <String>['俱乐部类型', '路线方向', '俱乐部资料', '所在城市'];

const List<({String val, String sub})> _typeOptions =
    <({String val, String sub})>[
      (val: '校园社团', sub: '学生组织 · 校园路线'),
      (val: '旅行组织', sub: '城市探索 · 户外带队'),
      (val: '兴趣社群', sub: '同好聚集 · 城市路线'),
      (val: '商业活动组织方', sub: '品牌路线 · 商业执行'),
      (val: '内容创作团队', sub: '内容产出 · IP 运营'),
      (val: '其他', sub: ''),
    ];

const List<String> _dirOptions = <String>[
  '轻社交',
  '深度社交',
  'RPG体验',
  '城市定向',
  '解谜路线',
  '沉浸式剧情',
  '运动路线',
  '艺术体验',
  '美食体验',
  '主题聚会',
];

class _ClubCreatePageState extends ConsumerState<ClubCreatePage> {
  int _step = 1;
  String _clubType = '';
  List<String> _activityPrefs = const <String>[];
  final TextEditingController _name = TextEditingController();
  String _logo = '';
  String _cover = '';
  final TextEditingController _description = TextEditingController();
  final TextEditingController _keywords = TextEditingController();
  final TextEditingController _style = TextEditingController();
  String _city = '';
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _keywords.dispose();
    _style.dispose();
    super.dispose();
  }

  bool _canNext() {
    if (_step == 1) return _clubType.isNotEmpty;
    if (_step == 2) return true;
    if (_step == 3) return _name.text.trim().isNotEmpty;
    return _city.trim().isNotEmpty;
  }

  void _onBack() {
    if (_step == 1) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _step--);
  }

  void _onNext() {
    if (!_canNext()) return;
    if (_step < 4) {
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  Future<void> _pickLogo(BuildContext tileContext) async {
    final urls = await pickAndUploadImages(
      context,
      ref,
      maxCount: 1,
      cropAspect: PublishCropAspect.square,
      // S4:锚点 = 触发元素(这块 Logo 位)自己的矩形。
      sourceRect: cySourceRectOf(tileContext),
    );
    if (urls.isNotEmpty && mounted) setState(() => _logo = urls.first);
  }

  Future<void> _pickCover(BuildContext tileContext) async {
    final urls = await pickAndUploadImages(
      context,
      ref,
      maxCount: 1,
      cropAspect: PublishCropAspect.landscape16x9,
      // S4:锚点 = 触发元素(这块封面位)自己的矩形。
      sourceRect: cySourceRectOf(tileContext),
    );
    if (urls.isNotEmpty && mounted) setState(() => _cover = urls.first);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final city = _city.trim();
    try {
      final clubId = await ref.read(clubApiProvider).create(<String, dynamic>{
        'name': _name.text.trim(),
        'logo': _logo,
        'cover': _cover,
        'description': _description.text.trim(),
        'clubType': _clubType,
        'activityPrefs': _activityPrefs.join(','),
        'city': city,
        'address': city,
        'keywords': _keywords.text.trim(),
        'style': _style.text.trim(),
      });
      if (!mounted) return;
      CyNativeNotice.show(context, stringsOf(context).clubFormCreated);
      // 创建成功的下一步是管理自己的俱乐部,不再把主理人送回泛发现页。
      ref.invalidate(clubMyProvider);
      if (clubId > 0) {
        context.go('/club/$clubId');
      } else {
        context.go('/clubs');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      // 异常原文只进日志 —— 上屏的永远是人话(后端原话优先)。
      debugPrint('[club-create] 创建俱乐部失败: $e');
      CyNativeNotice.show(
        context,
        clubApiErrorMessage(context, e, fallback: stringsOf(context).clubFormCreateError),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final role = user?.effectiveRole;
    return ClubStepScaffold(
      title: clubFormValueLabel(context, _stepTitles[_step - 1]),
      step: _step,
      stepCount: 4,
      backLabel: _step == 1 ? stringsOf(context).clubFormBack : clubFormValueLabel(context, _stepTitles[_step - 2]),
      onBack: _onBack,
      nextLabel: _step < 4 ? stringsOf(context).clubFormNext : stringsOf(context).clubFormCreate,
      canNext: _canNext(),
      busy: _submitting,
      onNext: _onNext,
      // 预检①:不是主理人(且不是商户/未登录) → 先去做主理人申请。
      // 预检②:已达 2 个俱乐部上限 → 去管理自己的俱乐部。
      child: _StepGate(
        role: role,
        onBecoming: () async {
          if (!await requireLogin(context, ref)) return;
          if (!mounted) return;
          ref.read(authControllerProvider.notifier).refreshRole();
        },
        child: switch (_step) {
          1 => _stepType(),
          2 => _stepDirection(),
          3 => _stepProfile(),
          _ => _stepCity(),
        },
      ),
    );
  }

  Widget _stepType() {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final opt in _typeOptions)
          Padding(
            padding: const EdgeInsets.only(bottom: CyTokens.space2),
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: () => setState(
                () => _clubType = _clubType == opt.val ? '' : opt.val,
              ),
              child: Container(
                padding: const EdgeInsets.all(CyTokens.space3),
                decoration: BoxDecoration(
                  color: _clubType == opt.val
                      ? CyTokens.brandSoft
                      : AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                  border: Border.all(
                    color: _clubType == opt.val
                        ? CyTokens.brand
                        : CyTokens.borderSubtle,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(clubFormValueLabel(context, opt.val), style: textTheme.bodyMedium),
                          if (opt.sub.isNotEmpty) ...<Widget>[
                            const SizedBox(height: CyTokens.space1),
                            Text(
                              clubFormValueLabel(context, opt.sub),
                              style: textTheme.labelSmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_clubType == opt.val)
                      const Icon(
                        CupertinoIcons.check_mark_circled_solid,
                        size: 20,
                        color: CyTokens.brand,
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _stepDirection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: CyTokens.space2,
          runSpacing: CyTokens.space2,
          children: <Widget>[
            for (final String dir in _dirOptions)
              CyChip(
                label: clubFormValueLabel(context, dir),
                selected: _activityPrefs.contains(dir),
                onTap: () => setState(() {
                  if (_activityPrefs.contains(dir)) {
                    _activityPrefs = _activityPrefs
                        .where((String d) => d != dir)
                        .toList();
                  } else if (_activityPrefs.length < 3) {
                    _activityPrefs = <String>[..._activityPrefs, dir];
                  } else {
                    CyNativeNotice.show(context, stringsOf(context).clubFormMaxThree);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: CyTokens.space4),
        Text(
          stringsOf(context).clubFormDirectionHint,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: CyTokens.textTertiary),
        ),
      ],
    );
  }

  Widget _stepProfile() {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _ImagePickerTile(
                label: stringsOf(context).clubFormCoverHint,
                url: _cover,
                onTap: _pickCover,
                aspect: 16 / 9,
              ),
            ),
            const SizedBox(width: CyTokens.space3),
            Expanded(
              child: _ImagePickerTile(
                label: stringsOf(context).clubFormLogoHint,
                url: _logo,
                onTap: _pickLogo,
              ),
            ),
          ],
        ),
        const SizedBox(height: CyTokens.space3),
        CyField(
          label: stringsOf(context).clubFormClubName,
          child: _input(_name, stringsOf(context).clubFormNameHint, maxLength: 30),
        ),
        CyField(
          label: stringsOf(context).clubFormShortIntroduction,
          child: _textarea(_description, stringsOf(context).clubFormShortIntroductionHint, maxLength: 200),
        ),
        Text(
          stringsOf(context).clubFormRequiredNameHint,
          style: textTheme.labelSmall?.copyWith(color: CyTokens.textTertiary),
        ),
      ],
    );
  }

  Widget _stepCity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CyField(
          label: stringsOf(context).clubFormCityField,
          child: CupertinoTextField(
            onChanged: (String v) => setState(() => _city = v),
            placeholder: stringsOf(context).clubFormCityHint,
            maxLength: 20,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            autocorrect: true,
            enableSuggestions: true,
            padding: const EdgeInsets.all(CyTokens.space3),
            decoration: _inputDecoration(),
          ),
        ),
        CyField(
          label: stringsOf(context).clubFormOptionalKeywords,
          child: _input(_keywords, stringsOf(context).clubFormCommaKeywordsHint, maxLength: 60),
        ),
        CyField(
          label: stringsOf(context).clubFormOptionalStyle,
          child: _input(_style, stringsOf(context).clubFormExampleStyle, maxLength: 30),
        ),
        Text(
          stringsOf(context).clubFormRequiredCityHint,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: CyTokens.textTertiary),
        ),
      ],
    );
  }

  Widget _input(
    TextEditingController controller,
    String hint, {
    required int maxLength,
  }) {
    return CupertinoTextField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      placeholder: hint,
      maxLength: maxLength,
      textInputAction: TextInputAction.next,
      textCapitalization: TextCapitalization.sentences,
      autocorrect: true,
      enableSuggestions: true,
      clearButtonMode: OverlayVisibilityMode.editing,
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: _inputDecoration(),
    );
  }

  Widget _textarea(
    TextEditingController controller,
    String hint, {
    required int maxLength,
  }) {
    return CupertinoTextField(
      controller: controller,
      minLines: 3,
      maxLines: 3,
      maxLength: maxLength,
      placeholder: hint,
      textInputAction: TextInputAction.newline,
      textCapitalization: TextCapitalization.sentences,
      autocorrect: true,
      enableSuggestions: true,
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: _inputDecoration(),
    );
  }

  BoxDecoration _inputDecoration() => BoxDecoration(
    color: CyTokens.inputBgEmpty,
    border: Border.all(color: CyTokens.borderSubtle),
    borderRadius: BorderRadius.circular(CyTokens.radiusMd),
  );
}

/// 创建页预检闸:主理人(role==club)直接看表单;游客先登录再判断;
/// 商户与普通玩家给「先去申请主理人」引导(与小程序 apply 预检同判据)。
class _StepGate extends StatelessWidget {
  const _StepGate({
    required this.role,
    required this.onBecoming,
    required this.child,
  });

  final String? role;
  final Future<void> Function() onBecoming;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (role == 'club') return child;
    if (role == null) {
      // 未登录:给一个「登录后申请主理人」的引导,避免游客填完四步。
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: CyTokens.space4),
          CupertinoButton(
            minimumSize: const Size.fromHeight(44),
            color: CyTokens.actionPrimaryBg,
            foregroundColor: CyTokens.actionPrimaryFg,
            onPressed: onBecoming,
            child: Text(stringsOf(context).clubFormLoginApply),
          ),
          const SizedBox(height: CyTokens.space2),
          Text(
            stringsOf(context).clubFormRegisterFirst,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: CyTokens.textTertiary),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: CyTokens.space4),
        CupertinoButton(
          minimumSize: const Size.fromHeight(44),
          color: CyTokens.actionPrimaryBg,
          foregroundColor: CyTokens.actionPrimaryFg,
          onPressed: onBecoming,
          child: Text(stringsOf(context).clubFormApplyOrganizer),
        ),
        const SizedBox(height: CyTokens.space2),
        Text(
          role == 'merchant' ? stringsOf(context).clubFormMerchantCreateBlocked : stringsOf(context).clubFormApplyFirst,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: CyTokens.textTertiary),
        ),
      ],
    );
  }
}

class _ImagePickerTile extends StatelessWidget {
  const _ImagePickerTile({
    required this.label,
    required this.url,
    required this.onTap,
    this.aspect = 1,
  });

  final String label;
  final String url;

  /// ★ 传**本 tile 的 context** 而不是 VoidCallback:action sheet 的锚点(S4)
  ///   要的正是触发元素自己的矩形,void 回调里拿不到它。
  final ValueChanged<BuildContext> onTap;
  final double aspect;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final has = url.isNotEmpty;
    return CupertinoButton(
      onPressed: () => onTap(context),
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      child: Column(
        children: <Widget>[
          AspectRatio(
            aspectRatio: aspect,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.bgSurface,
                borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                border: Border.all(color: CyTokens.borderSubtle),
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: has
                  ? Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                        CupertinoIcons.photo,
                        size: 24,
                        color: AppColors.textDisabled,
                      ),
                    )
                  : const Icon(
                      CupertinoIcons.photo_on_rectangle,
                      size: 24,
                      color: AppColors.textDisabled,
                    ),
            ),
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            has ? stringsOf(context).clubFormReplaceImage(label) : stringsOf(context).clubFormAddImage(label),
            style: textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
