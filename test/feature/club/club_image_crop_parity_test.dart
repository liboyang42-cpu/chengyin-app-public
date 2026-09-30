import 'dart:io';

import 'package:chengyin_app/feature/club/club_image_picker.dart';
import 'package:chengyin_app/feature/publish/publish_image_cropper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('创建页 Logo 与封面使用小程序固定比例', () {
    final String source = File(
      'lib/feature/club/club_create_page.dart',
    ).readAsStringSync();
    // 签名带上了触发元素 context(S4 锚点),按前缀定位。
    final int logoStart = source.indexOf('Future<void> _pickLogo(');
    final int coverStart = source.indexOf('Future<void> _pickCover(');
    final String logoPicker = source.substring(logoStart, coverStart);
    final String coverPicker = source.substring(
      coverStart,
      source.indexOf('Future<void> _submit()', coverStart),
    );

    expect(logoPicker, contains('cropAspect: PublishCropAspect.square'));
    expect(
      logoPicker,
      isNot(contains('cropAspect: PublishCropAspect.landscape16x9')),
    );
    expect(
      coverPicker,
      contains('cropAspect: PublishCropAspect.landscape16x9'),
    );
    expect(
      coverPicker,
      isNot(contains('cropAspect: PublishCropAspect.square')),
    );
  });

  test('俱乐部固定比例图片先裁剪再上传', () async {
    final List<String> calls = <String>[];

    final List<String>? result = await cropAndUploadClubImages(
      sourcePaths: const <String>['/tmp/logo.jpg'],
      maxCount: 1,
      aspect: PublishCropAspect.square,
      crop: (String path, PublishCropAspect aspect) async {
        calls.add('crop:${aspect.name}');
        return '$path.cropped';
      },
      upload: (String path) async {
        calls.add('upload:$path');
        return 'https://cdn.example/logo.jpg';
      },
      cleanup: (String path) async => calls.add('cleanup:$path'),
    );

    expect(result, const <String>['https://cdn.example/logo.jpg']);
    expect(calls, const <String>[
      'crop:square',
      'upload:/tmp/logo.jpg.cropped',
      'cleanup:/tmp/logo.jpg.cropped',
    ]);
  });

  test('裁剪取消不上传并清理已产生的临时文件', () async {
    final List<String> uploads = <String>[];
    final List<String> cleaned = <String>[];

    final List<String>? result = await cropAndUploadClubImages(
      sourcePaths: const <String>['/tmp/a.jpg', '/tmp/b.jpg'],
      maxCount: 2,
      aspect: PublishCropAspect.landscape16x9,
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

  test('上传失败仍清理所有已产生的临时裁剪文件', () async {
    final List<String> cleaned = <String>[];

    await expectLater(
      cropAndUploadClubImages(
        sourcePaths: const <String>['/tmp/cover.jpg'],
        maxCount: 1,
        aspect: PublishCropAspect.landscape16x9,
        crop: (String path, PublishCropAspect aspect) async => '$path.cropped',
        upload: (String path) async => throw StateError('上传失败'),
        cleanup: (String path) async => cleaned.add(path),
      ),
      throwsStateError,
    );

    expect(cleaned, const <String>['/tmp/cover.jpg.cropped']);
  });
}
