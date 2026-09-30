import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/cy_tokens.dart';

enum FilterShotStyle { nightVision, petPov }

typedef FilterShotRenderer =
    Future<File> Function(File source, FilterShotConfig config);

class FilterShotConfig {
  const FilterShotConfig(this.style);

  final FilterShotStyle style;

  static FilterShotConfig? tryParse(Map<String, dynamic> json) {
    return switch (json['filterStyle']) {
      'night_vision' => const FilterShotConfig(FilterShotStyle.nightVision),
      'pet_pov' => const FilterShotConfig(FilterShotStyle.petPov),
      _ => null,
    };
  }
}

class FilterShotCameraException implements Exception {
  const FilterShotCameraException(this.reason);

  final FilterShotCameraFailure reason;
}

enum FilterShotCameraFailure { unavailable, permissionDenied, captureFailed }

/// 可注入的相机边界，测试不需要真正初始化平台相机。
abstract interface class FilterShotCameraGateway {
  bool get isInitialized;

  Future<void> initialize();

  Widget buildPreview();

  Future<File> takePicture();

  Future<void> dispose();
}

class DeviceFilterShotCameraGateway implements FilterShotCameraGateway {
  CameraController? _controller;

  @override
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  @override
  Future<void> initialize() async {
    if (isInitialized) return;
    try {
      final List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw const FilterShotCameraException(
          FilterShotCameraFailure.unavailable,
        );
      }
      final CameraDescription camera = cameras.firstWhere(
        (CameraDescription item) =>
            item.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final CameraController controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      _controller = controller;
      await controller.initialize();
    } on CameraException catch (error) {
      await dispose();
      final String code = error.code.toLowerCase();
      if (code.contains('denied') ||
          code.contains('permission') ||
          code.contains('restricted')) {
        throw const FilterShotCameraException(
          FilterShotCameraFailure.permissionDenied,
        );
      }
      throw const FilterShotCameraException(
        FilterShotCameraFailure.unavailable,
      );
    }
  }

  @override
  Widget buildPreview() {
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return CameraPreview(controller);
  }

  @override
  Future<File> takePicture() async {
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw const FilterShotCameraException(
        FilterShotCameraFailure.unavailable,
      );
    }
    try {
      final XFile file = await controller.takePicture();
      return File(file.path);
    } on CameraException {
      throw const FilterShotCameraException(
        FilterShotCameraFailure.captureFailed,
      );
    }
  }

  @override
  Future<void> dispose() async {
    final CameraController? controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}

/// 把滤镜真实烧进新 PNG，而不是只在预览层叠一层 UI。
Future<File> renderFilterShot(
  File source,
  FilterShotConfig config, {
  String? outputPath,
}) async {
  final Uint8List sourceBytes = await source.readAsBytes();
  final ui.Codec codec = await ui.instantiateImageCodec(sourceBytes);
  final ui.FrameInfo frame = await codec.getNextFrame();
  codec.dispose();
  final ui.Image input = frame.image;

  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  final ui.Rect bounds = ui.Rect.fromLTWH(
    0,
    0,
    input.width.toDouble(),
    input.height.toDouble(),
  );

  switch (config.style) {
    case FilterShotStyle.nightVision:
      _drawNightVision(canvas, input, bounds);
    case FilterShotStyle.petPov:
      _drawPetPov(canvas, input, bounds);
  }

  final ui.Image output = await recorder.endRecording().toImage(
    input.width,
    input.height,
  );
  input.dispose();
  final ByteData? png = await output.toByteData(format: ui.ImageByteFormat.png);
  output.dispose();
  if (png == null) {
    throw const FilterShotCameraException(
      FilterShotCameraFailure.captureFailed,
    );
  }

  final String destination = outputPath ?? '${source.path}.filtered.png';
  final File result = File(destination);
  await result.writeAsBytes(png.buffer.asUint8List(), flush: true);
  return result;
}

void _drawNightVision(ui.Canvas canvas, ui.Image image, ui.Rect bounds) {
  final ui.Paint greenMatrix = ui.Paint()
    ..colorFilter = const ui.ColorFilter.matrix(<double>[
      0.05,
      0.10,
      0.02,
      0,
      0,
      0.28,
      0.68,
      0.18,
      0,
      18,
      0.04,
      0.15,
      0.04,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]);
  canvas.drawImageRect(
    image,
    ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    bounds,
    greenMatrix,
  );

  final double scanStep = math.max(3, bounds.height / 180);
  final ui.Paint scanLine = ui.Paint()
    ..color = AppColors.filterNightVisionDim.withValues(alpha: 0.20)
    ..strokeWidth = math.max(1, scanStep / 3);
  for (double y = 0; y < bounds.height; y += scanStep) {
    canvas.drawLine(ui.Offset(0, y), ui.Offset(bounds.width, y), scanLine);
  }
}

void _drawPetPov(ui.Canvas canvas, ui.Image image, ui.Rect bounds) {
  const int stripCount = 72;
  final double stripHeight = bounds.height / stripCount;
  final double sourceHeight = image.height / stripCount;
  final ui.Paint paint = ui.Paint()..filterQuality = ui.FilterQuality.high;

  for (int strip = 0; strip < stripCount; strip++) {
    final double t = strip / (stripCount - 1);
    final double curve = math.pow((t - 0.18).abs(), 1.65).toDouble();
    final double cropRatio = (0.05 + 0.20 * curve).clamp(0, 0.28);
    final double crop = image.width * cropRatio;
    final ui.Rect sourceStrip = ui.Rect.fromLTWH(
      crop,
      strip * sourceHeight,
      image.width - crop * 2,
      sourceHeight + 1,
    );
    final ui.Rect destinationStrip = ui.Rect.fromLTWH(
      0,
      strip * stripHeight,
      bounds.width,
      stripHeight + 1,
    );
    canvas.drawImageRect(image, sourceStrip, destinationStrip, paint);
  }

  final ui.Paint shade = ui.Paint()
    ..shader = ui.Gradient.linear(
      ui.Offset(0, bounds.height * 0.48),
      ui.Offset(0, bounds.height),
      <ui.Color>[
        CyTokens.overlay.withValues(alpha: 0),
        CyTokens.overlay.withValues(alpha: 0.54),
      ],
    );
  canvas.drawRect(bounds, shade);

  final ui.Paint frame = ui.Paint()
    ..color = AppColors.filterPetPov
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = math.max(2, bounds.shortestSide * 0.018);
  final double inset = math.max(4, bounds.shortestSide * 0.05);
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      bounds.deflate(inset),
      ui.Radius.circular(inset * 0.7),
    ),
    frame,
  );
}
