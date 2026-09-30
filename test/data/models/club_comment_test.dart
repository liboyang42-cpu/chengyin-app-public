// 俱乐部评论的删除权限。
//
// ★ 这条**不是「只能删自己的」**。后端 `ApiClubController.canModerate:171-179`
//   放行三种人:评论作者本人 / 俱乐部创建者 / 该俱乐部里 role==1 的管理员。
//   那是**社区代管**语义:主理人要能清掉别人发的脏东西。
//
// ⚠️ 前端这层只决定**显示哪个入口**(删除 or 举报),不是权限判据:
//   · 判宽了 —— 多显示一个会被后端挡下的按钮,代价小;
//   · 判窄了 —— **主理人管不了自己的圈子**,而且没有任何报错,代价大。
//   所以宁可对齐后端的三种人,不要简化成「作者 == 我」。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/club_comment.dart';

void main() {
  group('canModerateComment 对齐后端 canModerate', () {
    test('作者本人可以删', () {
      expect(
        canModerateComment(
          viewerMemberId: 11,
          commentAuthorId: 11,
          clubOwnerMemberId: 99,
          viewerIsClubAdmin: false,
        ),
        isTrue,
      );
    });

    test('★ 俱乐部创建者可以删别人的评论', () {
      expect(
        canModerateComment(
          viewerMemberId: 99,
          commentAuthorId: 11,
          clubOwnerMemberId: 99,
          viewerIsClubAdmin: false,
        ),
        isTrue,
        reason: '简化成「作者==我」会让主理人清不掉脏内容,而且不报错',
      );
    });

    test('★ role==1 的管理员可以删别人的评论', () {
      expect(
        canModerateComment(
          viewerMemberId: 55,
          commentAuthorId: 11,
          clubOwnerMemberId: 99,
          viewerIsClubAdmin: true,
        ),
        isTrue,
      );
    });

    test('普通成员不能删别人的', () {
      expect(
        canModerateComment(
          viewerMemberId: 55,
          commentAuthorId: 11,
          clubOwnerMemberId: 99,
          viewerIsClubAdmin: false,
        ),
        isFalse,
      );
    });

    test('★ 没登录一律不给 —— null 不能落进任何一支放行', () {
      expect(
        canModerateComment(
          viewerMemberId: null,
          commentAuthorId: null,
          clubOwnerMemberId: null,
          viewerIsClubAdmin: true,
        ),
        isFalse,
        reason: 'viewerMemberId 为 null 时,连管理员位也不该放行',
      );
    });

    test('★ 作者 id 缺席时不能靠 null==null 蒙混过关', () {
      expect(
        canModerateComment(
          viewerMemberId: 11,
          commentAuthorId: null,
          clubOwnerMemberId: null,
          viewerIsClubAdmin: false,
        ),
        isFalse,
      );
    });
  });

  group('评论展示', () {
    ClubComment c(Map<String, dynamic> j) =>
        ClubComment.fromJson(<String, dynamic>{'id': 1, ...j});

    test('没有昵称时兜底文案不进头像', () {
      final ClubComment x = c(<String, dynamic>{'content': '匿名一条'});
      expect(x.displayName, '城瘾用户');
      expect(x.avatarName, isNull,
          reason: '兜底文案进头像会渲出一个「城」字当姓氏');
    });

    test('有昵称时头像用昵称', () {
      final ClubComment x = c(<String, dynamic>{'nickname': '路人甲'});
      expect(x.displayName, '路人甲');
      expect(x.avatarName, '路人甲');
    });

    test('空白昵称按缺席处理', () {
      expect(c(<String, dynamic>{'nickname': '   '}).avatarName, isNull);
    });
  });

  group('★ 成员管理与删评论是三档不同的权限', () {
    // 后端实况:
    //   删评论      → 创建者 + role==1 管理员 + 作者本人  (canModerate:171-179)
    //   移除成员    → **只有创建者**                      (:577-579)
    //   设/取消管理员 → **只有创建者**                      (:1188)
    // 混成同一个「isAdmin」判据,管理员会看到一堆点了必失败的按钮。
    const int owner = 99;
    const int admin = 55;
    const int normal = 11;

    test('管理员能删评论,但**不能**踢人', () {
      expect(
        canModerateComment(
          viewerMemberId: admin,
          commentAuthorId: normal,
          clubOwnerMemberId: owner,
          viewerIsClubAdmin: true,
        ),
        isTrue,
      );
      expect(
        canManageClubMembers(
            viewerMemberId: admin, clubOwnerMemberId: owner),
        isFalse,
        reason: '管理员踢人会被后端「无权管理该俱乐部」挡下 —— 别给这个按钮',
      );
    });

    test('创建者两样都能做', () {
      expect(
        canManageClubMembers(
            viewerMemberId: owner, clubOwnerMemberId: owner),
        isTrue,
      );
    });

    test('普通成员什么都不能', () {
      expect(
        canManageClubMembers(
            viewerMemberId: normal, clubOwnerMemberId: owner),
        isFalse,
      );
    });

    test('★ 创建者那一行不给「移除」—— 后端会拒,别让人点一个注定失败的钮', () {
      expect(
        canRemoveThisMember(
          viewerMemberId: owner,
          clubOwnerMemberId: owner,
          targetMemberId: owner,
        ),
        isFalse,
      );
      expect(
        canRemoveThisMember(
          viewerMemberId: owner,
          clubOwnerMemberId: owner,
          targetMemberId: normal,
        ),
        isTrue,
      );
    });

    test('未登录/拿不到 owner id 一律不给', () {
      expect(
        canManageClubMembers(viewerMemberId: null, clubOwnerMemberId: owner),
        isFalse,
      );
      expect(
        canManageClubMembers(viewerMemberId: owner, clubOwnerMemberId: null),
        isFalse,
        reason: 'owner 拿不到时不能靠 null==null 蒙混成"我是创建者"',
      );
    });
  });
}
