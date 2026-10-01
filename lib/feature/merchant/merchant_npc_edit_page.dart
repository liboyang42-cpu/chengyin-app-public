import '../../l10n/strings.dart';
import 'merchant_node_strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import 'merchant_error_view.dart';
import '../../data/models/merchant_npc.dart';
import 'package:go_router/go_router.dart';
import '../club/club_image_picker.dart';

/// 商家自助配置门店 AI 形象。
///
/// <p>★★ 这一页决定「玩家在店铺主页点开这个形象、问『有什么推荐』时,它拿什么来答」。
///
/// ★ 三条语义,每条对应一个真会犯的错:
///
///   ① **人设与店铺知识是两件事,分开填。**
///      人设 = 怎么说话(口吻、性格);店铺知识 = 说什么(菜单、招牌、营业信息)。
///      合成一栏的话,商家会把菜单写进人设,模型把菜单当成"性格描述"复述,
///      问推荐时反而答不出来。
///
///   ② **保存即回到待审,而且要在按钮上说清。**
///      后端 `updateMerchantSelfNpc` 无条件把 audit_status 打回 0。
///      不在 UI 上说的话,商家改一个错别字后以为立刻生效,实际下线等审核。
///
///   ③ **审核状态文案由后端下发,这里不自己拼。**
///      两端各写一套,同一个状态会出现两种说法。
class MerchantNpcEditPage extends ConsumerStatefulWidget {
  const MerchantNpcEditPage({super.key});

  @override
  ConsumerState<MerchantNpcEditPage> createState() =>
      _MerchantNpcEditPageState();
}

class _MerchantNpcEditPageState extends ConsumerState<MerchantNpcEditPage> {
  MerchantNpcProfile _draft = const MerchantNpcProfile();

  final Map<String, TextEditingController> _c = <String, TextEditingController>{
    'name': TextEditingController(),
    'greeting': TextEditingController(),
    'persona': TextEditingController(),
    'knowledge': TextEditingController(),
  };

  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;
  bool _revoking = false;
  String? _loadError;

  /// 声音克隆开没开放。★ 从服务端读,客户端不猜供应商接没接。
  bool _voiceAvailable = false;

