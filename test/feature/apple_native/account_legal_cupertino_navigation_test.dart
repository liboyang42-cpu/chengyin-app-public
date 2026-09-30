import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 源码 grep 型断言对 dart format 的换行/缩进免疫：比较前剥离全部空白字符。
String _flat(String s) => s.replaceAll(RegExp(r'\s+'), '');

void main() {
  test('地址、收益、邀请与法律页使用 iOS 原生导航壳', () {
    const List<String> paths = <String>[
      'lib/feature/account/address_list_page.dart',
      'lib/feature/account/address_edit_page.dart',
      'lib/feature/account/income_detail_page.dart',
      'lib/feature/account/invite_history_page.dart',
      'lib/feature/legal/legal_doc_page.dart',
    ];

    for (final String path in paths) {
      final String source = File(path).readAsStringSync();
      expect(source, contains('CupertinoPageScaffold('), reason: path);
      expect(source, contains('CupertinoNavigationBar('), reason: path);
      expect(source, isNot(contains('return Scaffold(')), reason: path);
      expect(source, isNot(contains('appBar: AppBar(')), reason: path);
    }
  });

  test('账户表单保留 iOS 系统键盘与自动填充契约', () {
    final String source = File(
      'lib/feature/account/address_edit_page.dart',
    ).readAsStringSync();

    expect(source, contains('CupertinoTextFormFieldRow('));
    expect(source, contains('TextInputType.phone'));
    expect(source, contains('AutofillHints.name'));
    expect(source, contains('AutofillHints.telephoneNumber'));
    expect(
      _flat(source),
      contains(
        _flat(
          'keyboardDismissBehavior: '
          'ScrollViewKeyboardDismissBehavior.onDrag',
        ),
      ),
      reason: '属性必须真实存在于源码，仅对 format 折行免疫',
    );
  });
}
