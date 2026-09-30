import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/widgets/cy_native_notice.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/role_provider.dart';
import '../../data/models/role_info.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_inline_error.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../auth/auth_controller.dart';
import '../publisher/publisher_identity.dart';
import '../publisher/publisher_identity_fields.dart';
import 'club_form_scaffold.dart';
import 'club_image_picker.dart';

/// 注册成为俱乐部主理人(D18 表单A):身份资格 + 能力档案 → L1-L5 定级依据。
/// 对齐小程序 `pages/club/apply`:
/// - 账户互斥:已注册商户(role==merchant)不能申请,一账户只能商户或主理人之一;
/// - 已是主理人(role==club)不再重复填表,直接进「已成为主理人」态;
/// - 填完即有:提交即 role→club,能力档案挂 club_leader,后台异步定级。
class ClubApplyPage extends ConsumerStatefulWidget {
  const ClubApplyPage({super.key});

  @override
  ConsumerState<ClubApplyPage> createState() => _ClubApplyPageState();
}

const List<String> _stepTitles = <String>['主理人实名', '组织经验', '能力自评', '资质证明'];

const List<String> _expOptions = <String>['没有经验', '1-5场', '5-20场', '20场以上'];

class _ClubApplyPageState extends ConsumerState<ClubApplyPage> {
  int _step = 1;
  // 身份
  final TextEditingController _leaderName = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _identity = TextEditingController();
  final TextEditingController _coFounders = TextEditingController();
  // 经验
  String _experience = '';
  final TextEditingController _maxEventSize = TextEditingController();
  final TextEditingController _avgEventSize = TextEditingController();
  // 能力自评
  bool _canDesignRoute = false;
  bool _canDesignTask = false;
  bool _canNpc = false;
  bool _canMerchantCoop = false;
  // 资质
  bool _hasGuideCert = false;
  List<String> _certImages = const <String>[];
  // 发布者实名(RUN-52):姓名+身份证号只在第 4 步收一次,登记过就不再出现这两个字段。
  final PublisherIdentityController _publisherIdentity =
      PublisherIdentityController(source: kIdentitySourceClubApply);
  bool _identityStatusRequested = false;
  bool _submitting = false;
  bool _done = false;
  // 提交失败 = 页内错误条(真源 apply/index.wxml:159 `cy-inline-error`,
  // 分 network/data 两档文案 + 「重试」动作),不叠弹窗。
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _publisherIdentity.addListener(_onIdentityChanged);
  }

  void _onIdentityChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _publisherIdentity.removeListener(_onIdentityChanged);
    _publisherIdentity.dispose();
    _leaderName.dispose();
    _phone.dispose();
    _identity.dispose();
    _coFounders.dispose();
    _maxEventSize.dispose();
    _avgEventSize.dispose();
    super.dispose();
  }

  bool get _isMerchantAccount =>
      ref.read(authControllerProvider).user?.isMerchantView == true;

  bool _canNext() {
    if (_step == 1) {
      return _leaderName.text.trim().isNotEmpty &&
          _phone.text.trim().isNotEmpty;
    }
    if (_step == 2) return _experience.isNotEmpty;
    // 第 4 步是「资质(选填) + 发布者实名(必填)」。实名是硬闸:姓名 + 身份证号 +
    // 单独同意三项齐了「成为主理人」才亮,规则只有 publisher_identity.dart 一份。
    if (_step == 4) return _publisherIdentity.satisfied;
    return true;
  }

  // 实名登记状态:走到第四屏才问一次(资格还没确认、停在前三步的人都不该多发
  // 这一发)。已登记的人据此收起那两个字段。查询失败按「未登记」处理。
  Future<void> _ensureIdentityStatus() async {
    if (_identityStatusRequested) return;
    _identityStatusRequested = true;
    if (await ref.read(publisherIdentityApiProvider).status()) {
      if (!mounted) return;
      _publisherIdentity.markRegistered();
    }
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
      if (_step == 4) _ensureIdentityStatus();
    } else {
      _submit();
    }
  }

  Future<void> _pickCerts() async {
    final remain = 9 - _certImages.length;
    if (remain <= 0) {
      CyNativeNotice.show(context, '最多9张');
      return;
    }
    final urls = await pickAndUploadImages(context, ref, maxCount: remain);
    if (urls.isEmpty || !mounted) return;
    setState(() {
      _certImages = <String>[..._certImages, ...urls].take(9).toList();
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_isMerchantAccount) {
      _showBlocked();
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    // 实名登记是「申请之前」的一发独立写:先落身份、再落主理人档案。
    // 顺序不能反 —— /api/club/become-leader 在服务端要查实名是否已登记
    // (ApiClubController 的闸),两发并排发会被拦成「请先登记实名信息」。
    // 已登记的人直接跳过这一发。
    if (!_publisherIdentity.registered) {
      _publisherIdentity.setBusy(true);
      final outcome = await registerPublisherIdentity(
        ref.read(publisherIdentityApiProvider),
        _publisherIdentity.form,
      );
      _publisherIdentity.setBusy(false);
      if (!mounted) return;
      if (!outcome.ok) {
        setState(() {
          _submitting = false;
          _submitError = outcome.message;
        });
        return;
      }
      // 登记成功当场把这一屏的字段收起:口径是只回状态,值不下发也不再看第二遍。
      _publisherIdentity.markRegistered();
    }
    await _sendLeaderApply();
  }

  Future<void> _sendLeaderApply() async {
    final maxEventSize = int.tryParse(_maxEventSize.text.trim());
    final avgEventSize = int.tryParse(_avgEventSize.text.trim());
    try {
      await ref.read(clubApiProvider).becomeLeader(<String, dynamic>{
        'leaderName': _leaderName.text.trim(),
        'phone': _phone.text.trim(),
        'identity': _identity.text.trim(),
        'coFounders': _coFounders.text.trim(),
        'experience': _experience,
        'hasExperience': _experience == '没有经验' ? 0 : 1,
        'maxEventSize': maxEventSize,
        'avgEventSize': avgEventSize,
        'canDesignRoute': _canDesignRoute ? 1 : 0,
        'canDesignTask': _canDesignTask ? 1 : 0,
        'canNpc': _canNpc ? 1 : 0,
        'canMerchantCoop': _canMerchantCoop ? 1 : 0,
        'hasGuideCert': _hasGuideCert ? 1 : 0,
        'certImages': _certImages.join(','),
      });
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _done = true;
      });
      ref.read(authControllerProvider.notifier).refreshRole();
    } catch (e) {
      if (!mounted) return;
      // 真源 `isTransportFailure` 两档:连不上/超时走网络文案,其余原样显示
      // 后端话术(它带可执行信息),缺话时兜底「提交没有完成,请稍后重试」。
      final String detail = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _submitting = false;
        _submitError = _isNetworkFailure(e)
            ? '网络异常，请检查连接后重试'
            : (detail.isEmpty ? '提交没有完成，请稍后重试' : detail);
      });
    }
  }

  /// 传输层失败:业务拒绝走 [ClubApiException](后端原文),剩下的
  /// DioException 都是没连上/超时/HTTP 层异常 —— 对齐真源 isTransportFailure。
  static bool _isNetworkFailure(Object error) => error is DioException;

  void _showBlocked() {
    // 纯告知不弹 alert(S7);页内状态壳(build 的 merchantBlocked 分支)
    // 已经常驻讲同一个原因 —— 真源 apply/index.js:88 明说「不再叠一个
    // 同义的『知道了』弹窗」。这里只补一条轻提示点一下正在按提交的按钮。
    CyNativeNotice.show(
      context,
      '您已注册为商户,一个账户不能同时是商户与俱乐部主理人。',
      isError: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return _doneView();

    // ★★ 判据走**后端的单一事实源** `/api/role/info`,不再自己从 role 推。
    //   后端:`canCreateClub = !isMerchant && ownedClubCount < 2`。
    //   App 原来用 `effectiveRole == 'club'` 一律拦死 ——
    //   **已是主理人、但还没建满 2 个的人被挡在外面**,还被告知"已成为主理人"。
    final AsyncValue<RoleInfo> roleAsync = ref.watch(roleInfoProvider);

    // 还没读回来时**不预判**:这一页的入口本身已经是"我想申请",
    // 预判成"不能申请"会把人挡在一个我们还不知道结论的门外。
    final RoleInfo? role = roleAsync.value;
    if (role != null && !role.can('canCreateClub')) {
      final bool merchantBlocked = role.isMerchant;
      final bool quotaFull =
          !merchantBlocked && role.ownedClubCount >= role.maxOwnedClubs;
      return CupertinoPageScaffold(
        backgroundColor: CyPalette.of(context).bgPage,
        navigationBar: const CupertinoNavigationBar(),
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const CyPageTitle('主理人申请'),
                Expanded(
                  child: StatusView(
                    message: merchantBlocked ? '无法申请' : '暂时不能再建',
                    sub: merchantBlocked
                        ? '您已注册为商户,一个账户不能同时是商户与俱乐部主理人。'
                        : (quotaFull
                              // 说清是**建满了**,不是"已成为主理人" ——
                              // 后者会让人以为功能没了。
                              ? '你已经有 ${role.ownedClubCount} 个俱乐部,'
                                    '达到上限 ${role.maxOwnedClubs} 个了。'
                              : '当前身份暂时不能创建俱乐部。'),
                    icon: merchantBlocked
                        ? Icons.lock_outline
                        : Icons.info_outline,
                    large: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ClubStepScaffold(
      title: _stepTitles[_step - 1],
      step: _step,
      stepCount: 4,
      backLabel: _step == 1 ? '设置' : _stepTitles[_step - 2],
      onBack: _onBack,
      nextLabel: _step < 4 ? '继续' : '成为俱乐部主理人',
      canNext: _canNext(),
      busy: _submitting,
      onNext: _onNext,
      child: switch (_step) {
        1 => _stepIdentity(),
        2 => _stepExperience(),
        3 => _stepAbility(),
        _ => _stepCert(),
      },
    );
  }

  Widget _doneView() {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final CyPalette palette = CyPalette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const CyPageTitle('成为主理人'),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(CyTokens.space4),
                  children: <Widget>[
                    const CySectionTitle('已成为主理人'),
                    const SizedBox(height: CyTokens.space3),
                    Container(
                      padding: const EdgeInsets.all(CyTokens.space4),
                      decoration: BoxDecoration(
                        color: palette.bgSurface,
                        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                        border: Border.all(color: palette.borderSubtle),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '已生效',
                            style: textTheme.labelMedium?.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: CyTokens.space3),
                          Text(
                            '你已成为俱乐部主理人,身份立即生效。L1-L5 等级由平台后台稍后评定,不影响你现在创建与运营俱乐部。',
                            style: textTheme.bodyMedium,
                          ),
                          const SizedBox(height: CyTokens.space4),
                          Row(
                            children: <Widget>[
                              Text(
                                '可建俱乐部',
                                style: textTheme.labelMedium?.copyWith(
                                  color: palette.textSecondary,
                                ),
                              ),
                              const Spacer(),
                              Text('最多 2 个', style: textTheme.bodyMedium),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: CyTokens.space3),
                    Text(
                      '接下来创建你的第一个俱乐部,开始招募成员、发布城市路线。',
                      style: textTheme.labelSmall?.copyWith(
                        color: palette.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(
                  CyTokens.space4,
                  CyTokens.space2,
                  CyTokens.space4,
                  CyTokens.space3,
                ),
                child: CupertinoButton.filled(
                  minimumSize: const Size.fromHeight(44),
                  onPressed: () => context.replace('/club/create'),
                  child: const Text('创建我的俱乐部'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepIdentity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CyField(
          label: '实名/昵称',
          child: _input(
            _leaderName,
            '你的称呼',
            key: const ValueKey<String>('club-apply-leader-name'),
            keyboard: TextInputType.name,
            action: TextInputAction.next,
            autofillHints: const <String>[AutofillHints.name],
          ),
        ),
        CyField(
          label: '联系方式',
          child: _input(
            _phone,
            '手机号或微信号',
            key: const ValueKey<String>('club-apply-phone'),
            keyboard: TextInputType.text,
            action: TextInputAction.next,
          ),
        ),
        CyField(
          label: '身份说明',
          child: _input(
            _identity,
            '如 高校社团负责人 / 户外领队',
            key: const ValueKey<String>('club-apply-identity'),
            action: TextInputAction.next,
          ),
        ),
        CyField(
          label: '联合创始人',
          child: _input(
            _coFounders,
            '选填,多人用逗号分隔',
            key: const ValueKey<String>('club-apply-cofounders'),
            action: TextInputAction.done,
          ),
        ),
      ],
    );
  }

  Widget _stepExperience() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const CyField(label: '过往组织经验', child: SizedBox.shrink()),
        Wrap(
          spacing: CyTokens.space2,
          runSpacing: CyTokens.space2,
          children: <Widget>[
            for (final String opt in _expOptions)
              _NativeChoicePill(
                key: ValueKey<String>('club-apply-exp-$opt'),
                label: opt,
                selected: _experience == opt,
                onTap: () => setState(() => _experience = opt),
              ),
          ],
        ),
        const SizedBox(height: CyTokens.space3),
        CyField(
          label: '最大带队人数',
          child: _input(
            _maxEventSize,
            '如 50',
            key: const ValueKey<String>('club-apply-max-size'),
            keyboard: TextInputType.number,
            action: TextInputAction.next,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
          ),
        ),
        CyField(
          label: '平均参与人数',
          child: _input(
            _avgEventSize,
            '如 20',
            key: const ValueKey<String>('club-apply-avg-size'),
            keyboard: TextInputType.number,
            action: TextInputAction.done,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepAbility() {
    // L1:开关只活在列表行里 —— 四行能力自评走 insetGrouped,不落裸黑底。
    return CupertinoListSection.insetGrouped(
      footer: Text(
        '能力越强、案例越足,越可能被定到更高等级。',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: CyTokens.textTertiary),
      ),
      children: <Widget>[
        for (final (String field, String label) in <(String, String)>[
          ('route', '能设计城市路线'),
          ('task', '能设计任务/解谜'),
          ('npc', '能带 NPC/角色'),
          ('merchant', '能与商家联动'),
        ])
          _abilityRow(field, label),
      ],
    );
  }

  Widget _abilityRow(String field, String label) {
    final bool value = switch (field) {
      'route' => _canDesignRoute,
      'task' => _canDesignTask,
      'npc' => _canNpc,
      _ => _canMerchantCoop,
    };
    return CupertinoListTile(
      title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      trailing: CupertinoSwitch(
        value: value,
        onChanged: (bool v) => setState(() {
          switch (field) {
            case 'route':
              _canDesignRoute = v;
            case 'task':
              _canDesignTask = v;
            case 'npc':
              _canNpc = v;
            default:
              _canMerchantCoop = v;
          }
        }),
      ),
    );
  }

  Widget _stepCert() {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_submitError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: CyTokens.space3),
            child: CyInlineError(
              key: const Key('apply-submit-error'),
              title: '提交没有完成',
              detail: _submitError!,
              actionLabel: '重试',
              onAction: _submit,
            ),
          ),
        // L1:同上,开关进列表行,不落裸黑底。
        CupertinoListSection.insetGrouped(
          children: <Widget>[
            CupertinoListTile(
              title: Text(
                '持导游/旅游资质',
                style: textTheme.bodyMedium,
              ),
              trailing: CupertinoSwitch(
                value: _hasGuideCert,
                onChanged: (bool v) => setState(() => _hasGuideCert = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: CyTokens.space2),
        Text(
          '资质/案例图',
          style: textTheme.labelMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: CyTokens.space2),
        if (_certImages.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: CyTokens.space3),
            child: Wrap(
              spacing: CyTokens.space2,
              runSpacing: CyTokens.space2,
              children: <Widget>[
                for (int i = 0; i < _certImages.length; i++)
                  _CertThumb(
                    url: _certImages[i],
                    onRemove: () => setState(() {
                      _certImages = <String>[..._certImages]..removeAt(i);
                    }),
                  ),
              ],
            ),
          ),
        CupertinoButton.tinted(
          minimumSize: const Size.fromHeight(44),
          onPressed: _pickCerts,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(CupertinoIcons.photo_on_rectangle, size: 20),
              const SizedBox(width: CyTokens.space2),
              Text(_certImages.isEmpty ? '添加资质证明' : '继续添加'),
            ],
          ),
        ),
        const SizedBox(height: CyTokens.space4),
        // RUN-52 发布者实名:放最后一步。已登记的人不再给填字段的入口 ——
        // 只回状态、改绑走人工,这里连值都不下发。
        PublisherIdentityFields(
          controller: _publisherIdentity,
          title: '发布者实名',
          footHint: '填过一次就不再出现。营业执照、导游证仍在上方「资质 / 案例图」,两件事互不替代。',
        ),
      ],
    );
  }

  Widget _input(
    TextEditingController controller,
    String hint, {
    Key? key,
    TextInputType keyboard = TextInputType.text,
    TextInputAction? action,
    Iterable<String>? autofillHints,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoTextField(
      key: key,
      controller: controller,
      keyboardType: keyboard,
      textInputAction: action,
      autofillHints: autofillHints,
      inputFormatters: inputFormatters,
      autocorrect: keyboard != TextInputType.number,
      enableSuggestions: keyboard != TextInputType.number,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      onChanged: (_) => setState(() {}),
      placeholder: hint,
      decoration: BoxDecoration(
        color: palette.bgSurface,
        border: Border.all(color: palette.borderSubtle),
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
    );
  }
}

class _NativeChoicePill extends StatelessWidget {
  const _NativeChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      excludeSemantics: true,
      button: true,
      selected: selected,
      label: label,
      child: CupertinoButton(
        minimumSize: const Size(44, 44),
        padding: EdgeInsets.zero,
        pressedOpacity: reduceMotion ? 1 : 0.4,
        onPressed: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : CyMotion.fast,
          curve: Curves.easeOutCubic,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? palette.brand : palette.bgGlass,
            borderRadius: BorderRadius.circular(CyTokens.radiusPill),
            border: Border.all(
              color: selected ? palette.brand : palette.borderSubtle,
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected ? palette.textInverse : palette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _CertThumb extends StatelessWidget {
  const _CertThumb({required this.url, required this.onRemove});
  final String url;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(CyTokens.radiusSm),
          child: Image.network(
            url,
            width: 72,
            height: 72,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                Container(width: 72, height: 72, color: AppColors.bgElevated),
          ),
        ),
        Positioned(
          right: -8,
          top: -8,
          child: Semantics(
            button: true,
            label: '删除资质图片',
            child: CupertinoButton(
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
              onPressed: onRemove,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xCC000000),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.xmark,
                  size: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
