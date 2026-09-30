// 「还没有成员」和「名单没取到」是两件事。
//
// ★★ 看图发现的:俱乐部详情页上面写着「128 名成员」,
//   下面成员区却是「还没有成员」—— 同一屏自相矛盾。
//   一个有 128 人的俱乐部**不可能**没有成员;名单回来是空的,
//   真相是「这一页没取到」,不是「没有人」。
//
//   这就是本轮反复撞到的那一类:把「没拿到」说成「没有」。
//   前面几处是数字(0.0 km / 0% / ¥0.00),这处是名单。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_manage.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_detail_page.dart';
import 'package:chengyin_app/feature/club/club_posts_section.dart';
import 'package:chengyin_app/data/models/club_post.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';

class _FixedAuth extends AuthController {
  _FixedAuth(this._s);
  final AuthState _s;
  @override
  AuthState build() => _s;
}

Future<void> _pump(WidgetTester t, {required int memberCount}) async {
  await t.binding.setSurfaceSize(const Size(390, 2200));
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(
          () => _FixedAuth(
            AuthState(
              user: User(id: 1, nickname: '阿兰', avatar: '', role: 'player'),
              initialized: true,
            ),
          ),
        ),
        clubDetailProvider(3).overrideWith(
          (ref) async => Club.fromJson(<String, dynamic>{
            'id': 3,
            'name': '城市夜骑俱乐部',
            'memberCount': memberCount,
            'isJoined': true,
          }),
        ),
        clubMembersProvider(3).overrideWith((ref) async => <ClubMember>[]),
        clubTopicsProvider(3).overrideWith((ref) async => <ClubTopic>[]),
        clubPostsProvider(3).overrideWith((ref) async => <ClubPost>[]),
      ].cast(),
      child: const MaterialApp(home: ClubDetailPage(clubId: 3)),
    ),
  );
  await t.pumpAndSettle();
  await t.tap(find.text('概览'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('★★ 说有 128 人却拿到空名单 —— 不许说「还没有成员」', (WidgetTester t) async {
    await _pump(t, memberCount: 128);
    expect(
      find.text('还没有成员'),
      findsNothing,
      reason: '和上面那行「128 名成员」直接打架 —— 同一屏不能自相矛盾',
    );
    expect(find.textContaining('没取到'), findsOneWidget);
  });

  testWidgets('★ 真的一个人都没有时,照实说', (WidgetTester t) async {
    await _pump(t, memberCount: 0);
    expect(find.text('还没有成员'), findsOneWidget, reason: '空俱乐部是真事实,不能被上一条一起吞掉');
  });
}
