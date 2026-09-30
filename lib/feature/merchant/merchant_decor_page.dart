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
      if (mounted) CyNativeNotice.show(context, '已保存');
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
      if (mounted) CyNativeNotice.show(context, '已保存');
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
                      child: const Text('完成'),
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
          title: const Text('选择行业'),
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
            child: const Text('取消'),
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
                      const Expanded(child: Text('选择特色标签')),
                      CupertinoButton(
                        minimumSize: const Size(44, 44),
                        onPressed: () => Navigator.of(context).pop(draft),
                        child: const Text('完成'),
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
                                Text(entry.key),
                                const SizedBox(height: CyTokens.space1),
                                Wrap(
                                  spacing: CyTokens.space1,
                                  runSpacing: CyTokens.space1,
                                  children: entry.value
                                      .map(
                                        (String tag) => CyChip(
                                          label: tag,
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
                        const Text('自定义'),
                        const SizedBox(height: CyTokens.space1),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: CupertinoTextField(
                                key: const Key('merchant-decor-custom-tag'),
                                controller: customController,
                                placeholder: '输入自定义标签',
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
                              child: const Text('添加'),
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
      CyNativeNotice.show(context, '资料加载中', isError: true);
      return;
    }
    context.push('/merchant/public-home/member/$memberId');
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    navigationBar: const CupertinoNavigationBar(middle: Text('店铺装修')),
    child: Material(
      color: Colors.transparent,
      child: SafeArea(top: false, child: _body()),
    ),
  );

  Widget _body() => switch (_loadState) {
    _DecorLoadState.loading => const CySkeleton(type: CySkeletonType.detail),
    _DecorLoadState.error => StatusView(
      message: '店铺装修加载失败',
      sub: '网络或登录状态暂时不可用，请重试。',
      onRetry: _load,
      retryLabel: '重新载入',
      large: true,
    ),
    _DecorLoadState.empty => StatusView(
      message: '暂时无法装修店铺',
      sub: '这个账号还没有店铺，先完成商家入驻拿到店铺，再回来填行业类型和品牌资料。',
      onRetry: () => context.push('/merchant/apply'),
      retryLabel: '去商家入驻',
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
      if (_profile['capacity'] != null) '${_profile['capacity']} 人',
      if ((_profile['availableTime'] ?? '').toString().isNotEmpty)
        _profile['availableTime'].toString(),
      (_profile['chargeType'] as num?)?.toInt() == 1 ? '收费承接' : '免费承接',
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
            _section('品牌资料', <Widget>[
              _row(
                '封面头图 · 16:9',
                _decor.coverImage == null ? '未上传' : '已上传',
                () => _pickImage(cover: true),
              ),
              _row(
                'Logo · 1:1',
                (_profile['logo'] ?? '').toString().isEmpty ? '未上传' : '已上传',
                () => _pickImage(cover: false),
              ),
              _row(
                '店铺名称',
                (_profile['name'] ?? '填写店铺名称').toString(),
                () => _editField(
                  key: 'name',
                  label: '店铺名称',
                  placeholder: '店铺名称(必填)',
                  brand: true,
                ),
              ),
              _row(
                '行业类型',
                categoryNames.isEmpty ? '选择行业(平台固定，主页显示)' : categoryNames,
                _chooseCategory,
              ),
              _row(
                '门店定位',
                (_profile['locationVerified'] as num?)?.toInt() == 1
                    ? '已定位 ✓'
                    : '点击校准店址',
                _chooseLocation,
              ),
            ]),
            _section('品牌内容', <Widget>[
              _row(
                '城市角色名',
                _decor.cityRole ?? '如:巷口的夜间补给站',
                () => _editField(
                  key: 'cityRole',
                  label: '城市角色名',
                  placeholder: '如:巷口的夜间补给站',
                  brand: false,
                ),
              ),
              _row(
                '一句话 slogan',
                _decor.slogan ?? '一句话说清你的店',
                () => _editField(
                  key: 'slogan',
                  label: '一句话 slogan',
                  placeholder: '一句话说清你的店',
                  brand: false,
                ),
              ),
              _row(
                '品牌故事',
                (_profile['description'] ?? '').toString().isEmpty
                    ? '还没写'
                    : (_decor.storyTitle ?? '已填写'),
                () => _openChild('/merchant/decor/story'),
              ),
              _row(
                '衍生权益',
                (_profile['derivatives'] ?? '如 限定饮品 / 核销折扣').toString(),
                () => _editField(
                  key: 'derivatives',
                  label: '衍生权益',
                  placeholder: '如 限定饮品 / 核销折扣 / 路线纪念章',
                  brand: true,
                ),
              ),
              _row(
                '特色标签',
                _decor.tags.isEmpty
                    ? '还没选标签'
                    : '${_decor.tags.first}${_decor.tags.length > 1 ? ' 等 ${_decor.tags.length} 个' : ''}',
                _chooseTags,
              ),
              _row(
                '门店相册 · 16:9',
                _decor.gallery.isEmpty
                    ? '还没上传'
                    : '${_decor.gallery.length}/9 张',
                () => _openChild('/merchant/decor/gallery'),
              ),
            ]),
            _section('承接与经营(B2B 撮合)', <Widget>[
              _row(
                '承接设置',
                coopSummary,
                () => context.push('/merchant/coop-profile'),
              ),
              _row(
                '招牌主推',
                _decor.featuredId == null ? '选 1 个活动置顶' : '已选主推',
                () => context.push('/my-projects'),
              ),
              _row('常备权益', '查看与管理', () => context.push('/coop/perk-templates')),
            ]),
            _section(null, <Widget>[
              _row(
                '升级权益',
                '查看可开通的权益',
                () => context.push('/merchant/subscription'),
              ),
            ]),
            _section(null, <Widget>[
              _row(
                '成为城市节点 · 挂互动玩法',
                '',
                () => context.push('/merchant/city-nodes'),
              ),
              _row('用户照片 · 探索记录 · 评价', '即将开放', null),
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
            label: '封面头图',
            done: (_decor.coverImage ?? '').trim().isNotEmpty,
            action: () => _pickImage(cover: true),
          ),
          (
            label: '店铺 Logo',
            done:
                (_profile['logo'] ?? '').toString().trim().isNotEmpty &&
                _profile['logo'] != '/images/mer1.jpg',
            action: () => _pickImage(cover: false),
          ),
          (
            label: '店铺名称',
            done: (_profile['name'] ?? '').toString().trim().isNotEmpty,
            action: () => _editField(
              key: 'name',
              label: '店铺名称',
              placeholder: '店铺名称(必填)',
              brand: true,
            ),
          ),
          (
            label: '行业类型',
            done: _decor.categoryId != null,
            action: _chooseCategory,
          ),
          (
            label: '门店定位',
            done: (_profile['locationVerified'] as num?)?.toInt() == 1,
            action: _chooseLocation,
          ),
          (
            label: '一句话 slogan',
            done: (_decor.slogan ?? '').trim().isNotEmpty,
            action: () => _editField(
              key: 'slogan',
              label: '一句话 slogan',
              placeholder: '一句话说清你的店',
              brand: false,
            ),
          ),
          (
            label: '品牌故事',
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
              const Expanded(child: Text('资料完整度')),
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
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(top: CyTokens.space1),
                child: Text('必填资料都齐了'),
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
                  '还没有封面头图',
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
                      Text((profile['name'] ?? '还没填店铺名称').toString()),
                      Text(
                        '看公开主页 ›',
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
                          ? '已打烊'
                          : '营业中',
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
