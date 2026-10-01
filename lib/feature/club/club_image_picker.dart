import '../../l10n/error_presentation.dart';
import '../../l10n/strings.dart';
import '../../core/network/request_session_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers.dart';
import '../../core/widgets/cy_image_source_sheet.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../data/api/play_api.dart';
import '../publish/publish_image_cropper.dart';

bool shouldPickMultipleClubImages({
  required CyImagePickSource source,
  required int maxCount,
}) => source == CyImagePickSource.gallery && maxCount > 1;

/// 俱乐部固定比例图片复用发布域已验证的“整批先裁后传”队列。
///
/// 任意一张取消都返回 `null` 且不上传；成功、取消或上传失败都会
/// 清理裁剪器产生的临时文件。
Future<List<String>?> cropAndUploadClubImages({
  required List<String> sourcePaths,
  required int maxCount,
  required PublishCropAspect aspect,
  required PublishImageUpload upload,
  PublishImageCrop crop = cropPublishImageWithNativeUIKit,
  PublishImageCleanup? cleanup,
}) {
  if (cleanup == null) {
    return cropPublishImageQueue(
      sourcePaths: sourcePaths,
      maxCount: maxCount,
      aspect: aspect,
      crop: crop,
      upload: upload,
    );
  }
  return cropPublishImageQueue(
    sourcePaths: sourcePaths,
    maxCount: maxCount,
    aspect: aspect,
    crop: crop,
    upload: upload,
    cleanup: cleanup,
  );
}

/// 选图并上传 OSS 的通用流程(对齐小程序 `app.chooseImage` → wx.uploadFile)。
///
/// 1. 底部弹「拍照 / 从相册选择 / 取消」;
/// 2. image_picker 取图(最多 [maxCount] 张);
/// 3. 逐张走 `/api/common/uploadOSS`,返回上传后的 URL 列表。
///
/// 用户取消返回空列表;**不抛异常到页面** —— 上传失败以 toast 形式提示后
/// 返回当前已成功的部分,让页面继续(表单里 logo/cover/certs 都是选填位)。
Future<List<String>> pickAndUploadImages(
  BuildContext context,
  WidgetRef ref, {
  int maxCount = 1,
  PublishCropAspect? cropAspect,
  Rect? sourceRect,
}) async {
  final scope = RequestSessionScope.current;
  bool active() => context.mounted && (scope?.isCurrent() ?? true);
  if (!active()) return const <String>[];
  // [sourceRect] = S4 锚点:传**触发元素**的矩形,action sheet 才从它旁边弹。
  final CyImagePickSource? source = await cyChooseImageSource(
    context,
    sourceRect: sourceRect,
  );
  if (source == null || !active()) return const <String>[];

  final ImagePicker picker = ImagePicker();
  final ImageSource imageSource = source == CyImagePickSource.camera
      ? ImageSource.camera
      : ImageSource.gallery;
  final List<XFile> files =
      shouldPickMultipleClubImages(source: source, maxCount: maxCount)
      ? await picker.pickMultiImage(limit: maxCount, imageQuality: 85)
      : await _pickSingle(picker, imageSource);
  if (files.isEmpty || !active()) return const <String>[];

  final api = ref.read(playApiProvider);
  if (cropAspect != null) {
    try {
      return await cropAndUploadClubImages(
            sourcePaths: files.map((XFile file) => file.path).toList(),
            maxCount: maxCount,
            aspect: cropAspect,
            upload: api.uploadImage,
          ) ??
          const <String>[];
    } catch (e) {
      if (!active()) return const <String>[];
      final msg = presentError(e, stringsOf(context),
        fallback: stringsOf(context).imageCropUploadFailed,
        originalApiMessage: e is PlayException ? e.message : null,
      ).noticeText;
      CyNativeNotice.show(context, msg, isError: true);
      return const <String>[];
    }
  }

  final List<String> uploaded = <String>[];
  for (final XFile f in files) {
    if (!active()) return const <String>[];
    try {
      uploaded.add(await api.uploadImage(f.path));
    } catch (e) {
      if (!active()) return uploaded;
      final msg = presentError(e, stringsOf(context),
        fallback: stringsOf(context).imageUploadFailed,
        originalApiMessage: e is PlayException ? e.message : null,
      ).noticeText;
      CyNativeNotice.show(context, msg, isError: true);
      return uploaded;
    }
  }
  return uploaded;
}

Future<List<XFile>> _pickSingle(ImagePicker picker, ImageSource source) async {
  final XFile? file = await picker.pickImage(source: source, imageQuality: 85);
  return file == null ? const <XFile>[] : <XFile>[file];
}
