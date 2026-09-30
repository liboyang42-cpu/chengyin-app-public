import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 契约是「动画尊重 Reduce Motion」，不是「动画恰好是 180ms」。
/// 早先这里绑死了毫秒字面量，结果调一次档位就要回来改一次测试，
/// 而它本来就不关心时长是多少。现在只要求降级三元读的是 CyMotion 档位。
bool _respectsReduceMotion(String source) {
  final String compact = source.replaceAll(RegExp(r'\s+'), ' ');
  return compact.contains('MediaQuery.disableAnimationsOf(context)') &&
      RegExp(
        r'duration: reduceMotion \? Duration\.zero : CyMotion\.\w+',
      ).hasMatch(compact);
}

void main() {
  test('负控：固定动画时长不会被当成支持 Reduce Motion', () {
    expect(
      _respectsReduceMotion(
        'AnimatedContainer(duration: const Duration(milliseconds: 180))',
      ),
      isFalse,
    );
    // 光有 MediaQuery 查询、时长却写死，同样不算数。
    expect(
      _respectsReduceMotion(
        'MediaQuery.disableAnimationsOf(context); '
        'AnimatedContainer(duration: const Duration(milliseconds: 180))',
      ),
      isFalse,
    );
  });

  test('交互切换与展开动画尊重 Reduce Motion', () {
    const List<String> contracts = <String>[
      'lib/feature/activity/participant_picker.dart',
      'lib/feature/publish/publish_chooser_sheet.dart',
      'lib/feature/tickets/tickets_page.dart',
      'lib/feature/club/club_enroll_page.dart',
    ];

    for (final String path in contracts) {
      expect(
        _respectsReduceMotion(File(path).readAsStringSync()),
        isTrue,
        reason: '$path 仍在强制播放动画',
      );
    }
  });

  test('原生 Sheet 在 Reduce Motion 下不缩放背景', () {
    for (final String path in <String>[
      'lib/feature/activity/participant_picker.dart',
      'lib/feature/participation/participation_detail_sheet.dart',
    ]) {
      final String compact = File(
        path,
      ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
      expect(
        compact,
        contains(
          'backgroundZoomScale: MediaQuery.disableAnimationsOf(context) ? 1 : 0.96',
        ),
        reason: '$path 仍在 Reduce Motion 下强制缩放背景',
      );
    }
  });
}
