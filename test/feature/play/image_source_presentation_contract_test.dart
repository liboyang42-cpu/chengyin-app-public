import 'package:flutter_test/flutter_test.dart';

import '../../support/source_text.dart';

void main() {
  test('俱乐部上传与节点拍照复用同一 Apple 来源选择，集邮相机保持实时取景', () {
    final String club = codeOf('lib/feature/club/club_image_picker.dart');
    final String play = codeOf('lib/feature/play/play_session_page.dart');
    final String stamp = codeOf('lib/feature/roam/stamp_camera_page.dart');

    expect(club.contains('cyChooseImageSource'), isTrue);
    expect(play.contains('cyChooseImageSource'), isTrue);
    expect(club.contains('showModalBottomSheet<ImageSource>'), isFalse);
    expect(play.contains('showModalBottomSheet<ImageSource>'), isFalse);

    expect(stamp.contains('CameraController'), isTrue);
    expect(
      stamp.contains('cyChooseImageSource'),
      isFalse,
      reason: '集邮相机是实时构图仪式，不是相机/相册来源选择',
    );
  });
}
