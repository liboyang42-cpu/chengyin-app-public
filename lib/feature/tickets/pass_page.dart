import 'dart:async';

import '../../l10n/strings.dart';
import '../orders/registration_order_strings.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/activity.dart';
import '../../core/widgets/cy_widgets.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';

/// 出示核销码页:玩家出码,商家/俱乐部扫。
/// `POST /api/verify/dyncode/issue` 签发,TTL 由后端下发(当前 5 分钟)。
///
/// 后端会拒的场景(未登录 / 非本人票 / 未支付 / 已核销完)一律抛异常并展示后端原文,
/// 不在前端复刻这套判据 —— 复刻两份必然漂移。
///
/// ⚠️ 二维码图由服务端渲染上传 OSS 后返回 URL;出图失败时后端返回 null,
/// 此时回落展示可选中的 code 文本供商家手输。
class PassPage extends ConsumerStatefulWidget {
  const PassPage({super.key, required this.registrationId});
  final int registrationId;

  @override
  ConsumerState<PassPage> createState() => _PassPageState();
}

class _PassPageState extends ConsumerState<PassPage> {
  DynCode? _code;
  Object? _error;
  bool _loading = true;
  Timer? _ticker;

  /// 剩余秒数,由 expiresAt 绝对时间实时算,不本地递减(避免后台挂起后走偏)。
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _issue();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final c = _code;
      if (c == null || !mounted) return;
      setState(() => _remaining = c.remaining());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _issue() async {
    // 游客:签发接口必然 401 —— 先不发注定失败的请求,由页内登录门解释
    // (见 build);登完门上的「去登录」会把这次签发补上。
    if (!ref.read(authControllerProvider).isLoggedIn) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await ref
          .read(activityApiProvider)
          .issueDynamicCode(widget.registrationId);
      if (!mounted) return;
      setState(() {
        _code = c;
        _remaining = c.remaining();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  String get _countdownText {
    final s = _remaining.inSeconds;
    if (s <= 0) return stringsOf(context).ticketPassExpired;
    return stringsOf(context).ticketPassCountdown('${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}');
  }

  @override
  Widget build(BuildContext context) {
    // ★ 游客深链落地时给登录门,而不是被静默弹回首页(B1 报告 #231 P1)。
    //   刻意不自动弹登录弹窗:冷启动深链直接盖一层 sheet 同样像"链接坏了"。
    final bool guest = !ref.watch(authControllerProvider).isLoggedIn;
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            // 页标题左对齐:Column 默认 crossAxisAlignment 是 center,
            // 不显式 stretch 会把 58rpx 大标题推到屏幕正中,与小程序完全不同。
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              CyPageTitle(stringsOf(context).ticketPassTitle),
              Expanded(
                child: guest
                    ? StatusView(
                        key: const Key('ticket-pass-login-gate'),
                        message: stringsOf(context).ticketPassLogin,
                        sub: stringsOf(context).ticketPassLoginDetail,
                        icon: Icons.lock_outline,
                        large: true,
                        retryLabel: stringsOf(context).ticketPassSignIn,
                        onRetry: () async {
                          if (!await requireLogin(context, ref)) return;
                          if (!mounted) return;
                          unawaited(_issue());
                        },
                      )
                    : _buildBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingView();
    final err = _error;
    if (err != null) {
      return StatusView(
        message: localizedOrderError(context, err),
        icon: CupertinoIcons.exclamationmark_triangle,
        scrollable: true,
        onRetry: _issue,
      );
    }
    final code = _code;
    if (code == null) {
      return StatusView(
        message: stringsOf(context).ticketPassIssueError,
        icon: CupertinoIcons.exclamationmark_triangle,
        scrollable: true,
        onRetry: _issue,
      );
    }

    final expired = _remaining == Duration.zero;
    final textTheme = Theme.of(context).textTheme;
    final CyPalette palette = CyPalette.of(context);
    return ListView(
      padding: const EdgeInsets.all(CyTokens.space5),
      children: <Widget>[
        // ★ 说「核销」不说「扫描」:二维码加载失败时会回落成一串手输码
        //   (见 _QrArea 的 errorBuilder),那时**没有东西可扫**,而这句是页面上
        //   最醒目的指令 —— 再让它说「交给商家扫描」就是在指错方向,
        //   偏偏那正是商家站在旁边等着的时刻。
        //   扫码与手输都是核销,用这个词两种情形都成立,也省掉一套只为改文案
        //   而把失败状态从 _QrArea 抬到页面层的传递。
        // ★ 字级按真源 `.qr__title`:subtitle 档(= card-title 32rpx→16pt)+ w600。
        //   不写死则落 M3 `titleMedium`(14/w500)—— 全页最醒目的指令反而比真源小。
        Text(
          stringsOf(context).ticketPassShowMerchant,
          textAlign: TextAlign.center,
          style: textTheme.titleMedium?.copyWith(
            fontSize: CyTokens.typeCardTitle,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: CyTokens.space5),
        Center(
          child: Opacity(
            opacity: expired ? 0.25 : 1,
            child: _QrArea(code: code),
          ),
        ),
        const SizedBox(height: CyTokens.space4),
        Text(
          _countdownText,
          textAlign: TextAlign.center,
          // 真源 `.qr__count` 是次级字(caption 档 22rpx→11pt、w400),不是主操作色:
          // 原来取 `AppColors.primary`(= 主按钮**底色** token)当文字色,
          // 属「挪用语义色含义」(C3)。过期是「这一段没用了」,压到 disabled 档。
          // ★ 字级同样对齐真源:不写死则落 M3 `titleSmall`(12/w500),
          //   比真源的辅助信息档大一档、还自带中粗。
          style: textTheme.bodySmall?.copyWith(
            fontSize: CyTokens.typeCaption,
            fontWeight: FontWeight.w400,
            color: expired ? palette.textDisabled : palette.textSecondary,
          ),
        ),
        const SizedBox(height: CyTokens.space5),
        // ★ 码已过期时「刷新」是**唯一出路**,此时整屏压暗、再配一个次要样式的按钮,
        //   用户不知道该点哪。过期态提为主按钮,未过期时保持次要(主视觉让给码本身)。
        if (expired)
          CupertinoButton(
            minimumSize: const Size.fromHeight(CyTokens.btnH),
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.btnPadX),
            color: palette.actionPrimaryBg,
            foregroundColor: palette.actionPrimaryFg,
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
            onPressed: _issue,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.refresh, size: 18),
                const SizedBox(width: CyTokens.space2),
                Flexible(child: Text(stringsOf(context).ticketPassReload, textAlign: TextAlign.center)),
              ],
            ),
          )
        else
          CupertinoButton(
            minimumSize: const Size.fromHeight(CyTokens.btnH),
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.btnPadX),
            color: palette.actionSecondaryBg,
            foregroundColor: palette.textPrimary,
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
            onPressed: _issue,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.refresh, size: 18),
                const SizedBox(width: CyTokens.space2),
                Flexible(child: Text(stringsOf(context).ticketPassRefresh, textAlign: TextAlign.center)),
              ],
            ),
          ),
      ],
    );
  }
}

