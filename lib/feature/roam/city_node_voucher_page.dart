import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/city_node_detail.dart';
import 'city_node_voucher_logic.dart';

/// 玩家据点核销码(对齐小程序 `subpackageRoam/citynode-code`):
/// 到店打卡完成后出示给商家扫码领券。动态码,倒计时到 0 自动重新出码。
///
/// ★ 缺参态与出码失败分家:缺参不可能靠重试变出参数,
///   给「重试」就是假按钮 —— 那一态只给返回。
class CityNodeVoucherPage extends ConsumerStatefulWidget {
  const CityNodeVoucherPage({super.key, this.poiId, this.name});

  final int? poiId;
  final String? name;

  @override
  ConsumerState<CityNodeVoucherPage> createState() =>
      _CityNodeVoucherPageState();
}

class _CityNodeVoucherPageState extends ConsumerState<CityNodeVoucherPage> {
  CityNodeVoucherPhase _phase = voucherInitialPhase(
    poiId: null,
  ); // initState 前占位,init 里重算
  String _qrcodeUrl = '';
  String _code = '';
  int _countdown = 0;
  String _errMsg = '';
  Timer? _timer;
  bool _issuing = false;

  @override
  void initState() {
    super.initState();
    _phase = voucherInitialPhase(poiId: widget.poiId);
    if (_phase != CityNodeVoucherPhase.missing) {
      _issue();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _issue() async {
    final int poiId = widget.poiId ?? 0;
    if (poiId <= 0 || _issuing) return;
    _issuing = true;
    _stopCountdown();
    setState(() {
      _phase = CityNodeVoucherPhase.loading;
      _qrcodeUrl = '';
      _code = '';
      _errMsg = '';
    });
    try {
      final CityNodeVoucher v = await ref
          .read(roamApiProvider)
          .issueCityNodeCode(poiId);
      if (!mounted) return;
      final CityNodeVoucherPhase next = voucherPhaseFromIssue(v);
      setState(() {
        _phase = next;
        _qrcodeUrl = v.qrcodeUrl;
        _code = v.code;
        if (next == CityNodeVoucherPhase.ready) {
          _startCountdown(v.countdownSeconds);
        } else {
          _errMsg = '暂时无法生成核销码，请稍后重试';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = CityNodeVoucherPhase.error;
        _errMsg = voucherErrorMessage(e);
      });
    } finally {
      _issuing = false;
    }
  }

  void _startCountdown(int seconds) {
    _stopCountdown();
    setState(() => _countdown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final int? next = nextVoucherCountdown(_countdown);
      if (next == null) {
        _issue(); // 过期自动重新出码
        return;
      }
      setState(() => _countdown = next);
    });
  }

  void _stopCountdown() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget build(BuildContext context) {
    final String title = widget.name?.trim().isNotEmpty == true
        ? widget.name!.trim()
        : '据点';
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: _phase == CityNodeVoucherPhase.missing
              ? _MissingView(onBack: () => Navigator.of(context).maybePop())
              : _VoucherCard(
                  title: title,
                  phase: _phase,
                  qrcodeUrl: _qrcodeUrl,
                  code: _code,
                  countdown: _countdown,
                  errorText: _errMsg.isEmpty ? '出码失败' : _errMsg,
                  onRetry: _issue,
                ),
        ),
      ),
    );
  }
}

