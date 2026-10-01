import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/merchant_decor.dart';

enum _StoryLoadState { loading, ready, empty, error }

/// 品牌故事全屏编辑器。小程序真源已删除标题输入，本页只编辑正文。
class MerchantDecorStoryPage extends ConsumerStatefulWidget {
  const MerchantDecorStoryPage({super.key});

  @override
  ConsumerState<MerchantDecorStoryPage> createState() =>
      _MerchantDecorStoryPageState();
}

class _MerchantDecorStoryPageState
    extends ConsumerState<MerchantDecorStoryPage> {
  _StoryLoadState _loadState = _StoryLoadState.loading;
  Map<String, dynamic> _profile = <String, dynamic>{};
  MerchantDecor _decor = const MerchantDecor();
  final TextEditingController _controller = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loadState = _StoryLoadState.loading);
    try {
      final Map<String, dynamic> profile = await ref
          .read(merchantApiProvider)
          .coopProfile();
      if (!mounted) return;
      if (profile.isEmpty) {
        setState(() => _loadState = _StoryLoadState.empty);
        return;
      }
      _controller.text = (profile['description'] ?? '').toString();
      setState(() {
        _profile = Map<String, dynamic>.of(profile);
        _decor = MerchantDecor.fromJson(profile);
        _loadState = _StoryLoadState.ready;
      });
    } catch (_) {
      if (mounted) setState(() => _loadState = _StoryLoadState.error);
    }
  }

  Future<void> _save() async {
    if (_saving || _loadState != _StoryLoadState.ready) return;
    setState(() => _saving = true);
    try {
      final api = ref.read(merchantApiProvider);
      await Future.wait<void>(<Future<void>>[
        api.saveDecorStoryTitle(_decor.storyTitle ?? ''),
        api.updateMerchant(
          logo: (_profile['logo'] ?? '').toString(),
          name: (_profile['name'] ?? '').toString(),
          description: _controller.text,
          derivatives: (_profile['derivatives'] ?? '').toString(),
          website: (_profile['website'] ?? '').toString(),
          preference: (_profile['preference'] ?? '').toString(),
        ),
      ]);
      if (!mounted) return;
      CyNativeNotice.show(context, stringsOf(context).merchantStoreSaved);
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

  void _goBack() {
    final NavigatorState navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      GoRouter.maybeOf(context)?.go('/merchant/decor');
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    navigationBar: CupertinoNavigationBar(
      middle: Text(stringsOf(context).merchantStoreStory),
      leading: CupertinoButton(
        key: const Key('merchant-story-back'),
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
  );

  Widget _body() => switch (_loadState) {
    _StoryLoadState.loading => const CySkeleton(
      type: CySkeletonType.list,
      count: 3,
    ),
    _StoryLoadState.error => StatusView(
      message: stringsOf(context).merchantStoreStoryFailed,
      sub: stringsOf(context).merchantStoreNetworkSession,
      onRetry: _load,
      retryLabel: stringsOf(context).merchantStoreReload,
      large: true,
    ),
    _StoryLoadState.empty => StatusView(
      message: stringsOf(context).merchantStoreStoryUnavailable,
      sub: stringsOf(context).merchantStoreStoryNoStore,
      onRetry: () => GoRouter.maybeOf(context)?.go('/merchant/apply'),
      retryLabel: stringsOf(context).merchantStoreApply,
      large: true,
    ),
    _StoryLoadState.ready => Column(
      children: <Widget>[
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(CyTokens.pageX),
            child: CupertinoTextField(
              key: const Key('merchant-decor-story-body'),
              controller: _controller,
              placeholder: stringsOf(context).merchantStoreStoryPrompt,
              maxLength: 300,
              minLines: 12,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              padding: const EdgeInsets.all(CyTokens.space3),
              decoration: BoxDecoration(
                color: CyPalette.of(context).bgSubtle,
                borderRadius: BorderRadius.circular(CyTokens.radiusSm),
              ),
            ),
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
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const CupertinoActivityIndicator()
                    : Text(stringsOf(context).merchantStoreSaveStory),
              ),
            ),
          ),
        ),
      ],
    ),
  };
}
