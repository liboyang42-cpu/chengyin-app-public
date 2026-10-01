import '../club/club_api_messages.dart';
import '../../core/theme/cy_palette.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../data/models/verification_scan.dart';
import '../../data/models/scan_result.dart';
import 'scan_choice.dart';
import '../../core/providers.dart';
import '../../l10n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_system_text_input_alert.dart';

/// 商家扫玩家动态核销码。
///
/// ★ A1 裁决:履约完成由**商家扫玩家动态码**坐实 —— 玩家扫店内静态码只算
///   「进店」,商家这一扫才是履约的硬证据,也是 G3 复办意愿的判据来源。
///
/// 商家现场是**连续核销多个玩家**,所以扫完一张不退出:暂停相机 → 出结果 →
/// 点「继续扫描」恢复。退出要靠返回键,避免核销一个人就被踢出去重进。
///
/// ⚠️ 权限由后端把关:scan_dynamic_code 内部做 HMAC 验签并校验核销资格,
///    客户端不复刻判据(复刻两份必然漂移,而这条链路错了会影响商家结算证据)。
class MerchantScanPage extends ConsumerStatefulWidget {
  const MerchantScanPage({super.key});

  @override
  ConsumerState<MerchantScanPage> createState() => _MerchantScanPageState();
}

class _MerchantScanPageState extends ConsumerState<MerchantScanPage> {
  final MobileScannerController _controller = MobileScannerController();

