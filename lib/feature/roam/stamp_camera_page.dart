import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/status_view.dart';
import '../../core/theme/cy_tokens.dart';
import '../../data/api/roam_api.dart';
import '../../data/models/roam.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';

const double _minFrameRatio = 0.4;
const double _maxFrameRatio = 0.9;
const double _defaultFrameRatio = 0.74;

@immutable
class StampCameraLayout {
  const StampCameraLayout({
    required this.art,
    required this.body,
    required this.screen,
    required this.frame,
    required this.shutter,
    required this.reviewActions,
  });

  final Rect art;
  final Rect body;
  final Rect screen;
  final Rect frame;
  final Rect shutter;
  final Rect reviewActions;

  factory StampCameraLayout.forViewport(
    Size viewport, {
    required double safeTop,
    double frameRatio = _defaultFrameRatio,
  }) {
    const double sourceW = 736;
    const double sourceH = 552;
    const Rect sourceBody = Rect.fromLTRB(40, 80, 694, 493);
    const Rect sourceLcd = Rect.fromLTRB(95, 190, 420, 441);
    const Offset sourceShutter = Offset(537, 315);
    const double sourceShutterSize = 112;
    final double artTop = math.max(safeTop + 74, viewport.height * .12);
    final double maxArtHeight = math.max(260, viewport.height - artTop - 24);
    final double desiredArtWidth = math.min(440, viewport.width * 1.13);
    final double artWidth = math.min(
      desiredArtWidth,
      maxArtHeight * sourceH / sourceW,
    );
    final double artHeight = artWidth * sourceW / sourceH;
    final double scale = artWidth / sourceH;
    final double artLeft = (viewport.width - artWidth) / 2;
    final Rect art = Rect.fromLTWH(artLeft, artTop, artWidth, artHeight);
    final Rect body = Rect.fromLTWH(
      artLeft + (sourceH - sourceBody.bottom) * scale,
      artTop + sourceBody.left * scale,
      (sourceBody.bottom - sourceBody.top) * scale,
      (sourceBody.right - sourceBody.left) * scale,
    );
    final Rect screen = Rect.fromLTWH(
      artLeft + (sourceH - sourceLcd.bottom) * scale,
      artTop + sourceLcd.left * scale,
      (sourceLcd.bottom - sourceLcd.top) * scale,
      (sourceLcd.right - sourceLcd.left) * scale,
    );
    final double ratio = frameRatio.clamp(_minFrameRatio, _maxFrameRatio);
    final double rawWidth = math.min(
      screen.width * ratio,
      (screen.height / 1.25) * ratio,
    );
    final double frameWidth = math.max(4, (rawWidth / 4).floor() * 4);
    final Rect frame = Rect.fromCenter(
      center: screen.center,
      width: frameWidth,
      height: frameWidth * 5 / 4,
    );
    final double shutterSize = sourceShutterSize * scale;
    final Rect shutter = Rect.fromCenter(
      center: Offset(
        artLeft + (sourceH - sourceShutter.dy) * scale,
        artTop + sourceShutter.dx * scale,
      ),
      width: shutterSize,
      height: shutterSize,
    );
    return StampCameraLayout(
      art: art,
      body: body,
      screen: screen,
      frame: frame,
      shutter: shutter,
      reviewActions: Rect.fromLTWH(
        body.left + 12,
        math.min(body.bottom - 72, screen.bottom + 16),
        body.width - 24,
        52,
      ),
    );
  }
}

@immutable
class StampCropRect {
  const StampCropRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;

