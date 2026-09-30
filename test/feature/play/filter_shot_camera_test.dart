import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/play/filter_shot_camera.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FilterShotConfig', () {
    test('only accepts the two backend-defined filter styles', () {
      expect(
        FilterShotConfig.tryParse(<String, dynamic>{
          'filterStyle': 'night_vision',
        })?.style,
        FilterShotStyle.nightVision,
      );
      expect(
        FilterShotConfig.tryParse(<String, dynamic>{
          'filterStyle': 'pet_pov',
        })?.style,
        FilterShotStyle.petPov,
      );
      expect(
        FilterShotConfig.tryParse(<String, dynamic>{
          'filterStyle': ' NIGHT_VISION ',
        }),
        isNull,
      );
      expect(
        FilterShotConfig.tryParse(<String, dynamic>{'filterStyle': 'retro'}),
        isNull,
      );
      expect(FilterShotConfig.tryParse(<String, dynamic>{}), isNull);
    });
  });

  group('renderFilterShot', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('filter-shot-test-');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('night vision writes a new PNG with the effect baked in', () async {
      final File source = File('${tempDir.path}/source.png');
      await source.writeAsBytes(await _solidPng(const ui.Color(0xFFCC6677)));
      final Uint8List original = await source.readAsBytes();

      final File result = await renderFilterShot(
        source,
        const FilterShotConfig(FilterShotStyle.nightVision),
        outputPath: '${tempDir.path}/night.png',
      );

      expect(result.path, isNot(source.path));
      expect(await result.readAsBytes(), isNot(equals(original)));
      expect(
        (await result.readAsBytes()).take(8),
        orderedEquals(<int>[137, 80, 78, 71, 13, 10, 26, 10]),
      );
      final ui.Image decoded = await _decode(await result.readAsBytes());
      final ByteData rgba = (await decoded.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final int red = _channelAt(rgba, x: 12, y: 1, channel: 0);
      final int green = _channelAt(rgba, x: 12, y: 1, channel: 1);
      final int blue = _channelAt(rgba, x: 12, y: 1, channel: 2);
      expect(green, greaterThan(red + 80));
      expect(green, greaterThan(blue + 80));
      decoded.dispose();
      expect(await source.exists(), isTrue, reason: '合成器只产出新图，原图生命周期由相机页统一管理');
    });

    test(
      'pet POV uses a nonlinear strip mapping and low-angle frame',
      () async {
        final File source = File('${tempDir.path}/source.png');
        await source.writeAsBytes(await _stripedPng());
        final Uint8List original = await source.readAsBytes();

        final File result = await renderFilterShot(
          source,
          const FilterShotConfig(FilterShotStyle.petPov),
          outputPath: '${tempDir.path}/pet.png',
        );

        expect(await result.readAsBytes(), isNot(equals(original)));
        final ui.Image decoded = await _decode(await result.readAsBytes());
        expect(decoded.width, 24);
        expect(decoded.height, 24);
        final ByteData rgba = (await decoded.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        expect(
          _channelAt(rgba, x: 3, y: 2, channel: 0),
          lessThan(80),
          reason: '阴影层之上的原白色列应被非线性取样映射到暗条纹',
        );
        decoded.dispose();
      },
    );
  });
}

Future<Uint8List> _solidPng(ui.Color color) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 24, 24),
    ui.Paint()..color = color,
  );
  final ui.Image image = await recorder.endRecording().toImage(24, 24);
  final ByteData data = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!;
  image.dispose();
  return data.buffer.asUint8List();
}

Future<Uint8List> _stripedPng() async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  for (int x = 0; x < 24; x += 4) {
    canvas.drawRect(
      ui.Rect.fromLTWH(x.toDouble(), 0, 4, 24),
      ui.Paint()
        ..color = (x ~/ 4).isEven
            ? const ui.Color(0xFFFFFFFF)
            : const ui.Color(0xFF111111),
    );
  }
  final ui.Image image = await recorder.endRecording().toImage(24, 24);
  final ByteData data = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!;
  image.dispose();
  return data.buffer.asUint8List();
}

int _channelAt(
  ByteData rgba, {
  required int x,
  required int y,
  required int channel,
}) {
  return rgba.getUint8((y * 24 + x) * 4 + channel);
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  final ui.FrameInfo frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}
