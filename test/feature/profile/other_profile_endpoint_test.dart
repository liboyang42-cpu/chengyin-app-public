// 他人主页走哪个接口。
//
// ★ `/api/user/info` 与 `/api/user/public-info` 的差别**不是「字段少一点」**,
//   是**能不能匿名访问**:
//     · /user/info        —— 后端 getAppUserId() 拿不到就 error("请先登录")
//     · /user/public-info —— 白名单字段,匿名可访问
//       (后端注释原话:「未登录不算错误:这条接口就是给匿名冷启动用的」)
//
//   他人主页原来走 /user/info —— **游客点别人主页会撞「请先登录」**,
//   而这一页本来就该是能逛的。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final String api =
      File('lib/data/api/registration_api.dart').readAsStringSync();
  final String page =
      File('lib/feature/profile/user_profile_page.dart').readAsStringSync();

  test('★ 公开资料接口已接', () {
    expect(api.contains("'/api/user/public-info'"), isTrue);
  });

  test('★ 他人主页用 publicUserInfo,不是 userDetail', () {
    expect(page.contains('publicUserInfo('), isTrue);
    expect(page.contains('userDetail('), isFalse,
        reason: 'userDetail 走 /user/info,游客会撞「请先登录」—— '
            '他人主页本来就该能匿名逛');
  });

  test('★ member_id 必传 —— 公开接口没有「留空取自己」这回事', () {
    final int at = api.indexOf('publicUserInfo(int memberId)');
    expect(at, greaterThan(0));
    final String body = api.substring(at, at + 500);
    expect(body.contains("'member_id': memberId.toString()"), isTrue);
    // 不能写成 `if (memberId > 0)` 那种可选形式 —— 那是 userDetail 的语义,
    // 漏传时会变成「查自己」,而调用方以为在看别人。
    expect(body.contains('if (memberId'), isFalse,
        reason: '公开接口必须带 member_id;做成可选会在漏传时静默变成查自己');
  });

  test('看自己仍然走 userDetail(要登录、字段全)', () {
    expect(api.contains("'/api/user/info'"), isTrue,
        reason: '别把自己的资料卡一起换成公开接口 —— 那会少掉只有本人可见的字段');
  });
}
