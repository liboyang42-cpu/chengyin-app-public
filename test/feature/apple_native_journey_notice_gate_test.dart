import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const List<String> _journeyDirectories = <String>[
  'lib/feature/club',
  'lib/feature/topic',
  'lib/feature/template',
  'lib/feature/activity',
  'lib/feature/play',
  'lib/feature/roam',
  'lib/feature/publish',
];

final RegExp _materialJourneyChrome = RegExp(
  r'\b(ScaffoldMessenger|SnackBar|SnackBarAction|MaterialPageRoute|Dialog\.fullscreen)\b',
);

List<String> _violations(String source) => _materialJourneyChrome
    .allMatches(source)
    .map((Match match) => match.group(1)!)
    .toList(growable: false);

void main() {
  test('负控：Material 通知和页面转场会被范围门禁抓到', () {
    expect(
      _violations(
        'ScaffoldMessenger.of(context); SnackBar(content: Text("x")); '
        'SnackBarAction(label: "undo", onPressed: callback); '
        'MaterialPageRoute<void>(builder: builder); Dialog.fullscreen();',
      ),
      <String>[
        'ScaffoldMessenger',
        'SnackBar',
        'SnackBarAction',
        'MaterialPageRoute',
        'Dialog.fullscreen',
      ],
    );
    expect(
      _violations(
        'CyNativeNotice.show(context, "ok"); '
        'CupertinoPageRoute<void>(builder: builder);',
      ),
      isEmpty,
    );
  });

  test('主旅程页使用 Apple 原生通知与页面转场', () {
    final List<String> failures = <String>[];
    int scanned = 0;

    for (final String directoryPath in _journeyDirectories) {
      for (final FileSystemEntity entity in Directory(
        directoryPath,
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        scanned++;
        final List<String> found = _violations(entity.readAsStringSync());
        if (found.isNotEmpty) {
          failures.add('${entity.path}: ${found.join(', ')}');
        }
      }
    }

    expect(scanned, greaterThanOrEqualTo(30));
    expect(
      failures,
      isEmpty,
      reason:
          '轻量反馈使用 CyNativeNotice，页面转场使用 '
          'CupertinoPageRoute；保留原文案、动作和返回落点。\n'
          '${failures.join('\n')}',
    );
  });
}
