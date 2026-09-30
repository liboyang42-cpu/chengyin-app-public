import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('iOS 26 icon-only UITab keeps a VoiceOver label', () {
    final source = _read(
      'third_party/native_liquid_glass/ios/native_liquid_glass/Sources/'
      'native_liquid_glass/LiquidGlassTabBar/LiquidGlassTabBarView.swift',
    );

    expect(source, contains('uiTab.accessibilityLabel = tab.label'));
    expect(
      source,
      contains('searchTab.accessibilityLabel = actionButton.label'),
    );
  });

  test('native alert completes interactive dismissal exactly once', () {
    final source = _read(
      'third_party/native_liquid_glass/ios/native_liquid_glass/Sources/'
      'native_liquid_glass/LiquidGlassPresenter/LiquidGlassPresenter.swift',
    );

    expect(source, contains('presentedAlerts'));
    expect(source, contains('alertDidDismiss(id: id)'));
    expect(source, contains('AlertDismissDelegateProxy'));
    expect(source, contains('"alertDismissed"'));
  });

  test('alert sheet and popover share one presenter callback dispatcher', () {
    const String root = 'third_party/native_liquid_glass/lib/src';
    final String dispatcher = _read(
      '$root/utils/liquid_glass_presenter_channel.dart',
    );
    expect(
      RegExp(r'setMethodCallHandler').allMatches(dispatcher),
      hasLength(1),
    );
    for (final String file in <String>[
      'liquid_glass_alert.dart',
      'liquid_glass_sheet.dart',
      'liquid_glass_popover.dart',
    ]) {
      final String source = _read('$root/$file');
      expect(source, contains('LiquidGlassPresenterChannel.register'));
      expect(source, isNot(contains('.setMethodCallHandler')));
    }
  });

  test('native popover retains its delegate and honors barrier dismissal', () {
    final source = _read(
      'third_party/native_liquid_glass/ios/native_liquid_glass/Sources/'
      'native_liquid_glass/LiquidGlassPresenter/LiquidGlassPresenter.swift',
    );

    expect(source, contains('popoverDelegates'));
    final popoverProxy = RegExp(
      r'private final class PopoverDelegateProxy[\s\S]+?'
      r'(?=// MARK: - Sheet Dismiss Delegate Proxy)',
    ).firstMatch(source)?.group(0);
    expect(popoverProxy, isNotNull);
    expect(
      popoverProxy,
      contains(
        'init(presenter: LiquidGlassPresenter, id: Int, '
        'barrierDismissible: Bool)',
      ),
    );
    expect(popoverProxy, contains('private let barrierDismissible: Bool'));
    expect(popoverProxy, contains('presentationControllerShouldDismiss'));
    expect(
      popoverProxy,
      contains('popoverPresentationControllerShouldDismissPopover'),
    );

    final alertProxy = RegExp(
      r'private final class AlertDismissDelegateProxy[\s\S]+?'
      r'(?=// MARK: - Popover Delegate Proxy)',
    ).firstMatch(source)?.group(0);
    expect(alertProxy, isNot(contains('barrierDismissible')));
  });

  test('native plugin Swift packages are revision locked', () {
    const paths = <String>[
      'ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved',
      'ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/'
          'Package.resolved',
    ];
    final locks = paths.map(_read).toList();
    expect(locks[1], locks[0]);

    final json = jsonDecode(locks.first) as Map<String, dynamic>;
    final pins = (json['pins'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (final identity in <String>['svgkit', 'tocropviewcontroller']) {
      final pin = pins.singleWhere((entry) => entry['identity'] == identity);
      final state = pin['state'] as Map<String, dynamic>;
      expect(state['revision'], isNotEmpty);
      expect(state['version'], isNotEmpty);
    }
  });

  test('UIProgressView remains native on every supported iOS version', () {
    final source = _read(
      'third_party/native_liquid_glass/lib/src/liquid_glass_progress_view.dart',
    );

    expect(source, contains('defaultTargetPlatform == TargetPlatform.iOS'));
  });

  test('fixed crop direction is not overridden by the iOS plugin', () {
    final source = _read(
      'third_party/image_cropper/ios/image_cropper/Sources/image_cropper/'
      'FLTImageCropperPlugin.m',
    );

    expect(
      RegExp(
        r'if \(ratioX[^}]+aspectRatioLockDimensionSwapEnabled = YES;',
        dotAll: true,
      ).hasMatch(source),
      isFalse,
    );
  });
}