  factory StampCropRect.fromFrame({
    required Size image,
    required Size viewport,
    required Rect frame,
  }) {
    final double scale = math.max(
      viewport.width / image.width,
      viewport.height / image.height,
    );
    final double offsetLeft = (viewport.width - image.width * scale) / 2;
    final double offsetTop = (viewport.height - image.height * scale) / 2;
    double x = ((frame.left - offsetLeft) / scale).clamp(0, image.width);
    double y = ((frame.top - offsetTop) / scale).clamp(0, image.height);
    double width =
        ((frame.right - offsetLeft) / scale).clamp(0, image.width) - x;
    double height =
        ((frame.bottom - offsetTop) / scale).clamp(0, image.height) - y;
    if (width <= 0 || height <= 0) throw StateError('取景框不在相机画面内');
    const double target = 4 / 5;
    if (width / height > target) {
      final double next = height * target;
      x += (width - next) / 2;
      width = next;
    } else if (width / height < target) {
      final double next = width / target;
      y += (height - next) / 2;
      height = next;
    }
    final int ix = x.round().clamp(0, image.width.toInt() - 1);
    final int iy = y.round().clamp(0, image.height.toInt() - 1);
    int outputWidth = math.max(4, (width / 4).floor() * 4);
    outputWidth = outputWidth.clamp(4, image.width.toInt() - ix);
    outputWidth = math.max(4, outputWidth ~/ 4 * 4);
    int outputHeight = outputWidth * 5 ~/ 4;
    if (iy + outputHeight > image.height) {
      outputHeight = image.height.toInt() - iy;
      outputWidth = math.max(4, (outputHeight * 4 / 5).floor() ~/ 4 * 4);
      outputHeight = outputWidth * 5 ~/ 4;
    }
    return StampCropRect(
      x: ix,
      y: iy,
      width: outputWidth,
      height: outputHeight,
    );
  }
}

/// 集邮相机：实时取景 → Canon 机身快门 → 4:5 重编码 → 上传入册。
class StampCameraPage extends ConsumerStatefulWidget {
  const StampCameraPage({super.key});

  @override
  ConsumerState<StampCameraPage> createState() => _StampCameraPageState();
}

