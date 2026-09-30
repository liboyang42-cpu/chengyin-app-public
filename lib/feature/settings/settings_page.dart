import '../../l10n/strings.dart';
import '../../l10n/locale_preference.dart';
import '../../core/widgets/cy_native_action_sheet.dart';
import '../../core/theme/cy_palette.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/widgets/cy_confirm.dart';
import '../account/inviter_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mjn_liquid_ui/mjn_liquid_ui.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

import '../../core/providers.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/account_api.dart';
import '../../data/models/user.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';
import '../legal/legal_doc_page.dart';
import 'marketing_consent_sheet.dart';
import '../legal/legal_docs.dart';
import '../map/map_controller.dart';
import '../roam/roam_live_controller.dart';
import 'sound_haptics_settings.dart';

/// 设置页。对齐小程序 `pages/shezhi/shezhi`:
/// 身份卡 + 菜单(个人资料 / 主理人 / 商家 / 玩法 / 喜欢 / 声音触感 / 隐私定位 /
/// 协议 / 注销 / 关于)+ 退出账号,声音触感与隐私定位就地开半屏弹窗。
///
/// 行高钩子 112rpx 对齐小程序 `--cy-comp-cell-min-h`;菜单行间 gap space-2。
/// 「成为主理人 / 成为商家」只对无商家、无俱乐部身份的用户显示(与小程序
/// `!isMerchantView && !isClubView` 同源)。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, this.liquidGlassSupported});

  /// 测试固定 iOS 26 capability；运行时仍以系统版本为准。
  final bool? liquidGlassSupported;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String? get _role => ref.read(authControllerProvider).user?.effectiveRole;

  bool get _isMerchant => _role == 'merchant';
  bool get _isClub => _role == 'club';

  void _goProfile() =>
      context.push(_isMerchant ? '/merchant/decor' : '/profile/edit');
  void _goClubs() => context.push('/club/apply');
  void _goAgreement() =>
      context.push(LegalDocPage.routeOf(LegalDocType.userAgreement));

  /// 注销页整页需登录(`app_router.dart` 的 `_loginRequiredPrefixes` 含 `/deregister`)。
  /// 不先弹登录门的话,这次 push 会被 redirect **静默兜底回首页** ——
  /// 用户只看到"点了没反应",不知道是在要登录。
  Future<void> _goDeregister() async {
    if (!await requireLogin(context, ref)) return;
    if (!mounted) return;
    context.push('/deregister');
  }

  void _goAbout() => context.push('/settings/about');

  /// 同一前缀陷阱:`/merchant/apply` 落在 `_loginRequiredPrefixes` 的 `/merchant`
  /// 下,游客点「成为商家」与注销一样会被静默兜底回首页。同一处修,别只修一半。
  Future<void> _goMerchantApply() async {
    if (!await requireLogin(context, ref)) return;
    if (!mounted) return;
    context.push('/merchant/apply');
  }

  Future<void> _openSoundHaptics() async {
    await showCupertinoSheet<void>(
      context: context,
      showDragHandle: true,
      scrollableBuilder: (BuildContext context, ScrollController controller) {
        return _SoundHapticsSheet(
          scrollController: controller,
          liquidGlassSupported:
              widget.liquidGlassSupported ??
              NativeLiquidGlassUtils.supportsLiquidGlass,
        );
      },
    );
  }

  Future<void> _openPrivacy() async {
    await showCupertinoSheet<void>(
      context: context,
      showDragHandle: true,
      scrollableBuilder: (BuildContext context, ScrollController controller) {
        return _PrivacySheet(scrollController: controller);
      },
    );
  }

  /// 退出账号:确认 → 清 token → 回主页。可逆动作,随时可再登录。
  Future<void> _logout() async {
    // 标题原来是「提示」—— 那等于什么都没说。标题就该说清在做什么。
    final bool ok = await cyConfirm(
      context,
      title: '退出账号',
      content: '退出后需要重新登录才能查看订单和票券。',
      confirmText: '退出',
      danger: true,
    );
    if (!ok || !mounted) return;
    await ref.read(authControllerProvider.notifier).logout();
    if (mounted) context.go(kHomeRoute);
  }

  Future<void> _chooseLanguage() async {
    final strings = stringsOf(context);
    final choice = await showCyNativeActionSheet<String>(
      context: context,
      title: strings.language,
      cancelLabel: strings.cancel,
      actions: <CyNativeAction<String>>[
        CyNativeAction(value: 'system', label: strings.followSystem),
        CyNativeAction(value: 'zh', label: strings.chineseLanguage),
        CyNativeAction(value: 'en', label: strings.englishLanguage),
      ],
    );
    if (choice == null || !mounted) return;
    try {
      await ref.read(localePreferenceProvider.notifier)
          .select(choice == 'system' ? null : choice);
    } catch (_) {
      if (mounted) {
        CyNativeNotice.show(context, stringsOf(context).languageSaveError,
          isError: true);
      }
    }
  }

  Widget _cell({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return CyCell(
      title: title,
      subtitle: subtitle,
      minHeight: 56, // 112rpx:小程序设置页行高钩子
      leading: Icon(icon, size: 20, color: CyPalette.of(context).textSecondary),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final strings = stringsOf(context);
    final language = ref.watch(localePreferenceProvider)?.languageCode;
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.only(bottom: CyTokens.space6),
            children: <Widget>[
              CyPageTitle(strings.settings),
              _cell(
                icon: Icons.language,
                title: strings.language,
                subtitle: switch (language) {
                  'en' => strings.englishLanguage,
                  'zh' => strings.chineseLanguage,
                  _ => strings.followSystem,
                },
                onTap: _chooseLanguage,
              ),
              _ProfileCard(user: user, onEdit: _goProfile),
              Padding(
                padding: const EdgeInsets.only(top: CyTokens.space2),
                child: Column(
                  children: <Widget>[
                    _cell(
                      icon: Icons.person_outline,
                      title: '个人资料',
                      subtitle: '昵称、头像与介绍',
                      onTap: _goProfile,
                    ),
                    _cell(
                      icon: Icons.groups_outlined,
                      title: '参与人信息',
                      subtitle: '报名时可直接选,不用每次手填',
                      onTap: () => context.push('/participants'),
                    ),
                    // 「收货地址」行已删(B1 账号域报告 P1-3):真源 shezhi 没有
                    // 这一行,收货/配送语义系 App 虚构 —— 同一张表的资料入口只有
                    // 上面「参与人信息」一条。
                    _cell(
                      icon: Icons.card_giftcard_outlined,
                      title: '填写邀请人',
                      subtitle: '只能绑定一次',
                      onTap: () => showInviterSheet(context),
                    ),
                    if (!_isMerchant && !_isClub)
                      _cell(
                        icon: Icons.flag_outlined,
                        title: '成为俱乐部主理人',
                        subtitle: '主理人身份 · 之后可创建俱乐部带团',
                        onTap: _goClubs,
                      ),
                    if (!_isMerchant && !_isClub)
                      _cell(
                        icon: Icons.storefront_outlined,
                        title: '成为商家',
                        subtitle: '提供场地 · 参与招募 · 发布优惠',
                        onTap: _goMerchantApply,
                      ),
                    _cell(
                      icon: Icons.public,
                      title: '城瘾玩法',
                      subtitle: '城市探索说明',
                      onTap: () => context.push('/play-guide'),
                    ),
                    _cell(
                      icon: Icons.route_outlined,
                      title: '我走过的',
                      subtitle: '完成过的路线',
                      onTap: () => context.push('/my-plays'),
                    ),
                    _cell(
                      icon: Icons.favorite_border,
                      title: '我的喜欢',
                      subtitle: '已收藏的主题',
                      onTap: () => context.push('/my-likes'),
                    ),
                    _cell(
                      icon: Icons.volume_up_outlined,
                      title: '声音与触感',
                      subtitle: '声音与触感',
                      onTap: _openSoundHaptics,
                    ),
                    _cell(
                      icon: Icons.privacy_tip_outlined,
                      title: '隐私与定位',
                      subtitle: '管理漫游定位同意',
                      onTap: _openPrivacy,
                    ),
                    // 真源 `pages/shezhi/shezhi.wxml:23` 的
                    // `settings-marketing-consent`:隐私与定位的下一行。
                    _cell(
                      icon: Icons.campaign_outlined,
                      title: '营销消息与优惠券',
                      subtitle: '按商家管理同意与退订',
                      onTap: () => showMarketingConsentSheet(context),
                    ),
                    _cell(
                      icon: Icons.description_outlined,
                      title: '用户服务协议',
                      subtitle: '查看服务条款',
                      onTap: _goAgreement,
                    ),
                    _cell(
                      icon: Icons.person_remove_outlined,
                      title: '账号注销',
                      subtitle: '申请或撤销注销，注销后账号不可恢复',
                      onTap: _goDeregister,
                    ),
                    _cell(
                      icon: Icons.info_outline,
                      title: '关于',
                      subtitle: '版本、协议、联系与我的二维码',
                      onTap: _goAbout,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: CyTokens.space4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.pageX,
                  ),
                  child: CyNativeButton(
                    onPressed: _logout,
                    label: '退出账号',
                    role: CyNativeButtonRole.secondary,
                    icon: const CyNativeButtonIcon(
                      sfSymbol: 'rectangle.portrait.and.arrow.right',
                      fallback: CupertinoIcons.square_arrow_right,
                    ),
                    width: double.infinity,
                  ),
                ),
              ),
              // 署名是 game-icons.net 的 CC BY 3.0 **许可条件**,必须离线可见
              // (小程序 shezhi.wxml 的 .sz-attribution,独立页退役后放设置页底部)。
              const _Attribution(),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.sz-attribution` 素材署名 —— 两条许可条件,各带一个「复制来源地址」。
/// ★ 文案逐字照小程序 shezhi.wxml(许可要求署名,不许改写);
///   链接动作 = 复制到剪贴板(小程序 wx.setClipboardData),不跳浏览器:
///   署名是许可条件,不是导流入口。
class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space5,
        CyTokens.pageX,
        0,
      ),
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: palette.bgElevated,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      ),
      child: Semantics(
        label: '素材署名',
        container: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '素材署名',
              style: textTheme.bodyLarge?.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            _block(
              context,
              name: 'game-icons.net 游戏图标 · Creative Commons BY 3.0（要求署名）',
              body: '作者：Delapouite、Lorc、Skoll、Sbed、Quoting、Lord Berandas',
              link: 'https://game-icons.net/',
              linkLabel: '复制来源地址 · game-icons.net',
            ),
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(vertical: CyTokens.space3),
              color: palette.borderSubtle,
            ),
            _block(
              context,
              name: '像素城市场景 · Luis Zuno（ansimuz）· CC0 1.0',
              body: '底图：Synth Cities、Warped City、Warped Miami Synth',
              link: 'https://ansimuz.itch.io/',
              linkLabel: '复制来源地址 · ansimuz.itch.io',
            ),
          ],
        ),
      ),
    );
  }

  Widget _block(
    BuildContext context, {
    required String name,
    required String body,
    required String link,
    required String linkLabel,
  }) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          name,
          style: textTheme.bodySmall?.copyWith(color: palette.textPrimary),
        ),
        const SizedBox(height: CyTokens.space1),
        Text(
          body,
          style: textTheme.bodySmall?.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: CyTokens.space2),
        CupertinoButton(
          key: Key('attribution-copy-$link'),
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          alignment: Alignment.centerLeft,
          onPressed: () => _copyLink(context, link),
          child: Text(
            linkLabel,
            style: textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
              decoration: TextDecoration.underline,
              decorationColor: palette.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _copyLink(BuildContext context, String link) async {
    try {
      await Clipboard.setData(ClipboardData(text: link));
      if (!context.mounted) return;
      CyNativeNotice.show(context, '来源地址已复制');
    } catch (_) {
      if (!context.mounted) return;
      CyNativeNotice.show(context, '复制失败，可长按选中地址', isError: true);
    }
  }
}

/// `.sz-card` 身份卡:头像 + 昵称 + 身份行 + 右侧编辑圆钮。
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({this.user, required this.onEdit});

  final User? user;
  final VoidCallback onEdit;

  String get _roleLabel {
    final role = user?.effectiveRole;
    if (role == 'merchant') return '商家';
    if (role == 'club') return '俱乐部主理人';
    return '城瘾玩家';
  }

  @override
  Widget build(BuildContext context) {
    final hasUser =
        user != null && (user!.nickname.isNotEmpty || user!.avatar.isNotEmpty);
    return Container(
      margin: EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space4,
        CyTokens.pageX,
        0,
      ),
      // 右侧避让:给编辑圆钮(88rpx 命中区)留出结构性空间。
      padding: const EdgeInsets.fromLTRB(
        CyTokens.space4,
        CyTokens.space4,
        60,
        CyTokens.space4,
      ),
      constraints: const BoxConstraints(minHeight: 99), // 198rpx
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgElevated,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      ),
      child: Row(
        children: <Widget>[
          CyAvatar(
            url: user?.avatar,
            fallback: user?.nickname,
            size: 65, // 130rpx
          ),
          // 昵称贴头像右沿(与小程序 162rpx 对齐值一致,不另加间隙)。
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  hasUser ? user!.nickname : '未登录',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: CyTokens.typeCardTitle,
                    fontWeight: FontWeight.w600,
                    color: CyPalette.of(context).textPrimary,
                  ),
                ),
                const SizedBox(height: CyTokens.space1),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.person_outline,
                      size: 14,
                      color: CyPalette.of(context).textSecondary,
                    ),
                    const SizedBox(width: CyTokens.space1_5),
                    Flexible(
                      child: Text(
                        _roleLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: CyTokens.typeLabel,
                          fontWeight: FontWeight.w500,
                          color: CyPalette.of(context).textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // .sz-card-edit:88rpx 圆钮,命中区按 DS §3.8 给足。
          Padding(
            padding: const EdgeInsets.only(left: CyTokens.space2),
            child: CyNativeIconButton(
              label: '编辑资料',
              icon: const CyNativeButtonIcon(
                sfSymbol: 'pencil',
                fallback: CupertinoIcons.pencil,
              ),
              onPressed: onEdit,
            ),
          ),
        ],
      ),
    );
  }
}

/// `scene-sound-haptics`:声音/触感 + 环境音两组开关。
class _SoundHapticsSheet extends ConsumerStatefulWidget {
  const _SoundHapticsSheet({
    required this.scrollController,
    required this.liquidGlassSupported,
  });

  final ScrollController scrollController;
  final bool liquidGlassSupported;

  @override
  ConsumerState<_SoundHapticsSheet> createState() => _SoundHapticsSheetState();
}

class _SoundHapticsSheetState extends ConsumerState<_SoundHapticsSheet> {
  SoundHapticsSettings? _values;
  Object? _loadError;
  String? _saveError;
  final Set<String> _saving = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _values = null;
      _loadError = null;
      _saveError = null;
    });
    try {
      final SoundHapticsSettings value = await ref
          .read(soundHapticsSettingsStoreProvider)
          .read();
      if (mounted) setState(() => _values = value);
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  Future<void> _setValue(String key, bool value) async {
    final SoundHapticsSettings? current = _values;
    if (current == null || _saving.isNotEmpty) return;
    final SoundHapticsSettings next = current.copyWithKey(key, value);
    setState(() {
      _saving.add(key);
      _saveError = null;
    });
    try {
      // 与小程序同步写入语义一致；写失败时绝不把内存状态冒充已保存。
      await ref.read(soundHapticsSettingsStoreProvider).write(next);
      if (mounted) setState(() => _values = next);
    } catch (_) {
      if (mounted) setState(() => _saveError = '设置没保存，请重试');
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  Widget _divider() => Container(
    height: 1, // 2rpx
    margin: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
    color: CyPalette.of(context).borderSubtle,
  );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CyPalette.of(context).bgPage,
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space3,
            CyTokens.pageX,
            CyTokens.space5,
          ),
          children: <Widget>[
            Text(
              '声音与触感',
              textAlign: TextAlign.center,
              style: CyType.title2.copyWith(
                fontWeight: FontWeight.w600,
                color: CyPalette.of(context).textPrimary,
              ),
            ),
            const SizedBox(height: CyTokens.space4),
            if (_loadError != null)
              StatusView(message: '声音与触感没读出来', onRetry: _load)
            else if (_values == null)
              const SizedBox(
                height: 240,
                child: Center(child: CupertinoActivityIndicator()),
              )
            else
              ..._settingsContent(_values!),
          ],
        ),
      ),
    );
  }

  List<Widget> _settingsContent(SoundHapticsSettings values) {
    return <Widget>[
      _SoundCard(
        children: <Widget>[
          _row(values, 'sound', Icons.volume_up_outlined, '声音'),
          _divider(),
          _row(values, 'haptics', Icons.touch_app_outlined, '触感'),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          CyTokens.space1,
          CyTokens.space5,
          CyTokens.space1,
          CyTokens.space3,
        ),
        child: Text(
          '环境音',
          style: TextStyle(
            fontSize: CyTokens.typeCardTitle,
            fontWeight: FontWeight.w600,
            color: CyPalette.of(context).textPrimary,
          ),
        ),
      ),
      _SoundCard(
        children: <Widget>[
          _row(values, 'airplane', Icons.flight_takeoff, '飞机引擎'),
          _divider(),
          _row(values, 'ocean', Icons.waves, '海浪'),
          _divider(),
          _row(values, 'raindrop', Icons.grain, '雨滴'),
          _divider(),
          _row(values, 'forest', Icons.forest, '森林'),
        ],
      ),
      if (_saveError != null)
        Padding(
          padding: const EdgeInsets.only(top: CyTokens.space3),
          child: Text(
            _saveError!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: CyTokens.typeLabel,
              color: CyPalette.of(context).statusDanger,
            ),
          ),
        ),
    ];
  }

  Widget _row(
    SoundHapticsSettings values,
    String key,
    IconData icon,
    String label,
  ) {
    final bool on = values.valueFor(key);
    return _SoundRow(
      key: Key('sound-haptics-row-$key'),
      icon: icon,
      label: label,
      on: on,
      saving: _saving.isNotEmpty,
      liquidGlassSupported: widget.liquidGlassSupported,
      onChanged: (bool value) => _setValue(key, value),
    );
  }
}

/// `.shc__card` 卡片容器。
class _SoundCard extends StatelessWidget {
  const _SoundCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      child: ColoredBox(
        color: CyPalette.of(context).bgElevated,
        child: Column(children: children),
      ),
    );
  }
}

/// `.shc__row`:保留小程序图标、文案和行高，状态控件采用 Apple switch。
class _SoundRow extends StatelessWidget {
  const _SoundRow({
    super.key,
    required this.icon,
    required this.label,
    required this.on,
    required this.saving,
    required this.liquidGlassSupported,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool on;
  final bool saving;
  final bool liquidGlassSupported;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    void change(bool value) {
      if (!saving) onChanged(value);
    }

    return Semantics(
      container: true,
      label: label,
      value: on ? '已开启' : '已关闭',
      toggled: on,
      enabled: !saving,
      onTap: saving ? null : () => change(!on),
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Row(
            children: <Widget>[
              Expanded(
                child: CupertinoButton(
                  onPressed: saving ? null : () => change(!on),
                  minimumSize: const Size(44, 60),
                  padding: const EdgeInsets.only(left: CyTokens.space3),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: <Widget>[
                      Icon(
                        icon,
                        size: 20,
                        color: CyPalette.of(
                          context,
                        ).textSecondary.withValues(alpha: .6),
                      ),
                      const SizedBox(width: CyTokens.space3), // 24rpx
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: CyTokens.typeCardTitle,
                            color: CyPalette.of(context).textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AbsorbPointer(
                absorbing: saving,
                child: SizedBox(
                  key: Key('sound-haptics-control-$label'),
                  width: 76,
                  height: 60,
                  child: liquidGlassSupported
                      ? AppleLiquidSwitch(
                          value: on,
                          width: 76,
                          height: 60,
                          onChanged: change,
                        )
                      : Center(
                          child: CupertinoSwitch(value: on, onChanged: change),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `cy-privacy-sheet`:说明 + 隐私指引入口 + 撤回漫游定位同意。
class _PrivacySheet extends ConsumerStatefulWidget {
  const _PrivacySheet({required this.scrollController});

  final ScrollController scrollController;

  @override
  ConsumerState<_PrivacySheet> createState() => _PrivacySheetState();
}

class _PrivacySheetState extends ConsumerState<_PrivacySheet> {
  late final String _requestId = AccountApi.newRequestId();
  bool _submitting = false;
  String? _feedback;
  bool _feedbackIsError = false;

  Future<void> _withdraw() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _feedback = null;
      _feedbackIsError = false;
    });
    try {
      await ref
          .read(accountApiProvider)
          .revokeRoamLocationConsent(requestId: _requestId);
    } catch (_) {
      if (mounted) {
        setState(() {
          _feedback = '撤回记录失败，请检查网络后重试';
          _feedbackIsError = true;
        });
      }
      return;
    }

    try {
      await ref
          .read(roamLiveControllerProvider.notifier)
          .stopLocationTracking();
    } catch (_) {
      if (mounted) {
        setState(() {
          _feedback = '撤回已记录，但定位尚未停止，请重试';
          _feedbackIsError = true;
        });
      }
      return;
    }

    try {
      await ref.read(mapPrivacyStoreProvider).setAgreed(false);
    } catch (_) {
      ref.invalidate(mapPrivacyAgreementProvider);
      ref.invalidate(currentMapLocationProvider);
      ref.invalidate(mapPageDataProvider);
      if (mounted) {
        setState(() {
          _feedback = '撤回已记录，定位已停止；本地状态保存失败，请重试';
          _feedbackIsError = true;
        });
      }
      return;
    }

    ref.invalidate(mapPrivacyAgreementProvider);
    ref.invalidate(currentMapLocationProvider);
    ref.invalidate(mapPageDataProvider);
    if (mounted) {
      setState(() {
        _feedback = '已撤回漫游定位同意';
        _feedbackIsError = false;
      });
    }
  }

  Future<void> _runWithdrawal() async {
    try {
      await _withdraw();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: !_submitting,
      child: ColoredBox(
        color: CyPalette.of(context).bgPage,
        child: SafeArea(
          top: false,
          minimum: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(
              CyTokens.pageX,
              CyTokens.space3,
              CyTokens.pageX,
              CyTokens.space5,
            ),
            children: <Widget>[
              Text(
                '隐私与定位',
                textAlign: TextAlign.center,
                style: CyType.title2.copyWith(
                  fontWeight: FontWeight.w600,
                  color: CyPalette.of(context).textPrimary,
                ),
              ),
              const SizedBox(height: CyTokens.space4),
              Text(
                '城瘾会在你使用相关功能时处理必要信息。漫游定位仅用于实时位置展示、到点打卡和轨迹记录；不使用时不会在后台持续采集。',
                style: TextStyle(
                  fontSize: CyTokens.typeBody,
                  height: CyTokens.leadingLoose,
                  color: CyPalette.of(context).textSecondary,
                ),
              ),
              SizedBox(height: CyTokens.space3_5),
              Align(
                alignment: Alignment.centerLeft,
                child: CupertinoButton(
                  key: const Key('privacy-policy-link'),
                  minimumSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                  onPressed: _submitting
                      ? null
                      : () => context.push(
                          LegalDocPage.routeOf(LegalDocType.privacyPolicy),
                        ),
                  child: Text(
                    '查看《用户隐私保护指引》',
                    style: TextStyle(
                      fontSize: CyTokens.typeBody,
                      color: CyPalette.of(context).textPrimary,
                      decoration: TextDecoration.underline,
                      decorationColor: CyPalette.of(context).textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: CyTokens.space5),
              Text(
                '漫游定位',
                style: TextStyle(
                  fontSize: CyTokens.typeCardTitle,
                  fontWeight: FontWeight.w600,
                  color: CyPalette.of(context).textPrimary,
                ),
              ),
              const SizedBox(height: CyTokens.space1_5),
              Text(
                '撤回后，漫游不会继续读取实时位置或记录新的轨迹。',
                style: TextStyle(
                  fontSize: CyTokens.typeLabel,
                  height: CyTokens.leadingNormal,
                  color: CyPalette.of(context).textSecondary,
                ),
              ),
              const SizedBox(height: CyTokens.space3),
              CyNativeButton(
                key: const Key('privacy-revoke-button'),
                label: _submitting ? '撤回中…' : '撤回漫游定位同意',
                onPressed: _submitting ? null : _runWithdrawal,
                loading: _submitting,
                role: CyNativeButtonRole.destructive,
                icon: const CyNativeButtonIcon(
                  sfSymbol: 'location.slash',
                  fallback: CupertinoIcons.location_slash,
                ),
              ),
              if (_feedback != null) ...<Widget>[
                const SizedBox(height: CyTokens.space3),
                Text(
                  _feedback!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: CyTokens.typeLabel,
                    color: _feedbackIsError
                        ? CyPalette.of(context).statusDanger
                        : CyPalette.of(context).textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
