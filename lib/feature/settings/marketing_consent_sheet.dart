import '../../l10n/strings.dart';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../data/models/marketing_consent.dart';
import '../auth/login_gate.dart';

/// 与小程序同一个形状(`pages/shezhi/components/marketing-consent/index.js:117`
/// 的 `crm-consent-<动作>-<36 进制时间>-<36 进制随机>`)—— 后端按它幂等。
String newMarketingConsentRequestId(bool optedIn) {
  final String stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final String rand = math.Random().nextInt(0xFFFFFF).toRadixString(36);
  return 'crm-consent-${optedIn ? 'opt-in' : 'opt-out'}-$stamp-$rand';
}

/// `cy-marketing-consent`:按商家管理营销同意与退订
/// (真源 `pages/shezhi/components/marketing-consent/index.js`)。
///
/// ★★ 默认关闭。只有用户明确打开后,该商家才能按渠道触达;关掉就是立即退订 ——
///   所以两个开关的当前值必须**来自服务端回读**,不能乐观改本地那一格:
///   [PageParityApi.setMarketingConsent] 已经把「写完回读确认」做在里面了。
Future<void> showMarketingConsentSheet(BuildContext context) {
  return showCupertinoSheet<void>(
    context: context,
    showDragHandle: true,
    scrollableBuilder: (BuildContext context, ScrollController controller) =>
        _MarketingConsentSheet(scrollController: controller),
  );
}

class _MarketingConsentSheet extends ConsumerStatefulWidget {
  const _MarketingConsentSheet({required this.scrollController});

  final ScrollController scrollController;

  @override
  ConsumerState<_MarketingConsentSheet> createState() =>
      _MarketingConsentSheetState();
}

class _MarketingConsentSheetState
    extends ConsumerState<_MarketingConsentSheet> {
  bool _loading = true;
  String? _loadError;
  bool _needLogin = false;
  List<MarketingConsent> _rows = const <MarketingConsent>[];

  /// 一次只写一条(与小程序 `savingKey` 同义):两条并发写回读会互相盖。
  String? _savingKey;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _needLogin = false;
    });
    try {
      final List<MarketingConsent> rows = await ref
          .read(pageParityApiProvider)
          .marketingConsents();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // 游客态后端回 401 —— 那是**有意拒绝**,不是故障。直出 DioException
        // 只会得到英文 + developer.mozilla.org 链接,还把人送去反复点重试。
        _needLogin = isUnauthorizedError(e);
        _loadError = _needLogin
            ? null
            : e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loginThenLoad() async {
    if (!await requireLogin(context, ref)) return;
    if (!mounted) return;
    await _load();
  }

  Future<void> _toggle(
    MarketingConsent row,
    String channel,
    bool optedIn,
  ) async {
    if (_savingKey != null) return;
    setState(() {
      _savingKey = '${row.merchantRowId}:$channel';
      _actionError = null;
    });
    try {
      final List<MarketingConsent> rows = await ref
          .read(pageParityApiProvider)
          .setMarketingConsent(
            merchantRowId: row.merchantRowId,
            merchantOwnerMemberId: row.merchantOwnerMemberId,
            channel: channel,
            optedIn: optedIn,
            requestId: newMarketingConsentRequestId(optedIn),
          );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _savingKey = null;
      });
      CyNativeNotice.show(context, optedIn ? stringsOf(context).settingsResidualOptedIn : stringsOf(context).settingsResidualOptedOut);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingKey = null;
        _actionError = e.toString().replaceFirst('Exception: ', '');
      });
      // 没写成就把服务端的真值读回来 —— 半开着的开关比报错更坏。
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    return ColoredBox(
      color: p.bgPage,
      child: SafeArea(
        top: false,
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
              stringsOf(context).settingsResidualMarketing,
              textAlign: TextAlign.center,
              style: CyType.title2.copyWith(
                fontWeight: FontWeight.w600,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            Text(
              stringsOf(context).miscMarketingDisclosure,
              style: TextStyle(
                fontSize: CyTokens.typeBody,
                height: CyTokens.leadingLoose,
                color: p.textSecondary,
              ),
            ),
            const SizedBox(height: CyTokens.space4),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(CyTokens.space4),
                child: Center(child: CupertinoActivityIndicator()),
              )
            else if (_loadError != null)
              _LoadFailed(message: stringsOf(context).settingsResidualMarketingError(_loadError!), onRetry: _load)
            else if (_needLogin)
              _LoadFailed(
                message: stringsOf(context).settingsResidualMarketingLogin,
                needLogin: true,
                onRetry: _loginThenLoad,
              )
            else if (_rows.isEmpty)
              Text(
                stringsOf(context).settingsResidualMarketingEmpty,
                key: const Key('marketing-consent-empty'),
                style: t.bodyMedium?.copyWith(color: p.textSecondary),
              )
            else
              ..._rows.map(
                (MarketingConsent row) => _MerchantConsentCard(
                  row: row,
                  savingKey: _savingKey,
                  onToggle: _toggle,
                ),
              ),
            if (_actionError != null)
              Padding(
                padding: const EdgeInsets.only(top: CyTokens.space3),
                child: Text(
                  _actionError!,
                  key: const Key('marketing-consent-action-error'),
                  style: t.bodySmall?.copyWith(color: p.statusDanger),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({
    required this.message,
    required this.onRetry,
    this.needLogin = false,
  });

  final String message;
  final Future<void> Function() onRetry;
  final bool needLogin;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          message,
          key: const Key('marketing-consent-load-error'),
          // needLogin 分支保住「去登录」引导的次级色;非登录分支走双值
          // `p.statusDanger` —— 恒浅页上暗端常量 `CyTokens.statusDanger` 偏浅。
          style: t.bodyMedium?.copyWith(
            color: needLogin ? p.textSecondary : p.statusDanger,
          ),
        ),
        const SizedBox(height: CyTokens.space2),
        CupertinoButton(
          key: const Key('marketing-consent-retry'),
          minimumSize: const Size.fromHeight(44),
          padding: EdgeInsets.zero,
          onPressed: onRetry,
          child: Text(
            needLogin ? stringsOf(context).settingsResidualSignIn : stringsOf(context).settingsResidualRetry,
            style: t.titleSmall?.copyWith(color: p.brand),
          ),
        ),
      ],
    );
  }
}

