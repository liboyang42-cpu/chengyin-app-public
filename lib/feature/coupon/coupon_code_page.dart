import '../../l10n/strings.dart';
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/coupon_api.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';

/// 券码出示页(对齐小程序 `subpackageMember/coupon-qr/index`):
/// 动态二维码(60s 时效,倒计时自动刷新)+ 每 5s 轮询核销状态。
/// 终态切结果页(✓ 已核销 / 该券已过期 / 该券已失效);410 = 券已停用,
/// 停掉全部节拍只留原因。
///
/// ⚠️ 本页有自己的状态机(loading/ready/error + useStatus),错误文案用稳定的人话,
///    不直接展示后端原始报错 —— 与小程序「禁止把原始 API/鉴权信息弹成灰 toast」同一纪律。
class CouponCodePage extends ConsumerStatefulWidget {
  const CouponCodePage({super.key, required this.couponHistoryId});

  final int couponHistoryId;

  @override
  ConsumerState<CouponCodePage> createState() => _CouponCodePageState();
}

enum _CouponFailure { generate, poll, unavailable, login, network }

_CouponFailure _friendlyCouponFailure(Object error, _CouponFailure fallback) {
  final text = '$error';
  if (RegExp(r'登录|认证|401|token', caseSensitive: false).hasMatch(text)) {
    return _CouponFailure.login;
  }
  if (RegExp(r'网络|timeout|fail|502|503', caseSensitive: false).hasMatch(text)) {
    return _CouponFailure.network;
  }
  return fallback;
}

class _CouponCodePageState extends ConsumerState<CouponCodePage> {
  String _qrState = 'loading'; // loading | ready | error
  String _qrUrl = '';
  String _errMsg = '';
  String _couponName = '';
  _CouponFailure? _failure;
  String _description = '';
  String _endTimeText = '';
  int _countdown = 60;
  int _useStatus = 0; // 0 待使用 / 1 已核销 / 2 已过期 / 3 已失效
  String _useTimeText = '';
  String _startTime = '';
  _CouponFailure? _pollFailure;
  bool _refreshing = false;
  bool _sessionStarted = false;
  Timer? _countTimer;
  Timer? _pollTimer;

  String _failureText(_CouponFailure failure) => switch (failure) {
    _CouponFailure.generate => stringsOf(context).couponCodeGenerateError,
    _CouponFailure.poll => stringsOf(context).couponCodePollError,
    _CouponFailure.unavailable => stringsOf(context).couponCodeUnavailable,
    _CouponFailure.login => stringsOf(context).benefitsLoginExpired,
    _CouponFailure.network => stringsOf(context).benefitsNetwork,
  };

  @override
  void initState() {
    super.initState();
    // 缺参 / 游客:不换码、不计时、不轮询 —— 状态机整个不启动
    // (真源 missing-param 与 requireOwner 同此;游客深链落地给页内登录门)。
    // 会话在 build 观测到已登录后才启动(见 _ensureSession)。
  }

  /// 登录态就绪后才拉起换码 + 倒计时 + 轮询;只启动一次。
  void _ensureSession() {
    if (_sessionStarted || widget.couponHistoryId <= 0) return;
    _sessionStarted = true;
    _refreshToken();
    _startCountdown();
    _startPolling();
  }

  @override
  void dispose() {
    _clearTimers();
    super.dispose();
  }

  void _clearTimers() {
    _countTimer?.cancel();
    _countTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _toast(String msg) {
    if (!mounted) return;
    CyNativeNotice.show(context, msg, isError: true);
  }

  /// 对齐小程序 fmt:`T` 换空格后截前 16 位(去秒)。
  static String _fmt(String? t) {
    if (t == null || t.isEmpty) return '';
    final s = t.replaceFirst('T', ' ');
    return s.length <= 16 ? s : s.substring(0, 16);
  }

  /// 有效期只展示到「日」(2026-09-17 全站拍板,真源 `formatDayDots`:'YYYY.MM.DD')。
  static String _dayDots(String? t) {
    final s = (t ?? '').trim();
    if (s.length < 10) return '';
    final day = s.replaceFirst('T', ' ').substring(0, 10);
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)
        ? day.replaceAll('-', '.')
        : '';
  }

