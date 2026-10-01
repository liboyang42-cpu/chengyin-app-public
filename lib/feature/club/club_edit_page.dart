import 'club_api_messages.dart';
import '../../l10n/strings.dart';
import 'club_form_labels.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_notice.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_image_source_sheet.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/club_api.dart';
import '../../data/models/club.dart';
import 'club_controller.dart';
import 'club_image_picker.dart';
import '../../core/widgets/unsaved_guard.dart';

/// 编辑俱乐部资料 + 解散流程。对齐小程序 `components/cy/scene-club-edit`:
/// - 字段模型与创建页一致(clubType/activityPrefs/city/keywords/style/logo/cover/description),
///   另加 prioritySignupEnabled / memberReservedQuota / joinPolicy;
/// - ⚠️ 成员优惠价(member_discount_price)已停用,**不再提交该字段** —— 提 null 会把库里
///   存量抹平,而它是有意保留的恢复退路;
/// - 解散:有非创建者成员时先确认成员后果;后端有资金阻断时给出阻断列表
///   (actionItems),跳「解散前待处理」逐笔处理。
class ClubEditPage extends ConsumerWidget {
  const ClubEditPage({super.key, required this.clubId});
  final int clubId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(clubDetailProvider(clubId));
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
              CyPageTitle(stringsOf(context).clubFormEditTitle),
              Expanded(
                child: detail.when(
                  loading: () => const CySkeleton(type: CySkeletonType.detail),
                  error: (Object err, StackTrace st) => StatusView(
                    message: stringsOf(context).clubFormLoadError,
                    sub: stringsOf(context).clubFormRetryNetwork,
                    icon: CupertinoIcons.exclamationmark_triangle,
                    onRetry: () => ref.invalidate(clubDetailProvider(clubId)),
                  ),
                  data: (Club club) => _EditForm(club: club),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

class _EditForm extends ConsumerStatefulWidget {
  const _EditForm({required this.club});
  final Club club;

  @override
  ConsumerState<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends ConsumerState<_EditForm> {
  late final TextEditingController _name = TextEditingController(
    text: widget.club.name,
  );
  late final TextEditingController _city = TextEditingController(
    text: widget.club.city ?? widget.club.address ?? '',
  );
  late final TextEditingController _keywords = TextEditingController(
    text: widget.club.keywords ?? '',
  );
  late final TextEditingController _style = TextEditingController(
    text: widget.club.style ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.club.description ?? '',
  );
  late final TextEditingController _memberReservedQuota = TextEditingController(
    text: widget.club.memberReservedQuota > 0
        ? '${widget.club.memberReservedQuota}'
        : '',
  );

  late String _clubType = widget.club.clubType ?? '';
  late List<String> _activityPrefs = List<String>.from(
    widget.club.activityPrefs,
  );
  late String _logo = widget.club.logo ?? '';
  late String _cover = widget.club.cover ?? '';
  late bool _prioritySignupEnabled = widget.club.prioritySignupEnabled;
  late int _joinPolicy = widget.club.joinPolicy;
  bool _saving = false;
  bool _dissolving = false;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _keywords.dispose();
    _style.dispose();
    _description.dispose();
    _memberReservedQuota.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _name.text.trim().isNotEmpty && _city.text.trim().isNotEmpty;

  /// 表单脏了没有。★ 与**原值**比,不是「有没有敲过字」——
  /// 只看敲没敲会把「敲了又改回去」也算脏,用户明明什么都没变还被拦一下,
  /// 拦多了他就会开始盲点确认,那时这道闸对真正该拦的那次也失效了。
  bool get _dirty {
    final c = widget.club;
    return _name.text != (c.name) ||
        _city.text != (c.city ?? c.address ?? '') ||
        _keywords.text != (c.keywords ?? '') ||
        _style.text != (c.style ?? '') ||
        _description.text != (c.description ?? '') ||
        _memberReservedQuota.text !=
            (c.memberReservedQuota > 0 ? '${c.memberReservedQuota}' : '') ||
        _clubType != (c.clubType ?? '') ||
        _logo != (c.logo ?? '') ||
        _cover != (c.cover ?? '') ||
        _prioritySignupEnabled != c.prioritySignupEnabled ||
        _joinPolicy != c.joinPolicy ||
        _activityPrefs.join(',') != c.activityPrefs.join(',');
  }

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    setState(() => _saving = true);
    final club = widget.club;
    final quota = _memberReservedQuota.text.trim();
    final payload = <String, dynamic>{
      'id': club.id,
      'name': _name.text.trim(),
      'logo': _logo,
      'cover': _cover,
      'description': _description.text.trim(),
      'clubType': _clubType,
      'activityPrefs': _activityPrefs.join(','),
      'city': _city.text.trim(),
      'address': _city.text.trim(),
      'keywords': _keywords.text.trim(),
      'style': _style.text.trim(),
      'operationConfigUpdated': true,
      'prioritySignupEnabled': _prioritySignupEnabled ? 1 : 0,
      'memberReservedQuota': quota.isEmpty ? 0 : (int.tryParse(quota) ?? 0),
    };
    if (club.joinPolicySupported) {
      payload['joinPolicy'] = _joinPolicy;
    }
    try {
      await ref.read(clubApiProvider).updateMine(payload);
      if (!mounted) return;
      ref.invalidate(clubDetailProvider(club.id));
      CyNativeNotice.show(context, stringsOf(context).clubFormSaved);
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      // 异常原文只进日志 —— 上屏的永远是人话(后端原话优先)。
      debugPrint('[club-edit] 保存失败: $e');
      CyNativeNotice.show(
        context,
        clubApiErrorMessage(context, e, fallback: stringsOf(context).clubFormSaveError),
        isError: true,
      );
    }
  }

  Future<void> _dissolve() async {
    final club = widget.club;
    if (!club.isOwner || _dissolving) return;

    // 第一档确认:解散本身不可逆。
    final confirmed = await _confirm(
      title: stringsOf(context).clubFormDissolve,
      message: stringsOf(context).clubFormDissolveConfirm,
      confirmLabel: stringsOf(context).clubFormContinue,
    );
    if (!confirmed || !mounted) return;

    // 第二档:有非创建者成员时必须确认成员后果。
    if (club.nonOwnerMemberCount > 0) {
      final membersConfirmed = await _confirm(
        title: stringsOf(context).clubFormMemberConsequences,
        message: stringsOf(context).clubFormMemberImpact(club.nonOwnerMemberCount),
        confirmLabel: stringsOf(context).clubFormDissolveAnyway,
        destructive: true,
      );
      if (!membersConfirmed || !mounted) return;
    }

    setState(() => _dissolving = true);
    try {
      await ref
          .read(clubApiProvider)
          .dissolve(
            id: club.id,
            memberConsequencesConfirmed: club.nonOwnerMemberCount > 0,
          );
      if (!mounted) return;
      ref.invalidate(clubDetailProvider(club.id));
      ref.invalidate(clubMyProvider);
      ref.invalidate(clubListProvider);
      CyNativeNotice.show(context, stringsOf(context).clubFormDissolved);
      context.go('/clubs');
    } on ClubApiException catch (e) {
      if (!mounted) return;
      setState(() => _dissolving = false);
      if (e.message.contains('再次确认成员')) {
        final membersConfirmed = await _confirm(
          title: stringsOf(context).clubFormMemberConsequences,
          message: stringsOf(context).clubFormOtherMembersConsequence,
          confirmLabel: stringsOf(context).clubFormDissolveAnyway,
          destructive: true,
        );
        if (membersConfirmed && mounted) {
          setState(() => _dissolving = true);
          await _dissolveAfterMembersConfirmed(club.id);
        }
        return;
      }
      final items = e.data?['actionItems'];
      if (items is List<dynamic> && items.isNotEmpty) {
        await _showBlockers(club.id);
        return;
      }
      if (!mounted) return;
      CyNativeNotice.show(context, clubApiErrorMessage(context, e), isError: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _dissolving = false);
      // 异常原文只进日志 —— 上屏的永远是人话(后端原话优先)。
      debugPrint('[club-edit] 解散失败: $e');
      CyNativeNotice.show(
        context,
        clubApiErrorMessage(context, e, fallback: stringsOf(context).clubFormDissolveError),
        isError: true,
      );
    }
  }

  Future<void> _dissolveAfterMembersConfirmed(int clubId) async {
    try {
      await ref
          .read(clubApiProvider)
          .dissolve(id: clubId, memberConsequencesConfirmed: true);
      if (!mounted) return;
      ref.invalidate(clubDetailProvider(clubId));
      ref.invalidate(clubMyProvider);
      ref.invalidate(clubListProvider);
      CyNativeNotice.show(context, stringsOf(context).clubFormDissolved);
      context.go('/clubs');
    } catch (e) {
      if (!mounted) return;
      setState(() => _dissolving = false);
      // 异常原文只进日志 —— 上屏的永远是人话(后端原话优先)。
      debugPrint('[club-edit] 解散失败: $e');
      CyNativeNotice.show(
        context,
        friendlyErrorMessage(e, fallback: stringsOf(context).clubFormDissolveError),
        isError: true,
      );
    }
  }

  Future<void> _showBlockers(int clubId) async {
    // 确认键不是「继续做那件事」而是「去看待办」—— cyConfirm 只回 bool,
    // 跳转放在调用方,弹窗组件不掺业务跳转。
    final bool go = await cyConfirm(
      context,
      title: stringsOf(context).clubFormResolveOutstanding,
      content: stringsOf(context).clubFormFinancialStateRequired,
      confirmText: stringsOf(context).clubFormViewOutstanding,
    );
    if (go && mounted) {
      context.push('/club/$clubId/dissolution-blockers');
    }
    if (mounted) setState(() => _dissolving = false);
  }

  /// 页面内确认助手。返回**非空** bool —— cyConfirm 已把「点遮罩」的 null
  /// 收敛掉,调用方不必再写 `!= true` 这种防御式判断。
  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) {
    // 这里本来就是个页面内的通用确认助手(带 destructive 标志)—— 思路是对的,
    // 只是「危险」只体现在文字变红,两颗按钮的形态仍然一样。收编进 cyConfirm。
    return cyConfirm(
      context,
      title: title,
      content: message,
      confirmText: confirmLabel,
      danger: destructive,
    );
  }

  @override
  Widget build(BuildContext context) {
    final club = widget.club;
    final textTheme = Theme.of(context).textTheme;
    // ★ 12 个输入框的表单 —— 误触返回丢掉的代价最大,这道闸最该在这儿。
    return UnsavedGuard(
      isDirty: () => _dirty,
      child: ListView(
        padding: const EdgeInsets.all(CyTokens.space4),
        children: <Widget>[
          CySectionTitle(stringsOf(context).clubFormImages),
          const SizedBox(height: CyTokens.space3),
          _ImagePickerTile(
            label: stringsOf(context).clubFormAvatar,
            accessibilityHint: stringsOf(context).clubFormAvatarHint,
            url: _logo,
            width: 48,
            height: 48,
            circular: true,
            onTap: (BuildContext tileContext) async {
              final urls = await pickAndUploadImages(
                context,
                ref,
                maxCount: 1,
                // S4:锚点 = 触发元素(头像位)自己的矩形。
                sourceRect: cySourceRectOf(tileContext),
              );
              if (urls.isNotEmpty && mounted) {
                setState(() => _logo = urls.first);
              }
            },
          ),
          const SizedBox(height: CyTokens.space3),
          _ImagePickerTile(
            label: stringsOf(context).clubFormCover,
            accessibilityHint: stringsOf(context).clubFormCoverHint,
            url: _cover,
            width: 80,
            height: 45,
            onTap: (BuildContext tileContext) async {
              final urls = await pickAndUploadImages(
                context,
                ref,
                maxCount: 1,
                // S4:锚点 = 触发元素(封面位)自己的矩形。
                sourceRect: cySourceRectOf(tileContext),
              );
              if (urls.isNotEmpty && mounted) {
                setState(() => _cover = urls.first);
              }
            },
          ),
          const SizedBox(height: CyTokens.space2),
          Text(
            stringsOf(context).clubFormImageHint,
            style: textTheme.labelSmall?.copyWith(color: CyTokens.textTertiary),
          ),
          const SizedBox(height: CyTokens.space5),
          CySectionTitle(stringsOf(context).clubFormBasics),
          const SizedBox(height: CyTokens.space3),
          CyField(
            label: stringsOf(context).clubFormName,
            child: _input(
              _name,
              key: const ValueKey<String>('club-edit-name'),
              placeholder: stringsOf(context).clubFormClubName,
              keyboardType: TextInputType.name,
              textInputAction: TextInputAction.next,
              autofillHints: const <String>[AutofillHints.organizationName],
            ),
          ),
          CyField(
            label: stringsOf(context).clubFormCityField,
            child: _input(
              _city,
              key: const ValueKey<String>('club-edit-city'),
              placeholder: clubFormValueLabel(context, '所在城市'),
              textInputAction: TextInputAction.next,
              autofillHints: const <String>[AutofillHints.addressCity],
            ),
          ),
          CyField(
            label: stringsOf(context).clubFormKeywords,
            child: _input(
              _keywords,
              key: const ValueKey<String>('club-edit-keywords'),
              placeholder: stringsOf(context).clubFormKeywordsHint,
              textInputAction: TextInputAction.next,
            ),
          ),
          CyField(
            label: stringsOf(context).clubFormStyle,
            child: _input(
              _style,
              key: const ValueKey<String>('club-edit-style'),
              placeholder: stringsOf(context).clubFormStyleHint,
              textInputAction: TextInputAction.next,
            ),
          ),

          const SizedBox(height: CyTokens.space5),
          CySectionTitle(stringsOf(context).clubFormIntroductionTitle),
          const SizedBox(height: CyTokens.space3),
          CyField(
            label: stringsOf(context).clubFormIntroduction,
            child: _textarea(
              _description,
              key: const ValueKey<String>('club-edit-description'),
              placeholder: stringsOf(context).clubFormIntroductionHint,
            ),
          ),

          const SizedBox(height: CyTokens.space4),
          CySectionTitle(clubFormValueLabel(context, '俱乐部类型')),
          const SizedBox(height: CyTokens.space3),
          Wrap(
            spacing: CyTokens.space2,
            runSpacing: CyTokens.space2,
            children: <Widget>[
              for (final opt in _typeOptions)
                _NativeChoicePill(
                  key: ValueKey<String>('club-edit-type-${opt.val}'),
                  label: clubFormValueLabel(context, opt.val),
                  selected: _clubType == opt.val,
                  onTap: () => setState(() => _clubType = opt.val),
                ),
            ],
          ),
          const SizedBox(height: CyTokens.space4),
          CySectionTitle(stringsOf(context).clubFormPreferences),
          const SizedBox(height: CyTokens.space2),
          Wrap(
            spacing: CyTokens.space2,
            runSpacing: CyTokens.space2,
            children: <Widget>[
              for (final String dir in _dirOptions)
                _NativeChoicePill(
                  key: ValueKey<String>('club-edit-pref-$dir'),
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
          CySectionTitle(stringsOf(context).clubFormMembershipSettings),
          const SizedBox(height: CyTokens.space3),
          _switchRow(
            stringsOf(context).clubFormPriorityRegistration,
            stringsOf(context).clubFormPriorityRegistrationHint,
            _prioritySignupEnabled,
            (bool v) => setState(() => _prioritySignupEnabled = v),
          ),
          CyField(
            label: stringsOf(context).clubFormReservedPlaces,
            child: CupertinoTextField(
              key: const ValueKey<String>('club-member-reserved-quota'),
              controller: _memberReservedQuota,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              onChanged: (_) => setState(() {}),
              placeholder: '0',
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: _fieldDecoration(context),
            ),
          ),
          if (club.joinPolicySupported)
            _switchRow(
              stringsOf(context).clubFormApprovalRequired,
              stringsOf(context).clubFormApprovalRequiredHint,
              _joinPolicy == 1,
              (bool v) => setState(() => _joinPolicy = v ? 1 : 0),
            ),

          const SizedBox(height: CyTokens.space5),
          CupertinoButton.filled(
            minimumSize: const Size.fromHeight(44),
            onPressed: (_canSave && !_saving) ? _save : null,
            child: _saving
                ? const CupertinoActivityIndicator()
                : Text(stringsOf(context).clubFormSaveChanges),
          ),

          if (club.isOwner) ...<Widget>[
            const SizedBox(height: CyTokens.space6),
            CySectionTitle(stringsOf(context).clubFormDissolve),
            const SizedBox(height: CyTokens.space2),
            Text(
              stringsOf(context).clubFormDissolveFinancialHint,
              style: textTheme.labelSmall?.copyWith(
                color: CyTokens.textTertiary,
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            CupertinoButton(
              minimumSize: const Size.fromHeight(44),
              onPressed: _dissolving ? null : _dissolve,
              color: AppColors.danger,
              disabledColor: CyTokens.bgSubtle,
              child: _dissolving
                  ? const CupertinoActivityIndicator()
                  : Text(stringsOf(context).clubFormDissolve),
            ),
            const SizedBox(height: CyTokens.space3),
            CupertinoButton(
              minimumSize: const Size.fromHeight(44),
              onPressed: () =>
                  context.push('/club/${club.id}/dissolution-blockers'),
              child: Text(stringsOf(context).clubFormViewDissolutionBlockers),
            ),
          ],
        ],
      ),
    );
  }

  Widget _input(
    TextEditingController controller, {
    Key? key,
    String? placeholder,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    Iterable<String>? autofillHints,
  }) {
    return CupertinoTextField(
      key: key,
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      autocorrect: true,
      enableSuggestions: true,
      placeholder: placeholder,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      onChanged: (_) => setState(() {}),
      decoration: _fieldDecoration(context),
    );
  }

  Widget _textarea(
    TextEditingController controller, {
    Key? key,
    String? placeholder,
  }) {
    return CupertinoTextField(
      key: key,
      controller: controller,
      minLines: 3,
      maxLines: 3,
      maxLength: 200,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      autocorrect: true,
      enableSuggestions: true,
      placeholder: placeholder,
      padding: const EdgeInsets.all(14),
      onChanged: (_) => setState(() {}),
      decoration: _fieldDecoration(context),
    );
  }

  Widget _switchRow(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    final textTheme = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CyTokens.space1_5),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 44,
              child: Center(
                child: CupertinoSwitch(value: value, onChanged: onChanged),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _fieldDecoration(BuildContext context) {
  final CyPalette palette = CyPalette.of(context);
  return BoxDecoration(
    color: palette.bgSurface,
    border: Border.all(color: palette.borderSubtle),
    borderRadius: BorderRadius.circular(CyTokens.radiusMd),
  );
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
          duration: reduceMotion ? Duration.zero : CyMotion.fast,
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

class _ImagePickerTile extends StatelessWidget {
  const _ImagePickerTile({
    required this.label,
    required this.accessibilityHint,
    required this.url,
    required this.onTap,
    required this.width,
    required this.height,
    this.circular = false,
  });

  final String label;
  final String accessibilityHint;
  final String url;

  /// ★ 传**本 tile 的 context** 而不是 VoidCallback:action sheet 的锚点(S4)
  ///   要的正是触发元素自己的矩形,void 回调里拿不到它。
  final ValueChanged<BuildContext> onTap;
  final double width;
  final double height;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final has = url.isNotEmpty;
    return Semantics(
      excludeSemantics: true,
      button: true,
      label: has ? stringsOf(context).clubFormReplaceImage(accessibilityHint) : stringsOf(context).clubFormAddImage(accessibilityHint),
      child: CupertinoButton(
        minimumSize: Size.fromHeight(height < 44 ? 44 : height),
        padding: EdgeInsets.zero,
        onPressed: () => onTap(context),
        child: Row(
          children: <Widget>[
            Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: AppColors.bgSurface,
                borderRadius: circular
                    ? null
                    : BorderRadius.circular(CyTokens.radiusSm),
                shape: circular ? BoxShape.circle : BoxShape.rectangle,
                border: Border.all(color: CyTokens.borderSubtle),
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: has
                  ? Image.network(
                      url,
                      fit: BoxFit.cover,
                      width: width,
                      height: height,
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
            const SizedBox(width: CyTokens.space2),
            const Icon(
              CupertinoIcons.chevron_forward,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