/// 码卡色板 —— 二维码那张卡是**物理浅色**(扫码硬要求),卡内颜色一律不随主题走。
/// 逐值对齐真源 `components/cy/qr-voucher/index.wxss`,沿用它的 `ds-ok` 豁免口径,
/// 集中在这里是为了让「豁免」有出处可查,而不是散落成五个说不清来历的字面量。
const Color _kQrCardBg = Color(0xFFFFFFFF); // .qr__card  background:#FFFFFF
/// .qr__code-text = `var(--cy-color-text-on-light)`(tokens.wxss:157)。
/// ★ 2026-09-01 D4 真源把浅卡内的深字**去墨蓝**:#0F172B → #181818;
///   App 侧此前停在去墨蓝之前的旧值,同卡的定位角/图标一并跟上(黑白系里
///   中性墨色,不是蓝黑)。
const Color _kQrCardInk = Color(0xFF181818);
const Color _kQrCardInkSecondary = Color(0xFF64748B); // .qr__count 浅卡内次级字
const Color _kQrCardPlaceholder = Color(
  0xFFF1F4F7,
); // .qr__ph 浅端 surface-subtle

/// 二维码区。版式对齐小程序 `components/cy/qr-voucher`:
/// 码卡 **物理白底、不随主题变深** —— 二维码必须能被扫到,这是设计系统的
/// 显式豁免(wxss 原注释「码卡物理浅色,不随主题 ds-ok」),不要"顺手"
/// 改成 bgSurface 让它跟着暗色走。卡内色值见上面 `_kQrCard*`。
///
/// 尺寸按 tokens 换算:面板 max-width 600rpx→300、码区 440rpx→220、
/// 内边距 space-5(48rpx)→24、圆角 radius-lg(32rpx)→16。
class _QrArea extends StatelessWidget {
  const _QrArea({required this.code});
  final DynCode code;

