import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../core/theme/cy_tokens.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/widgets/status_view.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../data/api/address_api.dart';
import '../auth/auth_controller.dart';
import 'account_login_gate.dart';
import 'address_list_page.dart';

/// 新增 / 编辑参与人信息。对齐小程序 `pages/addressinfo`。
///
/// ★ 小程序当前只显示姓名 / 手机号；编辑时读回的 province / detailAddress /
///   isDefault 必须原样带回，否则改手机号会意外清空同一行的旧数据。
///
/// ★ 真源这页唯一的入口是**登录后的报名流程**(报名页 → 参与人列表 → 本页);
///   游客直进空表单点保存必然 401 —— 所以页内先给登录门(B1 报告 P1-4)。
class AddressEditPage extends ConsumerStatefulWidget {
  const AddressEditPage({super.key, this.addressId});

  /// null = 新增。
  final int? addressId;

  @override
  ConsumerState<AddressEditPage> createState() => _AddressEditPageState();
}

class _AddressEditPageState extends ConsumerState<AddressEditPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _region = TextEditingController();
  final TextEditingController _detail = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  bool _isDefault = false;

  bool _loading = false;
  bool _saving = false;

  /// 读回旧数据失败,与「保存失败」是两件事:前者整页换掉(见 build),
  /// 后者只是表单下方的一行提示。存**错误对象**而不是文案:
  /// 401 要换成一扇登录门,不是一行英文栈(B1 报告 P1-1)。
  Object? _loadError;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 游客不发注定 401 的回读请求(build 里先挡登录门)。
    if (widget.addressId != null &&
        ref.read(authControllerProvider).isLoggedIn) {
      _load();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _region.dispose();
    _detail.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final MemberAddress a = await ref
          .read(addressApiProvider)
          .info(widget.addressId!);
      if (!mounted) return;
      setState(() {
        _name.text = a.fullName;
        _phone.text = a.mobilePhone;
        _region.text = a.province ?? '';
        _detail.text = a.detailAddress ?? '';
        _isDefault = a.isDefault;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // 「地址不可用」既可能是不存在也可能不属于本人 —— 原话透传;
      // 401 在 build 里换成登录门。
      setState(() {
        _loading = false;
        _loadError = e;
      });
    }
  }

  bool get _canSave =>
      _name.text.trim().isNotEmpty &&
      RegExp(r'^1\d{10}$').hasMatch(_phone.text.trim()) &&
      !_saving;

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(addressApiProvider)
          .save(
            id: widget.addressId,
            fullName: _name.text.trim(),
            mobilePhone: _phone.text.trim(),
            province: _region.text.trim(),
            detailAddress: _detail.text.trim(),
            isDefault: _isDefault,
          );
      ref.invalidate(addressListProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = accountFailureCopy(e, networkFallback: '保存没有成功,请稍后重试');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 游客(含会话已失效)不进表单 —— 新增/回读/保存全都要登录。
    final Object? loadError = _loadError;
    if (!ref.watch(authControllerProvider).isLoggedIn ||
        (loadError != null && accountLoginRequired(loadError))) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('参与人信息')),
        child: SafeArea(
          bottom: false,
          child: AccountLoginGate(
            key: const Key('address-edit-login-gate'),
            message: '登录后填写参与人信息',
            sub: '参与人存在账号里,登录完就能继续。',
            onSignedIn: () {
              if (widget.addressId != null) {
                _loadError = null;
                _load();
              }
            },
          ),
        ),
      );
    }
    if (_loading) {
      // 真源 pages/addressinfo/addressinfo.wxml:11 =
      // `cy-skeleton type="form-section" count="2"` —— 与表单字段同构,不是封面卡。
      return const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text('参与人信息')),
        child: SafeArea(
          bottom: false,
          child: CySkeleton(type: CySkeletonType.formSection, count: 2),
        ),
      );
    }
    // 读不到旧数据时**不进表单** —— 表单是空的,而保存会按当前字段整行写回,
    // 手填姓名手机号再保存会把这一行原有的省市区/详细地址清空(数据丢失)。
    // 真源 pages/addressinfo/addressinfo.wxml:19-21 同款:加载失败盖住表单,
    // 只留「重新加载」一个出口,底部保存条也一并收起。
    if (loadError != null) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('参与人信息')),
        child: StatusView(
          message: '参与人信息没能加载出来',
          sub: accountFailureCopy(
            loadError,
            networkFallback: '请检查网络后再进来，数据不会丢失',
          ),
          large: true,
          onRetry: _load,
          retryLabel: '重新加载',
        ),
      );
    }
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('参与人信息')),
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: <Widget>[
            Expanded(
              child: SafeArea(
                bottom: false,
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(CyTokens.space4),
                  children: <Widget>[
                    Text(
                      '用于报名联系和到场核验，不会公开展示，也不用于配送。',
                      // 辅助说明行 = Footnote 13;系统语义色随主题解析。
                      style: CyType.footnote.copyWith(
                        color: CupertinoColors.secondaryLabel,
                      ),
                    ),
                    const SizedBox(height: CyTokens.space3),
                    AutofillGroup(
                      child: CupertinoFormSection.insetGrouped(
                        margin: EdgeInsets.zero,
                        children: <Widget>[
                          CupertinoTextFormFieldRow(
                            controller: _name,
                            focusNode: _nameFocus,
                            prefix: const Text('姓名'),
                            placeholder: '输入姓名',
                            textInputAction: TextInputAction.next,
                            autofillHints: const <String>[AutofillHints.name],
                            onFieldSubmitted: (_) => _phoneFocus.requestFocus(),
                            onChanged: (_) => setState(() {}),
                          ),
                          CupertinoTextFormFieldRow(
                            controller: _phone,
                            focusNode: _phoneFocus,
                            prefix: const Text('手机号'),
                            placeholder: '输入手机号',
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.done,
                            autofillHints: const <String>[
                              AutofillHints.telephoneNumber,
                            ],
                            maxLength: 11,
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onFieldSubmitted: (_) {
                              if (_canSave) _save();
                            },
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: CyTokens.space2),
                      // 真源 cy-inline-error:标题说清「什么没保存」,
                      // 原话透传做副标,动作给「重试保存」。
                      Text(
                        '参与人信息没有保存',
                        style: CyType.subhead.copyWith(
                          fontWeight: FontWeight.w600,
                          color: CyPalette.of(context).statusDanger,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _error!,
                        // 错误色走语义色板,不向 Material colorScheme 取。
                        style: CyType.footnote.copyWith(
                          color: CyPalette.of(context).statusDanger,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: CupertinoButton(
                          key: const Key('address-retry-save'),
                          minimumSize: const Size(44, 44),
                          padding: EdgeInsets.zero,
                          onPressed: _canSave ? _save : null,
                          child: const Text('重试保存'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // 真源保存钮钉底(cy-footer-bar),表单再长也不会滚丢。
            CyFooterBar(
              primary: CupertinoButton.filled(
                key: const Key('address-save-participant'),
                onPressed: _canSave ? _save : null,
                minimumSize: const Size.fromHeight(CyTokens.btnH),
                child: Text(_saving ? '保存中…' : '保存参与人信息'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