/// 缺参态:真插画 + 真实原因 + 唯一走得通的出口,零重试。
/// 对齐小程序:缺参不把 state 交给码卡(卡内错误态硬编码「点此重试」,是假按钮)。
///
/// 用共用层 [StatusView] 承载(小程序同一个 `cy-empty`,club 域同款写法):
/// 出口是 44pt 的 `CyNativeButton`,冷启动深链进来没有上一页时,
/// 它还会补一个「回首页」—— `maybePop` 在那种进法下什么都按不出来。
class _MissingView extends StatelessWidget {
  const _MissingView({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return StatusView(
      icon: Icons.qr_code_2,
      message: '这个核销码打不开',
      sub: '链接缺少据点参数,请回据点页重新进入',
      large: true,
      retryLabel: '返回',
      onRetry: onBack,
    );
  }
}

/// 白色码卡(物理白底,不随暗色主题 —— 二维码必须能被扫到,
/// 同券码出示页的显式豁免)。对齐小程序 cy-qr-voucher。
class _VoucherCard extends StatelessWidget {
  const _VoucherCard({
    required this.title,
    required this.phase,
    required this.qrcodeUrl,
    required this.code,
    required this.countdown,
    required this.errorText,
    required this.onRetry,
  });

  final String title;
  final CityNodeVoucherPhase phase;
  final String qrcodeUrl;
  final String code;
  final int countdown;
  final String errorText;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final bool error = phase == CityNodeVoucherPhase.error;
    final bool ready = phase == CityNodeVoucherPhase.ready;
    return ListView(
      padding: const EdgeInsets.all(CyTokens.space5),
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Container(
              padding: const EdgeInsets.all(CyTokens.space5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(CyTokens.radiusLg),
              ),
              child: Column(
                children: <Widget>[
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: CyTokens.typeCardTitle,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172B),
                    ),
                  ),
                  const SizedBox(height: CyTokens.space1),
                  const Text(
                    // desc 照小程序原文(citynode-code/index.wxml 的 desc 属性)。
                    '出示给商家扫码,即可领取优惠券',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: CyTokens.typeCaption,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: CyTokens.space4),
                  error
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: CyTokens.space5,
                          ),
                          child: Column(
                            children: <Widget>[
                              const Icon(
                                Icons.qr_code_2,
                                size: 48,
                                color: Color(0xFF64748B),
                              ),
                              const SizedBox(height: CyTokens.space2_5),
                              Text(
                                errorText,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: CyTokens.typeLabel,
                                  color: Color(0xFF475569),
                                ),
                              ),
                              const SizedBox(height: CyTokens.space3),
                              CupertinoButton(
                                onPressed: onRetry,
                                minimumSize: const Size(44, 44),
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          children: <Widget>[
                            _QrArea(
                              ready: ready,
                              qrcodeUrl: qrcodeUrl,
                              code: code,
                            ),
                            if (ready) ...<Widget>[
                              const SizedBox(height: CyTokens.space3),
                              Text(
                                code,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: CyTokens.typeLabel,
                                  color: Color(0xFF0F172B),
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: CyTokens.space2),
                              Text(
                                '$countdown s 后自动刷新',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: CyTokens.typeCaption,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ],
                        ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _QrArea extends StatelessWidget {
  const _QrArea({
    required this.ready,
    required this.qrcodeUrl,
    required this.code,
  });

  final bool ready;
  final String qrcodeUrl;
  final String code;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: !ready || qrcodeUrl.isEmpty
                ? Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F4F7),
                      borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                    ),
                    child: Center(
                      child: Text(
                        // 有码没图:不是故障,是后端二维码生成失败 —— 占位图不能
                        // 说成「加载失败」,也不能假装在转圈。
                        ready ? '二维码图片未生成' : '',
                        style: const TextStyle(
                          fontSize: CyTokens.typeCaption,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  )
                : Image.network(
                    qrcodeUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F4F7),
                        borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                      ),
                      child: const Center(
                        child: Text(
                          '二维码图片未生成',
                          style: TextStyle(
                            fontSize: CyTokens.typeCaption,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          if (!ready)
            const Center(child: CupertinoActivityIndicator(radius: 12)),
          const Positioned.fill(child: _CornerFrame()),
        ],
      ),
    );
  }
}

class _CornerFrame extends StatelessWidget {
  const _CornerFrame();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _CornerPainter());
}

class _CornerPainter extends CustomPainter {
  static const double _len = 22;
  static const double _stroke = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0F172B)
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
