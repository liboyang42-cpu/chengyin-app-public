import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/theme/cy_tokens.dart';
import 'filter_shot_camera.dart';

typedef FilterShotSettingsOpener = Future<bool> Function();
typedef FilterShotFileCleaner = Future<void> Function(File? file);

Future<bool> _openSystemSettings() => Geolocator.openAppSettings();

class FilterShotCameraPage extends StatefulWidget {
  const FilterShotCameraPage({
    super.key,
    required this.title,
    required this.config,
    required this.onSubmit,
    this.cameraGateway,
    this.renderer = renderFilterShot,
    this.openSettings = _openSystemSettings,
    this.fileCleaner = _deleteFile,
  });

  final String title;
  final FilterShotConfig config;
  final Future<void> Function(File composite) onSubmit;
  final FilterShotCameraGateway? cameraGateway;
  final FilterShotRenderer renderer;
  final FilterShotSettingsOpener openSettings;
  final FilterShotFileCleaner fileCleaner;

  @override
  State<FilterShotCameraPage> createState() => _FilterShotCameraPageState();
}

class _FilterShotCameraPageState extends State<FilterShotCameraPage>
    with WidgetsBindingObserver {
  late final FilterShotCameraGateway _camera =
      widget.cameraGateway ?? DeviceFilterShotCameraGateway();

  bool _consented = false;
  bool _initializing = false;
  bool _cameraReady = false;
  bool _processing = false;
  bool _submitting = false;
  bool _submitted = false;
  int _cameraGeneration = 0;
  File? _source;
  File? _composite;
  String? _error;
  FilterShotCameraFailure? _cameraFailure;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_consented) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _cameraGeneration += 1;
      if (_cameraReady || _initializing) {
        unawaited(_releaseCamera());
      }
      return;
    }
    if (state == AppLifecycleState.resumed && _composite == null) {
      unawaited(_startCamera());
    }
  }

  Future<void> _acceptPurpose() async {
    if (_consented) return;
    setState(() => _consented = true);
    await _startCamera();
  }

  Future<void> _startCamera() async {
    if (!_consented ||
        _initializing ||
        _cameraReady ||
        _processing ||
        _composite != null ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final int generation = ++_cameraGeneration;
    if (mounted) {
      setState(() {
        _initializing = true;
        _error = null;
        _cameraFailure = null;
      });
    }
    try {
      await _camera.initialize();
      if (!mounted ||
          generation != _cameraGeneration ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        await _camera.dispose();
        return;
      }
      setState(() {
        _initializing = false;
        _cameraReady = true;
      });
    } on FilterShotCameraException catch (error) {
      await _camera.dispose();
      if (!mounted || generation != _cameraGeneration) return;
      setState(() {
        _initializing = false;
        _cameraReady = false;
        _error = switch (error.reason) {
          FilterShotCameraFailure.permissionDenied => '未获得相机权限',
          FilterShotCameraFailure.unavailable => '当前设备没有可用相机',
          FilterShotCameraFailure.captureFailed => '相机启动失败',
        };
        _cameraFailure = error.reason;
      });
    } catch (_) {
      await _camera.dispose();
      if (!mounted || generation != _cameraGeneration) return;
      setState(() {
        _initializing = false;
        _cameraReady = false;
        _error = '相机启动失败';
        _cameraFailure = FilterShotCameraFailure.unavailable;
      });
    }
  }

  Future<void> _releaseCamera() async {
    await _camera.dispose();
    if (!mounted) return;
    setState(() {
      _initializing = false;
      _cameraReady = false;
    });
    if (_consented &&
        _composite == null &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      unawaited(_startCamera());
    }
  }

  Future<void> _capture() async {
    if (!_cameraReady || _processing || _submitting) return;
    setState(() {
      _processing = true;
      _error = null;
      _cameraFailure = null;
    });

    File? source;
    File? composite;
    try {
      source = await _camera.takePicture();
      _source = source;
      await _camera.dispose();
      _cameraReady = false;
      composite = await widget.renderer(source, widget.config);
      if (!mounted) {
        await widget.fileCleaner(composite);
        return;
      }
      _composite = composite;
      setState(() => _processing = false);
    } catch (_) {
      await widget.fileCleaner(composite);
      if (mounted) {
        setState(() {
          _processing = false;
          _cameraReady = _camera.isInitialized;
          _error = '没能生成滤镜照片，请重拍';
          _cameraFailure = FilterShotCameraFailure.captureFailed;
        });
      }
    } finally {
      if (source != null && source.path != composite?.path) {
        await widget.fileCleaner(source);
      }
      _source = null;
    }
  }

  Future<void> _retake() async {
    if (_processing || _submitting) return;
    final File? old = _composite;
    setState(() {
      _composite = null;
      _error = null;
    });
    await widget.fileCleaner(old);
    await _startCamera();
  }

  Future<void> _submit() async {
    final File? composite = _composite;
    if (composite == null || _submitting || _submitted) return;
    setState(() {
      _submitting = true;
      _submitted = true;
      _error = null;
    });
    try {
      await widget.onSubmit(composite);
      await widget.fileCleaner(composite);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitted = false;
          _error = '提交失败，请重试';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraGeneration += 1;
    unawaited(_camera.dispose());
    unawaited(widget.fileCleaner(_source));
    unawaited(widget.fileCleaner(_composite));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_processing && !_submitting,
      child: CupertinoPageScaffold(
        backgroundColor: AppColors.bgDeep,
        navigationBar: CupertinoNavigationBar(
          middle: Text(widget.title),
          // 不传背景色/不传 brightness(M5):app 根是恒暗 CupertinoTheme,
          // 栏色取系统的 barBackgroundColor 即可;写死色会跟玻璃与根主题打架。
        ),
        // 没有 Scaffold 时 MaterialApp 给的 DefaultTextStyle 是黄色双下划线,
        // CyNativeButton 的 label 是裸 Text —— 这层透明 Material 只为把基座文字样式接回来
        // (与 merchant_scan_page / my_plays_page 同一条)。
        child: Material(
          color: Colors.transparent,
          child: SafeArea(child: _body()),
        ),
      ),
    );
  }

  Widget _body() {
    if (!_consented) return _purposeDisclosure();
    if (_composite != null) return _review();
    if (_error != null && !_cameraReady) return _closedError();
    return _cameraView();
  }

  Widget _purposeDisclosure() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CyTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.photo_camera_outlined,
              size: CyTokens.stillnessGuideSize,
              color: _accentColor,
            ),
            const SizedBox(height: CyTokens.space4),
            Text(
              _styleName,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: CyTokens.typePageTitle,
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            const Text(
              '仅在本次滤镜拍摄中使用相机，拍摄后在本机合成效果，不录音，不后台采集。'
              '你点提交后才上传滤镜成片，用于完成打卡和安全审核；相机原图不上传并清理。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: CyTokens.typeBody,
                height: CyTokens.leadingNormal,
              ),
            ),
            const SizedBox(height: CyTokens.space5),
            CyNativeButton(label: '同意并打开相机', onPressed: _acceptPurpose),
            const SizedBox(height: CyTokens.space2),
            CupertinoButton(
              minimumSize: const Size(44, 44),
              onPressed: () => Navigator.of(context).maybePop(false),
              child: const Text('暂不使用'),
            ),
            const SizedBox(height: CyTokens.space3),
            const Text(
              '未成年人请在监护人陪同下使用。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: CyTokens.typeCaption,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _closedError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CyTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.no_photography_outlined,
              color: AppColors.textSecondary,
              size: CyTokens.stillnessGuideSize,
            ),
            const SizedBox(height: CyTokens.space3),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: CyTokens.typeSectionTitle,
              ),
            ),
            const SizedBox(height: CyTokens.space2),
            const Text(
              '滤镜玩法必须由 App 相机完成，不会改用普通照片绕过。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: CyTokens.typeBody,
              ),
            ),
            if (_cameraFailure ==
                FilterShotCameraFailure.permissionDenied) ...<Widget>[
              const SizedBox(height: CyTokens.space3),
              CyNativeButton(
                key: const Key('filter-shot-open-settings'),
                label: '打开系统设置',
                role: CyNativeButtonRole.secondary,
                onPressed: widget.openSettings,
              ),
            ] else ...<Widget>[
              const SizedBox(height: CyTokens.space3),
              CyNativeButton(
                key: const Key('filter-shot-reopen-camera'),
                label: '重新打开相机',
                role: CyNativeButtonRole.secondary,
                onPressed: _startCamera,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cameraView() {
    return Column(
      children: <Widget>[
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
            child: _cameraReady
                ? Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      _camera.buildPreview(),
                      IgnorePointer(child: _previewOverlay()),
                    ],
                  )
                : const Center(child: CupertinoActivityIndicator()),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.pageX,
              CyTokens.space2,
              CyTokens.pageX,
              0,
            ),
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(CyTokens.space4),
          child: CyNativeButton(
            key: const Key('filter-shot-capture'),
            label: _processing ? '合成中…' : '拍摄',
            icon: const CyNativeButtonIcon(
              sfSymbol: 'camera.fill',
              fallback: CupertinoIcons.camera_fill,
            ),
            onPressed: _cameraReady && !_processing ? _capture : null,
          ),
        ),
      ],
    );
  }

  Widget _previewOverlay() {
    if (widget.config.style == FilterShotStyle.nightVision) {
      return Stack(
        key: const Key('filter-shot-night-signature'),
        fit: StackFit.expand,
        children: <Widget>[
          CustomPaint(
            painter: _NightScanPainter(
              lineColor: AppColors.filterNightVisionDim,
            ),
          ),
          const Center(
            child: Icon(
              Icons.center_focus_strong,
              color: AppColors.filterNightVision,
            ),
          ),
          const Positioned(
            left: CyTokens.space3,
            bottom: CyTokens.space3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: CyTokens.bgGlass,
                borderRadius: BorderRadius.all(
                  Radius.circular(CyTokens.radiusSm),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: CyTokens.space2,
                  vertical: CyTokens.space1,
                ),
                child: Text(
                  '异常热源扫描中',
                  style: TextStyle(
                    color: AppColors.filterNightVision,
                    fontSize: CyTokens.typeCaption,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return CustomPaint(
      key: const Key('filter-shot-pet-signature'),
      painter: _PetPovGuidePainter(
        guideColor: AppColors.filterPetPov,
        shadeColor: CyTokens.overlay,
      ),
      child: const SizedBox.expand(),
    );
  }

  Widget _review() {
    return Column(
      children: <Widget>[
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
            child: Image.file(
              _composite!,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const ColoredBox(color: AppColors.bgElevated),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space2),
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(CyTokens.space4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: CyNativeButton(
                  label: '重拍',
                  role: CyNativeButtonRole.secondary,
                  onPressed: _submitting ? null : _retake,
                ),
              ),
              const SizedBox(width: CyTokens.space3),
              Expanded(
                child: CyNativeButton(
                  label: _submitting ? '提交中…' : '提交照片',
                  onPressed: _submitting || _submitted ? null : _submit,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String get _styleName => switch (widget.config.style) {
    FilterShotStyle.nightVision => '夜视仪滤镜',
    FilterShotStyle.petPov => '宠物低机位 POV',
  };

  Color get _accentColor => switch (widget.config.style) {
    FilterShotStyle.nightVision => AppColors.filterNightVision,
    FilterShotStyle.petPov => AppColors.filterPetPov,
  };
}

class _NightScanPainter extends CustomPainter {
  const _NightScanPainter({required this.lineColor});

  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    const double gap = CyTokens.space2;
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    final Paint border = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(Offset.zero & size, border);
  }

  @override
  bool shouldRepaint(_NightScanPainter oldDelegate) =>
      oldDelegate.lineColor != lineColor;
}

class _PetPovGuidePainter extends CustomPainter {
  const _PetPovGuidePainter({
    required this.guideColor,
    required this.shadeColor,
  });

  final Color guideColor;
  final Color shadeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint shade = Paint()..color = shadeColor.withValues(alpha: 0.46);
    final Paint guide = Paint()
      ..color = guideColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final double baseY = size.height * 0.82;
    final Path silhouette = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, baseY)
      ..quadraticBezierTo(
        size.width * 0.16,
        size.height * 0.66,
        size.width * 0.30,
        baseY,
      )
      ..quadraticBezierTo(
        size.width * 0.50,
        size.height * 0.70,
        size.width * 0.70,
        baseY,
      )
      ..quadraticBezierTo(
        size.width * 0.84,
        size.height * 0.66,
        size.width,
        baseY,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(silhouette, shade);

    final Path ears = Path()
      ..moveTo(size.width * 0.28, baseY)
      ..lineTo(size.width * 0.34, size.height * 0.61)
      ..lineTo(size.width * 0.43, baseY)
      ..moveTo(size.width * 0.57, baseY)
      ..lineTo(size.width * 0.66, size.height * 0.61)
      ..lineTo(size.width * 0.72, baseY);
    canvas.drawPath(ears, guide);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.50, size.height * 0.86),
        width: size.width * 0.16,
        height: size.height * 0.06,
      ),
      guide,
    );
  }

  @override
  bool shouldRepaint(_PetPovGuidePainter oldDelegate) =>
      oldDelegate.guideColor != guideColor ||
      oldDelegate.shadeColor != shadeColor;
}

Future<void> _deleteFile(File? file) async {
  if (file == null) return;
  try {
    if (await file.exists()) await file.delete();
  } on FileSystemException {
    // 临时文件可能已被平台相机回收，清理必须幂等。
  }
}