  /// 已捕获一张码、正在处理或展示结果 —— 期间不再接受新的扫描结果。
  bool _handling = false;
  String? _resultMsg;
  bool _resultOk = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    for (final Barcode b in capture.barcodes) {
      final String? raw = b.rawValue;
      if (raw == null || raw.isEmpty) continue;
      setState(() => _handling = true);
      await _controller.stop();
      await _verify(raw);
      return;
    }
  }

  Future<void> _verify(String raw) async {
    // ★★ 先按码型路由。此前这里**无条件调 scanDynamicCode** ——
    //   商家扫优惠券码 / 团码 / 旧版票码都会被打到错的端点,
    //   拿回一句莫名其妙的失败。路由表对齐小程序 utils/verification-scan.js。
    //   ⚠️ 这只是路由,不是校验:真实性由服务端 HMAC 验签。
    final VerificationScan scan = VerificationScan.resolve(raw);
    if (scan.kind == ScanKind.invalid) {
      if (!mounted) return;
      setState(() {
        _resultOk = false;
        // 「暂不支持此动态码」和「二维码格式错误」是两回事,原样区分。
        _resultMsg = scan.message == '暂不支持此动态码'
            ? stringsOf(context).merchantRedemptionUnsupported
            : stringsOf(context).merchantRedemptionInvalid;
      });
      return;
    }
    final ticketSuccess = stringsOf(context).merchantRedemptionTicketSuccess;
    try {
      final String msg = switch (scan.kind) {
        ScanKind.group =>
          await _redeemGroup(scan.code),
        ScanKind.coupon => await ref.read(couponApiProvider).verify(scan.code),
        // ⚠️ 用 **Detailed** 版本,不用 scanQrCode ——
        //   后者在"需要选章"时抛异常,而且抛的那句话是
        //   「请到商家核销页扫码」:这里**就是**商家核销页,自相矛盾。
        //   更要紧的是抛异常会把候选列表连同 data 一起丢掉,
        //   商家看到红字「请选择要核销的章节」却没有可选的东西 ——
        //   scan_result.dart 的注释把这个死胡同写死了。
        ScanKind.legacyTicket => await _legacy(scan),
        ScanKind.dynamicTicket => _dynamicMsg(
          await ref.read(activityApiProvider).scanDynamicCode(scan.code),
          ticketSuccess,
        ),
        ScanKind.invalid => '',
      };
      if (!mounted) return;
      setState(() {
        _resultOk = true;
        _resultMsg = msg;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resultOk = false;
        // 后端原因原样展示:码无效/已过期/已核销/无权限等,客户端不改写。
        _resultMsg = clubApiErrorMessage(context, e);
      });
    }
  }

  Future<String> _redeemGroup(String code) async {
    final localSuccess = stringsOf(context).boundedApiGroupSuccess;
    final receipt = await ref.read(groupCodeApiProvider).redeemWithReceipt(code);
    return receipt.isLocalFallback ? localSuccess : receipt.message;
  }

  /// 旧版票码。★ 走 **Detailed** 版本 + 选章面板,不用 scanQrCode ——
  /// 后者在"需要选章"时抛异常,抛的那句还是「请到商家核销页扫码」
  /// (这里就是商家核销页),而且会把候选列表连同 data 一起丢掉。
  Future<String> _legacy(VerificationScan scan) async {
    final cancelledMessage = stringsOf(context).merchantRedemptionCancelled;
    final ScanResult r = await ref
        .read(registrationApiProvider)
        .scanQrCodeDetailed(type: scan.legacyType!, code: scan.code);
    // 拿到结果之后页面可能已经不在了 —— 弹面板前先确认。
    if (!mounted) throw Exception(cancelledMessage);
    return resolveScanChoice(
      context: context,
      ref: ref,
      result: r,
      code: scan.code,
    );
  }

  /// 动态票码成功后的话:后端带回章节就说清是哪一章。
  String _dynamicMsg(Map<String, dynamic> data, String fallback) {
    final Object? chapter = data['chapterId'];
    if (chapter == null || !mounted) return fallback;
    return stringsOf(context).merchantRedemptionChapterResult(fallback, chapter.toString());
  }

  Future<void> _scanNext() async {
    setState(() {
      _handling = false;
      _resultMsg = null;
    });
    await _controller.start();
  }

  /// 码扫不出时的手工回落(光线差 / 屏幕反光 / 玩家截图模糊)。
  Future<void> _manualInput() async {
    final String? code = await showCySystemTextInputAlert(
      context: context,
      title: stringsOf(context).merchantRedemptionManualTitle,
      placeholder: stringsOf(context).merchantRedemptionPlayerReadHint,
      confirmText: stringsOf(context).merchantRedemptionRedeem,
      keyboardKind: CySystemKeyboardKind.ascii,
    );
    if (code == null || code.isEmpty) return;
    setState(() => _handling = true);
    await _controller.stop();
    await _verify(code);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CyPalette.of(context).bgPage,
      navigationBar: CupertinoNavigationBar(
        trailing: CupertinoButton(
          onPressed: _manualInput,
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          child: Semantics(
            button: true,
            label: stringsOf(context).merchantRedemptionManual,
            child: const Icon(CupertinoIcons.keyboard),
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Padding(
            // Material AppBar 的内容高 56pt，Cupertino 导航栏是 44pt。
            // 保留这 12pt 只为锁住取景区和结果覆盖层的旧几何。
            padding: const EdgeInsets.only(
              top: kToolbarHeight - kMinInteractiveDimensionCupertino,
            ),
            child: Column(
              // 页标题左对齐:Column 默认 crossAxisAlignment 是 center,
              // 不显式 stretch 会把 58rpx 大标题推到屏幕正中,与小程序完全不同。
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                CyPageTitle(stringsOf(context).merchantRedemptionTitle),
                Expanded(
                  child: Stack(
                    children: <Widget>[
                      MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                      ),
                      if (_resultMsg != null)
                        _ResultOverlay(
                          ok: _resultOk,
                          message: _resultMsg!,
                          onNext: _scanNext,
                        ),
                      if (_handling && _resultMsg == null)
                        ColoredBox(
                          color: CyPalette.of(context).overlay,
                          child: const Center(
                            child: CupertinoActivityIndicator(),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultOverlay extends StatelessWidget {
  const _ResultOverlay({
    required this.ok,
    required this.message,
    required this.onNext,
  });
  final bool ok;
  final String message;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ColoredBox(
      color: CyPalette.of(context).overlay,
      child: Center(
        child: Container(
          margin: EdgeInsets.all(CyTokens.space6),
          padding: EdgeInsets.all(CyTokens.space5),
          decoration: BoxDecoration(
            // 结果卡浮在 56% 黑遮罩之上,用 bgSurface(#0A0A0B)与遮罩几乎同色
            // ⇒ 看不出卡片边界。改用 elevated 并加描边:浮层要比它盖住的东西亮。
            color: CyPalette.of(context).bgElevated,
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
            border: Border.all(
              color: CyPalette.of(context).borderSubtle,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                ok ? Icons.check_circle : Icons.error_outline,
                size: 48,
                color: ok ? AppColors.success : AppColors.danger,
              ),
              SizedBox(height: CyTokens.space3),
              Text(
                message,
                textAlign: TextAlign.center,
                style: textTheme.titleMedium,
              ),
              SizedBox(height: CyTokens.space5),
              CyNativeButton(onPressed: onNext, label: stringsOf(context).merchantRedemptionNext),
            ],
          ),
        ),
      ),
    );
  }
}
