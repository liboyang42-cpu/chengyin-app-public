import '../../l10n/strings.dart';
import '../../core/theme/cy_palette.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/cy_confirm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../data/api/merchant_api.dart';
import 'merchant_error_view.dart';
import '../../core/widgets/unsaved_guard.dart';

/// 商家资料读取:`POST /api/merchant/info`。★ 与 `/update` 成对,此前两条都没接。
final merchantInfoProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) {
  return ref.watch(merchantApiProvider).merchantInfo();
});

/// 店铺资料。对齐后端白名单(ApiMerchantController:536-541):
/// logo / name / description / derivatives / website / preference。
/// 别的字段(地址/坐标等)不在这页 —— 后端根本不认,做成可编辑就是骗用户。
class MerchantEditPage extends ConsumerWidget {
  const MerchantEditPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(merchantInfoProvider);
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantStoreProfile)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: async.when(
            loading: () => const Center(child: CupertinoActivityIndicator()),
            error: (Object e, _) => merchantErrorView(
              context,
              e,
              onRetry: () => ref.invalidate(merchantInfoProvider),
            ),
            data: (Map<String, dynamic> info) => _EditForm(info: info),
          ),
        ),
      ),
    );
  }
}

class _EditForm extends ConsumerStatefulWidget {
  const _EditForm({required this.info});
  final Map<String, dynamic> info;

