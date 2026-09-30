import 'package:chengyin_app/core/widgets/cy_image_source_sheet.dart';
import 'package:chengyin_app/feature/club/club_image_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('多图位选择拍照仍打开相机且只拍一张', () {
    expect(
      shouldPickMultipleClubImages(
        source: CyImagePickSource.camera,
        maxCount: 5,
      ),
      isFalse,
    );
  });

  test('只有相册且允许多图时才打开系统多选相册', () {
    expect(
      shouldPickMultipleClubImages(
        source: CyImagePickSource.gallery,
        maxCount: 5,
      ),
      isTrue,
    );
    expect(
      shouldPickMultipleClubImages(
        source: CyImagePickSource.gallery,
        maxCount: 1,
      ),
      isFalse,
    );
  });
}
