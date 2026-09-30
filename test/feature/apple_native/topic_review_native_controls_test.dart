import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('路线评价使用 Apple 文本输入和 44pt 星级按钮', () {
    // 复核半屏已从详情页抽到独立文件(它要挂原生 sheet),判据跟着走。
    final String source = File(
      'lib/feature/topic/topic_review_sheet.dart',
    ).readAsStringSync();

    expect(source, contains("key: const Key('topic-review-content')"));
    expect(source, contains('CupertinoTextField('));
    expect(source, contains('CupertinoButton('));
    expect(source, contains('minimumSize: const Size(44, 44)'));
    expect(RegExp(r'(?<!Cupertino)\bTextField\(').hasMatch(source), isFalse);
  });
}
