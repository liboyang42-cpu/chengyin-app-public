@Tags(<String>['needs-local-env'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copy_parity 能跑完,不因 page_parity 改名崩溃', () {
    final ProcessResult r = Process.runSync('python3', <String>[
      'tool/copy_parity.py',
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(r.stdout.toString(), startsWith('比对 '));
  });
}
