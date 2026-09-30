import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/theme/cy_tokens.dart';
import '../../../../core/widgets/cy_net_image.dart';
import '../playkit_fullscreen.dart';
import '../playkit_projection.dart';
import 'playkit_fullscreen_parts.dart';
import 'playkit_misc_data.dart';

/// `cy-playkit-scan` · 扫码参与 · 最轻的一种:扫码即完成,不出题、不判定。
///
/// 真源:`~/城瘾app/xcx-ref/pages/play/components/playkit-scan/`。
///
/// 这一屏刻意**没有**三样东西,都不是漏做(真源注释原文):
/// 没有限时/次数(扫完就结束了)、没有判定屏(没有对错)、
/// 没有「收下」按钮(摆一个等于在问「你要不要收」,而这本来就不是能拒绝的东西)。
///
/// ## 进店只认扫码
/// 「GPS 可以伪造,客户端说扫了也不算数」—— 码要交给服务端比对。
/// 取景框点开的是系统的扫码页(`mobile_scanner`),取消不报错:
/// 那是玩家改主意,不是出事;只有真读到码才抛 `SUBMIT_SCAN { code }`。
///
/// ## 三种回复形态都遵守同一条:商家没填就不出
/// 玩家看到的应该只有商家写的东西,商家没写就是没有,不需要一句话替他解释为什么没有。
///
/// ## 与真源的已知差异(§7.2 accepted,「iOS 27 原生化」)
/// * 语音条:**播放本身是宿主的活**(真源组件只 `triggerEvent('audio')`,
///   由页面放)。所以只有宿主接了 [onVoiceToggle] 时才画那颗播放键;
///   没接就是一条只读的语音气泡 + 商家留的文字 —— 不摆一颗按下去没声音的假按钮。
///   时长读数走不到服务端(kit 没有 seconds 字段),先钉死 12″,记遗留。
/// * 取景框保留道具色(近黑);**气泡不保留** —— 真源 `.sc__bub` 是白底黑字
///   (「回的那条是给玩家的话,不是这一屏的界面色」),逐值 1:1;字重 800 → w600。
class PlayKitScanView extends StatefulWidget {
  const PlayKitScanView({
    super.key,
    required this.data,
    this.scanCode,
    this.onVoiceToggle,
  });

  final PlayKitFullscreenContext data;

  /// 取码口。生产路径 = 全屏扫码页;测试注入假实现
  /// (相机是平台视图,单测里跑不起来 —— 与 `filter_shot_camera` 同一口径)。
  /// 返回 null / 空串 = 玩家取消。
  final Future<String?> Function()? scanCode;

  /// 语音条的播放意图。宿主接上才画播放键。
  final ValueChanged<bool>? onVoiceToggle;

  @override
  State<PlayKitScanView> createState() => _PlayKitScanViewState();
}

/// 皮肤 `skin-qadark`(`style/play-surface.wxss:28`)的逐值道具色。
/// (`--soft` #1b1b20 已无处引用:气泡/语音条/占位图在真源里都不是台面色,是道具色。)
const Color _kScanSurface = Color(0xFF0D0D10);
const Color _kScanInk = Color(0xFFF6F6F8);
const Color _kScanSub = Color(0xFF8A8A92);

/// 真源组件默认标题(`const TITLE = '扫一下门口的码'`)。
const String _kScanDefaultTitle = '扫一下门口的码';

/// 真源 `.sc__sub` 的字面灰(语音条下面那行说明;与 skin-qadark 的 `--sub`
/// #8a8a92 不同值 —— 那条写死在组件自己的 wxss 里,ds-ok)。
const Color _kScanCaption = Color(0xFF8E8E98);

/// 取景框扫描线循环周期:框里没有东西在动的话,看着像一张静态图,
/// 不像相机开着(真源注释)。属**连续环境循环**,不是态切换,所以不套 CyMotion 档;
/// 减动效下停住只留静态框(与 `kCountdownWaveA` 同口径,见 motion_ratchet 白名单)。
const Duration kPlayKitScanLinePeriod = Duration(milliseconds: 2200);

