import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers.dart';
import '../../core/widgets/cy_image_source_sheet.dart';
import '../../core/widgets/cy_native_notice.dart';

enum PublishCropAspect {
  square(1, 1),
  landscape16x9(16, 9),
  portrait3x4(3, 4),
  node4x3(4, 3);

  const PublishCropAspect(this.width, this.height);

  final double width;
  final double height;
}

typedef PublishImageCrop =
    Future<String?> Function(String path, PublishCropAspect aspect);
typedef PublishImageUpload = Future<String> Function(String path);
typedef PublishImageCleanup = Future<void> Function(String path);

Future<void> _deleteTemporaryCroppedImage(String path) async {
  final File file = File(path);
  if (await file.exists()) await file.delete();
}

/// 小程序裁剪页会先完成整批裁剪，再一次性把结果交回上传链。
/// 因此任意一张点“取消”都取消整批，且不会先上传前几张留下孤儿文件。
Future<List<String>?> cropPublishImageQueue({
  required List<String> sourcePaths,
  required int maxCount,
  required PublishCropAspect aspect,
  required PublishImageCrop crop,
  required PublishImageUpload upload,
  PublishImageCleanup cleanup = _deleteTemporaryCroppedImage,
}) async {
  if (maxCount <= 0 || sourcePaths.isEmpty) return const <String>[];

  final List<String> croppedPaths = <String>[];
  try {
    for (final String sourcePath in sourcePaths.take(maxCount)) {
      final String? croppedPath = await crop(sourcePath, aspect);
      if (croppedPath == null) return null;
      final String normalizedPath = croppedPath.trim();
      if (normalizedPath.isEmpty) {
        throw StateError('裁剪没有返回图片');
      }
      croppedPaths.add(normalizedPath);
    }

    final List<String> urls = <String>[];
    for (final String croppedPath in croppedPaths) {
      final String url = (await upload(croppedPath)).trim();
      if (url.isEmpty) throw StateError('上传没有返回文件地址');
      urls.add(url);
    }
    return urls;
  } finally {
    final Set<String> sources = sourcePaths.toSet();
    for (final String croppedPath in croppedPaths) {
      if (sources.contains(croppedPath)) continue;
      try {
        await cleanup(croppedPath);
      } on FileSystemException {
        // Temporary-file cleanup must not replace the upload result/error.
      }
    }
  }
}

Future<String?> cropPublishImageWithNativeUIKit(
  String sourcePath,
  PublishCropAspect aspect,
) async {
  final CroppedFile? file = await ImageCropper().cropImage(
    sourcePath: sourcePath,
    maxWidth: 1440,
    maxHeight: 1440,
    aspectRatio: CropAspectRatio(ratioX: aspect.width, ratioY: aspect.height),
    compressFormat: ImageCompressFormat.jpg,
    compressQuality: 90,
    uiSettings: <PlatformUiSettings>[
      IOSUiSettings(
        title: '裁剪',
        doneButtonTitle: '选取',
        cancelButtonTitle: '取消',
        showCancelConfirmationDialog: true,
        aspectRatioLockEnabled: true,
        aspectRatioLockDimensionSwapEnabled: false,
        rotateButtonsHidden: true,
        resetAspectRatioEnabled: false,
        aspectRatioPickerButtonHidden: true,
      ),
    ],
  );
  if (file == null) return null;

  final File croppedFile = File(file.path);
  final img.Image? decoded = img.decodeImage(await croppedFile.readAsBytes());
  if (decoded == null || decoded.height == 0) {
    await croppedFile.delete();
    throw StateError('无法读取裁剪结果');
  }
  final double actual = decoded.width / decoded.height;
  final double expected = aspect.width / aspect.height;
  final double onePixelTolerance = 1 / decoded.height;
  if ((actual - expected).abs() > onePixelTolerance) {
    await croppedFile.delete();
    throw StateError('裁剪结果比例不符合要求');
  }
  return file.path;
}

/// 发布域固定比例图片的唯一选取→裁剪→上传入口。
///
/// iOS 选图继续使用 Flutter 官方 [ImagePicker]；裁剪界面由
/// `image_cropper` 的 UIKit `TOCropViewController` 渲染，并锁定小程序真源比例。
/// 用户取消选图返回空列表；在裁剪器取消整批返回 `null`。
Future<List<String>?> pickCropAndUploadPublishImages(
  BuildContext context,
  WidgetRef ref, {
  required int maxCount,
  required PublishCropAspect aspect,
  ImagePicker? picker,
  PublishImageCrop crop = cropPublishImageWithNativeUIKit,
  PublishImageUpload? upload,
  Rect? sourceRect,
}) async {
  if (maxCount <= 0) return const <String>[];
  try {
    // [sourceRect] = S4 锚点(触发元素矩形);不传按 context 自身矩形兜底。
    final CyImagePickSource? source = await cyChooseImageSource(
      context,
      sourceRect: sourceRect,
    );
    if (source == null || !context.mounted) return const <String>[];

    final ImagePicker imagePicker = picker ?? ImagePicker();
    final List<XFile> files =
        source == CyImagePickSource.gallery && maxCount > 1
        ? await imagePicker.pickMultiImage(limit: maxCount, imageQuality: 100)
        : <XFile>[
            if (await imagePicker.pickImage(
                  source: source == CyImagePickSource.camera
                      ? ImageSource.camera
                      : ImageSource.gallery,
                  imageQuality: 100,
                )
                case final XFile file)
              file,
          ];
    if (files.isEmpty) return const <String>[];

    return cropPublishImageQueue(
      sourcePaths: files.map((XFile file) => file.path).toList(),
      maxCount: maxCount,
      aspect: aspect,
      crop: crop,
      upload:
          upload ??
          (String path) => ref.read(publishApiProvider).uploadImage(path),
    );
  } catch (error) {
    if (context.mounted) {
      CyNativeNotice.show(
        context,
        error
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
    return const <String>[];
  }
}
