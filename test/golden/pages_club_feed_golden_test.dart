// 俱乐部圈子快照。
//
// 此前这一页是**纯只读**的:互动数只是一行文字,看得到「3 赞」却点不了赞;
// 也没有举报入口(Apple 1.2 对 UGC 是硬要求)。
// 后端 /api/club/post/{like,create,delete,report} 一直都在,App 侧从没接。
//
// fixture 覆盖:已赞 / 未赞 / 只有图没有字 / 零互动 / 拿不到作者 id。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_club_feed_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/club_post.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/club/club_feed_page.dart';
import 'golden_theme.dart';

class _FixedAuth extends AuthController {
  _FixedAuth(this._s);
  final AuthState _s;
  @override
  AuthState build() => _s;
}

Widget _app(List<dynamic> overrides, Widget home) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: goldenTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

Future<void> _shot(WidgetTester tester, Widget app, String goldenPath) async {
  setGoldenViewport(tester, const Size(390, 860));
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

void main() {
  testWidgets('★ 圈子:已赞 / 未赞 / 零互动 / 无作者 id', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        [
          authControllerProvider.overrideWith(() => _FixedAuth(AuthState(
                user: User(id: 11, nickname: '阿兰', avatar: '', role: 'player'),
                initialized: true,
              ))),
          clubFeedProvider.overrideWith((ref) async =>
              ClubFeed.fromJson(<String, dynamic>{
                'clubCount': 2,
                'rows': <dynamic>[
                  // 已赞 —— 心形应是实心且与未赞可分
                  <String, dynamic>{
                    'id': 1,
                    'clubId': 3,
                    'authorMemberId': 21,
                    'nickname': '夜骑老王',
                    'content': '今晚静安寺出发,来了六个人。',
                    'likeCount': 12,
                    'commentCount': 3,
                    'liked': true,
                    'createTime': '2026-08-18 21:10:00',
                  },
                  // 未赞 + 零互动 —— 计数是 0 也要显示,因为按钮本身要能点
                  <String, dynamic>{
                    'id': 2,
                    'clubId': 3,
                    'authorMemberId': 11, // 就是我 → 「更多」里应给删除
                    'nickname': '阿兰',
                    'content': '我自己发的一条,还没人理。',
                    'likeCount': 0,
                    'commentCount': 0,
                    'createTime': '2026-08-18 20:00:00',
                  },
                  // ★ 拿不到作者 id —— 头像/昵称不给点(跳 /user/0 是空主页)
                  <String, dynamic>{
                    'id': 3,
                    'clubId': 3,
                    'content': '作者信息缺失的一条。',
                    'likeCount': 1,
                    'createTime': '2026-08-17 09:00:00',
                  },
                ],
              })),
        ],
        const ClubFeedPage(),
      ),
      'goldens/page_club_feed.png',
    );
  });

  testWidgets('★ 圈子:一个俱乐部都没加入(与「加了但没人发帖」是两回事)',
      (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        [
          authControllerProvider.overrideWith(() => _FixedAuth(
              const AuthState(initialized: true))),
          clubFeedProvider.overrideWith((ref) async =>
              ClubFeed.fromJson(
                  <String, dynamic>{'clubCount': 0, 'rows': <dynamic>[]})),
        ],
        const ClubFeedPage(),
      ),
      'goldens/page_club_feed_no_club.png',
    );
  });
}
