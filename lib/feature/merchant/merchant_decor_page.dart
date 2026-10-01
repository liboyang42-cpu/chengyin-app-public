import 'merchant_store_strings.dart';
import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/category.dart';
import '../../data/models/merchant_decor.dart';

enum _DecorLoadState { loading, ready, empty, error }

/// 店铺装修根页。信息架构对齐小程序 `pages/merchant/decor/index`。
class MerchantDecorPage extends ConsumerStatefulWidget {
  const MerchantDecorPage({super.key});

  @override
  ConsumerState<MerchantDecorPage> createState() => _MerchantDecorPageState();
}

class _MerchantDecorPageState extends ConsumerState<MerchantDecorPage> {
  static const Map<String, List<String>> _tagLibrary = <String, List<String>>{
    '空间': <String>['老街', '天台', '独立空间', '宠物友好', '夜间开放', '适合拍照'],
    '体验': <String>['适合单人', '适合情侣', '适合亲子', '适合组队', '雨天可去', '安静'],
    '人群': <String>['学生党', '上班族', '摄影爱好者', '美食探店', '亲子家庭', '潮流青年'],
  };

  _DecorLoadState _loadState = _DecorLoadState.loading;
  Map<String, dynamic> _profile = <String, dynamic>{};
  MerchantDecor _decor = const MerchantDecor();
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loadState = _DecorLoadState.loading);
    try {
      final Map<String, dynamic> profile = await ref
          .read(merchantApiProvider)
          .coopProfile();
      if (!mounted) return;
      if (profile.isEmpty) {
        setState(() => _loadState = _DecorLoadState.empty);
        return;
      }
      setState(() {
        _profile = Map<String, dynamic>.of(profile);
        _decor = MerchantDecor.fromJson(profile);
        _loadState = _DecorLoadState.ready;
      });
    } catch (_) {
      if (mounted) setState(() => _loadState = _DecorLoadState.error);
    }
  }

  Future<void> _saveDecor(MerchantDecor next) async {
    final MerchantDecor before = _decor;
    setState(() {
      _decor = next;
      _saving = true;
    });
    try {
      await ref.read(merchantApiProvider).saveDecor(next);
      if (mounted) CyNativeNotice.show(context, stringsOf(context).merchantStoreSaved);
    } catch (error) {
      if (!mounted) return;
      setState(() => _decor = before);
      CyNativeNotice.show(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveBrandField(String key, String value) async {
    final Map<String, dynamic> before = Map<String, dynamic>.of(_profile);
    setState(() {
      _profile[key] = value;
      _saving = true;
    });
    try {
      await _saveBrandProfile();
      if (mounted) CyNativeNotice.show(context, stringsOf(context).merchantStoreSaved);
    } catch (error) {
      if (!mounted) return;
      setState(() => _profile = before);
      CyNativeNotice.show(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveBrandProfile() => ref
      .read(merchantApiProvider)
      .updateMerchant(
        logo: (_profile['logo'] ?? '').toString(),
        name: (_profile['name'] ?? '').toString(),
        description: (_profile['description'] ?? '').toString(),
        derivatives: (_profile['derivatives'] ?? '').toString(),
        website: (_profile['website'] ?? '').toString(),
        preference: (_profile['preference'] ?? '').toString(),
      );

  Future<void> _editField({
    required String key,
    required String label,
    required String placeholder,
    required bool brand,
  }) async {
    final String initial = brand
        ? (_profile[key] ?? '').toString()
        : switch (key) {
            'cityRole' => _decor.cityRole ?? '',
            'slogan' => _decor.slogan ?? '',
            _ => '',
          };
    final TextEditingController controller = TextEditingController(
      text: initial,
    );
    final String? value = await showCupertinoModalPopup<String>(
      context: context,
      // 系统弹窗材质(#383 口径):不再自绘实色卡片 + 自定义圆角。
      builder: (BuildContext sheetContext) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
        child: CupertinoPopupSurface(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              CyTokens.pageX,
              CyTokens.space3,
              CyTokens.pageX,
              CyTokens.space3 + MediaQuery.paddingOf(sheetContext).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        label,
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                    ),
                    CupertinoButton(
                      minimumSize: const Size(44, 44),
                      onPressed: () =>
                          Navigator.of(sheetContext).pop(controller.text),
                      child: Text(stringsOf(context).merchantStoreDone),
                    ),
                  ],
                ),
                CupertinoTextField(
                  key: const Key('merchant-decor-field-input'),
                  controller: controller,
                  autofocus: true,
                  placeholder: placeholder,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    if (brand) {
      await _saveBrandField(key, value);
    } else if (key == 'cityRole') {
      await _saveDecor(_decor.copyWith(cityRole: value));
    } else if (key == 'slogan') {
      await _saveDecor(_decor.copyWith(slogan: value));
    }
  }

  Future<void> _pickImage({required bool cover}) async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final String url = await ref.read(playApiProvider).uploadImage(file.path);
      if (!mounted) return;
      if (cover) {
        await _saveDecor(_decor.copyWith(coverImage: url));
      } else {
        _profile['logo'] = url;
        await _saveBrandProfile();
        if (mounted) setState(() {});
      }
    } catch (error) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _chooseCategory() async {
    try {
      final List<Category> categories = await ref
          .read(categoryApiProvider)
          .list();
      if (!mounted) return;
      final Category? selected = await showCupertinoModalPopup<Category>(
        context: context,
        builder: (BuildContext sheetContext) => CupertinoActionSheet(
          title: Text(stringsOf(context).merchantStoreSelectIndustry),
          actions: categories
              .map(
                (Category category) => CupertinoActionSheetAction(
                  onPressed: () => Navigator.of(sheetContext).pop(category),
                  child: Text(category.name),
                ),
              )
              .toList(),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: Text(stringsOf(context).merchantStoreCancel),
          ),
        ),
      );
      if (selected == null || !mounted) return;
      _profile['sysCategoryList'] = <Map<String, dynamic>>[
        <String, dynamic>{'categoryName': selected.name},
      ];
      await _saveDecor(_decor.copyWith(categoryId: selected.id));
    } catch (error) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    }
  }

  Future<void> _chooseLocation() async {
    final (String, double, double)? point = await context
        .push<(String, double, double)>('/publish/poi');
    if (point == null || !mounted) return;
    _profile['locationVerified'] = 1;
    _profile['address'] = point.$1;
    await _saveDecor(
      _decor.copyWith(
        locationLat: point.$2,
        locationLng: point.$3,
        locationVerified: 1,
      ),
    );
  }

  Future<void> _chooseTags() async {
    final List<String> draft = List<String>.of(_decor.tags);
    final TextEditingController customController = TextEditingController();
    final List<String>? result = await showCupertinoModalPopup<List<String>>(
      context: context,
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setSheetState) => ClipRRect(
          // 系统弹窗材质(#383 口径):不再自绘实色卡片 + 自定义圆角。
          borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
          child: CupertinoPopupSurface(
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .72,
              ),
              padding: EdgeInsets.fromLTRB(
                CyTokens.pageX,
                CyTokens.space3,
                CyTokens.pageX,
                MediaQuery.paddingOf(context).bottom + CyTokens.space3,
              ),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(child: Text(stringsOf(context).merchantStoreSelectTags)),
                      CupertinoButton(
                        minimumSize: const Size(44, 44),
                        onPressed: () => Navigator.of(context).pop(draft),
                        child: Text(stringsOf(context).merchantStoreDone),
                      ),
                    ],
                  ),
                  Expanded(
                    child: ListView(
                      children: <Widget>[
                        ..._tagLibrary.entries.map(
                          (entry) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: CyTokens.space3,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(merchantStoreTagOption(context, entry.key)),
                                const SizedBox(height: CyTokens.space1),
                                Wrap(
                                  spacing: CyTokens.space1,
                                  runSpacing: CyTokens.space1,
                                  children: entry.value
                                      .map(
                                        (String tag) => CyChip(
                                          label: merchantStoreTagOption(context, tag),
                                          selected: draft.contains(tag),
                                          onTap: () => setSheetState(() {
                                            if (draft.contains(tag)) {
                                              draft.remove(tag);
                                            } else if (draft.length < 12) {
                                              draft.add(tag);
                                            }
                                          }),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Text(stringsOf(context).merchantStoreCustom),
                        const SizedBox(height: CyTokens.space1),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: CupertinoTextField(
                                key: const Key('merchant-decor-custom-tag'),
                                controller: customController,
                                placeholder: stringsOf(context).merchantStoreCustomHint,
                              ),
                            ),
                            CupertinoButton(
                              minimumSize: const Size(44, 44),
                              onPressed: () {
                                final String tag = customController.text.trim();
                                if (tag.isEmpty ||
                                    draft.contains(tag) ||
                                    draft.length >= 12) {
                                  return;
                                }
                                setSheetState(() {
                                  draft.add(tag);
                                  customController.clear();
                                });
                              },
                              child: Text(stringsOf(context).merchantStoreAdd),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    customController.dispose();
    if (result == null || !mounted) return;
    await _saveDecor(_decor.copyWith(tags: result));
  }

  Future<void> _openChild(String route) async {
    await context.push<void>(route);
    if (mounted) await _load();
  }

  Future<void> _toggleBusiness(bool open) async {
    final Object? before = _profile['businessStatus'];
    setState(() => _profile['businessStatus'] = open ? 1 : 0);
    try {
      final String message = await ref
          .read(merchantApiProvider)
          .updateBusinessStatus(open: open);
      if (mounted) CyNativeNotice.show(context, message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _profile['businessStatus'] = before);
      CyNativeNotice.show(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  void _openPreview() {
    final int memberId = (_profile['memberId'] as num?)?.toInt() ?? 0;
    if (memberId < 1) {
      CyNativeNotice.show(context, stringsOf(context).merchantStoreLoading, isError: true);
      return;
    }
    context.push('/merchant/public-home/member/$memberId');
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantStoreDecor)),
    child: Material(
      color: Colors.transparent,
      child: SafeArea(top: false, child: _body()),
    ),
  );

  Widget _body() => switch (_loadState) {
    _DecorLoadState.loading => const CySkeleton(type: CySkeletonType.detail),
    _DecorLoadState.error => StatusView(
      message: stringsOf(context).merchantStoreDecorFailed,
      sub: stringsOf(context).merchantStoreNetworkSession,
      onRetry: _load,
      retryLabel: stringsOf(context).merchantStoreReload,
      large: true,
    ),
    _DecorLoadState.empty => StatusView(
      message: stringsOf(context).merchantStoreDecorUnavailable,
      sub: stringsOf(context).merchantStoreDecorNoStore,
      onRetry: () => context.push('/merchant/apply'),
      retryLabel: stringsOf(context).merchantStoreApply,
      large: true,
    ),
    _DecorLoadState.ready => _readyBody(),
  };

  Widget _readyBody() {
    final String categoryNames =
        ((_profile['sysCategoryList'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map value) => (value['categoryName'] ?? '').toString())
            .where((String value) => value.isNotEmpty)
            .join(' · ');
    final String coopSummary = <String>[
      if (_profile['capacity'] != null) stringsOf(context).merchantStoreCapacity(_profile['capacity'].toString()),
      if ((_profile['availableTime'] ?? '').toString().isNotEmpty)
        _profile['availableTime'].toString(),
      (_profile['chargeType'] as num?)?.toInt() == 1 ? stringsOf(context).merchantStorePaidHosting : stringsOf(context).merchantStoreFreeHosting,
    ].join(' · ');
    return Stack(
      children: <Widget>[
        ListView(
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space2,
            CyTokens.pageX,
            CyTokens.space6,
          ),
          children: <Widget>[
            _PreviewCard(
              profile: _profile,
              decor: _decor,
              onPreview: _openPreview,
              onBusinessChanged: _toggleBusiness,
            ),
            const SizedBox(height: CyTokens.space3),
            _guideCard(),
            const SizedBox(height: CyTokens.space3),
            _section(stringsOf(context).merchantStoreBrandProfile, <Widget>[
              _row(
                stringsOf(context).merchantStoreCoverRatio,
                _decor.coverImage == null ? stringsOf(context).merchantStoreNotUploaded : stringsOf(context).merchantStoreUploaded,
                () => _pickImage(cover: true),
              ),
              _row(
                'Logo · 1:1',
                (_profile['logo'] ?? '').toString().isEmpty ? stringsOf(context).merchantStoreNotUploaded : stringsOf(context).merchantStoreUploaded,
                () => _pickImage(cover: false),
              ),
              _row(
                stringsOf(context).merchantStoreStoreName,
                (_profile['name'] ?? stringsOf(context).merchantStoreEnterName).toString(),
                () => _editField(
                  key: 'name',
                  label: stringsOf(context).merchantStoreStoreName,
                  placeholder: stringsOf(context).merchantStoreNameRequired,
                  brand: true,
                ),
              ),
              _row(
                stringsOf(context).merchantStoreIndustry,
                categoryNames.isEmpty ? stringsOf(context).merchantStoreIndustryHint : categoryNames,
                _chooseCategory,
              ),
              _row(
                stringsOf(context).merchantStoreLocation,
                (_profile['locationVerified'] as num?)?.toInt() == 1
                    ? stringsOf(context).merchantStoreLocated
                    : stringsOf(context).merchantStoreCalibrate,
                _chooseLocation,
              ),
            ]),
            _section(stringsOf(context).merchantStoreBrandContent, <Widget>[
              _row(
                stringsOf(context).merchantStoreCityRole,
                _decor.cityRole ?? stringsOf(context).merchantStoreCityRoleHint,
                () => _editField(
                  key: 'cityRole',
                  label: stringsOf(context).merchantStoreCityRole,
                  placeholder: stringsOf(context).merchantStoreCityRoleHint,
                  brand: false,
                ),
              ),
              _row(
                stringsOf(context).merchantStoreSlogan,
                _decor.slogan ?? stringsOf(context).merchantStoreSloganHint,
                () => _editField(
                  key: 'slogan',
                  label: stringsOf(context).merchantStoreSlogan,
                  placeholder: stringsOf(context).merchantStoreSloganHint,
                  brand: false,
                ),
              ),
              _row(
                stringsOf(context).merchantStoreStory,
                (_profile['description'] ?? '').toString().isEmpty
                    ? stringsOf(context).merchantStoreUnwritten
                    : (_decor.storyTitle ?? stringsOf(context).merchantStoreCompleted),
                () => _openChild('/merchant/decor/story'),
              ),
              _row(
                stringsOf(context).merchantStoreBenefits,
                (_profile['derivatives'] ?? stringsOf(context).merchantStoreBenefitsHint).toString(),
                () => _editField(
                  key: 'derivatives',
                  label: stringsOf(context).merchantStoreBenefits,
                  placeholder: stringsOf(context).merchantStoreBenefitsEditHint,
                  brand: true,
                ),
              ),
              _row(
                stringsOf(context).merchantStoreTags,
                _decor.tags.isEmpty
                    ? stringsOf(context).merchantStoreNoTags
                    : _decor.tags.length > 1 ? stringsOf(context).merchantStoreTagSummary(_decor.tags.first, _decor.tags.length) : _decor.tags.first,
                _chooseTags,
              ),
              _row(
                stringsOf(context).merchantStoreGalleryRatio,
                _decor.gallery.isEmpty
                    ? stringsOf(context).merchantStoreNoUploads
                    : stringsOf(context).merchantStoreImageCount(_decor.gallery.length),
                () => _openChild('/merchant/decor/gallery'),
              ),
            ]),
            _section(stringsOf(context).merchantStoreBusiness, <Widget>[
              _row(
                stringsOf(context).merchantStoreHostingSettings,
                coopSummary,
                () => context.push('/merchant/coop-profile'),
              ),
              _row(
                stringsOf(context).merchantStoreFeatured,
                _decor.featuredId == null ? stringsOf(context).merchantStoreFeatureHint : stringsOf(context).merchantStoreFeatureSelected,
                () => context.push('/my-projects'),
              ),
              _row(stringsOf(context).merchantStoreStandingBenefits, stringsOf(context).merchantStoreManage, () => context.push('/coop/perk-templates')),
            ]),
            _section(null, <Widget>[
              _row(
                stringsOf(context).merchantStoreUpgrade,
                stringsOf(context).merchantStoreAvailableBenefits,
                () => context.push('/merchant/subscription'),
              ),
            ]),
            _section(null, <Widget>[
              _row(
                stringsOf(context).merchantStoreCityNode,
                '',
                () => context.push('/merchant/city-nodes'),
              ),
              _row(stringsOf(context).merchantStoreUserContent, stringsOf(context).merchantStoreComingSoon, null),
            ]),
          ],
        ),
        if (_saving || _uploading)
          const Positioned(
            right: CyTokens.pageX,
            top: CyTokens.space2,
            child: CupertinoActivityIndicator(),
          ),
      ],
    );
  }

  Widget _guideCard() {
    final List<({String label, bool done, VoidCallback action})> items =
        <({String label, bool done, VoidCallback action})>[
          (
            label: stringsOf(context).merchantStoreCover,
            done: (_decor.coverImage ?? '').trim().isNotEmpty,
            action: () => _pickImage(cover: true),
          ),
          (
            label: stringsOf(context).merchantStoreLogo,
            done:
                (_profile['logo'] ?? '').toString().trim().isNotEmpty &&
                _profile['logo'] != '/images/mer1.jpg',
            action: () => _pickImage(cover: false),
          ),
          (
            label: stringsOf(context).merchantStoreStoreName,
            done: (_profile['name'] ?? '').toString().trim().isNotEmpty,
            action: () => _editField(
              key: 'name',
              label: stringsOf(context).merchantStoreStoreName,
              placeholder: stringsOf(context).merchantStoreNameRequired,
              brand: true,
            ),
          ),
          (
            label: stringsOf(context).merchantStoreIndustry,
            done: _decor.categoryId != null,
            action: _chooseCategory,
          ),
          (
            label: stringsOf(context).merchantStoreLocation,
            done: (_profile['locationVerified'] as num?)?.toInt() == 1,
            action: _chooseLocation,
          ),
          (
            label: stringsOf(context).merchantStoreSlogan,
            done: (_decor.slogan ?? '').trim().isNotEmpty,
            action: () => _editField(
              key: 'slogan',
              label: stringsOf(context).merchantStoreSlogan,
              placeholder: stringsOf(context).merchantStoreSloganHint,
              brand: false,
            ),
          ),
          (
            label: stringsOf(context).merchantStoreStory,
            done: (_profile['description'] ?? '').toString().trim().isNotEmpty,
            action: () => _openChild('/merchant/decor/story'),
          ),
        ];
    final int done = items.where((item) => item.done).length;
    return Container(
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(stringsOf(context).merchantStoreCompleteness)),
              Text('$done/${items.length}'),
            ],
          ),
          for (final item in items.where((item) => !item.done))
            CupertinoButton(
              minimumSize: const Size.fromHeight(44),
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.space1),
              onPressed: item.action,
              child: Row(
                children: <Widget>[
                  Icon(
                    CupertinoIcons.circle,
                    size: 16,
                    color: CyPalette.of(context).textSecondary,
                  ),
                  const SizedBox(width: CyTokens.space2),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        color: CyPalette.of(context).textPrimary,
                      ),
                    ),
                  ),
                  const Icon(CupertinoIcons.chevron_forward, size: 16),
                ],
              ),
            ),
          if (done == items.length)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(top: CyTokens.space1),
                child: Text(stringsOf(context).merchantStoreComplete),
              ),
            ),
        ],
      ),
    );
  }

  Widget _section(String? title, List<Widget> rows) => Padding(
    padding: const EdgeInsets.only(bottom: CyTokens.space3),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(
              left: CyTokens.space1,
              bottom: CyTokens.space1,
            ),
            child: CySectionTitle(title),
          ),
        Container(
          decoration: BoxDecoration(
            color: CyPalette.of(context).bgSurface,
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: rows),
        ),
      ],
    ),
  );

  Widget _row(String label, String value, VoidCallback? onPressed) =>
      CupertinoButton(
        minimumSize: const Size.fromHeight(50),
        padding: const EdgeInsets.symmetric(
          horizontal: CyTokens.space3,
          vertical: CyTokens.space1,
        ),
        onPressed: (_saving || _uploading) ? null : onPressed,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: CyPalette.of(context).textPrimary),
              ),
            ),
            if (value.isNotEmpty)
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: CyPalette.of(context).textSecondary),
                ),
              ),
            if (onPressed != null) ...<Widget>[
              const SizedBox(width: CyTokens.space1),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 16,
                color: CyPalette.of(context).textSecondary,
              ),
            ],
          ],
        ),
      );
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.profile,
    required this.decor,
    required this.onPreview,
    required this.onBusinessChanged,
  });

  final Map<String, dynamic> profile;
  final MerchantDecor decor;
  final VoidCallback onPreview;
  final ValueChanged<bool> onBusinessChanged;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: CyPalette.of(context).bgSurface,
      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
    ),
    child: CupertinoButton(
      minimumSize: const Size.fromHeight(44),
      padding: EdgeInsets.zero,
      onPressed: onPreview,
      child: Column(
        children: <Widget>[
          if ((decor.coverImage ?? '').isNotEmpty)
            CyNetImage(
              decor.coverImage!,
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
            )
          else
            SizedBox(
              height: 140,
              child: Center(
                child: Text(
                  stringsOf(context).merchantStoreNoCover,
                  style: TextStyle(color: CyPalette.of(context).textSecondary),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(CyTokens.space3),
            child: Row(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                  child: (profile['logo'] ?? '').toString().isEmpty
                      ? const SizedBox(width: 44, height: 44)
                      : CyNetImage(
                          profile['logo'].toString(),
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        ),
                ),
                const SizedBox(width: CyTokens.space2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text((profile['name'] ?? stringsOf(context).merchantStoreNoName).toString()),
                      Text(
                        stringsOf(context).merchantStorePublicPage,
                        style: TextStyle(
                          color: CyPalette.of(context).textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: <Widget>[
                    Text(
                      (profile['businessStatus'] as num?)?.toInt() == 0
                          ? stringsOf(context).merchantStoreClosed
                          : stringsOf(context).merchantStoreOpen,
                    ),
                    CupertinoSwitch(
                      value: (profile['businessStatus'] as num?)?.toInt() != 0,
                      onChanged: onBusinessChanged,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
