import 'package:chengyin_app/feature/publish/publish_image_cropper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cropPublishImageQueue', () {
    test('crops the whole queue before uploading in source order', () async {
      final List<String> calls = <String>[];

      final List<String>? result = await cropPublishImageQueue(
        sourcePaths: const <String>['/tmp/a.jpg', '/tmp/b.jpg'],
        maxCount: 2,
        aspect: PublishCropAspect.landscape16x9,
        crop: (String path, PublishCropAspect aspect) async {
          calls.add('crop:$path:${aspect.name}');
          return '$path.cropped';
        },
        upload: (String path) async {
          calls.add('upload:$path');
          return 'https://cdn.example/${path.split('/').last}';
        },
      );

      expect(result, <String>[
        'https://cdn.example/a.jpg.cropped',
        'https://cdn.example/b.jpg.cropped',
      ]);
      expect(calls, <String>[
        'crop:/tmp/a.jpg:landscape16x9',
        'crop:/tmp/b.jpg:landscape16x9',
        'upload:/tmp/a.jpg.cropped',
        'upload:/tmp/b.jpg.cropped',
      ]);
    });

    test('cancelling one crop cancels the batch before any upload', () async {
      final List<String> uploads = <String>[];
      final List<String> cleaned = <String>[];

      final List<String>? result = await cropPublishImageQueue(
        sourcePaths: const <String>['/tmp/a.jpg', '/tmp/b.jpg'],
        maxCount: 2,
        aspect: PublishCropAspect.node4x3,
        crop: (String path, PublishCropAspect aspect) async =>
            path.endsWith('a.jpg') ? '$path.cropped' : null,
        upload: (String path) async {
          uploads.add(path);
          return path;
        },
        cleanup: (String path) async => cleaned.add(path),
      );

      expect(result, isNull);
      expect(uploads, isEmpty);
      expect(cleaned, const <String>['/tmp/a.jpg.cropped']);
    });

    test('limits work to the remaining image capacity', () async {
      final List<String> cropped = <String>[];

      final List<String>? result = await cropPublishImageQueue(
        sourcePaths: const <String>['/tmp/a.jpg', '/tmp/b.jpg', '/tmp/c.jpg'],
        maxCount: 2,
        aspect: PublishCropAspect.portrait3x4,
        crop: (String path, PublishCropAspect aspect) async {
          cropped.add(path);
          return '$path.cropped';
        },
        upload: (String path) async => path,
      );

      expect(cropped, const <String>['/tmp/a.jpg', '/tmp/b.jpg']);
      expect(result, const <String>[
        '/tmp/a.jpg.cropped',
        '/tmp/b.jpg.cropped',
      ]);
    });

    test('cleans every temporary crop after a successful upload', () async {
      final List<String> cleaned = <String>[];

      final List<String>? result = await cropPublishImageQueue(
        sourcePaths: const <String>['/tmp/a.jpg'],
        maxCount: 1,
        aspect: PublishCropAspect.square,
        crop: (String path, PublishCropAspect aspect) async => '$path.cropped',
        upload: (String path) async => 'https://cdn.example/a.jpg',
        cleanup: (String path) async => cleaned.add(path),
      );

      expect(result, const <String>['https://cdn.example/a.jpg']);
      expect(cleaned, const <String>['/tmp/a.jpg.cropped']);
    });
  });
}