  Future<void> _refreshToken() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      if (_qrState == 'error') {
        setState(() => _qrState = 'loading');
      }
      final qr = await ref
          .read(couponApiProvider)
          .qrToken(widget.couponHistoryId);
      if (!mounted) return;
      // useStatus 是服务端请求时快照:迟到响应不许把已核销/已过期打回未使用。
      final wasUnused = _useStatus == 0;
      setState(() {
        _qrUrl = qr.qrcodeUrl;
        _failure = null;
        _errMsg = '';
        _qrState = qr.qrcodeUrl.isNotEmpty ? 'ready' : 'error';
        _countdown = qr.expiresIn > 0 ? qr.expiresIn : 60;
        if (wasUnused || qr.useStatus == 1) _useStatus = qr.useStatus;
        if (qr.couponName != null && qr.couponName!.isNotEmpty) {
          _couponName = qr.couponName!;
        }
        if (qr.description != null && qr.description!.isNotEmpty) {
          _description = qr.description!;
        }
        final et = _dayDots(qr.endTime);
        if (et.isNotEmpty) _endTimeText = et;
        if (qr.startTime != null) _startTime = qr.startTime!;
        // 码换新了 = 核销状态那条链路也通了,旧的横条提示该撤掉。
        _pollFailure = null;
        if (_qrState == 'error') {
          _errMsg = '';
          _failure = _CouponFailure.generate;
        }
      });
      if (_useStatus != 0) _clearTimers();
      if (_useStatus == 1 && wasUnused) _onVerified();
    } on CouponUnavailableException catch (e) {
      // 410 = 券已停用/撤销:真源 `unavailable` —— 作废在途、停表、码下屏,
      // 不再倒计时/轮询(这不是可重试故障,重试只会再吃一发 410)。
      if (!mounted) return;
      _onUnavailable(e.message);
    } catch (e) {
      if (!mounted) return;
      // 异常原文只进日志 —— 上屏的永远是 friendlyErrorMessage 的三档人话。
      debugPrint('[coupon-qr] refreshToken 失败: $e');
      _onRefreshFail(_friendlyCouponFailure(e, _CouponFailure.generate));
    } finally {
      _refreshing = false;
    }
  }

  /// 券被停用(410):码已无意义,停掉全部节拍,只留服务端给的原因。
  void _onUnavailable(String message) {
    _clearTimers();
    setState(() {
      _qrUrl = '';
      _qrState = 'error';
      _countdown = 0;
      _pollFailure = null;
      _errMsg = message;
      _failure = message.isEmpty ? _CouponFailure.unavailable : null;
    });
  }

  /// 刷新失败分级:屏上还有码(TTL 内)就保持 ready 只提示;真无码才切 error。
  /// Error classification preserves the existing login/network/fallback branches.
  void _onRefreshFail(_CouponFailure failure) {
    if (_qrUrl.isNotEmpty && _qrState == 'ready' && _countdown > 1) {
      _toast(stringsOf(context).couponCodeRefreshFailed);
      return;
    }
    setState(() {
      _qrState = 'error';
      _errMsg = '';
      _failure = failure;
    });
  }

  void _startCountdown() {
    _countTimer?.cancel();
    _countTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // error 态冻结倒计时,防止到 0 后每秒空刷;由用户点重试/刷新恢复。
      if (_useStatus != 0 || _qrState == 'error') return;
      final c = _countdown - 1;
      if (c <= 0) {
        _refreshToken(); // 到点换新 token/二维码(refreshToken 会重置 countdown)
        return;
      }
      setState(() => _countdown = c);
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) return;
      // 任何非「待使用」都是终态(真源 `status !== 0 → clearTimers`):
      // 已核销/已过期/已失效之后继续轮询只是白打接口。
      if (_useStatus != 0) {
        _clearTimers();
        return;
      }
      try {
        final st = await ref
            .read(couponApiProvider)
            .status(widget.couponHistoryId);
        if (!mounted) return;
        setState(() => _useStatus = st.useStatus);
        if (st.useStatus == 1) {
          _useTimeText = _fmt(st.useTime);
          // 真源 `wx.vibrateShort(medium)`:核销成功的一刻给一次中等触感。
          HapticFeedback.mediumImpact();
          _onVerified();
        } else if (st.useStatus != 0) {
          _clearTimers();
          setState(() {}); // 切结果态(已过期/已失效)
        }
      } on CouponUnavailableException catch (e) {
        // 轮询链路同样吃 410 = 券已停用:与换码同处理,停表撤码。
        if (!mounted) return;
        _onUnavailable(e.message);
      } catch (e) {
        if (!mounted) return;
        debugPrint('[coupon-qr] 轮询核销状态失败: $e');
        _onPollFail(_friendlyCouponFailure(e, _CouponFailure.poll));
      }
    });
  }

  /// 轮询失败分级(真源 `onPollFail`):核销状态与二维码可用性是**两条链路**。
  /// 屏上还有 TTL 内的码就只横一条"状态暂未更新",码不能就这么撤下去 ——
  /// 一次轮询抖动把还能扫的码变成整屏报错,用户会以为券废了。
  void _onPollFail(_CouponFailure failure) {
    if (_useStatus == 0 && _qrState == 'ready' && _qrUrl.isNotEmpty) {
      setState(() => _pollFailure = failure);
      return;
    }
    setState(() {
      _qrState = 'error';
      _errMsg = '';
      _failure = failure;
      _pollFailure = null;
    });
  }

  /// 还没到可用时间。⚠️ 解析不出来时按"已开始"处理 —— 前端只负责展示,
  /// 服务端核销闸门才是权威判定(真源 notStartedAt 同此判据)。
  bool get _notStarted {
    final DateTime? start = DateTime.tryParse(
      _startTime.replaceFirst(' ', 'T'),
    );
    if (start == null) return false;
    return start.isAfter(DateTime.now());
  }

  /// 缺参态的出口。券包里重新进 —— 这一页是深链能直接打开的,
  /// 没有上一页时 `pop` 不动(Navigator.canPop 为假);App 内唯一入口
  /// 就是「我的优惠券」券包,回券包(b1-sim-coupon S5:此前跨域回错票夹)。
  void _backToWallet() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/coupons');
    }
  }

  /// 核销成功:停计时。
  void _onVerified() {
    _clearTimers();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // 缺券信息(真源 cy-state-shell kind=missing-param):链接里没有券 id,
    // 拉接口也不会有结果 —— 不给重试,只给出路。
    if (widget.couponHistoryId <= 0) {
      return CupertinoPageScaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        navigationBar: const CupertinoNavigationBar(),
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            bottom: false,
            child: StatusView(
              message: stringsOf(context).couponCodeMissing,
              sub: stringsOf(context).couponCodeMissingDetail,
              large: true,
              onRetry: _backToWallet,
              retryLabel: stringsOf(context).couponCodeBack,
            ),
          ),
        ),
      );
    }
    // ★ 游客深链落地给页内登录门,不静默弹回首页(b1-sim-coupon P1-1,
    //   同 roam #208 范式);登录前状态机不启动,不给注定 401 的换码/轮询。
    final AuthState auth = ref.watch(authControllerProvider);
    if (!auth.isLoggedIn) {
      return CupertinoPageScaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        navigationBar: const CupertinoNavigationBar(),
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            bottom: false,
            child: StatusView(
              key: const Key('coupon-code-login-gate'),
              message: stringsOf(context).couponCodeLogin,
              sub: stringsOf(context).couponCodeLoginDetail,
              icon: CupertinoIcons.lock,
              large: true,
              retryLabel: stringsOf(context).couponCodeSignIn,
              onRetry: () async {
                if (!await requireLogin(context, ref)) return;
                if (!mounted) return;
                _ensureSession();
              },
            ),
          ),
        ),
      );
    }
    _ensureSession();
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: _useStatus != 0
              ? _buildResult()
              // 使用期承诺:start 前不出码,只展示可用时间与等待(真源同此)。
              : (_notStarted
                    ? StatusView(
                        message: stringsOf(context).couponCodeNotStarted,
                        sub: _startTime.isEmpty
                            ? stringsOf(context).couponCodeNotStartedDetail
                            : stringsOf(context).couponCodeAvailableFrom(_fmt(_startTime)),
                        large: true,
                        onRetry: _refreshToken,
                        retryLabel: stringsOf(context).couponCodeReload,
                      )
                    : _buildShowcase()),
        ),
      ),
    );
  }

  /// 亮码态:白色码卡(物理白底,不随暗色主题)+ 倒计时 + 出示说明 + 刷新。
  Widget _buildShowcase() {
    final textTheme = Theme.of(context).textTheme;
    final loading = _qrState == 'loading';
    final error = _qrState == 'error';
    return ListView(
      // 真源 `.cq-page` padding: space-5(24) 上下 / page-x(16) 左右。
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space5,
        CyTokens.pageX,
        CyTokens.space5,
      ),
      children: <Widget>[
        // 真源 cy-qr-voucher 的 title:亮码态也要说清这是哪张券的码(b1-sim S5)。
        Text(
          _couponName.isEmpty ? stringsOf(context).couponWalletDefaultName : _couponName,
          textAlign: TextAlign.center,
          style: textTheme.titleMedium?.copyWith(
            fontSize: CyTokens.typeCardTitle,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: CyTokens.space3),
        if (error)
          // 真源 `cy-qr-voucher`:error 分支渲染的是 `.qr__error`,**不套白卡** ——
          // 白卡(.qr__card)只为承载可扫的码而存在,无码可扫时错误正文直接落在
          // 页面底上吃主题色(真源 scrim 上恒浅)。占住码区那块高度,换屏不跳版。
          _QrErrorState(
            errorText: _failure != null ? _failureText(_failure!)
                : _errMsg.isEmpty ? stringsOf(context).couponCodeNotLoaded : _errMsg,
            onRetry: _refreshToken,
          )
        else
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: _CodeCard(
                state: _qrState,
                qrUrl: _qrUrl,
                countdown: _qrState == 'ready' ? _countdown : null,
              ),
            ),
          ),
        SizedBox(height: CyTokens.space4),
        // 真源的 desc / 刷新钮与错误块是互斥的(条件必须一致,真源注释
        // 记过一次两者同屏的实拍事故),错误态只留错误块那一条出路。
        if (!error) ...<Widget>[
          Text(
            stringsOf(context).couponCodeShowMerchant,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              fontSize: CyTokens.typeBody,
              color: CyTokens.textSecondary,
            ),
          ),
          if (!loading) ...<Widget>[
            SizedBox(height: CyTokens.space3),
            Center(
              child: CupertinoButton(
                onPressed: _refreshToken,
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.space3,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(CupertinoIcons.refresh, size: 18),
                    const SizedBox(width: CyTokens.space1),
                    Text(stringsOf(context).couponCodeRefresh),
                  ],
                ),
              ),
            ),
          ],
          // 轮询抖动的**非阻断**提示:码还在,只是核销状态这会儿读不到。
          // 不给重试按钮 —— 5s 一次的轮询自己会重试,再摆一个按钮是假选择。
          if (_pollFailure != null) ...<Widget>[
            SizedBox(height: CyTokens.space3),
            Text(
              stringsOf(context).couponCodePollDelayed,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                fontSize: CyTokens.typeBody,
                color: CyTokens.statusWarning,
              ),
            ),
            SizedBox(height: CyTokens.space1),
            Text(
              _failureText(_pollFailure!),
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                fontSize: CyTokens.typeCaption,
                color: CyTokens.textSecondary,
              ),
            ),
          ],
        ],
      ],
    );
  }

  /// 结果态(已核销 / 过期):券信息卡 + 结果章。
  Widget _buildResult() {
    final verified = _useStatus == 1;
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      // 真源 `.cq-page` padding: space-5(24) 上下 / page-x(16) 左右。
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space5,
        CyTokens.pageX,
        CyTokens.space5,
      ),
      children: <Widget>[
        Card(
          child: Padding(
            padding: EdgeInsets.all(CyTokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _couponName.isEmpty ? stringsOf(context).couponWalletDefaultName : _couponName,
                  style: textTheme.titleMedium?.copyWith(
                    fontSize: CyTokens.typeCardTitle,
                    // 真源 `.cq-name` 是 600,不是 700。
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_description.isNotEmpty) ...<Widget>[
                  SizedBox(height: CyTokens.space2),
                  Text(
                    _description,
                    // 真源 `.cq-desc`:text-secondary @ type-label(不是 caption)。
                    style: textTheme.bodySmall?.copyWith(
                      fontSize: CyTokens.typeLabel,
                      color: CyTokens.textSecondary,
                    ),
                  ),
                ],
                // 真源渲染:「有效期至」只在已过期(2)时显示(告诉用户为什么
                // 用不了);已核销与已失效都不摆。日期只到日('YYYY.MM.DD')。
                if (_endTimeText.isNotEmpty && _useStatus == 2) ...<Widget>[
                  SizedBox(height: CyTokens.space3),
                  Text(
                    stringsOf(context).couponCodeValidUntil(_endTimeText),
                    // 真源 `.cq-valid`:text-tertiary @ caption。
                    style: textTheme.bodySmall?.copyWith(
                      fontSize: CyTokens.typeCaption,
                      color: CyTokens.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        SizedBox(height: CyTokens.space6),
        if (verified) ...<Widget>[
          Center(
            child: Container(
              // 真源 `.cq-badge`:120rpx **实心** success 底 + 反色勾
              // (text-primary 在绿底上暗端对比不达标,才换的反色字)。
              width: 60,
              height: 60,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: CyTokens.statusSuccess,
              ),
              child: const Icon(
                Icons.check,
                size: 28,
                color: CyTokens.textInverse,
              ),
            ),
          ),
          SizedBox(height: CyTokens.space4),
          Text(
            stringsOf(context).couponCodeVerified,
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(
              fontSize: CyTokens.typeSectionTitle,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_useTimeText.isNotEmpty) ...<Widget>[
            SizedBox(height: CyTokens.space2),
            Text(
              _useTimeText,
              textAlign: TextAlign.center,
              // 真源 `.cq-result-sub`:text-tertiary @ type-label。
              style: textTheme.bodySmall?.copyWith(
                fontSize: CyTokens.typeLabel,
                color: CyTokens.textTertiary,
              ),
            ),
          ],
        ] else ...<Widget>[
          // 真源 resultText:2→该券已过期 / 3→该券已失效;认不出的状态
          // 不冒充「已过期」(服务端才是权威闸门)。
          // 真源 `.cq-expired .cq-result-text`:过期/失效同走 secondary,
          // danger 色留给券面上的状态胶囊,结果标题不刷红。
          Text(
            switch (_useStatus) {
              2 => stringsOf(context).couponCodeExpired,
              3 => stringsOf(context).couponCodeInvalid,
              _ => stringsOf(context).couponCodeUnknown,
            },
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(
              fontSize: CyTokens.typeSectionTitle,
              fontWeight: FontWeight.w600,
              color: _useStatus == 2 || _useStatus == 3
                  ? CyTokens.textSecondary
                  : CyTokens.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}

/// 白码卡内的深墨字。真源 `--cy-color-text-on-light`(D4 起,#0F172B 已去墨蓝);
/// 属「码卡物理浅色、不随主题」那条例免的一部分,和 `Colors.white` 同批豁免。
const Color _kOnLightInk = Color(0xFF181818);

/// 白色码卡。对齐小程序 cy-qr-voucher 的 .qr__card:
/// **物理白底、不随主题变深**(二维码必须能被扫到,这是设计系统的显式豁免)。
/// 只承载 loading / ready 两态;error 态换 [_QrErrorState](真源不套白卡)。
class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.state, required this.qrUrl, this.countdown});

  final String state; // loading | ready
  final String qrUrl;
  final int? countdown;

  static const double _codeSize = 220; // 440rpx

  @override
  Widget build(BuildContext context) {
    final ready = state == 'ready';
    return Container(
      padding: EdgeInsets.all(CyTokens.space5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      ),
      child: Column(
        children: <Widget>[
          SizedBox(
            width: _codeSize,
            height: _codeSize,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: !ready
                      ? const _CodePlaceholder()
                      : (qrUrl.isEmpty
                            ? const _CodePlaceholder()
                            : Image.network(
                                qrUrl,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) =>
                                    const _CodePlaceholder(),
                                loadingBuilder: (ctx, child, progress) =>
                                    progress == null
                                    ? child
                                    : const _CodePlaceholder(),
                              )),
                ),
                // 四角取景框。
                const Positioned.fill(child: _CornerFrame()),
              ],
            ),
          ),
          if (ready && countdown != null) ...<Widget>[
            SizedBox(height: CyTokens.space3),
            Text(
              stringsOf(context).couponCodeCountdown(countdown!),
              textAlign: TextAlign.center,
              // 白色码卡内用深色字。
              style: const TextStyle(
                fontSize: CyTokens.typeCaption,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 出码失败态(真源 `.qr__error`):图标 + 正文 + 实心重试,落在页面底上吃主题色。
/// 正文就是这一屏的标题(真源 `.qr__err-txt` 走 section-title 档),
/// 重试走共用件 [CyNativeButton](真源 `.qr__err-retry` = btn-solid 药丸),
/// 与全 App 错误态同一个形态。
class _QrErrorState extends StatelessWidget {
  const _QrErrorState({required this.errorText, required this.onRetry});

  final String errorText;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 真源 `.qr__err-content` padding: 0 space-3。
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
      child: ConstrainedBox(
        // 真源 `.qr__error` min-height 440rpx = 码区那块高度。
        constraints: const BoxConstraints(minHeight: 220),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(
              // 真源 `.qr__error-ic` 是 no_data 插画 240rpx(=120pt),**不是码形**:
              // 这一屏的前提就是「没有码可扫」,摆个二维码图形会让人以为还能扫。
              // 仓内没有那张 svg(素材需单独立项),先用 iOS 侧同语义的警示三角代;
              // 实心字形比线稿插画视觉重,故收到 96 而不是照抄 120。
              CupertinoIcons.exclamationmark_triangle,
              size: 96,
              color: CyTokens.textTertiary,
            ),
            SizedBox(height: CyTokens.space4),
            Text(
              errorText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: CyTokens.typeSectionTitle,
                fontWeight: FontWeight.w600,
                color: CyTokens.textPrimary,
                height: CyTokens.leadingNormal,
              ),
            ),
            SizedBox(height: CyTokens.space2),
            CyNativeButton(label: stringsOf(context).couponCodeRetry, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

/// 加载占位:浅底 + 转圈。对齐小程序 .qr__ph。
class _CodePlaceholder extends StatelessWidget {
  const _CodePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F7),
        borderRadius: BorderRadius.circular(CyTokens.radiusSm),
      ),
      child: const Center(
        child: SizedBox(
          // 真源 `.qr__spin` 56rpx=28pt,顶弧吃深墨:组件 wxss 那行写的是
          // `--cy-color-text-primary`,但码卡是**物理白底**、玩家页 text-primary
          // 是 #F8F8F8,照字面取就白底白圈看不见。按 D4 的口径(浅卡内深字统一
          // 走 `--cy-color-text-on-light` #181818,原 #0F172B 已去墨蓝)取墨色。
          width: 28,
          height: 28,
          child: CupertinoActivityIndicator(radius: 14, color: _kOnLightInk),
        ),
      ),
    );
  }
}

/// 四角取景框。画在白色码卡里,故用深色描边。
class _CornerFrame extends StatelessWidget {
  const _CornerFrame();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _CornerPainter());
  }
}

class _CornerPainter extends CustomPainter {
  static const double _len = 20; // 真源 `.qr__corner` 40rpx
  static const double _stroke = 3; // 真源 border 6rpx

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kOnLightInk
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    final w = size.width, h = size.height;
    canvas.drawLine(const Offset(0, 0), const Offset(_len, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, _len), paint);
    canvas.drawLine(Offset(w, 0), Offset(w - _len, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, _len), paint);
    canvas.drawLine(Offset(0, h), Offset(_len, h), paint);
    canvas.drawLine(Offset(0, h), Offset(0, h - _len), paint);
    canvas.drawLine(Offset(w, h), Offset(w - _len, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w, h - _len), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter oldDelegate) => false;
}
