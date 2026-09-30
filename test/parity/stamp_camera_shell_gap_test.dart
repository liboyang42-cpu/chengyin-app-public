import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/feature/roam/stamp_camera_page.dart';

void main() {
  test('集邮相机已补齐实时取景、Canon 机身、快门、缩放与 4:5 重编码', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final String page = File(
      'lib/feature/roam/stamp_camera_page.dart',
    ).readAsStringSync();
    final File canon = File('assets/roam/stamp-camera-canon.jpg');

    expect(RegExp(r'^\s+camera:', multiLine: true).hasMatch(pubspec), isTrue);
    expect(RegExp(r'^\s+image:', multiLine: true).hasMatch(pubspec), isTrue);
    expect(canon.existsSync(), isTrue);
    expect(canon.lengthSync(), greaterThan(10 * 1024));
    expect(page.contains('CameraPreview('), isTrue);
    expect(page.contains('camera.takePicture()'), isTrue);
    expect(page.contains("Key('stamp-canon-body')"), isTrue);
    expect(
      page.contains('BlendMode.clear'),
      isTrue,
      reason: 'Canon LCD 必须真挖空，不能拿白色矩形盖住实时取景',
    );
    expect(page.contains("Key('stamp-shutter')"), isTrue);
    expect(page.contains('onScaleUpdate'), isTrue);
    expect(page.contains('img.copyCrop('), isTrue);
    expect(
      page.contains('img.encodeJpg('),
      isTrue,
      reason: '裁切后必须重编码，不能把带元数据的原图直接上传',
    );
    expect(page.contains('createStamp('), isTrue);
    expect(page.contains('uploadImage('), isTrue);
  });

  test('机身 LCD、快门和 4:5 裁切框共用同一几何真源', () {
    final StampCameraLayout layout = StampCameraLayout.forViewport(
      const Size(390, 844),
      safeTop: 47,
    );
    expect(layout.body.contains(layout.screen.topLeft), isTrue);
    expect(layout.body.contains(layout.screen.bottomRight), isTrue);
    expect(layout.body.contains(layout.shutter.center), isTrue);
    expect(layout.frame.width / layout.frame.height, closeTo(4 / 5, .0001));
    expect(layout.screen.contains(layout.frame.topLeft), isTrue);
    expect(layout.screen.contains(layout.frame.bottomRight), isTrue);

    final StampCropRect crop = StampCropRect.fromFrame(
      image: const Size(3024, 4032),
      viewport: const Size(390, 844),
      frame: layout.frame,
    );
    expect(crop.width % 4, 0);
    expect(crop.width / crop.height, closeTo(4 / 5, .0001));
  });
}
