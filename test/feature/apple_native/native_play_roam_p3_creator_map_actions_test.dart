import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const List<String> featureRoots = <String>[
    'lib/feature/play',
    'lib/feature/roam',
    'lib/feature/p3',
    'lib/feature/creator',
    'lib/feature/map',
  ];

  final RegExp materialActions = RegExp(
    r'\b(?:FilledButton|OutlinedButton|TextButton|IconButton|ElevatedButton|'
    r'FloatingActionButton|CircularProgressIndicator|InkWell)\b',
  );

  Iterable<File> dartSources() sync* {
    for (final String root in featureRoots) {
      yield* Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((File file) => file.path.endsWith('.dart'));
    }
  }

  test(
    'play roam p3 creator and map actions use native control primitives',
    () {
      final List<String> violations = dartSources()
          .where(
            (File file) => materialActions.hasMatch(file.readAsStringSync()),
          )
          .map((File file) => file.path)
          .toList(growable: false);

      expect(violations, isEmpty);
    },
  );

  test('the scope gate detects a raw Material action control', () {
    const String syntheticSource = 'return ElevatedButton(onPressed: () {});';

    expect(materialActions.hasMatch(syntheticSource), isTrue);
  });
}