class _MerchantConsentCard extends StatelessWidget {
  const _MerchantConsentCard({
    required this.row,
    required this.savingKey,
    required this.onToggle,
  });

  final MarketingConsent row;
  final String? savingKey;
  final Future<void> Function(MarketingConsent, String, bool) onToggle;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      key: Key('marketing-consent-${row.merchantRowId}'),
      margin: const EdgeInsets.only(bottom: CyTokens.space3),
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(row.merchantName, style: t.titleSmall),
          const SizedBox(height: CyTokens.space2),
          _ChannelSwitch(
            key: Key('marketing-consent-${row.merchantRowId}-IN_APP'),
            label: stringsOf(context).settingsResidualInApp,
            sub: stringsOf(context).settingsResidualInAppHint,
            value: row.inAppOptedIn,
            busy: savingKey != null,
            onChanged: (bool v) => onToggle(row, 'IN_APP', v),
          ),
          // 分隔线走调色板语义色;`Divider` 是 Material 件(§3.6 分工)。
          Container(
            height: CyTokens.space4,
            alignment: Alignment.center,
            child: Container(height: 1, color: p.borderSubtle),
          ),
          _ChannelSwitch(
            key: Key('marketing-consent-${row.merchantRowId}-COUPON'),
            label: stringsOf(context).settingsResidualCoupons,
            sub: stringsOf(context).settingsResidualCouponHint,
            value: row.couponOptedIn,
            busy: savingKey != null,
            onChanged: (bool v) => onToggle(row, 'COUPON', v),
          ),
        ],
      ),
    );
  }
}

class _ChannelSwitch extends StatelessWidget {
  const _ChannelSwitch({
    super.key,
    required this.label,
    required this.sub,
    required this.value,
    required this.busy,
    required this.onChanged,
  });

  final String label;
  final String sub;
  final bool value;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: t.bodyMedium),
              Text(sub, style: t.bodySmall?.copyWith(color: p.textSecondary)),
            ],
          ),
        ),
        CupertinoSwitch(
          value: value,
          onChanged: busy ? null : onChanged,
        ),
      ],
    );
  }
}