  /// 3D 形象生成开没开放。同上。
  bool _avatar3dAvailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final TextEditingController c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final MerchantNpcProfile p = await ref
          .read(merchantNpcApiProvider)
          .myProfile();
      // 声音开放状态与形象一起拉。★ 拉不到按「没开放」处理 ——
      // 失败方向是不显示入口,而不是显示一个点了会失败的入口。
      bool voiceAvailable = false;
      bool avatar3dAvailable = false;
      try {
        voiceAvailable =
            (await ref.read(merchantNpcApiProvider).voiceScript()).available;
      } catch (_) {
        voiceAvailable = false;
      }
      try {
        avatar3dAvailable =
            (await ref.read(merchantNpcApiProvider).avatarStatus()).available;
      } catch (_) {
        avatar3dAvailable = false;
      }
      if (!mounted) return;
      _c['name']!.text = p.name;
      _c['greeting']!.text = p.greeting ?? '';
      _c['persona']!.text = p.persona;
      _c['knowledge']!.text = p.knowledge ?? '';
      setState(() {
        _draft = p;
        _voiceAvailable = voiceAvailable;
        _avatar3dAvailable = avatar3dAvailable;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// 把输入框的当前值合进草稿。★ 每次校验/提交都从这里取,
  /// 不要各处直接读 controller —— 那样漏一处就会出现"看着填了、提交没带上"。
  MerchantNpcProfile get _current => _draft.copyWith(
    name: _c['name']!.text,
    greeting: _c['greeting']!.text.trim().isEmpty
        ? null
        : _c['greeting']!.text,
    persona: _c['persona']!.text,
    knowledge: _c['knowledge']!.text.trim().isEmpty
        ? null
        : _c['knowledge']!.text,
  );

  Future<void> _pickAvatar() async {
    setState(() => _uploading = true);
    try {
      final List<String> urls = await pickAndUploadImages(
        context,
        ref,
        maxCount: 1,
      );
      if (urls.isNotEmpty && mounted) {
        setState(() => _draft = _draft.copyWith(avatar: urls.first));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final MerchantNpcProfile next = _current;
    // ★ 先本地拦一道:让商家填的时候就知道缺什么,而不是提交完被打回。
    //   ⚠️ 真正算数的是后端那道 —— 这里只是省一次往返。
    final String? why = next.blocker;
    if (why != null) {
      CyNativeNotice.show(context, merchantNodeLocalText(context, why), isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final String msg = await ref.read(merchantNpcApiProvider).save(next);
      if (!mounted) return;
      CyNativeNotice.show(context, msg);
      // 回读:提交后状态变成「审核中」,必须从服务端拿回真值再显示,
      // 不要在本地伪造成已提交 —— 那会在保存失败时说谎。
      await _load();
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantNodeStoreCharacter)),
        child: Material(
          color: Colors.transparent,
          child: SafeArea(bottom: false, child: CySkeleton()),
        ),
      );
    }

    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    final MerchantNpcProfile cur = _current;

    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantNodeStoreCharacter)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: _loadError != null
              ? merchantErrorView(
                  context,
                  _loadError!,
                  onRetry: _load,
                  what: stringsOf(context).merchantNodeStoreCharacter,
                )
              : ListView(
                  padding: const EdgeInsets.all(CyTokens.space4),
                  children: <Widget>[
                    if (_draft.configured) _statusBanner(p, t),
                    Text(
                      stringsOf(context).merchantNodeStoreIntro,
                      style: t.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                    const SizedBox(height: CyTokens.space4),

                    CySectionTitle(stringsOf(context).merchantNodeAvatar),
                    const SizedBox(height: CyTokens.space2),
                    _avatarBlock(),
                    const SizedBox(height: CyTokens.space4),

                    _field('name', stringsOf(context).merchantNodeAvatarName, hint: stringsOf(context).merchantNodeAvatarNameHint),
                    _field(
                      'greeting',
                      stringsOf(context).merchantNodeGreetingOptional,
                      hint: stringsOf(context).merchantNodeGreetingHint,
                      maxLines: 2,
                    ),

                    const SizedBox(height: CyTokens.space2),
                    // 分类名跟小程序 `pages/merchant/decor/ai-npc/index.wxml:68`
                    // 的字段标题「性格设定」逐字一致 —— 两端同一个人格字段叫两个名字,
                    // 商家在小程序里填过的那栏,到 App 会认不出来。
                    CySectionTitle(stringsOf(context).merchantNodePersonality),
                    const SizedBox(height: CyTokens.space1),
                    Text(
                      stringsOf(context).merchantNodePersonalityHint,
                      style: t.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                    const SizedBox(height: CyTokens.space2),
                    _field(
                      'persona',
                      '',
                      hint: stringsOf(context).merchantNodePersonalityExample,
                      maxLines: 5,
                    ),

                    const SizedBox(height: CyTokens.space2),
                    CySectionTitle(stringsOf(context).merchantNodeKnowledge),
                    const SizedBox(height: CyTokens.space1),
                    Text(
                      stringsOf(context).merchantNodeKnowledgeHint,
                      style: t.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                    const SizedBox(height: CyTokens.space2),
                    _field(
                      'knowledge',
                      '',
                      hint: stringsOf(context).merchantNodeKnowledgeExample,
                      maxLines: 8,
                    ),

                    if (_avatar3dAvailable && _draft.configured) ...<Widget>[
                      const SizedBox(height: CyTokens.space2),
                      CySectionTitle(stringsOf(context).merchantNodeAppearance),
                      const SizedBox(height: CyTokens.space1),
                      Text(
                        _draft.modelUrl == null
                            ? stringsOf(context).merchantNodePhotoAppearance
                            : stringsOf(context).merchantNodeRegenerateAppearanceHint,
                        style: t.bodySmall?.copyWith(color: p.textSecondary),
                      ),
                      const SizedBox(height: CyTokens.space2),
                      CyNativeButton(
                        key: const Key('merchant-npc-avatar-entry'),
                        onPressed: () async {
                          await context.push('/merchant/npc/avatar');
                          // 生成是异步的,回来一定要回读 —— 页面上的
                          // modelUrl 与审核状态都可能已经变了。
                          if (mounted) await _load();
                        },
                        role: CyNativeButtonRole.secondary,
                        icon: const CyNativeButtonIcon(
                          sfSymbol: 'cube',
                          fallback: CupertinoIcons.cube,
                        ),
                        label: _draft.modelUrl == null ? stringsOf(context).merchantNodeGenerate3d : stringsOf(context).merchantNodeRegenerate,
                      ),
                    ],

                    if (_voiceAvailable) ...<Widget>[
                      const SizedBox(height: CyTokens.space2),
                      CySectionTitle(stringsOf(context).merchantNodeRoleVoice),
                      const SizedBox(height: CyTokens.space1),
                      _voiceBlock(p, t),
                    ],

                    const SizedBox(height: CyTokens.space4),
                    // ★ 把「保存 = 回到待审」写在按钮上方,不是藏在提示里。
                    Text(
                      _draft.isApproved
                          ? stringsOf(context).merchantNodeSaveReviewAgain
                          : stringsOf(context).merchantNodeSaveReview,
                      style: t.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                    const SizedBox(height: CyTokens.space2),
                    CyNativeButton(
                      key: const Key('merchant-npc-save'),
                      onPressed: _saving || !cur.canSubmit ? null : _save,
                      label: _saving ? stringsOf(context).merchantNodeSubmitting : stringsOf(context).merchantNodeSubmitReview,
                      loading: _saving,
                    ),
                    if (!cur.canSubmit) ...<Widget>[
                      const SizedBox(height: CyTokens.space2),
                      Text(
                        merchantNodeLocalText(context, cur.blocker!),
                        style: t.bodySmall?.copyWith(color: p.textSecondary),
                      ),
                    ],
                    const SizedBox(height: CyTokens.space6),
                  ],
                ),
        ),
      ),
    );
  }

  /// 声音区块。★ 只在 `_voiceAvailable` 为真时渲染 ——
  /// 供应商没接就不该出现这一整块,不是灰一个按钮。
  Widget _voiceBlock(CyPalette p, TextTheme t) {
    if (!_draft.configured) {
      // 还没有形象就没有可挂声音的对象。说清先后顺序,不给一个必然失败的入口。
      return Text(
        stringsOf(context).merchantNodeVoiceFirstSubmit,
        style: t.bodySmall?.copyWith(color: p.textSecondary),
      );
    }
    if (!_draft.hasVoice) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '录五句话,让店铺角色用你的声音说话。第一句是授权声明。',
            style: t.bodySmall?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: CyTokens.space2),
          CyNativeButton(
            key: const Key('merchant-npc-voice-entry'),
            onPressed: () async {
              final Object? done = await context.push('/merchant/npc/voice');
              // 录完回来要回读:hasVoice 变了,这一块要跟着变。
              if (done == true && mounted) await _load();
            },
            role: CyNativeButtonRole.secondary,
            icon: const CyNativeButtonIcon(
              sfSymbol: 'mic',
              fallback: CupertinoIcons.mic,
            ),
            label: stringsOf(context).merchantNodeRecordMyVoice,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          stringsOf(context).merchantNodeRecordedHint,
          style: t.bodySmall?.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: CyTokens.space2),
        Row(
          children: <Widget>[
            CupertinoButton(
              key: const Key('merchant-npc-voice-redo'),
              padding: EdgeInsets.zero,
              minimumSize: const Size(88, 44),
              onPressed: _revoking
                  ? null
                  : () async {
                      final Object? done =
                          await context.push('/merchant/npc/voice');
                      if (done == true && mounted) await _load();
                    },
              child: Text(stringsOf(context).merchantNodeRerecord),
            ),
            CupertinoButton(
              key: const Key('merchant-npc-voice-revoke'),
              padding: EdgeInsets.zero,
              minimumSize: const Size(88, 44),
              onPressed: _revoking ? null : _revokeVoice,
              child: Text(_revoking ? stringsOf(context).merchantNodeRevoking : stringsOf(context).merchantNodeRevokeDelete),
            ),
          ],
        ),
      ],
    );
  }

  /// 撤回声音授权。
  ///
  /// ★ 后端在「远端没删成」时返回失败,这里**如实告诉商家没删掉** ——
  ///   报成已撤回而供应商那边还留着音色,等于骗人。
  Future<void> _revokeVoice() async {
    setState(() => _revoking = true);
    try {
      final String msg = await ref.read(merchantNpcApiProvider).voiceRevoke();
      if (!mounted) return;
      CyNativeNotice.show(context, msg);
      await _load();
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _revoking = false);
    }
  }

  Widget _statusBanner(CyPalette p, TextTheme t) {
    // 状态文案来自后端,这里只决定用什么颜色。
    final String text = _draft.statusText ?? stringsOf(context).merchantNodeReviewing;
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space3),
      child: Container(
        padding: const EdgeInsets.all(CyTokens.space3),
        decoration: BoxDecoration(
          color: p.bgSurfaceSubtle,
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              _draft.isApproved
                  ? CupertinoIcons.checkmark_seal
                  : _draft.isRejected
                  ? CupertinoIcons.exclamationmark_circle
                  : CupertinoIcons.clock,
              size: 18,
              color: p.textSecondary,
            ),
            const SizedBox(width: CyTokens.space2),
            Expanded(child: Text(text, style: t.bodySmall)),
          ],
        ),
      ),
    );
  }

  Widget _avatarBlock() {
    final String? avatar = _draft.avatar;
    if ((avatar ?? '').isEmpty) {
      return CyNativeButton(
        key: const Key('merchant-npc-avatar-upload'),
        onPressed: _uploading ? null : _pickAvatar,
        role: CyNativeButtonRole.secondary,
        icon: const CyNativeButtonIcon(
          sfSymbol: 'person.crop.circle',
          fallback: CupertinoIcons.person_crop_circle,
        ),
        label: _uploading ? stringsOf(context).merchantNodeUploading : stringsOf(context).merchantNodeUploadAvatarSquare,
        loading: _uploading,
      );
    }
    return Row(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          child: CyNetImage(avatar, width: 72, height: 72, fit: BoxFit.cover),
        ),
        const SizedBox(width: CyTokens.space3),
        CupertinoButton(
          key: const Key('merchant-npc-avatar-replace'),
          onPressed: _uploading ? null : _pickAvatar,
          padding: EdgeInsets.zero,
          child: Text(stringsOf(context).merchantNodeChangeImage),
        ),
      ],
    );
  }

  Widget _field(
    String key,
    String label, {
    String? hint,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (label.isNotEmpty) ...<Widget>[
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: CyTokens.space1),
          ],
          CupertinoTextField(
            key: Key('merchant-npc-$key'),
            controller: _c[key],
            minLines: 1,
            maxLines: maxLines,
            placeholder: hint,
            padding: const EdgeInsets.symmetric(
              horizontal: CyTokens.space3,
              vertical: 12,
            ),
            textInputAction: maxLines > 1
                ? TextInputAction.newline
                : TextInputAction.next,
            clearButtonMode: OverlayVisibilityMode.editing,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }
}