  @override
  ConsumerState<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends ConsumerState<_EditForm> {
  late String _logo = (widget.info['logo'] as String?) ?? '';
  late String _name = (widget.info['name'] as String?) ?? '';
  late String _description = (widget.info['description'] as String?) ?? '';
  late String _derivatives = (widget.info['derivatives'] as String?) ?? '';
  late String _website = (widget.info['website'] as String?) ?? '';
  late String _preference = (widget.info['preference'] as String?) ?? '';
  bool _busy = false;
  bool _uploading = false;
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _derivativesController;
  late final TextEditingController _websiteController;
  late final TextEditingController _preferenceController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: _name);
    _descriptionController = TextEditingController(text: _description);
    _derivativesController = TextEditingController(text: _derivatives);
    _websiteController = TextEditingController(text: _website);
    _preferenceController = TextEditingController(text: _preference);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _derivativesController.dispose();
    _websiteController.dispose();
    _preferenceController.dispose();
    super.dispose();
  }

  /// 进页面时的原值快照。★ 用来判「脏不脏」——
  /// 只看「有没有敲过字」会把「敲了又改回去」也算脏,
  /// 那样用户明明什么都没变还被拦一下。
  late final Map<String, String> _original = <String, String>{
    'logo': _logo,
    'name': _name,
    'description': _description,
    'derivatives': _derivatives,
    'website': _website,
    'preference': _preference,
  };

  bool get _dirty =>
      _logo != _original['logo'] ||
      _name != _original['name'] ||
      _description != _original['description'] ||
      _derivatives != _original['derivatives'] ||
      _website != _original['website'] ||
      _preference != _original['preference'];

  int? get _memberId => (widget.info['memberId'] as num?)?.toInt();

  Future<void> _pickLogo() async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final url = await ref.read(playApiProvider).uploadImage(file.path);
      if (!mounted) return;
      setState(() => _logo = url);
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        stringsOf(context).merchantStoreUploadFailed(e.toString().replaceFirst('Exception: ', '')),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final msg = await ref
          .read(merchantApiProvider)
          .updateMerchant(
            logo: _logo,
            name: _name,
            description: _description,
            derivatives: _derivatives,
            website: _website,
            preference: _preference,
          );
      if (!mounted) return;
      CyNativeNotice.show(context, msg);
      ref.invalidate(merchantInfoProvider);
    } catch (e) {
      if (!mounted) return;
      if (e is MerchantApiException && e.isContentRejected) {
        await cyConfirm(
          context,
          title: stringsOf(context).merchantStoreRejected,
          content: stringsOf(context).merchantStoreReviewInstructions(e.message),
          confirmText: stringsOf(context).merchantStoreEdit,
          showCancel: false,
        );
        return;
      }
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ★ 脏表单返回时拦一下 —— 少这道闸,用户填了十分钟误触返回就全没了,
    //   而且没有任何提示说他刚丢了什么(见 unsaved_guard.dart)。
    return UnsavedGuard(
      isDirty: () => _dirty,
      child: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(CyTokens.pageX),
              children: <Widget>[
                const CySectionTitle('Logo'),
                const SizedBox(height: CyTokens.space2),
                Row(
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                      child: _logo.isEmpty
                          ? Container(
                              width: 64,
                              height: 64,
                              color: CyPalette.of(context).bgSurfaceStrong,
                            )
                          : CyNetImage(
                              _logo,
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                            ),
                    ),
                    const SizedBox(width: CyTokens.space3),
                    CupertinoButton(
                      minimumSize: const Size(44, 44),
                      onPressed: _uploading ? null : _pickLogo,
                      child: Text(_uploading ? stringsOf(context).merchantStoreUploading : stringsOf(context).merchantStoreChangeImage),
                    ),
                  ],
                ),
                // ★ logo 异步送检,保存成功不等于已过审 —— 别写「已生效」。
                Text(
                  stringsOf(context).merchantStoreLogoReview,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
                const SizedBox(height: CyTokens.space4),
                CyField(
                  label: stringsOf(context).merchantStoreBrandName,
                  child: _textField(
                    key: const Key('merchant-edit-name'),
                    controller: _nameController,
                    keyboardType: TextInputType.name,
                    autofillHints: const <String>[
                      AutofillHints.organizationName,
                    ],
                    onChanged: (String v) => setState(() => _name = v),
                  ),
                ),
                CyField(
                  label: stringsOf(context).merchantStoreIntroduction,
                  child: _textField(
                    key: const Key('merchant-edit-description'),
                    controller: _descriptionController,
                    maxLines: 3,
                    textInputAction: TextInputAction.newline,
                    onChanged: (String v) => setState(() => _description = v),
                  ),
                ),
                CyField(
                  label: stringsOf(context).merchantStoreMerchandise,
                  child: _textField(
                    key: const Key('merchant-edit-derivatives'),
                    controller: _derivativesController,
                    placeholder: stringsOf(context).merchantStoreOptional,
                    onChanged: (String v) => setState(() => _derivatives = v),
                  ),
                ),
                CyField(
                  label: stringsOf(context).merchantStoreWebsite,
                  child: _textField(
                    key: const Key('merchant-edit-website'),
                    controller: _websiteController,
                    placeholder: stringsOf(context).merchantStoreOptional,
                    keyboardType: TextInputType.url,
                    autofillHints: const <String>[AutofillHints.url],
                    onChanged: (String v) => setState(() => _website = v),
                  ),
                ),
                CyField(
                  label: stringsOf(context).merchantStorePreferences,
                  child: _textField(
                    key: const Key('merchant-edit-preference'),
                    controller: _preferenceController,
                    placeholder: stringsOf(context).merchantStoreOptional,
                    onChanged: (String v) => setState(() => _preference = v),
                  ),
                ),
                if (_memberId != null && _memberId! > 0) ...<Widget>[
                  const SizedBox(height: CyTokens.space3),
                  CupertinoButton(
                    key: const Key('merchant-edit-preview'),
                    minimumSize: const Size.fromHeight(44),
                    color: CyPalette.of(context).bgSurfaceStrong,
                    onPressed: () =>
                        context.push('/merchant/public-home/member/$_memberId'),
                    child: Text(stringsOf(context).merchantStorePreview),
                  ),
                ],
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
                  key: const Key('merchant-edit-save'),
                  minimumSize: const Size.fromHeight(44),
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CupertinoActivityIndicator(),
                        )
                      : Text(stringsOf(context).merchantStoreSave),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _textField({
    required Key key,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    String? placeholder,
    TextInputType? keyboardType,
    Iterable<String>? autofillHints,
    TextInputAction? textInputAction,
    int maxLines = 1,
  }) {
    final palette = CyPalette.of(context);
    return CupertinoTextField(
      key: key,
      controller: controller,
      placeholder: placeholder,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      textInputAction:
          textInputAction ??
          (maxLines == 1 ? TextInputAction.next : TextInputAction.newline),
      maxLines: maxLines,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: palette.bgSurface,
        border: Border.all(color: palette.borderSubtle),
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      onChanged: onChanged,
    );
  }
}