class _StampCameraPageState extends ConsumerState<StampCameraPage>
    with WidgetsBindingObserver {
  CameraController? _camera;
  ui.Image? _canon;
  XFile? _shot;
  String? _idemKey;
  bool _saving = false;
  bool _shooting = false;
  bool _purposeAccepted = false;
  bool _purposeAsked = false;
  bool _initializing = false;
  bool _cameraActive = true;
  bool _permissionDenied = false;
  int _cameraEpoch = 0;
  String? _error;
  double _frameRatio = _defaultFrameRatio;
  double _pinchStart = _defaultFrameRatio;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCanon();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 游客:连相机都不开(拍了也存不进去),由 build 里的登录门接管。
      if (!ref.read(authControllerProvider).isLoggedIn) return;
      _explainCameraPurpose();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _cameraActive = true;
        if (_shot == null) _initializeCamera();
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _cameraActive = false;
        unawaited(_stopCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraActive = false;
    _cameraEpoch += 1;
    final CameraController? current = _camera;
    if (current != null) unawaited(current.dispose());
    unawaited(_deleteOwnedFile(_shot));
    super.dispose();
  }

  Future<void> _explainCameraPurpose() async {
    if (!mounted || _purposeAccepted || _purposeAsked) return;
    _purposeAsked = true;
    final bool accepted =
        await showCupertinoModalPopup<bool>(
          context: context,
          builder: (BuildContext sheetContext) => CupertinoActionSheet(
            key: const Key('stamp-camera-purpose'),
            title: const Text('开启相机拍摄城市邮票'),
            message: const Text('相机仅用于拍摄城市邮票并裁切后存入你的集邮册，不会录音。'),
            actions: <Widget>[
              CupertinoActionSheetAction(
                isDefaultAction: true,
                onPressed: () => Navigator.of(sheetContext).pop(true),
                child: const Text('继续'),
              ),
            ],
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop(false),
              child: const Text('暂不'),
            ),
          ),
        ) ??
        false;
    if (!mounted) return;
    _purposeAsked = false;
    if (!accepted) {
      setState(() => _error = '需要使用相机拍摄城市邮票');
      return;
    }
    setState(() {
      _purposeAccepted = true;
      _error = null;
    });
    await _initializeCamera();
  }

  Future<void> _loadCanon() async {
    final ByteData data = await rootBundle.load(
      'assets/roam/stamp-camera-canon.jpg',
    );
    final ui.Codec codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
    );
    final ui.FrameInfo frame = await codec.getNextFrame();
    if (mounted) setState(() => _canon = frame.image);
  }

  Future<void> _initializeCamera() async {
    if (!_purposeAccepted || _initializing || !_cameraActive || _shot != null) {
      return;
    }
    final int epoch = ++_cameraEpoch;
    _initializing = true;
    CameraController? next;
    try {
      final List<CameraDescription> cameras = await availableCameras();
      if (!mounted || !_cameraActive || epoch != _cameraEpoch) return;
      if (cameras.isEmpty) {
        throw CameraException('no-camera', '没有可用相机');
      }
      final CameraDescription selected = cameras.firstWhere(
        (CameraDescription item) =>
            item.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      next = CameraController(
        selected,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await next.initialize();
      if (!mounted || !_cameraActive || epoch != _cameraEpoch) {
        await next.dispose();
        return;
      }
      final CameraController? previous = _camera;
      _camera = null;
      await previous?.dispose();
      if (!mounted || !_cameraActive || epoch != _cameraEpoch) {
        await next.dispose();
        return;
      }
      setState(() {
        _camera = next;
        _error = null;
        _permissionDenied = false;
      });
    } on CameraException catch (error) {
      if (next != null && next != _camera) await next.dispose();
      if (!mounted || !_cameraActive || epoch != _cameraEpoch) return;
      final bool denied = _looksLikePermissionDenied(error);
      setState(() {
        _permissionDenied = denied;
        _error = denied ? '没有相机权限，去设置里开启后再来拍' : '相机没能启动';
      });
    } catch (_) {
      if (next != null && next != _camera) await next.dispose();
      if (mounted && _cameraActive && epoch == _cameraEpoch) {
        setState(() => _error = '相机没能启动');
      }
    } finally {
      if (epoch == _cameraEpoch) _initializing = false;
    }
  }

  Future<void> _stopCamera() async {
    _cameraEpoch += 1;
    _initializing = false;
    final CameraController? current = _camera;
    _camera = null;
    await current?.dispose();
  }

  static bool _looksLikePermissionDenied(Object error) {
    final String value = error.toString().toLowerCase();
    return value.contains('permission') ||
        value.contains('denied') ||
        value.contains('cameraaccess');
  }

  String _newIdemKey() {
    final int ms = DateTime.now().millisecondsSinceEpoch;
    final int salt = math.Random().nextInt(1 << 32);
    return 'stamp-$ms-$salt';
  }

  Future<void> _takePhoto(StampCameraLayout layout, Size viewport) async {
    final CameraController? camera = _camera;
    if (camera == null || !camera.value.isInitialized || _shooting) return;
    setState(() => _shooting = true);
    XFile? raw;
    XFile? cropped;
    try {
      raw = await camera.takePicture();
      cropped = await _cropToFrame(raw, layout, viewport);
      await _deleteOwnedFile(raw);
      raw = null;
      if (!mounted) {
        await _deleteOwnedFile(cropped);
        return;
      }
      setState(() {
        _shot = cropped;
        _idemKey = _newIdemKey();
        _error = null;
        _shooting = false;
      });
    } catch (_) {
      await _deleteOwnedFile(cropped);
      if (!mounted) return;
      setState(() {
        _shooting = false;
        _error = '取景框裁切失败，请重拍';
      });
    } finally {
      if (raw != null) await _deleteOwnedFile(raw);
    }
  }

  Future<XFile> _cropToFrame(
    XFile raw,
    StampCameraLayout layout,
    Size viewport,
  ) async {
    final img.Image? decoded = img.decodeImage(await raw.readAsBytes());
    if (decoded == null) throw StateError('读取照片失败');
    final img.Image oriented = img.bakeOrientation(decoded);
    final StampCropRect crop = StampCropRect.fromFrame(
      image: Size(oriented.width.toDouble(), oriented.height.toDouble()),
      viewport: viewport,
      frame: layout.frame,
    );
    final img.Image output = img.copyCrop(
      oriented,
      x: crop.x,
      y: crop.y,
      width: crop.width,
      height: crop.height,
    );
    final String path = '${raw.path}.stamp.jpg';
    await File(
      path,
    ).writeAsBytes(img.encodeJpg(output, quality: 92), flush: true);
    return XFile(path);
  }

  Future<void> _deleteOwnedFile(XFile? file) async {
    if (file == null) return;
    try {
      final File owned = File(file.path);
      if (await owned.exists()) await owned.delete();
    } on FileSystemException {
      // 临时文件清理失败不阻断拍摄或保存主流程。
    }
  }

  Future<void> _discardShot() async {
    final XFile? old = _shot;
    setState(() {
      _shot = null;
      _idemKey = null;
      _error = null;
    });
    await _deleteOwnedFile(old);
  }

  Future<void> _retake() async {
    await _discardShot();
    if (_camera == null) _initializeCamera();
  }

  Future<void> _save() async {
    final XFile? shot = _shot;
    final String? key = _idemKey;
    if (shot == null || key == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final String url = await ref
          .read(publishApiProvider)
          .uploadImage(shot.path);
      final RoamStampCreated created = await ref
          .read(roamApiProvider)
          .createStamp(picUrl: url, idempotencyKey: key);
      if (!mounted) return;
      CyNativeNotice.show(context, created.idempotent ? '这张已经在册子里了' : '已存入集邮册');
      await _deleteOwnedFile(shot);
      _shot = null;
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on RoamApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '没能存入，请重试';
      });
    }
  }

  void _adjustFrame(double delta) {
    if (_shot != null) return;
    final double next = (_frameRatio + delta).clamp(
      _minFrameRatio,
      _maxFrameRatio,
    );
    if (next == _frameRatio) return;
    setState(() => _frameRatio = next);
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    // ★ 游客深链落地落在这一屏(B1 模拟器报告 P1):路由那边不再静默弹回
    //   首页 —— 页面自己不解释,用户只会以为链接坏了。登录门代替相机预览,
    //   登录完接着问相机用途;游客拿不到相机,所以这一段不碰下面的几何。
    if (!ref.watch(authControllerProvider).isLoggedIn) {
      return CupertinoPageScaffold(
        backgroundColor: CyTokens.bgPage,
        navigationBar: CupertinoNavigationBar(
          backgroundColor: Colors.transparent,
          border: null,
          brightness: Brightness.dark,
          middle: const Text('集邮相机'),
          leading: Navigator.of(context).canPop()
              ? CupertinoNavigationBarBackButton(
                  color: CyTokens.textPrimary,
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              : null,
        ),
        child: StatusView(
          key: const Key('stamp-camera-login-gate'),
          message: '登录后查看集邮相机',
          sub: '拍下的邮票要存进账号里的集邮册,登录完就能拍。',
          icon: CupertinoIcons.lock,
          large: true,
          retryLabel: '去登录',
          onRetry: () async {
            if (!await requireLogin(context, ref)) return;
            if (!mounted) return;
            await _explainCameraPurpose();
          },
        ),
      );
    }
    final Size viewport = media.size;
    final StampCameraLayout layout = StampCameraLayout.forViewport(
      viewport,
      safeTop: media.padding.top,
      frameRatio: _frameRatio,
    );
    return CupertinoPageScaffold(
      backgroundColor: CyTokens.bgPage,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: Colors.transparent,
        border: null,
        brightness: Brightness.dark,
        automaticallyImplyLeading: false,
        leading: Navigator.of(context).canPop()
            ? CupertinoNavigationBarBackButton(
                color: CyTokens.textPrimary,
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : GoRouter.maybeOf(context) == null
            ? null
            : Semantics(
                button: true,
                label: '关闭相机，返回集邮册',
                child: ExcludeSemantics(
                  child: CupertinoButton(
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    onPressed: () => context.go('/roam/stamp-album'),
                    child: const Icon(
                      CupertinoIcons.xmark,
                      color: CyTokens.textPrimary,
                    ),
                  ),
                ),
              ),
      ),
      // CupertinoPageScaffold 会为透明导航栏改写子树的 top
      // padding。此页所有相机几何均以原始 viewport/safeTop 为真源，
      // 因此在内层恢复进页时的 MediaQuery，保持 LCD、快门和裁切框不漂移。
      child: MediaQuery(
        data: media,
        child: GestureDetector(
          key: const Key('stamp-camera-viewport'),
          behavior: HitTestBehavior.opaque,
          onScaleStart: (_) => _pinchStart = _frameRatio,
          onScaleUpdate: (ScaleUpdateDetails details) {
            if (details.pointerCount < 2 || _shot != null) return;
            setState(() {
              _frameRatio = (_pinchStart * details.scale).clamp(
                _minFrameRatio,
                _maxFrameRatio,
              );
            });
          },
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (_shot == null) _preview(viewport) else _reviewImage(),
              if (_canon != null)
                IgnorePointer(
                  child: CustomPaint(
                    key: const Key('stamp-canon-body'),
                    painter: _CanonBodyPainter(image: _canon!, layout: layout),
                  ),
                ),
              if (_shot == null && _error == null) ...<Widget>[
                Positioned.fromRect(
                  rect: layout.screen,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Semantics(
                      container: true,
                      label: '裁切框大小',
                      value: '${(_frameRatio * 100).round()}%',
                      increasedValue: _frameRatio < _maxFrameRatio
                          ? '${((_frameRatio + .05).clamp(_minFrameRatio, _maxFrameRatio) * 100).round()}%'
                          : null,
                      decreasedValue: _frameRatio > _minFrameRatio
                          ? '${((_frameRatio - .05).clamp(_minFrameRatio, _maxFrameRatio) * 100).round()}%'
                          : null,
                      hint: '向上或向下滑动调整',
                      onIncrease: _frameRatio < _maxFrameRatio
                          ? () => _adjustFrame(.05)
                          : null,
                      onDecrease: _frameRatio > _minFrameRatio
                          ? () => _adjustFrame(-.05)
                          : null,
                      child: ExcludeSemantics(
                        child: Padding(
                          padding: const EdgeInsets.all(CyTokens.space2),
                          child: Text(
                            '点机身圆盘拍摄 · 双指缩放裁切 '
                            '${(layout.frame.width / layout.screen.width * 100).round()}%',
                            key: const Key('stamp-crop-label'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: CyTokens.textPrimary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: layout.shutter,
                  child: Semantics(
                    button: true,
                    label: '拍摄城市邮票',
                    enabled: !_shooting,
                    child: ExcludeSemantics(
                      child: CupertinoButton(
                        key: const Key('stamp-shutter'),
                        padding: EdgeInsets.zero,
                        onPressed: _shooting
                            ? null
                            : () => _takePhoto(layout, viewport),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: CyTokens.actionPrimaryBg,
                              width: 3,
                            ),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (_error != null)
                Positioned.fromRect(
                  rect: layout.screen,
                  child: ColoredBox(
                    color: CyTokens.overlay,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: CyTokens.space3,
                            ),
                            child: Semantics(
                              liveRegion: true,
                              label: _error!,
                              child: ExcludeSemantics(
                                child: Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: CyTokens.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_permissionDenied)
                            CupertinoButton(
                              key: const Key('stamp-open-settings'),
                              onPressed: Geolocator.openAppSettings,
                              child: const Text('去设置里开启'),
                            ),
                          if (!_permissionDenied && !_purposeAccepted)
                            CupertinoButton(
                              key: const Key('stamp-purpose-retry'),
                              onPressed: _explainCameraPurpose,
                              child: const Text('了解用途并继续'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_shot != null)
                Positioned.fromRect(
                  rect: layout.reviewActions,
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: CupertinoButton(
                          color: CyTokens.bgGlass,
                          onPressed: _saving ? null : _retake,
                          child: const Text(
                            '重拍',
                            style: TextStyle(color: CyTokens.textPrimary),
                          ),
                        ),
                      ),
                      const SizedBox(width: CyTokens.space2),
                      Expanded(
                        child: CupertinoButton(
                          color: CyTokens.actionPrimaryBg,
                          onPressed: _saving ? null : _save,
                          child: Text(
                            _saving ? '存入中…' : '存入集邮册',
                            style: TextStyle(
                              color: _saving
                                  ? CyTokens.textPlaceholder
                                  : CyTokens.actionPrimaryFg,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview(Size viewport) {
    final CameraController? camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return const ColoredBox(
        color: CyTokens.bgPage,
        child: Center(
          child: CupertinoActivityIndicator(color: CyTokens.textPrimary),
        ),
      );
    }
    final double deviceRatio = viewport.width / viewport.height;
    double scale = camera.value.aspectRatio / deviceRatio;
    if (scale < 1) scale = 1 / scale;
    return ClipRect(
      child: Transform.scale(
        scale: scale,
        child: Center(child: CameraPreview(camera)),
      ),
    );
  }

  Widget _reviewImage() => Image.file(
    File(_shot!.path),
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => const ColoredBox(color: CyTokens.bgPage),
  );
}

class _CanonBodyPainter extends CustomPainter {
  const _CanonBodyPainter({required this.image, required this.layout});

  final ui.Image image;
  final StampCameraLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.clipRRect(
      RRect.fromRectAndRadius(layout.body, const Radius.circular(24)),
    );
    canvas.save();
    canvas.translate(layout.art.center.dx, layout.art.center.dy);
    canvas.rotate(math.pi / 2);
    paintImage(
      canvas: canvas,
      rect: Rect.fromCenter(
        center: Offset.zero,
        width: layout.art.height,
        height: layout.art.width,
      ),
      image: image,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.high,
    );
    canvas.restore();
    canvas.drawRect(layout.screen, Paint()..blendMode = BlendMode.clear);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CanonBodyPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.layout != layout;
}
