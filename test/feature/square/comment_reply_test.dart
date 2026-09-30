// 广场帖文「回复态」可见性回归。
//
// §5.4 旧链路收口后，`CommentApi`（/api/comment/{list,add,report,like,delete}）
// 已整体删除，本文件原先的三条 reply_id 接口用例随之移除；回复能力由
// `/api/v1/community/posts/<id>/comments` 新链路 1:1 承接（见 square_api.dart）。
// 这里保留「回复态必须在界面上看得见」的源码断言 —— 页面行为与走哪条接口无关。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('★ 回复态必须在界面上看得见 —— 发出去就改不了了', () {
    final String src = File(
      'lib/feature/square/square_detail_page.dart',
    ).readAsStringSync().replaceAll(RegExp(r'//[^\n]*'), '');
    expect(
      src.contains("Key('replying-bar')"),
      isTrue,
      reason: '没有「回复 @某某」那一条，用户不知道这条会挂到谁下面',
    );
    expect(
      src.contains("Key('replying-cancel')"),
      isTrue,
      reason: '必须能退出回复态，否则下一条也会悄悄挂到同一个人下面',
    );
    expect(src.contains('_replyTo = null'), isTrue, reason: '发完要退出回复态');
  });
}