  /// 码区边长。小程序 440rpx。
  static const double _codeSize = 220;

  @override
  Widget build(BuildContext context) {
    final url = code.qrcodeUrl;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Container(
        padding: EdgeInsets.all(CyTokens.space5),
        decoration: BoxDecoration(
          color: _kQrCardBg,
          borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        ),
        child: SizedBox(
          width: _codeSize,
          height: _codeSize,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: (url == null || url.isEmpty)
                    ? _CodeFallback(code: code.code)
                    : Image.network(
                        url,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            _CodeFallback(code: code.code),
                        loadingBuilder: (ctx, child, progress) =>
                            progress == null ? child : const _CodePlaceholder(),
                      ),
              ),
              // 四角取景框,与小程序 .qr__corner--tl/tr/bl/br 对应。
              const Positioned.fill(child: _CornerFrame()),
            ],
          ),
        ),
      ),
    );
  }
}

/// 加载占位。小程序 .qr__ph:浅底 + radius-sm。
class _CodePlaceholder extends StatelessWidget {
  const _CodePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kQrCardPlaceholder,
        borderRadius: BorderRadius.circular(CyTokens.radiusSm),
      ),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CupertinoActivityIndicator(radius: 10),
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
  /// 真源 `.qr__corner`:width/height 40rpx ⇒ 20pt,`border: 6rpx` ⇒ 3pt。
  static const double _len = 20;
  static const double _stroke = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kQrCardInk
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    final w = size.width, h = size.height;
    // 左上
    canvas.drawLine(const Offset(0, 0), const Offset(_len, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, _len), paint);
    // 右上
    canvas.drawLine(Offset(w, 0), Offset(w - _len, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, _len), paint);
    // 左下
    canvas.drawLine(Offset(0, h), Offset(_len, h), paint);
    canvas.drawLine(Offset(0, h), Offset(0, h - _len), paint);
    // 右下
    canvas.drawLine(Offset(w, h), Offset(w - _len, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w, h - _len), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter oldDelegate) => false;
}

class _CodeFallback extends StatelessWidget {
  const _CodeFallback({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    // 回落内容要塞进 220 见方的码区:先按码区宽度排版(真源 `.qr__code-text`
    // 是 440rpx 定宽 + word-break 换行,大字号靠换行消化),仍装得下才由
    // FittedBox 整体缩小兜底 —— 若放任无限宽,大字号会把整列(图标/提示字)
    // 一起缩没。宁可缩小也不要 overflow(真机上会画黄黑条纹,比字小更难看)。
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: _QrArea._codeSize,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // ★ 在白色码卡内,必须用深色字 —— 沿用暗色主题的浅色文字会白底白字。
            Icon(Icons.qr_code_2, size: 48, color: _kQrCardInk),
            const SizedBox(height: CyTokens.space2),
            Text(
              stringsOf(context).ticketPassImageFallback,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: _kQrCardInkSecondary),
            ),
            const SizedBox(height: CyTokens.space2),
            SelectableText(
              code,
              textAlign: TextAlign.center,
              // ★ 这是二维码挂掉时商家要**照着手输**的码,且属应急路径:
              //   ① 等宽字体 —— 混合大小写+数字里 0/O、1/l、B/8 用比例字体极易看错,
              //      输错一次就得让玩家重新出码(码只有 5 分钟有效期)
              //   ② 字号/字重/字距逐值取真源 `.qr__code-text`:
              //      `--cy-font-page-title`(58rpx→29pt)/ `font-weight:600` /
              //      `letter-spacing:8rpx(=4pt)` —— 隔着柜台念/输时要逐字符辨得清
              style: TextStyle(
                fontFamily: 'monospace',
                fontFamilyFallback: const <String>[
                  'Menlo',
                  'Courier New',
                  'monospace',
                ],
                fontSize: CyTokens.typePageTitle,
                fontWeight: FontWeight.w600,
                letterSpacing: 4,
                color: _kQrCardInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
