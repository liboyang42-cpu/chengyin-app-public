import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('创建俱乐部使用 Cupertino 输入与向导操作控件', () {
    final String create = File(
      'lib/feature/club/club_create_page.dart',
    ).readAsStringSync();
    final String scaffold = File(
      'lib/feature/club/club_form_scaffold.dart',
    ).readAsStringSync();

    expect(
      RegExp(r'\bCupertinoTextField\(').allMatches(create).length,
      greaterThanOrEqualTo(3),
    );
    expect(RegExp(r'(?<!Cupertino)\bTextField\(').hasMatch(create), isFalse);
    expect(create, isNot(contains('FilledButton(')));
    expect(scaffold, contains('CupertinoButton('));
    expect(scaffold, isNot(contains('FilledButton(')));
    expect(scaffold, isNot(contains('OutlinedButton(')));
  });

  test('创建页字段分步顺序与小程序一致', () {
    final String source = File(
      'lib/feature/club/club_create_page.dart',
    ).readAsStringSync();
    final int profile = source.indexOf('Widget _stepProfile()');
    final int city = source.indexOf('Widget _stepCity()');
    final String profileBlock = source.substring(profile, city);
    final String cityBlock = source.substring(
      city,
      source.indexOf('Widget _input', city),
    );

    expect(
      profileBlock.indexOf("label: stringsOf(context).clubFormCoverHint"),
      lessThan(profileBlock.indexOf("label: stringsOf(context).clubFormLogoHint")),
    );
    expect(
      profileBlock.indexOf("label: stringsOf(context).clubFormClubName"),
      lessThan(profileBlock.indexOf("label: stringsOf(context).clubFormShortIntroduction")),
    );
    expect(profileBlock, isNot(contains("label: '一句话介绍(选填)'")));
    expect(profileBlock, isNot(contains("label: '关键词'")));
    expect(
      cityBlock.indexOf("label: stringsOf(context).clubFormCityField"),
      lessThan(cityBlock.indexOf("label: stringsOf(context).clubFormOptionalKeywords")),
    );
    expect(
      cityBlock.indexOf("label: stringsOf(context).clubFormOptionalKeywords"),
      lessThan(cityBlock.indexOf("label: stringsOf(context).clubFormOptionalStyle")),
    );
  });
}
