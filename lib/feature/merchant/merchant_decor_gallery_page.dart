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
import '../../core/widgets/status_view.dart';
import '../../core/widgets/unsaved_guard.dart';
import '../../data/models/merchant_decor.dart';

enum _GalleryLoadState { loading, ready, empty, error }

/// 门店相册独立三级页，对齐小程序 `decor/gallery`。
class MerchantDecorGalleryPage extends ConsumerStatefulWidget {
  const MerchantDecorGalleryPage({super.key});

  @override
  ConsumerState<MerchantDecorGalleryPage> createState() =>
      _MerchantDecorGalleryPageState();
}

class _MerchantDecorGalleryPageState
    extends ConsumerState<MerchantDecorGalleryPage> {
  _GalleryLoadState _loadState = _GalleryLoadState.loading;
  List<String> _gallery = <String>[];
  bool _dirty = false;
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loadState = _GalleryLoadState.loading);
    try {
      final Map<String, dynamic> profile = await ref
          .read(merchantApiProvider)
          .coopProfile();
      if (!mounted) return;
      if (profile.isEmpty) {
        setState(() => _loadState = _GalleryLoadState.empty);
        return;
      }
      setState(() {
        _gallery = List<String>.of(MerchantDecor.fromJson(profile).gallery);
        _dirty = false;
        _loadState = _GalleryLoadState.ready;
      });
    } catch (_) {
      if (mounted) setState(() => _loadState = _GalleryLoadState.error);
    }
  }

  Future<void> _add() async {
    if (_gallery.length >= 9) {
      CyNativeNotice.show(context, stringsOf(context).merchantStoreMaxImages, isError: true);
      return;
    }
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final String url = await ref.read(playApiProvider).uploadImage(file.path);
      if (!mounted) return;
      setState(() {
        _gallery = <String>[..._gallery, url].take(9).toList();
        _dirty = true;
      });
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

  Future<void> _save() async {
    if (!_dirty || _saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(merchantApiProvider).saveDecorGallery(_gallery);
      if (!mounted) return;
      setState(() => _dirty = false);
      CyNativeNotice.show(context, stringsOf(context).merchantStoreGallerySaved);
      _goBack();
    } catch (error) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// ★ 脏相册的返回先过 [UnsavedGuard](小程序「还没有保存」那道闸):
  ///   走 maybePop 而不是 pop —— pop 绕过 PopScope,闸就白装了。
  Future<void> _goBack() async {
    final NavigatorState navigator = Navigator.of(context);
    final bool popped = await navigator.maybePop();
    if (!popped && mounted) {
      GoRouter.maybeOf(context)?.go('/merchant/decor');
    }
  }

  @override
  Widget build(BuildContext context) => UnsavedGuard(
    isDirty: () => _dirty,
    // 小程序 `decor/gallery` 的原话,与俱乐部编辑那套不同。
    title: stringsOf(context).merchantStoreUnsaved,
    content: stringsOf(context).merchantStoreGalleryDiscard,
    confirmText: stringsOf(context).merchantStoreDiscard,
    cancelText: stringsOf(context).merchantStoreKeepEditing,
    child: CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(
        middle: Text(stringsOf(context).merchantStoreGallery),
        leading: CupertinoButton(
          key: const Key('merchant-gallery-back'),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          onPressed: _goBack,
          child: const Icon(CupertinoIcons.back),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(top: false, child: _body()),
      ),
    ),
  );

  Widget _body() => switch (_loadState) {
    _GalleryLoadState.loading => const CySkeleton(count: 6),
    _GalleryLoadState.error => StatusView(
      message: stringsOf(context).merchantStoreGalleryFailed,
      sub: stringsOf(context).merchantStoreNetworkRetry,
      onRetry: _load,
      retryLabel: stringsOf(context).merchantStoreReload,
      large: true,
    ),
    _GalleryLoadState.empty => StatusView(
      message: stringsOf(context).merchantStoreGalleryUnavailable,
      sub: stringsOf(context).merchantStoreGalleryNoStore,
      large: true,
    ),
    _GalleryLoadState.ready => Column(
      children: <Widget>[
        Expanded(
          child: CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.all(CyTokens.pageX),
                  padding: const EdgeInsets.all(CyTokens.space3),
                  decoration: BoxDecoration(
                    color: CyPalette.of(context).bgSurface,
                    borderRadius: BorderRadius.circular(CyTokens.radiusLg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(stringsOf(context).merchantStoreLandscape),
                      SizedBox(height: CyTokens.space1),
                      Text(stringsOf(context).merchantStoreGalleryHint),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: CyTokens.space2,
                    mainAxisSpacing: CyTokens.space2,
                    childAspectRatio: 16 / 9,
                  ),
                  delegate: SliverChildListDelegate(<Widget>[
                    for (int index = 0; index < _gallery.length; index++)
                      Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: ClipRRect(
                              key: Key('merchant-gallery-image-$index'),
                              borderRadius: BorderRadius.circular(
                                CyTokens.radiusLg,
                              ),
                              child: CyNetImage(
                                _gallery[index],
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: CupertinoButton(
                              key: Key('merchant-gallery-delete-$index'),
                              minimumSize: const Size(44, 44),
                              padding: EdgeInsets.zero,
                              onPressed: () => setState(() {
                                _gallery.removeAt(index);
                                _dirty = true;
                              }),
                              child: const Icon(
                                CupertinoIcons.xmark_circle_fill,
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (_gallery.length < 9)
                      CupertinoButton(
                        key: const Key('merchant-gallery-add'),
                        minimumSize: const Size(44, 44),
                        color: CyPalette.of(context).bgSurface,
                        onPressed: _uploading ? null : _add,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(CupertinoIcons.add),
                            Text(stringsOf(context).merchantStoreAddImage),
                          ],
                        ),
                      ),
                  ]),
                ),
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
              CyTokens.space2,
            ),
            child: SizedBox(
              width: double.infinity,
              child: CupertinoButton.filled(
                minimumSize: const Size.fromHeight(44),
                onPressed: (!_dirty || _saving) ? null : _save,
                child: _saving
                    ? const CupertinoActivityIndicator()
                    : Text(stringsOf(context).merchantStoreSaveGallery),
              ),
            ),
          ),
        ),
      ],
    ),
  };
}
