import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _materialNotice = RegExp(r'\b(ScaffoldMessenger|SnackBar)\b');

const Set<String> _separatelyOwnedDomains = <String>{
  'activity',
  'club',
  'merchant',
  'play',
  'publish',
  'roam',
  'template',
  'topic',
};

List<String> _violations(String source) => _materialNotice
    .allMatches(source)
    .map((Match match) => match.group(1)!)
    .toList(growable: false);

List<String> _nativeNoticeCalls(String source) {
  const String marker = 'CyNativeNotice.show(';
  final List<String> calls = <String>[];
  int offset = 0;
  while (true) {
    final int start = source.indexOf(marker, offset);
    if (start < 0) break;
    int depth = 0;
    int end = start + marker.length - 1;
    for (; end < source.length; end++) {
      final String char = source[end];
      if (char == '(') depth++;
      if (char == ')') {
        depth--;
        if (depth == 0) {
          end++;
          break;
        }
      }
    }
    calls.add(source.substring(start, end));
    offset = end;
  }
  return calls;
}

bool _looksLikeDirectFailure(String call) =>
    call.contains('.toString()') || RegExp(r'失败|暂不可用|未完成').hasMatch(call);

void main() {
  test('负控：其余功能页 Material 通知门禁会抓到违规用法', () {
    expect(
      _violations(
        "ScaffoldMessenger.of(context).showSnackBar("
        "const SnackBar(content: Text('已保存')));",
      ),
      <String>['ScaffoldMessenger', 'SnackBar'],
    );
    expect(_violations("CyNativeNotice.show(context, '已保存');"), isEmpty);
    expect(
      _nativeNoticeCalls(
        'CyNativeNotice.show(context, error.toString());',
      ).where(_looksLikeDirectFailure),
      isNotEmpty,
    );
    expect(
      _nativeNoticeCalls(
        'CyNativeNotice.show(context, error.toString(), isError: true);',
      ).where(
        (String call) =>
            _looksLikeDirectFailure(call) && !call.contains('isError: true'),
      ),
      isEmpty,
    );
  });

  test('其余功能页用 Apple 风格原生通知反馈', () {
    final Directory featureRoot = Directory('lib/feature');
    final List<String> failures = <String>[];
    final List<String> unmarkedFailures = <String>[];
    int scanned = 0;

    for (final FileSystemEntity entity in featureRoot.listSync(
      recursive: true,
    )) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String relative = entity.path.substring('lib/feature/'.length);
      final String domain = relative.split(Platform.pathSeparator).first;
      if (_separatelyOwnedDomains.contains(domain)) continue;

      scanned++;
      final List<String> found = _violations(entity.readAsStringSync());
      if (found.isNotEmpty) failures.add('${entity.path}: ${found.join(', ')}');
      for (final String call in _nativeNoticeCalls(entity.readAsStringSync())) {
        if (_looksLikeDirectFailure(call) && !call.contains('isError: true')) {
          unmarkedFailures.add('${entity.path}: $call');
        }
      }
    }

    expect(scanned, greaterThanOrEqualTo(100));
    expect(
      failures,
      isEmpty,
      reason:
          '轻量反馈统一使用 CyNativeNotice.show；失败路径必须传 '
          'isError: true。\n${failures.join('\n')}',
    );
    expect(
      unmarkedFailures,
      isEmpty,
      reason:
          '直接显示异常或失败文案时必须传 isError: true。\n'
          '${unmarkedFailures.join('\n')}',
    );
  });
}
