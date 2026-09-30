// 俱乐部成员管理 + 角色徽章。
//
// ★★★ 徽章标错了:App 用 `member.role == 1` 渲染「创建者」,
//   而后端 role==1 是**管理员**(ApiClubController:170「管理员(ClubMember.role==1)」,
//   1180「设置成员角色(创建者:0成员/1管理员)」,1192「管理员至多 2 个(**主理人之外**)」)。
//   创建者是 `isOwner`,和 role 是两回事 ——
//   现状是:每个管理员都被标成「创建者」,而真正的创建者一个徽章都没有。
//
// ★★★ 管理权限:**只有创建者**能移除成员 / 设管理员,
//   role==1 的管理员**不能**(后端 ApiClubController:577-579)。
//   把入口给管理员看 = 摆一个点下去必被拒的按钮。
//
// ★★ 创建者本人不能被移除(后端回「不能移除俱乐部创建者」)——
//   这一行不给移除入口。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/club_post.dart';
import 'package:chengyin_app/data/models/club_manage.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_detail_page.dart';
import 'package:chengyin_app/feature/club/club_posts_section.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/feature/club/club_member_actions.dart';

ClubMember _m({int role = 0, bool owner = false}) =>
    ClubMember.fromJson(<String, dynamic>{
      'memberId': 7,
      'nickname': '小李',
      'role': role,
      if (owner) 'isOwner': true,
    });

void main() {
  test('★★★ role==1 是管理员,不是创建者', () {
    expect(_m(role: 1).isAdmin, isTrue);
    expect(_m(role: 1).isOwner, isFalse, reason: '管理员被当成创建者 —— 徽章会标错人');
    expect(_m(owner: true).isOwner, isTrue);
    expect(
      _m(owner: true).isAdmin,
      isFalse,
      reason: '创建者的 role 是 0(后端:创建者 0成员/1管理员 之外)',
    );
  });

  test('★★ 创建者这一行不给移除入口', () {
    expect(
      canRemoveClubMember(viewerIsCreator: true, member: _m(owner: true)),
      isFalse,
      reason: '后端会拒「不能移除俱乐部创建者」',
    );
    expect(canRemoveClubMember(viewerIsCreator: true, member: _m()), isTrue);
  });

  test('★★★ 只有创建者能管理 —— 管理员也不行', () {
    expect(
      canRemoveClubMember(viewerIsCreator: false, member: _m()),
      isFalse,
      reason: '管理员看到这个入口点下去必被拒',
    );
    expect(canSetClubMemberRole(viewerIsCreator: false, member: _m()), isFalse);
  });

  test('★ 创建者不需要给自己设角色', () {
    expect(
      canSetClubMemberRole(viewerIsCreator: true, member: _m(owner: true)),
      isFalse,
      reason: '后端回「创建者无需设置角色」',
    );
    expect(canSetClubMemberRole(viewerIsCreator: true, member: _m()), isTrue);
  });

  testWidgets('★★★ 徽章:创建者说创建者,管理员说管理员', (WidgetTester t) async {
    await _pumpDetail(t, <ClubMember>[
      ClubMember.fromJson(<String, dynamic>{
        'memberId': 1,
        'nickname': '主理人',
        'isOwner': true,
      }),
      ClubMember.fromJson(<String, dynamic>{
        'memberId': 2,
        'nickname': '管理员甲',
        'role': 1,
      }),
      ClubMember.fromJson(<String, dynamic>{'memberId': 3, 'nickname': '普通成员'}),
    ]);
    expect(
      find.text('创建者'),
      findsOneWidget,
      reason: '原来用 role==1 判,会把每个管理员都标成创建者',
    );
    expect(find.text('管理员'), findsOneWidget);
  });

  testWidgets('★★★ 我不是创建者 ⇒ 一行管理入口都没有', (WidgetTester t) async {
    await _pumpDetail(t, <ClubMember>[
      ClubMember.fromJson(<String, dynamic>{'memberId': 3, 'nickname': '甲'}),
    ], iAmCreator: false);
    expect(find.byKey(const Key('member-role-3')), findsNothing);
    expect(
      find.byKey(const Key('member-remove-3')),
      findsNothing,
      reason: '管理员也不行 —— 后端只放行创建者',
    );
  });

  testWidgets('★★ 我是创建者:别人有管理入口,自己那一行没有', (WidgetTester t) async {
    await _pumpDetail(t, <ClubMember>[
      ClubMember.fromJson(<String, dynamic>{
        'memberId': 1,
        'nickname': '我',
        'isOwner': true,
      }),
      ClubMember.fromJson(<String, dynamic>{'memberId': 3, 'nickname': '甲'}),
    ]);
    expect(find.byKey(const Key('member-role-3')), findsOneWidget);
    expect(find.byKey(const Key('member-remove-3')), findsOneWidget);
    expect(
      find.byKey(const Key('member-role-1')),
      findsNothing,
      reason: '创建者不能被移除、也不需要给自己设角色',
    );
    expect(find.byKey(const Key('member-remove-1')), findsNothing);
  });
}

Future<void> _pumpDetail(
  WidgetTester t,
  List<ClubMember> members, {
  bool iAmCreator = true,
}) async {
  await t.binding.setSurfaceSize(const Size(390, 2200));
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(
          () => _FixedAuth(
            AuthState(
              user: User(id: 1, nickname: '我', avatar: '', role: 'player'),
              initialized: true,
            ),
          ),
        ),
        clubDetailProvider(3).overrideWith(
          (ref) async => Club.fromJson(<String, dynamic>{
            'id': 3,
            'name': '城市夜骑俱乐部',
            'memberCount': members.length,
            'isJoined': true,
            'isOwner': iAmCreator,
          }),
        ),
        clubMembersProvider(3).overrideWith((ref) async => members),
        clubTopicsProvider(3).overrideWith((ref) async => <ClubTopic>[]),
        clubPostsProvider(3).overrideWith((ref) async => <ClubPost>[]),
        clubLeaderboardProvider((
          clubId: 3,
          sort: ClubRankSort.composite,
        )).overrideWith((ref) async => <ClubRankRow>[]),
      ].cast(),
      child: const MaterialApp(home: ClubDetailPage(clubId: 3)),
    ),
  );
  await t.pumpAndSettle();
  await t.tap(find.text('概览'));
  await t.pumpAndSettle();
}

class _FixedAuth extends AuthController {
  _FixedAuth(this._s);
  final AuthState _s;
  @override
  AuthState build() => _s;
}