/// 取景框边长 424rpx = 212pt(真源 `.sc__frame`)。
const double _kScanFrameSize = 212;

class _PlayKitScanViewState extends State<PlayKitScanView>
    with SingleTickerProviderStateMixin {
  // 同 predict:显式初始化,别让 dispose 里那次访问成为第一次(见其注释)。
  late final AnimationController _line;

  bool _playing = false;
  bool _opening = false;

  // 按压态:真源取景框/语音条都挂 `hover-class="sc__press"`(opacity .88)。
  bool _framePressed = false;
  bool _voicePressed = false;

  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  Map<String, Object?> get _kit => widget.data.card.kit;

  String get _title {
    final String fromKit = '${_kit['title'] ?? ''}'.trim();
    return fromKit.isEmpty ? _kScanDefaultTitle : fromKit;
  }

  PlayKitScanKind get _kind => normalizeScanKind(_kit['kind']);

  String get _reply => '${_kit['reply'] ?? ''}'.trim();

  String get _audioUrl => '${_kit['audioUrl'] ?? ''}'.trim();

  String get _imageUrl => '${_kit['imageUrl'] ?? ''}'.trim();

  /// 扫过了就不再开相机:reply / 图 / 语音三样来一个就算(真源 `onScan` 的守卫)。
  bool get _scanned =>
      _reply.isNotEmpty || _audioUrl.isNotEmpty || _imageUrl.isNotEmpty;

  bool get _canScan => widget.data.enabled && !_scanned && !_opening;

  @override
  void initState() {
    super.initState();
    _line = AnimationController(vsync: this, duration: kPlayKitScanLinePeriod);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncLine());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLine();
  }

  @override
  void didUpdateWidget(covariant PlayKitScanView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 宿主回填 reply / 图 / 语音之后 `_scanned` 会翻真,这里把线收掉。
    _syncLine();
  }

  @override
  void dispose() {
    _line.dispose();
    super.dispose();
  }

  /// 减动效:扫描线不跑(真源 `.sc__frame--reduced` / `--reduced` 一族)。
  /// 扫完之后线也不再跑 —— 那时渲染分支已经把它摘掉(`if (!_scanned)`),
  /// 空转等于白白烧一个 ticker,直到这一屏被 pop。
  void _syncLine() {
    if (!mounted) return;
    if (_reduced || _scanned) {
      _line.stop();
      return;
    }
    if (!_line.isAnimating) _line.repeat();
  }

  Future<void> _onScan() async {
    if (!_canScan) return;
    setState(() => _opening = true);
    String? code;
    try {
      final Future<String?> Function()? opener = widget.scanCode;
      code = opener == null ? await _openScanner() : await opener();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
    final String trimmed = (code ?? '').trim();
    // 取消不报错:那是玩家改主意,不是出事(真源 scanCode 的 fail 分支是空函数)。
    if (trimmed.isEmpty) return;
    // 扫码回来时这一屏可能已经被摘掉 —— 触感要读 MediaQuery,得有 context 才震。
    if (!mounted) return;
    playKitHaptic(context, PlayKitHaptic.light);
    widget.data.onAction?.call(
      PlayKitAction(
        label: '扫一下门口的码',
        action: 'SUBMIT_SCAN',
        // 真源 serverPayload:`scan:scanned → { code: d.code }`。
        payload: <String, Object?>{'code': trimmed},
      ),
    );
  }

  Future<String?> _openScanner() {
    return Navigator.of(context).push<String>(
      CupertinoPageRoute<String>(
        fullscreenDialog: true,
        builder: (BuildContext context) => const _ScanCameraPage(),
      ),
    );
  }

  void _toggleVoice() {
    final ValueChanged<bool>? toggle = widget.onVoiceToggle;
    if (toggle == null) return;
    playKitHaptic(context, PlayKitHaptic.selection);
    setState(() => _playing = !_playing);
    toggle(_playing);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _kScanSurface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CyTokens.space4,
            vertical: CyTokens.space3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                _title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _kScanInk,
                  fontSize: CyTokens.typePageTitle,
                  fontWeight: FontWeight.w600,
                  height: CyTokens.leadingTight,
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: CyTokens.space5,
                        ),
                        child: _viewfinder(),
                      ),
                      _replyArea(),
                    ],
                  ),
                ),
              ),
              if (!_scanned)
                const Padding(
                  padding: EdgeInsets.only(top: CyTokens.space2),
                  child: Text(
                    '扫完就完成，不用再点别的。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _kScanSub,
                      fontSize: CyTokens.typeCaption,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _viewfinder() {
    final bool tappable = _canScan;
    return Semantics(
      button: tappable,
      label: '扫这个点位的码',
      child: GestureDetector(
        key: const Key('playkit-scan-frame'),
        behavior: HitTestBehavior.opaque,
        onTapDown: tappable
            ? (_) => setState(() => _framePressed = true)
            : null,
        onTapCancel: tappable
            ? () => setState(() => _framePressed = false)
            : null,
        onTapUp: tappable ? (_) => setState(() => _framePressed = false) : null,
        onTap: tappable ? () => unawaited(_onScan()) : null,
        // 按下 .88(真源 `hover-class="sc__press"`);按不动时(宿主忙/开相机中)
        // 压到 .55 —— 与同族 PlayKitStageButton 的 disabled 呈现同一契约。
        // 扫完(打勾)不压暗:那是完成态,不是不能点。
        child: Opacity(
          opacity: _framePressed ? 0.88 : (tappable || _scanned ? 1 : 0.55),
          child: Container(
            width: _kScanFrameSize,
            height: _kScanFrameSize,
            decoration: BoxDecoration(
              color: const Color(0xFF0C0C10),
              borderRadius: BorderRadius.circular(CyTokens.radiusXl),
              border: Border.all(color: const Color(0x12FFFFFF)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: <Widget>[
                // 四个角是直角括号,不是一整圈描边:整圈会把它变成一个「相框」。
                const Positioned(
                  left: 14,
                  top: 14,
                  child: _Corner(top: true, left: true),
                ),
                const Positioned(
                  right: 14,
                  top: 14,
                  child: _Corner(top: true, left: false),
                ),
                const Positioned(
                  left: 14,
                  bottom: 14,
                  child: _Corner(top: false, left: true),
                ),
                const Positioned(
                  right: 14,
                  bottom: 14,
                  child: _Corner(top: false, left: false),
                ),
                if (!_scanned)
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _line,
                      builder: (BuildContext context, Widget? child) {
                        final double t = _reduced ? 0.5 : _line.value;
                        return Align(
                          alignment: Alignment(0, -1 + 2 * t),
                          child: child,
                        );
                      },
                      child: Container(
                        height: 2,
                        margin: const EdgeInsets.symmetric(horizontal: 22),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              Color(0x00FFFFFF),
                              Color(0xE6FFFFFF),
                              Color(0x00FFFFFF),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_scanned)
                  const Center(
                    child: Icon(
                      CupertinoIcons.check_mark_circled_solid,
                      size: 44,
                      color: Color(0xFF3ECF8E),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _replyArea() {
    switch (_kind) {
      case PlayKitScanKind.voice:
        // 真源 `.sc__bub--voice`:白底气泡同款皮肤,只是钉死 344rpx=172pt 宽、
        // 内容横排 gap 18rpx=9pt。播放键黑(#000)、波形黑 .55、秒数黑 .6。
        final bool playable = widget.onVoiceToggle != null;
        return Column(
          children: <Widget>[
            Semantics(
              button: playable,
              label: playable ? (_playing ? '暂停商家的语音' : '播放商家的语音') : '商家留了一条语音',
              child: Opacity(
                opacity: _voicePressed && playable ? 0.88 : 1, // .sc__press
                child: GestureDetector(
                  key: const Key('playkit-scan-voice'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: playable
                      ? (_) => setState(() => _voicePressed = true)
                      : null,
                  onTapCancel: playable
                      ? () => setState(() => _voicePressed = false)
                      : null,
                  onTap: playable ? _toggleVoice : null,
                  onTapUp: playable
                      ? (_) => setState(() => _voicePressed = false)
                      : null,
                  child: Container(
                    width: 172,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: <Widget>[
                        if (playable) ...<Widget>[
                          Icon(
                            _playing
                                ? CupertinoIcons.pause_fill
                                : CupertinoIcons.play_arrow_solid,
                            size: 16,
                            color: const Color(0xFF000000),
                          ),
                          const SizedBox(width: 9),
                        ],
                        // 七根竖线(真源 `.pv-wave i:nth-child(n)` 的逐值高度)
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              for (final double bar in const <double>[
                                8,
                                15,
                                21,
                                12,
                                18,
                                9,
                                13,
                              ])
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 1.5,
                                  ),
                                  child: Container(
                                    width: 3,
                                    height: bar,
                                    decoration: BoxDecoration(
                                      // 真源 `.sc__wave-b` #000 × .55
                                      color: const Color(0x8C000000),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 9),
                        const Text(
                          '12″',
                          style: TextStyle(
                            // 真源 `.sc__sec` 黑 .6
                            color: Color(0x99000000),
                            fontSize: CyTokens.typeLabel, // 24rpx
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // 回的那条在语音形态下**不是气泡**,是 `.sc__sub` 那行灰字。
            if (_reply.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: CyTokens.space2),
                child: Text(
                  _reply,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _kScanCaption,
                    fontSize: CyTokens.typeLabel, // 24rpx
                    height: CyTokens.leadingNormal,
                  ),
                ),
              ),
          ],
        );
      case PlayKitScanKind.image:
        // 真源 `.sc__pic`:通栏、300rpx=150pt 高、圆角 24rpx=12pt。
        return Column(
          children: <Widget>[
            if (_imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CyNetImage(
                  _imageUrl,
                  width: double.infinity,
                  height: 150,
                ),
              )
            else
              // 商家还没传图时画的是「这儿有一张图」,不是假装某张图
              // (真源 `.sc__pic--empty`:135° 斜条纹两档深灰 + 灰字)。
              Container(
                width: double.infinity,
                height: 150,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Color(0xFF17171C),
                      Color(0xFF17171C),
                      Color(0xFF1D1D23),
                      Color(0xFF1D1D23),
                    ],
                    stops: <double>[0, 0.25, 0.25, 0.5],
                    tileMode: TileMode.repeated,
                  ),
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                child: const Text(
                  '扫完给的那张图',
                  style: TextStyle(
                    color: Color(0xFF5C5C66),
                    fontSize: CyTokens.typeLabel, // 24rpx
                  ),
                ),
              ),
            if (_reply.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: CyTokens.space3),
                child: _Bubble(text: _reply),
              ),
          ],
        );
      case PlayKitScanKind.text:
        // 商家没写就不出气泡 —— 不要用一句话替他解释为什么没有。
        return _reply.isEmpty ? const SizedBox.shrink() : _Bubble(text: _reply);
    }
  }
}

/// 取景框的一个角:两条边画成直角括号。
class _Corner extends StatelessWidget {
  const _Corner({required this.top, required this.left});

  final bool top;
  final bool left;

  @override
  Widget build(BuildContext context) {
    // 真源 `.sc__c`:5rpx=2.5pt 白描边、opacity .95。
    const Color color = Color(0xF2FFFFFF);
    return SizedBox(
      width: 30,
      height: 30,
      child: CustomPaint(
        painter: _CornerPainter(color: color, top: top, left: left),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter({
    required this.color,
    required this.top,
    required this.left,
  });

  final Color color;
  final bool top;
  final bool left;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final double x = left ? 0 : size.width;
    final double y = top ? 0 : size.height;
    // 三段折线:横臂远端 → 角点 → 竖臂远端。此前首末两点都写成了角点自己
    // (moveTo 与两个 lineTo 同点),整条 path 退化成一个点 ——
    // 截图里四角是四个小圆点,不是真源 `.sc__c` 的直角括号。
    final Path path = Path()
      ..moveTo(left ? size.width : 0, y)
      ..lineTo(x, y)
      ..lineTo(x, top ? size.height : 0);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.top != top ||
      oldDelegate.left != left;
}

/// 商家那句话的气泡。真源 `.sc__bub` 逐值:**白底黑字**(「回的那条是给玩家
/// 的话,所以是白底黑字的气泡,不是这一屏的界面色」)、max-width 86%、
/// 圆角 28rpx=14pt、padding 22/28rpx=11×14pt、27rpx≈13.5 字(上到 iOS 梯级
/// Body 14)、行高 1.6、居中。
class _Bubble extends StatelessWidget {
  const _Bubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86, // 真源 max-width 86%
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF000000),
              fontSize: CyTokens.typeBody,
              height: CyTokens.leadingNormal,
            ),
          ),
        ),
      ),
    );
  }
}

/// 全屏扫码页:扫到第一个 barcode 的 rawValue 即 pop 返回该字符串。
/// 与仓内既有四处的口径一致(`mobile_scanner`,`play_session_page.dart:3196` 同款)。
class _ScanCameraPage extends StatefulWidget {
  const _ScanCameraPage();

  @override
  State<_ScanCameraPage> createState() => _ScanCameraPageState();
}

class _ScanCameraPageState extends State<_ScanCameraPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;
  bool _denied = false;

  /// 权限之外的相机故障(初始化失败/不支持等)。此前一律 `SizedBox.shrink()`:
  /// 黑屏一条理由都没有 —— 说清「打不开 + 下一步」(§9.3 I2)。
  bool _broken = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final Barcode barcode in capture.barcodes) {
      final String? raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        _handled = true;
        Navigator.of(context).pop(raw);
        return;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      navigationBar: const CupertinoNavigationBar(
        backgroundColor: CupertinoColors.black,
        brightness: Brightness.dark,
        border: null,
        middle: Text('扫描点位二维码'),
      ),
      child: Stack(
        children: <Widget>[
          if (_denied || _broken)
            // 权限/相机不可用:说清发生了什么,并给得出下一步(§9.3 I2)。
            Center(
              child: Padding(
                padding: const EdgeInsets.all(CyTokens.space6),
                child: Text(
                  _denied
                      ? '相机打不开。到系统设置里允许城瘾使用相机，再回来扫这个点位的码。'
                      : '这台设备的相机暂时启动不了。退出这一页再进来试一次；如果还是不行，先重启 App。',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: CupertinoColors.white,
                    fontSize: CyTokens.typeBody,
                    height: CyTokens.leadingNormal,
                  ),
                ),
              ),
            )
          else
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder:
                  (BuildContext context, MobileScannerException error) {
                    final bool denied =
                        error.errorCode ==
                        MobileScannerErrorCode.permissionDenied;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      if (denied && !_denied) {
                        setState(() => _denied = true);
                      } else if (!denied && !_broken) {
                        setState(() => _broken = true);
                      }
                    });
                    return const SizedBox.shrink();
                  },
            ),
          if (!_denied && !_broken)
            Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: CupertinoColors.white, width: 2),
                  borderRadius: BorderRadius.circular(CyTokens.radiusLg),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
