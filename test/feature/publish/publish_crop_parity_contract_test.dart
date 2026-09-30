import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('publish fixed-ratio image slots use the native crop pipeline', () {
    final String activity = File(
      'lib/feature/publish/publish_activity_page.dart',
    ).readAsStringSync();
    final String proSheets = File(
      'lib/feature/publish/publish_pro_sheets.dart',
    ).readAsStringSync();

    expect(activity, contains('pickCropAndUploadPublishImages('));
    expect(activity, contains('PublishCropAspect.landscape16x9'));
    expect(activity, isNot(contains('pickAndUploadImages(')));

    expect(
      RegExp('pickCropAndUploadPublishImages\\(').allMatches(proSheets).length,
      4,
    );
    for (final String aspect in <String>[
      'PublishCropAspect.portrait3x4',
      'PublishCropAspect.landscape16x9',
      'PublishCropAspect.square',
      'PublishCropAspect.node4x3',
    ]) {
      expect(proSheets, contains(aspect));
    }
    expect(proSheets, isNot(contains('pickAndUploadImages(')));
  });

  test('story images keep the mini program free-ratio behavior', () {
    final String storyEditor = File(
      'lib/feature/publish/publish_pro_story_editor.dart',
    ).readAsStringSync();

    expect(storyEditor, contains('ImagePicker().pickImage('));
    expect(storyEditor, isNot(contains('PublishCropAspect.')));
  });
}
