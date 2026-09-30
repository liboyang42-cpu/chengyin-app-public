// 参与人页保留小程序的两个可见动作：编辑和删除。
// 后端 setDefault 能力仍保留，但不在该页擅自增加第三个入口。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final String api = File(
    'lib/data/api/participant_api.dart',
  ).readAsStringSync();
  final String page = File(
    'lib/feature/account/participants_page.dart',
  ).readAsStringSync();

  test('★ setDefault 接口已接', () {
    expect(api.contains("'/api/user/address/setDefault'"), isTrue);
  });

  test('★ 参与人列表严格保留小程序的编辑与删除两个入口', () {
    expect(page.contains("child: const Text('编辑')"), isTrue);
    expect(page.contains('CupertinoIcons.delete'), isTrue);
    expect(page.contains('p.isDefault'), isFalse);
    expect(
      page.contains('设为默认'),
      isFalse,
      reason: '小程序该页没有默认参与人入口，App 不能擅自增加第三个动作',
    );
  });

  test('失败原因原样透传 —— 可能是"不属于当前用户"不是网络问题', () {
    final int at = api.indexOf('Future<void> setDefault(');
    final String body = api.substring(at, (at + 600).clamp(0, api.length));
    expect(body.contains("body['msg']"), isTrue);
  });
}
